// ============================================================================
// QuizRail — Edge Function "verify-purchase" (Supabase, offre gratuite).
// Valide un achat Play Store côté serveur AVANT tout crédit (anti-fraude) :
// le client envoie { productId, purchaseToken }, la fonction vérifie le
// token via l'API Google Play Developer, puis crédite (jetons + droits).
// Sans "granted: true" d'ici, l'achat reste en suspens côté store.
//
// Configuration (quand la fiche Play Console existe) :
//   supabase secrets set PLAY_PACKAGE_NAME=com.quizrail.quizrail
//   supabase secrets set PLAY_SERVICE_ACCOUNT_JSON='{"type":"service_account",...}'
//   (compte de service avec accès "Voir les données financières" sur l'appli)
//   supabase functions deploy verify-purchase
// Sans ces secrets : 501 explicite, aucun crédit (comportement sûr).
// ============================================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { SignJWT, importPKCS8 } from "https://esm.sh/jose@5.9.6";

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

function json(status: number, data: unknown): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json" },
  });
}

async function playAccessToken(serviceAccountJson: string): Promise<string> {
  const sa = JSON.parse(serviceAccountJson) as {
    private_key: string;
    client_email: string;
  };
  const key = await importPKCS8(sa.private_key, "RS256");
  const now = Math.floor(Date.now() / 1000);
  const jwt = await new SignJWT({
    scope: "https://www.googleapis.com/auth/androidpublisher",
  })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .setIssuer(sa.client_email)
    .setSubject(sa.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .sign(key);
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!res.ok) throw new Error("oauth");
  const body = (await res.json()) as { access_token?: string };
  if (!body.access_token) throw new Error("oauth");
  return body.access_token;
}

serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "POST requis." });
  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const authHeader = req.headers.get("Authorization") ?? "";
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData.user) return json(401, { error: "Connexion requise." });
    const uid = userData.user.id;

    const packageName = Deno.env.get("PLAY_PACKAGE_NAME") ?? "";
    const serviceAccountJson = Deno.env.get("PLAY_SERVICE_ACCOUNT_JSON") ?? "";
    if (!packageName || !serviceAccountJson) {
      return json(501, { error: "Vérification d'achat non configurée." });
    }

    const body = (await req.json()) as { productId?: unknown; purchaseToken?: unknown };
    const productId = typeof body.productId === "string" ? body.productId : "";
    const purchaseToken = typeof body.purchaseToken === "string" ? body.purchaseToken : "";
    const known = productId in PACK_TOKENS ||
      productId in SKIN_PRODUCTS ||
      productId === REMOVE_ADS ||
      productId === BATTLE_PASS;
    if (!productId || !known || !purchaseToken) {
      return json(400, { error: "Achat non validé." });
    }

    const admin = createClient(supabaseUrl, serviceKey);
    // Idempotence : token déjà vu → succès sans re-créditer.
    const { data: existing } = await admin
      .from("purchases")
      .select("id")
      .eq("purchase_token", purchaseToken)
      .maybeSingle();
    if (existing) return json(200, { granted: true, duplicate: true });

    const accessToken = await playAccessToken(serviceAccountJson);
    const api = "https://androidpublisher.googleapis.com/androidpublisher/v3";
    let tokens = 0;

    if (productId in PACK_TOKENS) {
      const res = await fetch(
        `${api}/applications/${packageName}/purchases/products/${productId}/tokens/${encodeURIComponent(purchaseToken)}`,
        { headers: { authorization: `Bearer ${accessToken}` } },
      );
      if (!res.ok) return json(402, { error: "Achat non validé." });
      const purchase = (await res.json()) as { purchaseState?: number };
      if (purchase.purchaseState !== 0) return json(402, { error: "Achat non validé." });
      tokens = PACK_TOKENS[productId];
    } else if (productId === REMOVE_ADS || productId in SKIN_PRODUCTS) {
      const res = await fetch(
        `${api}/applications/${packageName}/purchases/products/${productId}/tokens/${encodeURIComponent(purchaseToken)}`,
        { headers: { authorization: `Bearer ${accessToken}` } },
      );
      if (!res.ok) return json(402, { error: "Achat non validé." });
      const purchase = (await res.json()) as {
        purchaseState?: number;
        acknowledgementState?: number;
      };
      if (purchase.purchaseState !== 0) return json(402, { error: "Achat non validé." });
      if ((purchase.acknowledgementState ?? 0) === 0) {
        await fetch(
          `${api}/applications/${packageName}/purchases/products/${productId}/tokens/${encodeURIComponent(purchaseToken)}:acknowledge`,
          {
            method: "POST",
            headers: {
              authorization: `Bearer ${accessToken}`,
              "content-type": "application/json",
            },
            body: "{}",
          },
        );
      }
      const { data: ent } = await admin.from("entitlements").select().eq("uid", uid).maybeSingle();
      const skins = new Set<string>((ent?.skins as string[] | undefined) ?? []);
      if (productId === REMOVE_ADS) {
        await admin.from("entitlements").upsert({ uid, remove_ads: true }, { onConflict: "uid" });
      } else {
        skins.add(SKIN_PRODUCTS[productId]);
        await admin.from("entitlements").upsert(
          { uid, skins: [...skins] },
          { onConflict: "uid" },
        );
      }
    } else {
      // Abonnement battle pass.
      const res = await fetch(
        `${api}/applications/${packageName}/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`,
        { headers: { authorization: `Bearer ${accessToken}` } },
      );
      if (!res.ok) return json(402, { error: "Achat non validé." });
      const sub = (await res.json()) as {
        lineItems?: Array<{ expiryTime?: string; autoRenewingPlan?: unknown }>;
      };
      const item = sub.lineItems?.[0];
      if (!item?.expiryTime || Date.parse(item.expiryTime) <= Date.now()) {
        return json(402, { error: "Achat non validé." });
      }
      await admin.from("entitlements").upsert({ uid, battle_pass: true }, { onConflict: "uid" });
      await admin.from("profiles").update({ battle_pass: true }).eq("uid", uid);
    }

    if (tokens > 0) {
      const { data: profile } = await admin.from("profiles").select("tokens").eq("uid", uid).maybeSingle();
      await admin.from("profiles").update({ tokens: ((profile?.tokens as number | undefined) ?? 0) + tokens }).eq("uid", uid);
    }
    await admin.from("purchases").insert({ uid, product_id: productId, purchase_token: purchaseToken, tokens });
    return json(200, { granted: true, tokens });
  } catch {
    return json(500, { error: "Vérification impossible, réessaie." });
  }
});
