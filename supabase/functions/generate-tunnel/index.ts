// ============================================================================
// QuizRail — Edge Function "generate-tunnel" (Supabase, offre gratuite).
// Génère 9 questions (3 par difficulté) via Gemini (repli OpenAI).
// Les clés restent dans les secrets du projet, jamais côté client.
//
// Déploiement :
//   supabase login
//   supabase link --project-ref TON_PROJECT_REF
//   supabase secrets set GEMINI_API_KEY=ta_cle  (aistudio.google.com, gratuit)
//   supabase secrets set OPENAI_API_KEY=ta_cle   (optionnel, repli)
//   supabase functions deploy generate-tunnel
// ============================================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const GEMINI_MODEL = "gemini-2.0-flash";
const OPENAI_MODEL = "gpt-4o-mini";
const MAX_PER_DAY = 5;

type Difficulty = "easy" | "medium" | "hard";

interface GeneratedQuestion {
  prompt: string;
  answer: string;
  difficulty: Difficulty;
}

function isDifficulty(v: unknown): v is Difficulty {
  return v === "easy" || v === "medium" || v === "hard";
}

function validateQuestions(raw: unknown): GeneratedQuestion[] {
  if (!Array.isArray(raw) || raw.length !== 9) throw new Error("bad-format");
  const questions = (raw as Array<Record<string, unknown>>).map((q) => {
    if (
      typeof q.prompt !== "string" || q.prompt.trim() === "" ||
      typeof q.answer !== "string" || q.answer.trim() === "" ||
      !isDifficulty(q.difficulty)
    ) {
      throw new Error("bad-format");
    }
    return {
      prompt: q.prompt.trim(),
      answer: q.answer.trim(),
      difficulty: q.difficulty,
    };
  });
  for (const d of ["easy", "medium", "hard"] as const) {
    if (questions.filter((q) => q.difficulty === d).length !== 3) {
      throw new Error("bad-split");
    }
  }
  return questions;
}

function buildPrompt(theme: string, lang: string): string {
  const langName = lang === "en" ? "English" : lang === "ar" ? "Arabic" : "French";
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

async function callGemini(theme: string, lang: string, key: string): Promise<string> {
  const langName = lang === "en" ? "English" : lang === "ar" ? "Arabic" : "French";
  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${key}`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: buildPrompt(theme, lang) }] },
        contents: [{ role: "user", parts: [{ text: `Theme: "${theme}" in ${langName}.` }] }],
        generationConfig: { responseMimeType: "application/json", maxOutputTokens: 2000, temperature: 0.7 },
      }),
    },
  );
  if (!res.ok) throw new Error(`gemini-${res.status}`);
  const body = (await res.json()) as {
    candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
  };
  const text = (body.candidates ?? [])
    .flatMap((c) => c.content?.parts ?? [])
    .map((p) => p.text ?? "")
    .join("");
  if (!text) throw new Error("empty");
  return text;
}

async function callOpenAI(theme: string, lang: string, key: string): Promise<string> {
  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${key}` },
    body: JSON.stringify({
      model: OPENAI_MODEL,
      messages: [
        { role: "system", content: buildPrompt(theme, lang) },
        { role: "user", content: `Theme: "${theme}".` },
      ],
      response_format: { type: "json_object" },
      max_tokens: 2000,
      temperature: 0.7,
    }),
  });
  if (!res.ok) throw new Error(`openai-${res.status}`);
  const body = (await res.json()) as {
    choices?: Array<{ message?: { content?: string } }>;
  };
  const text = body.choices?.[0]?.message?.content ?? "";
  if (!text) throw new Error("empty");
  return text;
}

function json(status: number, data: unknown): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "POST requis." });
  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const authHeader = req.headers.get("Authorization") ?? "";

    // Utilisateur authentifié (JWT du client).
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData.user) return json(401, { error: "Connexion requise." });
    const uid = userData.user.id;

    const body = (await req.json()) as { theme?: unknown; lang?: unknown };
    const theme = typeof body.theme === "string" ? body.theme.trim() : "";
    const lang = body.lang === "en" ? "en" : body.lang === "ar" ? "ar" : "fr";
    if (theme.length < 2 || theme.length > 80) {
      return json(400, { error: "Le thème doit faire entre 2 et 80 caractères." });
    }

    // Quota anti-abus : 5 générations / jour / utilisateur.
    const admin = createClient(supabaseUrl, serviceKey);
    const today = new Date().toISOString().slice(0, 10);
    const { data: quota } = await admin
      .from("ai_quotas")
      .select("count")
      .eq("uid", uid)
      .eq("day", today)
      .maybeSingle();
    if ((quota?.count as number | undefined ?? 0) >= MAX_PER_DAY) {
      return json(429, { error: "Quota IA du jour atteint (5 générations)." });
    }

    const geminiKey = Deno.env.get("GEMINI_API_KEY") ?? "";
    const openaiKey = Deno.env.get("OPENAI_API_KEY") ?? "";
    if (!geminiKey && !openaiKey) {
      return json(500, { error: "Clé API IA non configurée." });
    }

    let text: string | null = null;
    if (geminiKey) {
      try {
        text = await callGemini(theme, lang, geminiKey);
      } catch {
        text = null;
      }
    }
    if (text == null && openaiKey) {
      try {
        text = await callOpenAI(theme, lang, openaiKey);
      } catch {
        text = null;
      }
    }
    if (text == null || text.trim() === "") {
      return json(502, { error: "La génération IA a échoué, réessaie." });
    }

    let questions: GeneratedQuestion[];
    try {
      const cleaned = text.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "").trim();
      const parsed = JSON.parse(cleaned) as { questions?: unknown };
      questions = validateQuestions(parsed.questions);
    } catch {
      return json(502, { error: "L'IA a renvoyé un format invalide." });
    }

    await admin.from("ai_quotas").upsert(
      { uid, day: today, count: (quota?.count as number | undefined ?? 0) + 1 },
      { onConflict: "uid,day" },
    );
    return json(200, { questions });
  } catch {
    return json(500, { error: "La génération IA a échoué, réessaie." });
  }
});
