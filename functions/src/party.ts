import { initializeApp, getApps } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";

import { DUEL_BANK } from "./duel";
import { applyLeaderboardDirect } from "./social";

if (getApps().length === 0) initializeApp();

// ---------------------------------------------------------------------------
// Mode Party — un host anime, N joueurs répondent depuis leur téléphone.
// Anti-contention (charge) : la room porte l'état global (écrit par le host
// via functions), chaque joueur n'écrit QUE son doc players/{uid}
// (score, présence). 10 heartbeats/10 s = ~1 écriture/s au total.
// ---------------------------------------------------------------------------

const MAX_PARTY_PLAYERS = 12;
const MIN_ELAPSED_MS = 700;
const MAX_ELAPSED_MS = 600000;
const SCORE_CORRECT = 100;
const SCORE_STREAK_BONUS = 25;
const TOKEN_AWARD = 10;
const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

type Lang = "fr" | "en" | "ar";

interface PartyQuestionInput {
  prompt: string;
  answer: string;
  difficulty: string;
}

function toLang(v: unknown): Lang {
  return v === "en" ? "en" : v === "ar" ? "ar" : "fr";
}

function randomCode(): string {
  let code = "";
  for (let i = 0; i < 6; i++) {
    code += CODE_ALPHABET[Math.floor(Math.random() * CODE_ALPHABET.length)];
  }
  return code;
}

function validCustomQuestions(raw: unknown): PartyQuestionInput[] {
  if (!Array.isArray(raw) || raw.length !== 9) {
    throw new HttpsError("invalid-argument", "9 questions requises.");
  }
  const qs = raw.map((q) => {
    const o = q as Record<string, unknown>;
    if (
      typeof o.prompt !== "string" ||
      o.prompt.trim() === "" ||
      typeof o.answer !== "string" ||
      o.answer.trim() === "" ||
      !["easy", "medium", "hard"].includes(o.difficulty as string)
    ) {
      throw new HttpsError("invalid-argument", "Question invalide.");
    }
    return {
      prompt: o.prompt.trim(),
      answer: o.answer.trim(),
      difficulty: o.difficulty as string,
    };
  });
  for (const d of ["easy", "medium", "hard"]) {
    if (qs.filter((q) => q.difficulty === d).length !== 3) {
      throw new HttpsError(
        "invalid-argument",
        "3 questions par difficulté requises."
      );
    }
  }
  return qs;
}

async function buildQuestionSet(opts: {
  tunnelId?: string;
  customTunnel?: unknown;
}): Promise<{
  theme: string;
  prompts: Array<{ prompt: Record<Lang, string>; difficulty: string }>;
  answers: Array<Record<Lang, string[]>>;
}> {
  const db = getFirestore();
  if (opts.tunnelId) {
    const snap = await db.doc(`tunnels/${opts.tunnelId}`).get();
    if (!snap.exists) {
      throw new HttpsError("not-found", "Tunnel introuvable.");
    }
    const data = snap.data() ?? {};
    if (data.isPublic !== true) {
      throw new HttpsError("permission-denied", "Tunnel non public.");
    }
    const raw = (data.questions as Array<Record<string, unknown>> | undefined) ?? [];
    if (raw.length === 0) {
      throw new HttpsError("failed-precondition", "Tunnel vide.");
    }
    // Tunnel catalogue : énoncé FR + réponses FR (contrat actuel).
    return {
      theme: (data.theme as string | undefined) ?? "Party",
      prompts: raw.map((q) => ({
        prompt: { fr: String(q.prompt ?? ""), en: String(q.prompt ?? ""), ar: String(q.prompt ?? "") },
        difficulty: String(q.difficulty ?? "medium"),
      })),
      answers: raw.map((q) => ({
        fr: [String(q.answer ?? "")],
        en: [String(q.answer ?? "")],
        ar: [String(q.answer ?? "")],
      })),
    };
  }
  if (opts.customTunnel) {
    const t = opts.customTunnel as Record<string, unknown>;
    const qs = validCustomQuestions(t.questions);
    return {
      theme: String(t.theme ?? "Party"),
      prompts: qs.map((q) => ({
        prompt: { fr: q.prompt, en: q.prompt, ar: q.prompt },
        difficulty: q.difficulty,
      })),
      answers: qs.map((q) => ({ fr: [q.answer], en: [q.answer], ar: [q.answer] })),
    };
  }
  return {
    theme: "QuizRail Party",
    prompts: DUEL_BANK.map((q) => ({ prompt: q.prompt, difficulty: q.difficulty })),
    answers: DUEL_BANK.map((q) => q.answers),
  };
}

function freshPartyPlayer(uid: string, displayName: string) {
  return {
    uid,
    displayName,
    score: 0,
    correct: 0,
    answered: 0,
    streak: 0,
    bestStreak: 0,
    lastQuestionIndex: -1,
    finished: false,
    finishedAt: 0,
    connected: true,
    lastSeen: Date.now(),
  };
}

// ---------------------------------------------------------------------------
// createParty : le host crée la room (code 6 caractères unique).
// ---------------------------------------------------------------------------
export const createParty = onCall(
  { maxInstances: 5, timeoutSeconds: 60 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Connexion requise.");
    }
    const uid = request.auth.uid;
    const db = getFirestore();
    const set = await buildQuestionSet({
      tunnelId: request.data?.tunnelId as string | undefined,
      customTunnel: request.data?.customTunnel,
    });

    let code = "";
    for (let i = 0; i < 5; i++) {
      const candidate = randomCode();
      const dup = await db
        .collection("rooms")
        .where("code", "==", candidate)
        .where("status", "in", ["lobby", "playing"])
        .limit(1)
        .get();
      if (dup.empty) {
        code = candidate;
        break;
      }
    }
    if (!code) {
      throw new HttpsError("internal", "Impossible de générer un code.");
    }

    const roomRef = db.collection("rooms").doc();
    const userSnap = await db.doc(`users/${uid}`).get();
    const displayName =
      ((userSnap.data()?.displayName as string | undefined) ??
        `Host ${uid.slice(0, 4).toUpperCase()}`);
    await roomRef.set({
      code,
      hostId: uid,
      status: "lobby",
      theme: set.theme,
      questions: set.prompts,
      questionIndex: 0,
      playerIds: [uid],
      maxPlayers: MAX_PARTY_PLAYERS,
      winnerUid: null,
      isDraw: false,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    await roomRef.collection("players").doc(uid).set(freshPartyPlayer(uid, displayName));
    await roomRef.collection("secret").doc("answers").set({ answers: set.answers });
    return { roomId: roomRef.id, code };
  }
);

// ---------------------------------------------------------------------------
// joinParty : rejoindre avec le code (lobby uniquement, max 12).
// ---------------------------------------------------------------------------
export const joinParty = onCall(
  { maxInstances: 10, timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Connexion requise.");
    }
    const uid = request.auth.uid;
    const code = ((request.data?.code as string | undefined) ?? "")
      .trim()
      .toUpperCase();
    if (!/^[A-Z0-9]{6}$/.test(code)) {
      throw new HttpsError("invalid-argument", "Code à 6 caractères requis.");
    }
    const db = getFirestore();
    return db.runTransaction(async (tx) => {
      const q = await tx.get(
        db.collection("rooms").where("code", "==", code).limit(1)
      );
      if (q.empty) {
        throw new HttpsError("not-found", "Room introuvable.");
      }
      const roomRef = q.docs[0].ref;
      const room = q.docs[0].data();
      if (room.status !== "lobby") {
        throw new HttpsError("failed-precondition", "Partie déjà lancée.");
      }
      const playerIds = (room.playerIds as string[] | undefined) ?? [];
      if (!playerIds.includes(uid) && playerIds.length >= MAX_PARTY_PLAYERS) {
        throw new HttpsError("failed-precondition", "Room complète (12).");
      }
      if (!playerIds.includes(uid)) {
        const userSnap = await tx.get(db.doc(`users/${uid}`));
        const displayName =
          ((userSnap.data()?.displayName as string | undefined) ??
            `Joueur ${uid.slice(0, 4).toUpperCase()}`);
        tx.set(roomRef.collection("players").doc(uid), freshPartyPlayer(uid, displayName));
        tx.set(roomRef, {
          playerIds: FieldValue.arrayUnion([uid]),
          updatedAt: FieldValue.serverTimestamp(),
        }, { merge: true });
      }
      return { roomId: roomRef.id, theme: room.theme as string ?? "Party" };
    });
  }
);

// ---------------------------------------------------------------------------
// leaveParty : quitter (host → promotion du plus ancien restant,
// room vide → suppression).
// ---------------------------------------------------------------------------
export const leaveParty = onCall(
  { maxInstances: 5, timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Connexion requise.");
    }
    const uid = request.auth.uid;
    const roomId = request.data?.roomId as string | undefined;
    if (!roomId) throw new HttpsError("invalid-argument", "Room manquante.");
    const db = getFirestore();
    await db.runTransaction(async (tx) => {
      const roomRef = db.doc(`rooms/${roomId}`);
      const snap = await tx.get(roomRef);
      if (!snap.exists) return;
      const room = snap.data() ?? {};
      const playerIds = ((room.playerIds as string[] | undefined) ?? []).filter(
        (id) => id !== uid
      );
      tx.delete(roomRef.collection("players").doc(uid));
      if (playerIds.length === 0) {
        tx.delete(roomRef.collection("secret").doc("answers"));
        tx.delete(roomRef);
        return;
      }
      const update: Record<string, unknown> = {
        playerIds,
        updatedAt: FieldValue.serverTimestamp(),
      };
      if (room.hostId === uid) update.hostId = playerIds[0];
      tx.set(roomRef, update, { merge: true });
    });
    return { left: true };
  }
);

// ---------------------------------------------------------------------------
// startParty : le host lance (≥ 2 joueurs).
// ---------------------------------------------------------------------------
export const startParty = onCall(
  { maxInstances: 5, timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Connexion requise.");
    }
    const uid = request.auth.uid;
    const roomId = request.data?.roomId as string | undefined;
    if (!roomId) throw new HttpsError("invalid-argument", "Room manquante.");
    const db = getFirestore();
    const roomRef = db.doc(`rooms/${roomId}`);
    const snap = await roomRef.get();
    if (!snap.exists) throw new HttpsError("not-found", "Room introuvable.");
    const room = snap.data() ?? {};
    if (room.hostId !== uid) {
      throw new HttpsError("permission-denied", "Seul le host démarre.");
    }
    if (room.status !== "lobby") {
      throw new HttpsError("failed-precondition", "Déjà lancée.");
    }
    const playerIds = (room.playerIds as string[] | undefined) ?? [];
    if (playerIds.length < 2) {
      throw new HttpsError("failed-precondition", "2 joueurs minimum.");
    }
    await roomRef.set(
      { status: "playing", questionIndex: 0, updatedAt: FieldValue.serverTimestamp() },
      { merge: true }
    );
    return { started: true, players: playerIds.length };
  }
);

// ---------------------------------------------------------------------------
// submitPartyAnswer : réponse validée serveur (question courante, 1/question).
// ---------------------------------------------------------------------------
export const submitPartyAnswer = onCall(
  { maxInstances: 10, timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Connexion requise.");
    }
    const uid = request.auth.uid;
    const roomId = request.data?.roomId as string | undefined;
    const answer = (request.data?.answer as string | undefined) ?? "";
    const elapsedMs = request.data?.elapsedMs as number | undefined;
    const lang = toLang(request.data?.lang);
    if (!roomId) throw new HttpsError("invalid-argument", "Room manquante.");
    if (typeof elapsedMs !== "number" || elapsedMs < MIN_ELAPSED_MS) {
      throw new HttpsError("invalid-argument", "Réponse trop rapide.");
    }
    if (elapsedMs > MAX_ELAPSED_MS) {
      throw new HttpsError("invalid-argument", "Réponse périmée.");
    }

    const db = getFirestore();
    return db.runTransaction(async (tx) => {
      const roomRef = db.doc(`rooms/${roomId}`);
      const roomSnap = await tx.get(roomRef);
      if (!roomSnap.exists) throw new HttpsError("not-found", "Room introuvable.");
      const room = roomSnap.data() ?? {};
      if (room.status !== "playing") {
        throw new HttpsError("failed-precondition", "Partie non lancée.");
      }
      const playerIds = (room.playerIds as string[] | undefined) ?? [];
      if (!playerIds.includes(uid)) {
        throw new HttpsError("permission-denied", "Pas dans cette room.");
      }
      const questions = (room.questions as Array<unknown> | undefined) ?? [];
      const index = (room.questionIndex as number | undefined) ?? 0;
      if (index < 0 || index >= questions.length) {
        throw new HttpsError("failed-precondition", "Question terminée.");
      }
      const playerRef = roomRef.collection("players").doc(uid);
      const playerSnap = await tx.get(playerRef);
      const me = playerSnap.data() ?? {};
      if ((me.lastQuestionIndex as number | undefined ?? -1) >= index) {
        throw new HttpsError("failed-precondition", "Déjà répondu.");
      }

      const secretSnap = await tx.get(roomRef.collection("secret").doc("answers"));
      const all = (secretSnap.data()?.answers as Array<Record<Lang, string[]>> | undefined) ?? [];
      const accepted = all[index]?.[lang] ?? all[index]?.fr ?? [];
      const norm = answer.trim().toLowerCase();
      const correct = norm !== "" && accepted.map((a) => a.toLowerCase()).includes(norm);

      const streak = ((me.streak as number | undefined) ?? 0) + (correct ? 1 : 0);
      const gained = correct ? SCORE_CORRECT + (streak >= 3 ? SCORE_STREAK_BONUS : 0) : 0;
      const answered = ((me.answered as number | undefined) ?? 0) + 1;
      const finished = answered >= questions.length;
      const now = Date.now();
      tx.set(playerRef, {
        score: ((me.score as number | undefined) ?? 0) + gained,
        correct: ((me.correct as number | undefined) ?? 0) + (correct ? 1 : 0),
        answered,
        streak: correct ? streak : 0,
        bestStreak: Math.max((me.bestStreak as number | undefined) ?? 0, streak),
        lastQuestionIndex: index,
        finished,
        finishedAt: finished ? now : 0,
        lastSeen: now,
      }, { merge: true });
      if (correct) {
        tx.set(db.doc(`users/${uid}`), { tokens: FieldValue.increment(TOKEN_AWARD) }, { merge: true });
      }
      return { correct, gained, score: ((me.score as number | undefined) ?? 0) + gained, finished };
    });
  }
);

// ---------------------------------------------------------------------------
// advanceParty : le host passe à la question suivante.
// ---------------------------------------------------------------------------
export const advanceParty = onCall(
  { maxInstances: 5, timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Connexion requise.");
    }
    const uid = request.auth.uid;
    const roomId = request.data?.roomId as string | undefined;
    if (!roomId) throw new HttpsError("invalid-argument", "Room manquante.");
    const db = getFirestore();
    const roomRef = db.doc(`rooms/${roomId}`);
    const snap = await roomRef.get();
    if (!snap.exists) throw new HttpsError("not-found", "Room introuvable.");
    const room = snap.data() ?? {};
    if (room.hostId !== uid) {
      throw new HttpsError("permission-denied", "Seul le host anime.");
    }
    if (room.status !== "playing") {
      throw new HttpsError("failed-precondition", "Partie non lancée.");
    }
    const questions = (room.questions as Array<unknown> | undefined) ?? [];
    const next = ((room.questionIndex as number | undefined) ?? 0) + 1;
    if (next >= questions.length) {
      throw new HttpsError("failed-precondition", "Dernière question : termine la partie.");
    }
    await roomRef.set(
      { questionIndex: next, updatedAt: FieldValue.serverTimestamp() },
      { merge: true }
    );
    return { questionIndex: next, remaining: questions.length - 1 - next };
  }
);

// ---------------------------------------------------------------------------
// endParty : le host termine → gagnant + classements.
// ---------------------------------------------------------------------------
export const endParty = onCall(
  { maxInstances: 5, timeoutSeconds: 60 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Connexion requise.");
    }
    const uid = request.auth.uid;
    const roomId = request.data?.roomId as string | undefined;
    if (!roomId) throw new HttpsError("invalid-argument", "Room manquante.");
    const db = getFirestore();
    const roomRef = db.doc(`rooms/${roomId}`);
    const snap = await roomRef.get();
    if (!snap.exists) throw new HttpsError("not-found", "Room introuvable.");
    const room = snap.data() ?? {};
    if (room.hostId !== uid) {
      throw new HttpsError("permission-denied", "Seul le host termine.");
    }
    if (room.status !== "playing") {
      throw new HttpsError("failed-precondition", "Partie non lancée.");
    }
    const playersSnap = await roomRef.collection("players").get();
    const players: Array<Record<string, unknown> & { uid: string }> =
      playersSnap.docs.map((d) => ({
        uid: d.id,
        ...(d.data() as Record<string, unknown>),
      }));
    if (players.length === 0) {
      throw new HttpsError("failed-precondition", "Aucun joueur.");
    }
    const top = Math.max(...players.map((p) => (p.score as number | undefined) ?? 0));
    const winners = players.filter(((p) => ((p.score as number | undefined) ?? 0) === top));
    // Départage : premier à avoir fini (finishedAt le plus petit non nul).
    let winnerUid: string | null = null;
    let isDraw = false;
    if (winners.length === 1) {
      winnerUid = winners[0].uid;
    } else {
      const done = winners
        .filter((p) => ((p.finishedAt as number | undefined) ?? 0) > 0)
        .sort((a, b) => ((a.finishedAt as number) - (b.finishedAt as number)));
      if (done.length > 0) winnerUid = done[0].uid;
      else isDraw = true;
    }
    await roomRef.set(
      {
        status: "finished",
        winnerUid,
        isDraw,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    for (const p of players) {
      await applyLeaderboardDirect(p.uid, {
        score: (p.score as number | undefined) ?? 0,
        won: winnerUid !== null && p.uid === winnerUid,
      });
    }
    return { winnerUid, isDraw, players: players.length };
  }
);
