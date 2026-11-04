// Rédaction d'une actu par l'IA (US27). Seule fonction qui parle au service d'IA (OpenAI).
// 1. vérifie le jeton de l'utilisateur ; 2. vérifie la consigne (longueur, ton, pas d'email
// ni de téléphone) ; 3. vérifie le rôle et compte la génération (ai_usage_consume) ;
// 4. appelle OpenAI avec la consigne et le ton seulement ; 5. rend la génération si OpenAI échoue.
// Secrets : OPEN_AI_KEY (clé OpenAI, créée par Louis), OPENAI_MODEL (facultatif), SUPABASE_URL et
// SUPABASE_SERVICE_ROLE_KEY (fournis par Supabase). Aucune clé ne part vers le navigateur.
// Mistral a été abandonné le 2026-11-04 : son plan Free refusait tous les appels (429).
// Constantes en double de src/lib/news-ai.ts : la fonction est déployée seule.
import { createClient } from "jsr:@supabase/supabase-js@2";

const PROMPT_MIN = 10;
const PROMPT_MAX = 500;
const TITLE_MAX = 80;
const BODY_MAX = 1200;
/** Sous les 20 s du navigateur, pour pouvoir rendre la génération avant qu'il abandonne. */
const AI_TIMEOUT_MS = 18_000;
/** Modèle choisi par le secret OPENAI_MODEL ; sinon, le premier de la liste qui existe sur le compte. */
const MODELS = [Deno.env.get("OPENAI_MODEL"), "gpt-4.1-mini", "gpt-4o-mini"].filter(
  (m): m is string => !!m,
);

const TONES: Record<string, string> = {
  informatif: "informatif : clair, factuel, sans emphase",
  chaleureux: "chaleureux : convivial et positif, sans excès",
  court: "court : trois phrases au maximum",
};

const EMAIL = /[^\s@]+@[^\s@]+\.[^\s@]+/;
const PHONE = /(?:(?:\+|00)\d{2,3}[\s.-]?|\b0)[1-9](?:[\s.-]?\d{2}){4}\b/;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type Reason = "error" | "limit" | "forbidden" | "personal" | "invalid" | "unauthorized";

function reply(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

const fail = (status: number, reason: Reason) => reply(status, { ok: false, reason });

function systemPrompt(tone: string) {
  return [
    "Tu rédiges une actualité interne pour les collaborateurs d'un cabinet de recrutement.",
    "Écris en français, sans jargon. Tutoie le lecteur (« tu », « ton », « tes ») : n'écris jamais « vous » ni « votre ».",
    `Ton : ${TONES[tone]}.`,
    `Le titre fait ${TITLE_MAX} caractères au maximum. Le texte fait ${BODY_MAX} caractères au maximum, en paragraphes courts séparés par une ligne vide.`,
    "N'invente aucune donnée sur des personnes (nom, prénom, poste, chiffre, date, lieu) : mets à la place un repère entre crochets, comme [prénom], [date] ou [équipe].",
    'Réponds uniquement en JSON : {"title": "...", "body": "..."}.',
  ].join("\n");
}

function clip(value: unknown, max: number) {
  const text = typeof value === "string" ? value.trim() : "";
  return text.length > max ? `${text.slice(0, max - 1).trimEnd()}…` : text;
}

class AiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    detail: string,
  ) {
    super(`OpenAI ${status}${detail ? ` : ${detail}` : ""}`);
  }
}

async function callModel(
  model: string,
  key: string,
  prompt: string,
  tone: string,
  signal: AbortSignal,
) {
  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    signal,
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model,
      temperature: 0.7,
      max_completion_tokens: 800,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: systemPrompt(tone) },
        { role: "user", content: prompt },
      ],
    }),
  });
  if (!res.ok) {
    // Le message d'erreur d'OpenAI ne contient ni la clé ni la consigne.
    const text = await res.text().catch(() => "");
    let code = "";
    try {
      code = JSON.parse(text)?.error?.code ?? "";
    } catch {
      // réponse non JSON
    }
    throw new AiError(res.status, code, `${model} ${text.slice(0, 300)}`);
  }
  const data = await res.json();
  const parsed = JSON.parse(data?.choices?.[0]?.message?.content ?? "{}");
  const title = clip(parsed.title, TITLE_MAX);
  const body = clip(parsed.body, BODY_MAX);
  if (!title || !body) throw new Error(`Réponse incomplète (${model})`);
  return { title, body };
}

/** Modèle absent du compte : on passe au suivant. Toute autre erreur s'arrête là. */
const isMissingModel = (e: unknown) =>
  e instanceof AiError && (e.code === "model_not_found" || e.status === 404);

async function callAi(prompt: string, tone: string) {
  const key = Deno.env.get("OPEN_AI_KEY");
  if (!key) throw new Error("OPEN_AI_KEY manquant");
  const signal = AbortSignal.timeout(AI_TIMEOUT_MS);
  for (const [i, model] of MODELS.entries()) {
    try {
      return await callModel(model, key, prompt, tone, signal);
    } catch (e) {
      if (i === MODELS.length - 1 || !isMissingModel(e)) throw e;
      console.error("openai", (e as Error).message);
    }
  }
  throw new Error("Aucun modèle disponible");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return fail(405, "invalid");

  const url = Deno.env.get("SUPABASE_URL")!;
  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
  if (!token) return fail(401, "unauthorized");
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
  const { data: auth, error: authError } = await admin.auth.getUser(token);
  if (authError || !auth.user?.email) return fail(401, "unauthorized");

  let prompt = "";
  let tone = "";
  try {
    const body = await req.json();
    prompt = typeof body?.prompt === "string" ? body.prompt.trim() : "";
    tone = typeof body?.tone === "string" ? body.tone : "";
  } catch {
    return fail(400, "invalid");
  }
  if (prompt.length < PROMPT_MIN || prompt.length > PROMPT_MAX || !(tone in TONES)) {
    return fail(400, "invalid");
  }
  // Rien ne part vers le service d'IA si la consigne contient un email ou un numéro de téléphone.
  if (EMAIL.test(prompt) || PHONE.test(prompt)) return fail(400, "personal");

  const { data: usage, error: usageError } = await admin.rpc("ai_usage_consume", {
    _user_id: auth.user.id,
    _email: auth.user.email,
  });
  if (usageError) {
    console.error("ai_usage_consume", usageError.message);
    return fail(500, "error");
  }
  if (usage?.status === "forbidden") return fail(403, "forbidden");
  if (usage?.status === "limit") return fail(429, "limit");

  try {
    const draft = await callAi(prompt, tone);
    return reply(200, { ok: true, ...draft, remaining: usage?.remaining ?? 0 });
  } catch (e) {
    // Ni la consigne ni le texte ne sont journalisés.
    console.error("openai", e instanceof Error ? e.message : "erreur");
    await admin.rpc("ai_usage_refund", { _user_id: auth.user.id });
    return fail(502, "error");
  }
});
