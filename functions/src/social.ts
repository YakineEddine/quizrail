import { initializeApp, getApps } from "firebase-admin/app";
import {
  getFirestore,
  FieldValue,
  Transaction,
} from "firebase-admin/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";

if (getApps().length === 0) initializeApp();

// ---------------------------------------------------------------------------
// Social : classements, amis, notation tunnels, signalements.
// La collection `leaderboard/{uid}` n'est écrite QUE côté serveur
// (duels + party) : jamais de score auto-attribué.
// ---------------------------------------------------------------------------

export interface LeaderboardDelta {
  score: number;
  won: boolean;
}

async function readProfile(uid: string): Promise<{
  country: string;
  displayName: string;
}> {
  try {
    const snap = await getFirestore().doc(`users/${uid}`).get();
    const data = snap.data() ?? {};
    return {
      country: (data.country as string | undefined) ?? "--",
      displayName:
        (data.displayName as string | undefined) ??
        `Joueur ${uid.slice(0, 4).toUpperCase()}`,
    };
  } catch {
    return { country: "--", displayName: `Joueur ${uid.slice(0, 4).toUpperCase()}` };
  }
}

/** Mise à jour classement dans une transaction existante (duels). */
export async function applyLeaderboardTx(
  tx: Transaction,
  uid: string,
  delta: LeaderboardDelta
): Promise<void> {
  const db = getFirestore();
  const boardRef = db.doc(`leaderboard/${uid}`);
  const snap = await tx.get(boardRef);
  const prev = snap.data() ?? {};
  const bestScore = Math.max(
    (prev.bestScore as number | undefined) ?? 0,
    delta.score
  );
  const profile = await readProfile(uid);
  tx.set(
    boardRef,
    {
      bestScore,
      wins: ((prev.wins as number | undefined) ?? 0) + (delta.won ? 1 : 0),
      games: ((prev.games as number | undefined) ?? 0) + 1,
      country: profile.country,
      displayName: profile.displayName,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

/** Même chose hors transaction (forfait, fin de party). */
export async function applyLeaderboardDirect(
  uid: string,
  delta: LeaderboardDelta
): Promise<void> {
  const db = getFirestore();
  const boardRef = db.doc(`leaderboard/${uid}`);
  const snap = await boardRef.get();
  const prev = snap.data() ?? {};
  const bestScore = Math.max(
    (prev.bestScore as number | undefined) ?? 0,
    delta.score
  );
  const profile = await readProfile(uid);
  await boardRef.set(
    {
      bestScore,
      wins: ((prev.wins as number | undefined) ?? 0) + (delta.won ? 1 : 0),
      games: ((prev.games as number | undefined) ?? 0) + 1,
      country: profile.country,
      displayName: profile.displayName,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

// ---------------------------------------------------------------------------
// addFriend : ajout mutuel (les deux profils doivent exister).
// ---------------------------------------------------------------------------
export const addFriend = onCall(
  { maxInstances: 5, timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Connexion requise.");
    }
    const uid = request.auth.uid;
    const friendUid = (request.data?.friendUid as string | undefined)?.trim() ?? "";
    if (!friendUid || friendUid === uid) {
      throw new HttpsError("invalid-argument", "Ami invalide.");
    }
    const db = getFirestore();
    const friendSnap = await db.doc(`users/${friendUid}`).get();
    if (!friendSnap.exists) {
      throw new HttpsError("not-found", "Joueur introuvable.");
    }
    const batch = db.batch();
    batch.set(
      db.doc(`users/${uid}`),
      { friendIds: FieldValue.arrayUnion([friendUid]) },
      { merge: true }
    );
    batch.set(
      db.doc(`users/${friendUid}`),
      { friendIds: FieldValue.arrayUnion([uid]) },
      { merge: true }
    );
    await batch.commit();
    const data = friendSnap.data() ?? {};
    return {
      friendUid,
      displayName:
        (data.displayName as string | undefined) ??
        `Joueur ${friendUid.slice(0, 4).toUpperCase()}`,
    };
  }
);

// ---------------------------------------------------------------------------
// rateTunnel : 1 à 5 étoiles, une note par joueur (modifiable).
// L'agrégat (ratingSum/Count/Avg) est protégé des clients par les rules.
// ---------------------------------------------------------------------------
export const rateTunnel = onCall(
  { maxInstances: 10, timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Connexion requise.");
    }
    const uid = request.auth.uid;
    const tunnelId = request.data?.tunnelId as string | undefined;
    const stars = request.data?.stars as number | undefined;
    if (!tunnelId || stars === undefined || !Number.isInteger(stars) || stars < 1 || stars > 5) {
      throw new HttpsError("invalid-argument", "Note entre 1 et 5 requise.");
    }
    const db = getFirestore();
    return db.runTransaction(async (tx) => {
      const tunnelRef = db.doc(`tunnels/${tunnelId}`);
      const tunnelSnap = await tx.get(tunnelRef);
      if (!tunnelSnap.exists) {
        throw new HttpsError("not-found", "Tunnel introuvable.");
      }
      const ratingRef = tunnelRef.collection("ratings").doc(uid);
      const ratingSnap = await tx.get(ratingRef);
      const prev = (ratingSnap.data()?.stars as number | undefined) ?? 0;
      const data = tunnelSnap.data() ?? {};
      const sum = ((data.ratingSum as number | undefined) ?? 0) - prev + stars;
      const count =
        ((data.ratingCount as number | undefined) ?? 0) + (prev > 0 ? 0 : 1);
      tx.set(ratingRef, {
        stars,
        updatedAt: FieldValue.serverTimestamp(),
      });
      tx.set(
        tunnelRef,
        {
          ratingSum: sum,
          ratingCount: count,
          ratingAvg: count > 0 ? sum / count : 0,
        },
        { merge: true }
      );
      return { ratingAvg: count > 0 ? sum / count : 0, ratingCount: count };
    });
  }
);

// ---------------------------------------------------------------------------
// reportTunnel : signalement → collection `reports` (file admin).
// Consultable manuellement dans la console Firestore
// (reports where status == 'pending'). Doublon refusé.
// ---------------------------------------------------------------------------
const REPORT_REASONS = ["spam", "inappropriate", "offensive", "other"];

export const reportTunnel = onCall(
  { maxInstances: 5, timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Connexion requise.");
    }
    const uid = request.auth.uid;
    const tunnelId = request.data?.tunnelId as string | undefined;
    const reason = request.data?.reason as string | undefined;
    if (!tunnelId) {
      throw new HttpsError("invalid-argument", "Tunnel manquant.");
    }
    if (!reason || !REPORT_REASONS.includes(reason)) {
      throw new HttpsError("invalid-argument", "Motif invalide.");
    }
    const db = getFirestore();
    const dup = await db
      .collection("reports")
      .where("tunnelId", "==", tunnelId)
      .where("reporterUid", "==", uid)
      .where("status", "==", "pending")
      .limit(1)
      .get();
    if (!dup.empty) {
      throw new HttpsError("failed-precondition", "Déjà signalé.");
    }
    const ref = await db.collection("reports").add({
      tunnelId,
      reporterUid: uid,
      reason,
      status: "pending",
      createdAt: FieldValue.serverTimestamp(),
    });
    return { reportId: ref.id };
  }
);
