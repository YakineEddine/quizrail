import { createHash } from "crypto";
import { initializeApp, getApps } from "firebase-admin/app";
import {
  getFirestore,
  FieldValue,
  type Transaction,
} from "firebase-admin/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { google } from "googleapis";

if (getApps().length === 0) initializeApp();

// ---------------------------------------------------------------------------
// Monétisation : VÉRIFICATION SERVEUR obligatoire avant tout crédit.
// Le client envoie {productId, purchaseToken} ; la fonction valide le token
// auprès de l'API Google Play Developer (androidpublisher), puis crédite
// via Admin SDK. Le retour du Play Store côté client ne crédite JAMAIS rien
// tout seul : sans `granted: true` d'ici, l'achat reste en suspens.
//
// Prérequis prod (une fois, côté console) :
// 1. Produits créés dans Play Console avec EXACTEMENT les IDs ci-dessous.
// 2. API Google Play Developer activée + compte de service lié avec accès
//    financier (les fonctions utilisent les identifiants du projet).
// 3. Testeurs de licence ajoutés pour la phase de test.
// ---------------------------------------------------------------------------

const PACKAGE_NAME = "com.quizrail.quizrail";

// Catalogue serveur — SOURCE DE VÉRITÉ des attributions (le client affiche
// les prix du store mais ne décide jamais des gains).
const PACK_TOKENS: Record<string, number> = {
  quizrail_tokens_s: 120,
  quizrail_tokens_m: 550,
  quizrail_tokens_l: 1300,
};
const SKIN_PRODUCTS: Record<string, string> = {
  quizrail_skin_gold: "gold",
  quizrail_skin_neon: "neon",
};
const REMOVE_ADS = "quizrail_remove_ads";
const BATTLE_PASS = "quizrail_battle_pass";

function isKnownProduct(productId: string): boolean {
  return (
    productId in PACK_TOKENS ||
    productId in SKIN_PRODUCTS ||
    productId === REMOVE_ADS ||
    productId === BATTLE_PASS
  );
}

function playApi() {
  const auth = new google.auth.GoogleAuth({
    scopes: ["https://www.googleapis.com/auth/androidpublisher"],
  });
  return google.androidpublisher({ version: "v3", auth });
}

/** Battle pass actif ? (lu dans les tx duel/party pour le x2 des gains). */
export async function isPassActive(
  tx: Transaction,
  uid: string
): Promise<boolean> {
  try {
    const snap = await tx.get(
      getFirestore().doc(`users/${uid}/entitlements/profile`)
    );
    return (snap.data()?.battlePassActive as boolean | undefined) ?? false;
  } catch {
    return false;
  }
}

// ---------------------------------------------------------------------------
// verifyAndGrantPurchase : {productId, purchaseToken} → {granted, ...}
// Idempotent (clé = hash du token) : un même achat ne crédite qu'une fois,
// même si le store le ré-émet après un crash avant completePurchase.
// ---------------------------------------------------------------------------
export const verifyAndGrantPurchase = onCall(
  { maxInstances: 5, timeoutSeconds: 60 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Connexion requise.");
    }
    const uid = request.auth.uid;
    const productId = request.data?.productId as string | undefined;
    const purchaseToken = request.data?.purchaseToken as string | undefined;
    if (!productId || !isKnownProduct(productId)) {
      throw new HttpsError("invalid-argument", "Produit inconnu.");
    }
    if (!purchaseToken) {
      throw new HttpsError("invalid-argument", "Token d'achat manquant.");
    }

    const db = getFirestore();
    const key = createHash("sha256").update(purchaseToken).digest("hex");
    const purchaseRef = db.doc(`users/${uid}/purchases/${key}`);
    if ((await purchaseRef.get()).exists) {
      return { granted: true, duplicate: true };
    }

    // -- Vérification auprès de Google Play (jamais de confiance client) --
    let tokens = 0;
    const entitlements: Record<string, unknown> = {};
    const api = playApi();
    try {
      if (productId in PACK_TOKENS) {
        const res = await api.purchases.products.get({
          packageName: PACKAGE_NAME,
          productId,
          token: purchaseToken,
        });
        // purchaseState 0 = acheté. L'idempotence est assurée par
        // purchases/{key} (pas par consumptionState : un achat re-émis
        // après crash doit être re-validé sans re-créditer).
        if (res.data.purchaseState !== 0) {
          throw new HttpsError("failed-precondition", "Achat non valide.");
        }
        tokens = PACK_TOKENS[productId];
      } else if (productId === REMOVE_ADS || productId in SKIN_PRODUCTS) {
        const res = await api.purchases.products.get({
          packageName: PACKAGE_NAME,
          productId,
          token: purchaseToken,
        });
        if (res.data.purchaseState !== 0) {
          throw new HttpsError("failed-precondition", "Achat non valide.");
        }
        // Accusé de réception serveur (le client finalise aussi via
        // completePurchase) : sans ack sous 3 jours, remboursement auto.
        try {
          await api.purchases.products.acknowledge({
            packageName: PACKAGE_NAME,
            productId,
            token: purchaseToken,
            requestBody: {},
          });
        } catch {
          // Déjà accusé : on continue.
        }
        if (productId === REMOVE_ADS) entitlements.removeAds = true;
        else {
          entitlements.skins = FieldValue.arrayUnion([
            SKIN_PRODUCTS[productId],
          ]);
        }
      } else {
        // Abonnement battle pass.
        const res = await api.purchases.subscriptionsv2.get({
          packageName: PACKAGE_NAME,
          token: purchaseToken,
        });
        const state = res.data.subscriptionState ?? "";
        if (
          state !== "SUBSCRIPTION_STATE_ACTIVE" &&
          state !== "SUBSCRIPTION_STATE_IN_GRACE_PERIOD"
        ) {
          throw new HttpsError(
            "failed-precondition",
            "Abonnement non actif."
          );
        }
        const line = res.data.lineItems?.[0];
        const expiryMs = line?.expiryTime
          ? Date.parse(line.expiryTime)
          : 0;
        entitlements.battlePassActive = true;
        if (expiryMs > 0) entitlements.battlePassExpiryMs = expiryMs;
      }
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      throw new HttpsError(
        "internal",
        "Vérification Play impossible, réessaie.",
        e instanceof Error ? e.message : undefined
      );
    }

    // -- Attribution atomique (jetons + droits + preuve d'achat) ------------
    await db.runTransaction(async (tx) => {
      if ((await tx.get(purchaseRef)).exists) return;
      tx.set(purchaseRef, {
        productId,
        tokens,
        entitlements: Object.keys(entitlements),
        createdAt: FieldValue.serverTimestamp(),
      });
      if (tokens > 0) {
        tx.set(
          db.doc(`users/${uid}`),
          { tokens: FieldValue.increment(tokens) },
          { merge: true }
        );
      }
      if (Object.keys(entitlements).length > 0) {
        tx.set(
          db.doc(`users/${uid}/entitlements/profile`),
          { ...entitlements, updatedAt: FieldValue.serverTimestamp() },
          { merge: true }
        );
      }
    });
    return { granted: true, tokens };
  }
);
