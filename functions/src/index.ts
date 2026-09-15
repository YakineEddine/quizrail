import { initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";

initializeApp();

// Clé API Claude — Secret Manager uniquement, jamais côté client.
// Création : firebase functions:secrets:set CLAUDE_API_KEY
const claudeApiKey = defineSecret("CLAUDE_API_KEY");

// Modèle économe : un tunnel = ~1 500 tokens in / ~1 200 out ≈ 0,008 $.
const CLAUDE_MODEL = "claude-haiku-4-5-20251001";
const MAX_GENERATIONS_PER_DAY = 5;

type Difficulty = "easy" | "medium" | "hard";

interface GeneratedQuestion {
  prompt: string;
  answer: string;
  difficulty: Difficulty;
}

function isDifficulty(v: unknown): v is Difficulty {
  return v === "easy" || v === "medium" || v === "hard";
}

/** Valide le contrat Phase 1 : 9 questions, 3 par difficulté, réponses non vides. */
function validateQuestions(raw: unknown): GeneratedQuestion[] {
  if (!Array.isArray(raw) || raw.length !== 9) {
    throw new HttpsError("internal", "L'IA a renvoyé un format invalide.");
  }
  const questions = raw.map((q) => {
    const o = q as Record<string, unknown>;
    if (
      typeof o.prompt !== "string" ||
      o.prompt.trim() === "" ||
      typeof o.answer !== "string" ||
      o.answer.trim() === "" ||
      !isDifficulty(o.difficulty)
    ) {
      throw new HttpsError("internal", "L'IA a renvoyé un format invalide.");
    }
    return {
      prompt: o.prompt.trim(),
      answer: o.answer.trim(),
      difficulty: o.difficulty,
    };
  });
  for (const d of ["easy", "medium", "hard"] as const) {
    if (questions.filter((q) => q.difficulty === d).length !== 3) {
      throw new HttpsError(
        "internal",
        "L'IA n'a pas renvoyé 3 questions par difficulté."
      );
    }
  }
  return questions;
}

function buildPrompt(theme: string, lang: string): string {
  const langName =
    lang === "en" ? "English" : lang === "ar" ? "Arabic" : "French";
  return [
    `Generate a quiz tunnel about "${theme}" in ${langName}.`,
    "Return ONLY valid JSON (no markdown, no code fences) with this shape:",
    '{"questions":[{"prompt":"...","answer":"...","difficulty":"easy|medium|hard"}]}',
    "Rules: exactly 9 questions — 3 easy, 3 medium, 3 hard.",
    "Each answer must be short and exact (one word, name or number) so it can be",
    "checked against the player's free-text answer (case-insensitive).",
    "Questions must be varied, factual and family-friendly.",
  ].join("\n");
}

/**
 * Génère un tunnel (9 questions) via l'API Claude.
 * Callable authentifié : la clé API reste dans Secret Manager.
 * args: { theme: string, lang?: "fr"|"en"|"ar" }
 * returns: { questions: [{ prompt, answer, difficulty }] }
 */
export const generateTunnel = onCall(
  {
    secrets: [claudeApiKey],
    maxInstances: 5,
    timeoutSeconds: 120,
    memory: "256MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Connexion requise.");
    }
    const uid = request.auth.uid;
    const theme = (request.data?.theme as string | undefined)?.trim() ?? "";
    const lang = (request.data?.lang as string | undefined) ?? "fr";
    if (theme.length < 2 || theme.length > 80) {
      throw new HttpsError(
        "invalid-argument",
        "Le thème doit faire entre 2 et 80 caractères."
      );
    }
    if (!["fr", "en", "ar"].includes(lang)) {
      throw new HttpsError("invalid-argument", "Langue non supportée.");
    }

    // Quota anti-abus : 5 générations / jour / utilisateur.
    const db = getFirestore();
    const userRef = db.doc(`users/${uid}`);
    const today = new Date().toISOString().slice(0, 10);
    const quotaRef = userRef.collection("quotas").doc(`generateTunnel-${today}`);
    const quotaSnap = await quotaRef.get();
    const used = (quotaSnap.data()?.count as number | undefined) ?? 0;
    if (used >= MAX_GENERATIONS_PER_DAY) {
      throw new HttpsError(
        "resource-exhausted",
        "Quota IA du jour atteint (5 générations)."
      );
    }

    const apiKey = claudeApiKey.value();
    if (!apiKey) {
      throw new HttpsError("failed-precondition", "Clé API IA non configurée.");
    }

    let text: string;
    try {
      const res = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-api-key": apiKey,
          "anthropic-version": "2023-06-01",
        },
        body: JSON.stringify({
          model: CLAUDE_MODEL,
          max_tokens: 2000,
          messages: [{ role: "user", content: buildPrompt(theme, lang) }],
        }),
      });
      if (!res.ok) {
        throw new Error(`Claude API: ${res.status}`);
      }
      const body = (await res.json()) as {
        content?: Array<{ type?: string; text?: string }>;
      };
      text =
        body.content
          ?.filter((b) => b.type === "text" && typeof b.text === "string")
          .map((b) => b.text as string)
          .join("") ?? "";
      if (!text) throw new Error("Réponse IA vide.");
    } catch (e) {
      throw new HttpsError(
        "internal",
        "La génération IA a échoué, réessaie.",
        e instanceof Error ? e.message : undefined
      );
    }

    // Tolère les fences ```json ... ``` si le modèle en ajoute.
    const jsonText = text
      .replace(/^```(?:json)?\s*/i, "")
      .replace(/\s*```$/, "")
      .trim();
    let parsed: unknown;
    try {
      parsed = JSON.parse(jsonText);
    } catch {
      throw new HttpsError("internal", "L'IA a renvoyé un format invalide.");
    }
    const questions = validateQuestions(
      (parsed as { questions?: unknown }).questions
    );

    await quotaRef.set(
      { count: used + 1, updatedAt: FieldValue.serverTimestamp() },
      { merge: true }
    );
    return { questions };
  }
);
