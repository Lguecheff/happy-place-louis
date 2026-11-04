/**
 * Rédaction d'une actu par l'IA (US27) : constantes, textes et types partagés
 * entre le formulaire et la future fonction côté serveur (phase 2).
 * Seuls la consigne et le ton partent vers le service d'IA.
 */

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
} as const;

export type AiDraft = { title: string; body: string };

/** Réponse de la génération : un brouillon, ou la raison de l'échec. */
export type AiResult =
  ({ ok: true } & AiDraft) | { ok: false; reason: "error" | "limit" | "forbidden" };

/** Appel au service, côté serveur. `signal` s'arrête au délai dépassé ou à l'annulation. */
export type AiGenerate = (
  input: { prompt: string; tone: AiTone },
  signal: AbortSignal,
) => Promise<AiResult>;

export function aiPromptError(prompt: string): string | undefined {
  return prompt.trim().length < AI_PROMPT_MIN ? AI_MESSAGES.tooShort : undefined;
}
