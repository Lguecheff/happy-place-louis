// Rédaction d'une actu par l'IA (US27) et amélioration d'un texte écrit par l'auteur (US28,
// paramètre `action`). Seule fonction qui parle au service d'IA (OpenAI).
// US28 : seuls le texte (et le titre pour « corriger ») partent ; pas de filtre email /
// téléphone, l'interface avertit l'auteur. Même rôle et même limite partagée (ai_usage).
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
/** Limites d'une actu (newsContentSchema) : le texte à améliorer peut être plus long qu'une génération. */
const NEWS_TITLE_MAX = 160;
const NEWS_BODY_MAX = 5000;
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

/** US28 : consigne de chaque action. Seul « corriger » touche le titre. */
const ACTIONS: Record<string, { rule: string; withTitle: boolean }> = {
  corriger: {
    rule: "Corrige uniquement l'orthographe, la grammaire, la conjugaison et la ponctuation. Ne change ni le sens, ni le ton, ni la structure, ni les mots justes.",
    withTitle: true,
  },
  clarifier: {
    rule: "Rends le texte plus clair : phrases plus courtes, ordre logique, mots simples. Garde toutes les informations et le ton.",
    withTitle: false,
  },
  raccourcir: {
    rule: "Raccourcis le texte d'environ la moitié en gardant les informations essentielles (dates, lieux, actions demandées).",
    withTitle: false,
  },
  rechauffer: {
    rule: "Rends le texte plus chaleureux et convivial, sans excès ni emoji. Garde toutes les informations.",
    withTitle: false,
  },
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

function improvePrompt(action: string) {
  const { rule, withTitle } = ACTIONS[action];
  return [
    "Tu améliores une actualité interne écrite par un manager d'un cabinet de recrutement.",
    rule,
    "Écris en français. Garde le tutoiement s'il y en a ; n'introduis jamais « vous ».",
    "N'ajoute aucune information, aucun nom, aucun chiffre ni aucune date. Garde les repères entre crochets tels quels.",
    "Garde les paragraphes séparés par une ligne vide.",
    withTitle
      ? `Réponds uniquement en JSON : {"title": "...", "body": "..."}. Le titre fait ${NEWS_TITLE_MAX} caractères au maximum.`
      : 'Réponds uniquement en JSON : {"body": "..."}.',
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

type AiRequest = { system: string; user: string; temperature: number; tokens: number };
type Answer = { title: string; body: string };

async function callModel(model: string, key: string, req: AiRequest, signal: AbortSignal) {
  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    signal,
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model,
      temperature: req.temperature,
      max_completion_tokens: req.tokens,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: req.system },
        { role: "user", content: req.user },
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
  return JSON.parse(data?.choices?.[0]?.message?.content ?? "{}") as Record<string, unknown>;
}

/** Modèle absent du compte : on passe au suivant. Toute autre erreur s'arrête là. */
const isMissingModel = (e: unknown) =>
  e instanceof AiError && (e.code === "model_not_found" || e.status === 404);

async function callAi(req: AiRequest) {
  const key = Deno.env.get("OPEN_AI_KEY");
  if (!key) throw new Error("OPEN_AI_KEY manquant");
  const signal = AbortSignal.timeout(AI_TIMEOUT_MS);
  for (const [i, model] of MODELS.entries()) {
    try {
      return await callModel(model, key, req, signal);
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

  let input: Record<string, unknown> = {};
  try {
    input = (await req.json()) ?? {};
  } catch {
    return fail(400, "invalid");
  }
  const str = (v: unknown) => (typeof v === "string" ? v : "");
  const action = str(input.action);

  // Ce qui part vers le service d'IA, et comment lire sa réponse.
  let request: AiRequest;
  let read: (parsed: Record<string, unknown>) => Answer | { body: string } | null;
  if (action) {
    // US28 : amélioration du texte de l'auteur.
    if (!(action in ACTIONS)) return fail(400, "invalid");
    const { withTitle } = ACTIONS[action];
    const title = str(input.title).trim();
    const text = str(input.body).trim();
    if (!text || text.length > NEWS_BODY_MAX || title.length > NEWS_TITLE_MAX) {
      return fail(400, "invalid");
    }
    request = {
      system: improvePrompt(action),
      user: JSON.stringify(withTitle ? { title, body: text } : { body: text }),
      temperature: action === "corriger" ? 0.1 : 0.5,
      tokens: 3000,
    };
    read = (parsed) => {
      const body = clip(parsed.body, NEWS_BODY_MAX);
      if (!body) return null;
      if (!withTitle) return { body };
      return { title: clip(parsed.title, NEWS_TITLE_MAX) || title, body };
    };
  } else {
    // US27 : génération à partir d'une consigne.
    const prompt = str(input.prompt).trim();
    const tone = str(input.tone);
    if (prompt.length < PROMPT_MIN || prompt.length > PROMPT_MAX || !(tone in TONES)) {
      return fail(400, "invalid");
    }
    // Rien ne part vers le service d'IA si la consigne contient un email ou un numéro de téléphone.
    if (EMAIL.test(prompt) || PHONE.test(prompt)) return fail(400, "personal");
    request = { system: systemPrompt(tone), user: prompt, temperature: 0.7, tokens: 800 };
    read = (parsed) => {
      const title = clip(parsed.title, TITLE_MAX);
      const body = clip(parsed.body, BODY_MAX);
      return title && body ? { title, body } : null;
    };
  }

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
    const answer = read(await callAi(request));
    if (!answer) throw new Error("Réponse incomplète");
    return reply(200, { ok: true, ...answer, remaining: usage?.remaining ?? 0 });
  } catch (e) {
    // Ni la consigne ni le texte ne sont journalisés.
    console.error("openai", e instanceof Error ? e.message : "erreur");
    await admin.rpc("ai_usage_refund", { _user_id: auth.user.id });
    return fail(502, "error");
  }
});
