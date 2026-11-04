/**
 * Rédaction d'une actu par l'IA (US27) : constantes, textes, types et appel à la
 * fonction supabase/functions/ai-writer (qui garde ses propres copies des limites).
 * Seuls la consigne et le ton partent vers le service d'IA.
 */
import { supabase } from "@/integrations/supabase/client";

export const AI_PROMPT_MIN = 10;
export const AI_PROMPT_MAX = 500;
export const AI_TITLE_MAX = 80;
export const AI_BODY_MAX = 1200;
/** Au-delà, l'appel est abandonné et l'erreur s'affiche. */
export const AI_TIMEOUT_MS = 20_000;
/** Générations par utilisateur et par jour, partagées avec l'US28. */
export const AI_DAILY_LIMIT = 20;

export type AiTone = "informatif" | "chaleureux" | "court";

export const AI_TONES: { value: AiTone; label: string }[] = [
  { value: "informatif", label: "Informatif" },
  { value: "chaleureux", label: "Chaleureux" },
  { value: "court", label: "Court" },
];

export const AI_MESSAGES = {
  privacy: "N'écris pas de données personnelles.",
  review: "Texte proposé par l'IA, relis-le avant de publier.",
  error: "L'IA n'a pas pu répondre. Réessaie ou rédige toi-même.",
  limit: "Tu as atteint la limite du jour. Reviens demain.",
  loading: "L'IA rédige ton texte…",
  tooShort: `Écris au moins ${AI_PROMPT_MIN} caractères.`,
  personal: "Retire l'adresse email ou le numéro de téléphone de ta consigne.",
} as const;

export type AiDraft = { title: string; body: string };

/** Réponse de la génération : un brouillon, ou la raison de l'échec. */
export type AiResult =
  ({ ok: true } & AiDraft) | { ok: false; reason: "error" | "limit" | "forbidden" | "personal" };

/** Appel au service, côté serveur. `signal` s'arrête au délai dépassé ou à l'annulation. */
export type AiGenerate = (
  input: { prompt: string; tone: AiTone },
  signal: AbortSignal,
) => Promise<AiResult>;

// ---------------------------------------------------------------------------
// Amélioration d'un texte écrit par l'auteur (US28), même fonction ai-writer,
// avec un paramètre d'action. Même limite partagée de 20 par jour.
// ---------------------------------------------------------------------------

export type AiImproveAction = "corriger" | "clarifier" | "raccourcir" | "rechauffer";

export const AI_IMPROVE_ACTIONS: {
  value: AiImproveAction;
  label: string;
  icon: string;
  /** « Corriger les fautes » touche aussi le titre ; les autres, le texte seulement. */
  withTitle: boolean;
}[] = [
  { value: "corriger", label: "Corriger les fautes", icon: "spellcheck", withTitle: true },
  { value: "clarifier", label: "Rendre plus clair", icon: "lightbulb", withTitle: false },
  { value: "raccourcir", label: "Raccourcir", icon: "short_text", withTitle: false },
  { value: "rechauffer", label: "Rendre plus chaleureux", icon: "favorite", withTitle: false },
];

export const AI_IMPROVE_MESSAGES = {
  privacy: "Le texte de ton actu est envoyé au service d'IA. Évite les données personnelles.",
  loading: "L'IA améliore ton texte…",
  replaced: "Texte remplacé par la proposition de l'IA.",
  unchanged: "L'IA n'a rien trouvé à changer.",
} as const;

/** Durée pendant laquelle « Annuler le remplacement » reste possible. */
export const AI_UNDO_MS = 10_000;

/** Le titre n'est renvoyé que pour « Corriger les fautes ». */
export type AiImproveResult =
  | { ok: true; title?: string; body: string }
  | { ok: false; reason: "error" | "limit" | "forbidden" | "personal" };

export type AiImprove = (
  input: { action: AiImproveAction; title: string; body: string },
  signal: AbortSignal,
) => Promise<AiImproveResult>;

/** Mêmes règles que la fonction ai-writer, qui refuse aussi la consigne côté serveur. */
const EMAIL = /[^\s@]+@[^\s@]+\.[^\s@]+/;
const PHONE = /(?:(?:\+|00)\d{2,3}[\s.-]?|\b0)[1-9](?:[\s.-]?\d{2}){4}\b/;

export function hasPersonalData(prompt: string) {
  return EMAIL.test(prompt) || PHONE.test(prompt);
}

export function aiPromptError(prompt: string): string | undefined {
  if (prompt.trim().length < AI_PROMPT_MIN) return AI_MESSAGES.tooShort;
  if (hasPersonalData(prompt)) return AI_MESSAGES.personal;
  return undefined;
}

/**
 * Appelle la fonction ai-writer avec le jeton de la session. Seuls la consigne et le ton
 * partent ; la clé du service d'IA reste sur le serveur.
 */
export const generateNewsWithAi: AiGenerate = async ({ prompt, tone }, signal) => {
  const { data, error } = await supabase.functions.invoke("ai-writer", {
    body: { prompt, tone },
    signal,
  });
  if (!error) {
    const ok = data?.ok && typeof data.title === "string" && typeof data.body === "string";
    return ok ? { ok: true, title: data.title, body: data.body } : { ok: false, reason: "error" };
  }
  const reason = await readReason(error);
  return { ok: false, reason };
};

async function readReason(error: unknown): Promise<"error" | "limit" | "forbidden" | "personal"> {
  const response = (error as { context?: unknown }).context;
  if (!(response instanceof Response)) return "error";
  try {
    const body = await response.json();
    const reason = body?.reason;
    return reason === "limit" || reason === "forbidden" || reason === "personal" ? reason : "error";
  } catch {
    return "error";
  }
}

/**
 * US28 : appelle la même fonction ai-writer avec une action. Seuls le texte, et le titre
 * pour « Corriger les fautes », partent vers le service d'IA.
 */
export const improveNewsWithAi: AiImprove = async ({ action, title, body }, signal) => {
  const withTitle = AI_IMPROVE_ACTIONS.find((a) => a.value === action)?.withTitle;
  const { data, error } = await supabase.functions.invoke("ai-writer", {
    body: withTitle ? { action, title, body } : { action, body },
    signal,
  });
  if (!error) {
    if (!data?.ok || typeof data.body !== "string") return { ok: false, reason: "error" };
    return {
      ok: true,
      body: data.body,
      ...(withTitle && typeof data.title === "string" && { title: data.title }),
    };
  }
  return { ok: false, reason: await readReason(error) };
};
