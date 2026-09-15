import { initializeApp, getApps } from "firebase-admin/app";
import {
  getFirestore,
  FieldValue,
  Timestamp,
} from "firebase-admin/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";

import { applyLeaderboardDirect, applyLeaderboardTx } from "./social";
import { isPassActive } from "./monetization";

if (getApps().length === 0) initializeApp();

// ---------------------------------------------------------------------------
// Duel temps réel — arbitre serveur.
// - findDuel : file d'attente FIFO (appariement par ordre d'arrivée).
// - submitDuelAnswer : validation réponses + timing, score calculé ici.
// - usePower : pouvoirs payés en jetons, effets appliqués ici.
// - claimForfeit : victoire par forfait après 30 s de silence.
// - rematchDuel : revanche contre le même adversaire.
// Les clients ne peuvent JAMAIS modifier score/position : rules + functions.
// ---------------------------------------------------------------------------

const DUEL_QUESTIONS = 8;
const MIN_ELAPSED_MS = 700; // anti auto-click : rejet sous 700 ms
const MAX_ELAPSED_MS = 600000; // réponse périmée au-delà de 10 min
const FORFEIT_GRACE_MS = 30000; // forfait après 30 s sans signe de vie
const FREEZE_MS = 5000;
const DOUBLE_MS = 20000;
const STEAL_AMOUNT = 10;
const TOKEN_AWARD = 10; // jetons par bonne réponse en duel
const SCORE_CORRECT = 100;
const SCORE_STREAK_BONUS = 25; // à partir de 3 de suite

const POWER_COST: Record<string, number> = {
  freeze: 15,
  double: 10,
  steal: 20,
};

type Lang = "fr" | "en" | "ar";
type Difficulty = "easy" | "medium" | "hard";

interface BankEntry {
  prompt: Record<Lang, string>;
  answers: Record<Lang, string[]>;
  difficulty: Difficulty;
}

// Banque standard v1 — mêmes questions que le client (kQuestions).
// Exportée pour le mode Party. Les RÉPONSES vivent aussi dans
// duels/{id}/secret (illisible clients).
export const DUEL_BANK: BankEntry[] = [
  {
    prompt: {
      fr: "Capitale de la France ?",
      en: "Capital of France?",
      ar: "ما عاصمة فرنسا؟",
    },
    answers: { fr: ["paris"], en: ["paris"], ar: ["باريس", "paris"] },
    difficulty: "easy",
  },
  {
    prompt: {
      fr: "Combien font 2 + 6 ?",
      en: "How much is 2 + 6?",
      ar: "كم يساوي 2 + 6؟",
    },
    answers: {
      fr: ["8", "huit"],
      en: ["8", "eight"],
      ar: ["8", "٨", "ثمانية"],
    },
    difficulty: "easy",
  },
  {
    prompt: {
      fr: "Couleur du ciel par beau temps ?",
      en: "Color of a clear sky?",
      ar: "ما لون السماء الصافية؟",
    },
    answers: { fr: ["bleu"], en: ["blue"], ar: ["أزرق", "ازرق"] },
    difficulty: "easy",
  },
  {
    prompt: {
      fr: "Combien de pattes a une araignée ?",
      en: "How many legs does a spider have?",
      ar: "كم عدد أرجل العنكبوت؟",
    },
    answers: {
      fr: ["8", "huit"],
      en: ["8", "eight"],
      ar: ["8", "٨", "ثمانية"],
    },
    difficulty: "medium",
  },
  {
    prompt: {
      fr: "Le petit du chat s’appelle…",
      en: "A baby cat is called a…",
      ar: "ما اسم صغير القط؟",
    },
    answers: {
      fr: ["chaton"],
      en: ["kitten"],
      ar: ["هريرة", "قط صغير", "kitten"],
    },
    difficulty: "medium",
  },
  {
    prompt: {
      fr: "Planète la plus proche du Soleil ?",
      en: "Closest planet to the Sun?",
      ar: "ما أقرب كوكب إلى الشمس؟",
    },
    answers: { fr: ["mercure"], en: ["mercury"], ar: ["عطارد"] },
    difficulty: "medium",
  },
  {
    prompt: {
      fr: "Combien font 5 × 3 ?",
      en: "How much is 5 × 3?",
      ar: "كم يساوي 5 × 3؟",
    },
    answers: {
      fr: ["15", "quinze"],
      en: ["15", "fifteen"],
      ar: ["15", "١٥", "خمسة عشر"],
    },
    difficulty: "hard",
  },
  {
    prompt: {
      fr: "Quel animal miaule ?",
      en: "Which animal meows?",
      ar: "ما الحيوان الذي يموء؟",
    },
    answers: { fr: ["chat"], en: ["cat"], ar: ["قط", "قطة"] },
    difficulty: "hard",
  },
];

interface DuelPlayerState {
  lang: Lang;
  score: number;
  correct: number;
  wrong: number;
  streak: number;
  bestStreak: number;
  answered: number;
  position: number;
  totalElapsedMs: number;
  finished: boolean;
  connected: boolean;
  lastSeen: number;
  frozenUntil: number;
  doubleUntil: number;
}

function freshPlayer(lang: Lang): DuelPlayerState {
  return {
    lang,
    score: 0,
    correct: 0,
    wrong: 0,
    streak: 0,
    bestStreak: 0,
    answered: 0,
    position: 0,
    totalElapsedMs: 0,
    finished: false,
    connected: true,
    lastSeen: Date.now(),
    frozenUntil: 0,
    doubleUntil: 0,
  };
}

function toLang(v: unknown): Lang {
  return v === "en" ? "en" : v === "ar" ? "ar" : "fr";
}

function otherUid(playerIds: string[], uid: string): string {
  const o = playerIds.find((id) => id !== uid);
  if (!o) throw new HttpsError("failed-precondition", "Adversaire introuvable.");
  return o;
}

/** Contenu d'un doc duel (sans les réponses, stockées dans secret/). */
function buildDuelData(uidA: string, langA: Lang, uidB: string, langB: Lang) {
  return {
    playerIds: [uidA, uidB],
    status: "running",
    questions: DUEL_BANK.map((q) => ({
      prompt: q.prompt,
      difficulty: q.difficulty,
    })),
    players: {
      [uidA]: freshPlayer(langA),
      [uidB]: freshPlayer(langB),
    },
    winnerUid: null,
    finishReason: null,
    isDraw: false,
    rematchRequests: [],
    rematchDuelId: null,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function buildSecretData() {
  return {
    answers: DUEL_BANK.map((q) => q.answers),
  };
}

function decideWinner(
  aUid: string,
  a: DuelPlayerState,
  bUid: string,
  b: DuelPlayerState
): { winnerUid: string | null; isDraw: boolean } {
  if (a.score !== b.score) {
    return { winnerUid: a.score > b.score ? aUid : bUid, isDraw: false };
  }
  if (a.totalElapsedMs !== b.totalElapsedMs) {
    return {
      winnerUid: a.totalElapsedMs < b.totalElapsedMs ? aUid : bUid,
      isDraw: false,
    };
  }
  return { winnerUid: null, isDraw: true };
}

// ---------------------------------------------------------------------------
// findDuel : rejoint la file puis tente l'appariement atomique.
// Retourne { status: 'waiting' } ou { status: 'matched', duelId, opponentUid }.
// À appeler en boucle (toutes les ~3 s) jusqu'au match ou à l'abandon.
// ---------------------------------------------------------------------------
export const findDuel = onCall(
  { maxInstances: 5, timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Connexion requise.");
    }
    const uid = request.auth.uid;
    const lang = toLang(request.data?.lang);
    const db = getFirestore();

    return db.runTransaction(async (tx) => {
      // Le plus ancien en file (hors soi-même). Pas de filtre != :
      // on lit les 2 plus anciens et on ignore notre propre doc.
      const q = await tx.get(
        db.collection("duelQueue").orderBy("joinedAt", "asc").limit(2)
      );
      const opponent = q.docs.find((d) => d.id !== uid);

      if (!opponent) {
        tx.set(
          db.doc(`duelQueue/${uid}`),
          { uid, lang, joinedAt: FieldValue.serverTimestamp() },
          { merge: true }
        );
        return { status: "waiting" };
      }

      const opponentUid = opponent.id;
      const opponentLang = toLang(opponent.data().lang);
      const duelRef = db.collection("duels").doc();
      tx.create(duelRef, buildDuelData(uid, lang, opponentUid, opponentLang));
      tx.set(duelRef.collection("secret").doc("answers"), buildSecretData());
      tx.delete(db.doc(`duelQueue/${opponentUid}`));
      tx.delete(db.doc(`duelQueue/${uid}`));
      return { status: "matched", duelId: duelRef.id, opponentUid };
    });
  }
);

// ---------------------------------------------------------------------------
// submitDuelAnswer : validation + score 100 % serveur.
// ---------------------------------------------------------------------------
export const submitDuelAnswer = onCall(
  { maxInstances: 10, timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Connexion requise.");
    }
    const uid = request.auth.uid;
    const duelId = request.data?.duelId as string | undefined;
    const questionIndex = request.data?.questionIndex as number | undefined;
    const answer = (request.data?.answer as string | undefined) ?? "";
    const elapsedMs = request.data?.elapsedMs as number | undefined;
    if (!duelId || typeof questionIndex !== "number") {
      throw new HttpsError("invalid-argument", "Paramètres manquants.");
    }
    if (typeof elapsedMs !== "number" || elapsedMs < MIN_ELAPSED_MS) {
      throw new HttpsError(
        "invalid-argument",
        "Réponse trop rapide — prends le temps de lire."
      );
    }
    if (elapsedMs > MAX_ELAPSED_MS) {
      throw new HttpsError("invalid-argument", "Réponse périmée.");
    }

    const db = getFirestore();
    return db.runTransaction(async (tx) => {
      const duelRef = db.doc(`duels/${duelId}`);
      const duelSnap = await tx.get(duelRef);
      if (!duelSnap.exists) {
        throw new HttpsError("not-found", "Duel introuvable.");
      }
      const duel = duelSnap.data() as Record<string, unknown>;
      if (duel.status !== "running") {
        throw new HttpsError("failed-precondition", "Duel terminé.");
      }
      const playerIds = duel.playerIds as string[];
      if (!playerIds.includes(uid)) {
        throw new HttpsError("permission-denied", "Pas ton duel.");
      }
      const players = duel.players as Record<string, DuelPlayerState>;
      const me = players[uid];
      if (me.finished) {
        throw new HttpsError("failed-precondition", "Tu as fini tes questions.");
      }
      if (questionIndex !== me.answered) {
        throw new HttpsError("invalid-argument", "Question déjà jouée.");
      }
      if (questionIndex < 0 || questionIndex >= DUEL_QUESTIONS) {
        throw new HttpsError("invalid-argument", "Question invalide.");
      }
      const now = Date.now();
      if (now < me.frozenUntil) {
        throw new HttpsError("failed-precondition", "Gelé par l'adversaire !");
      }

      const secretSnap = await tx.get(
        duelRef.collection("secret").doc("answers")
      );
      const secret = secretSnap.data() as
        | { answers: Array<Record<Lang, string[]>> }
        | undefined;
      const accepted =
        secret?.answers?.[questionIndex]?.[me.lang] ??
        secret?.answers?.[questionIndex]?.fr ??
        [];
      const norm = answer.trim().toLowerCase();
      const correct =
        norm !== "" &&
        accepted.map((a) => a.toLowerCase()).includes(norm);

      let score = me.score;
      let correctCount = me.correct;
      let streak = me.streak;
      let gained = 0;
      if (correct) {
        streak += 1;
        gained = SCORE_CORRECT + (streak >= 3 ? SCORE_STREAK_BONUS : 0);
        if (now < me.doubleUntil) gained *= 2;
        score += gained;
        correctCount += 1;
        // Battle pass : jetons doublés (droit lu côté serveur, jamais
        // depuis le client). Le portefeuille local converge par merge max.
        const pass = await isPassActive(tx, uid);
        tx.set(
          db.doc(`users/${uid}`),
          { tokens: FieldValue.increment(pass ? TOKEN_AWARD * 2 : TOKEN_AWARD) },
          { merge: true }
        );
      } else {
        streak = 0;
      }

      const answered = me.answered + 1;
      const finished = answered >= DUEL_QUESTIONS;
      const updated: DuelPlayerState = {
        ...me,
        score,
        correct: correctCount,
        wrong: me.wrong + (correct ? 0 : 1),
        streak,
        bestStreak: Math.max(me.bestStreak, streak),
        answered,
        position: correctCount,
        totalElapsedMs: me.totalElapsedMs + elapsedMs,
        finished,
        lastSeen: now,
      };
      tx.set(
        duelRef,
        {
          players: { [uid]: updated },
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      // Fin de duel : les deux ont répondu aux 8 questions.
      const oppUid = otherUid(playerIds, uid);
      const opp = players[oppUid];
      let duelFinished = false;
      let winnerUid = (duel.winnerUid as string | null) ?? null;
      let isDraw = false;
      if (finished && opp.finished) {
        const all = { ...players, [uid]: updated };
        const d = decideWinner(uid, all[uid], oppUid, all[oppUid]);
        winnerUid = d.winnerUid;
        isDraw = d.isDraw;
        duelFinished = true;
        tx.set(
          duelRef,
          {
            status: "finished",
            winnerUid,
            isDraw,
            finishReason: "completed",
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
        // Classements (serveur uniquement).
        await applyLeaderboardTx(tx, uid, {
          score: all[uid].score,
          won: winnerUid === uid,
        });
        await applyLeaderboardTx(tx, oppUid, {
          score: all[oppUid].score,
          won: winnerUid === oppUid,
        });
      }
      return {
        correct,
        gained,
        score,
        position: correctCount,
        answered,
        finished,
        duelFinished,
        winnerUid,
        isDraw,
      };
    });
  }
);

// ---------------------------------------------------------------------------
// usePower : freeze (gel 5 s), double (gains x2 pendant 20 s), steal (10 jetons).
// ---------------------------------------------------------------------------
export const usePower = onCall(
  { maxInstances: 10, timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Connexion requise.");
    }
    const uid = request.auth.uid;
    const duelId = request.data?.duelId as string | undefined;
    const power = request.data?.power as string | undefined;
    const cost = power ? POWER_COST[power] : undefined;
    if (!duelId || cost === undefined) {
      throw new HttpsError("invalid-argument", "Pouvoir invalide.");
    }

    const db = getFirestore();
    return db.runTransaction(async (tx) => {
      const duelRef = db.doc(`duels/${duelId}`);
      const duelSnap = await tx.get(duelRef);
      if (!duelSnap.exists) {
        throw new HttpsError("not-found", "Duel introuvable.");
      }
      const duel = duelSnap.data() as Record<string, unknown>;
      if (duel.status !== "running") {
        throw new HttpsError("failed-precondition", "Duel terminé.");
      }
      const playerIds = duel.playerIds as string[];
      if (!playerIds.includes(uid)) {
        throw new HttpsError("permission-denied", "Pas ton duel.");
      }
      const userRef = db.doc(`users/${uid}`);
      const userSnap = await tx.get(userRef);
      const wallet = ((userSnap.data()?.tokens as number | undefined) ?? 0);
      if (wallet < cost) {
        throw new HttpsError(
          "failed-precondition",
          "Pas assez de jetons."
        );
      }

      const players = duel.players as Record<string, DuelPlayerState>;
      const now = Date.now();
      const oppUid = otherUid(playerIds, uid);
      let effect: Record<string, unknown> = {};

      if (power === "freeze") {
        if (now < players[oppUid].frozenUntil) {
          throw new HttpsError("failed-precondition", "Déjà gelé !");
        }
        const until = now + FREEZE_MS;
        tx.set(
          duelRef,
          { players: { [oppUid]: { frozenUntil: until } } },
          { merge: true }
        );
        effect = { frozenUntil: until };
      } else if (power === "double") {
        if (now < players[uid].doubleUntil) {
          throw new HttpsError("failed-precondition", "Déjà doublé !");
        }
        const until = now + DOUBLE_MS;
        tx.set(
          duelRef,
          { players: { [uid]: { doubleUntil: until } } },
          { merge: true }
        );
        effect = { doubleUntil: until };
      } else {
        // steal
        const oppRef = db.doc(`users/${oppUid}`);
        const oppSnap = await tx.get(oppRef);
        const oppWallet = ((oppSnap.data()?.tokens as number | undefined) ?? 0);
        if (oppWallet < STEAL_AMOUNT) {
          throw new HttpsError(
            "failed-precondition",
            "L'adversaire n'a pas assez de jetons."
          );
        }
        tx.set(
          oppRef,
          { tokens: FieldValue.increment(-STEAL_AMOUNT) },
          { merge: true }
        );
        tx.set(
          userRef,
          { tokens: FieldValue.increment(STEAL_AMOUNT) },
          { merge: true }
        );
        effect = { stolen: STEAL_AMOUNT };
      }

      tx.set(
        userRef,
        { tokens: FieldValue.increment(-cost) },
        { merge: true }
      );
      tx.set(
        duelRef,
        {
          players: { [uid]: { lastSeen: now } },
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      return { power, wallet: wallet - cost, ...effect };
    });
  }
);

// ---------------------------------------------------------------------------
// claimForfeit : victoire par forfait si l'adversaire est silencieux depuis 30 s.
// ---------------------------------------------------------------------------
export const claimForfeit = onCall(
  { maxInstances: 5, timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Connexion requise.");
    }
    const uid = request.auth.uid;
    const duelId = request.data?.duelId as string | undefined;
    if (!duelId) {
      throw new HttpsError("invalid-argument", "Duel manquant.");
    }
    const db = getFirestore();
    const duelRef = db.doc(`duels/${duelId}`);
    const snap = await duelRef.get();
    if (!snap.exists) {
      throw new HttpsError("not-found", "Duel introuvable.");
    }
    const duel = snap.data() as Record<string, unknown>;
    if (duel.status !== "running") {
      return { alreadyFinished: true, winnerUid: duel.winnerUid ?? null };
    }
    const playerIds = duel.playerIds as string[];
    if (!playerIds.includes(uid)) {
      throw new HttpsError("permission-denied", "Pas ton duel.");
    }
    const players = duel.players as Record<string, DuelPlayerState>;
    const oppUid = otherUid(playerIds, uid);
    const silentFor = Date.now() - (players[oppUid].lastSeen ?? 0);
    if (silentFor < FORFEIT_GRACE_MS) {
      throw new HttpsError(
        "failed-precondition",
        "L'adversaire est encore en jeu."
      );
    }
    await duelRef.set(
      {
        players: { [uid]: { finished: true } },
        status: "finished",
        winnerUid: uid,
        isDraw: false,
        finishReason: "forfeit",
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    await applyLeaderboardDirect(uid, {
      score: players[uid]?.score ?? 0,
      won: true,
    });
    await applyLeaderboardDirect(oppUid, {
      score: players[oppUid]?.score ?? 0,
      won: false,
    });
    return { winnerUid: uid, finishReason: "forfeit" };
  }
);

// ---------------------------------------------------------------------------
// rematchDuel : revanche — crée un nouveau duel quand les deux sont OK.
// ---------------------------------------------------------------------------
export const rematchDuel = onCall(
  { maxInstances: 5, timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Connexion requise.");
    }
    const uid = request.auth.uid;
    const duelId = request.data?.duelId as string | undefined;
    if (!duelId) {
      throw new HttpsError("invalid-argument", "Duel manquant.");
    }
    const db = getFirestore();

    try {
      return await db.runTransaction(async (tx) => {
        const duelRef = db.doc(`duels/${duelId}`);
        const snap = await tx.get(duelRef);
        if (!snap.exists) {
          throw new HttpsError("not-found", "Duel introuvable.");
        }
        const duel = snap.data() as Record<string, unknown>;
        if (duel.status !== "finished") {
          throw new HttpsError("failed-precondition", "Duel non terminé.");
        }
        const playerIds = duel.playerIds as string[];
        if (!playerIds.includes(uid)) {
          throw new HttpsError("permission-denied", "Pas ton duel.");
        }
        if (duel.rematchDuelId) {
          return {
            status: "matched",
            duelId: duel.rematchDuelId as string,
          };
        }
        const requested = new Set([
          ...((duel.rematchRequests as string[] | undefined) ?? []),
          uid,
        ]);
        if (!playerIds.every((id) => requested.has(id))) {
          tx.set(
            duelRef,
            { rematchRequests: [...requested] },
            { merge: true }
          );
          return { status: "waiting" };
        }
        // Les deux veulent rejouer : nouveau duel à id déterministe
        // (anti-doublon si les deux appels se croisent).
        const players = duel.players as Record<string, DuelPlayerState>;
        const [a, b] = playerIds;
        const freshRef = db.doc(`duels/rematch_${duelId}`);
        tx.create(
          freshRef,
          buildDuelData(a, players[a].lang, b, players[b].lang)
        );
        tx.set(freshRef.collection("secret").doc("answers"), buildSecretData());
        tx.set(
          duelRef,
          {
            rematchRequests: [...requested],
            rematchDuelId: freshRef.id,
          },
          { merge: true }
        );
        return { status: "matched", duelId: freshRef.id };
      });
    } catch (e) {
      // Doublon de création (les deux ont cliqué ensemble) : le duel existe,
      // on renvoie son id déterministe.
      if (e instanceof HttpsError) throw e;
      const code = (e as { code?: number }).code;
      if (code === 6) {
        const snap = await db.doc(`duels/${duelId}`).get();
        const existing = snap.data()?.rematchDuelId as string | undefined;
        if (existing) return { status: "matched", duelId: existing };
      }
      throw new HttpsError("internal", "Revanche impossible, réessaie.");
    }
  }
);

export { Timestamp };
