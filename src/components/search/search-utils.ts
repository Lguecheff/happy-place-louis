import { newsPublishedAt } from "@/components/overview/overview-utils";
import type { News, Submission } from "@/lib/dashboard";

export const SEARCH_MIN_LENGTH = 3;
export const SEARCH_MAX_PER_TYPE = 20;
const EXCERPT_RADIUS = 60;

export type SearchData = { news: News[]; submissions: Submission[] };

export type SearchGroup<T> = {
  /** Nombre réel de résultats, même au-delà de la limite affichée. */
  total: number;
  items: T[];
};

export type SearchResults = {
  news: SearchGroup<News>;
  submissions: SearchGroup<Submission>;
};

export type TextPart = { text: string; match: boolean };

/** Minuscules, sans accents : la base n'a pas d'extension unaccent, tout se compare ici. */
export function normalizeText(text: string) {
  return text.normalize("NFD").replace(/\p{M}/gu, "").toLowerCase();
}

/** `true` à partir de 3 caractères, espaces de début et de fin ignorés. */
export function isSearchable(query: string) {
  return normalizeText(query.trim()).length >= SEARCH_MIN_LENGTH;
}

function contains(text: string | null | undefined, term: string) {
  return !!text && normalizeText(text).includes(term);
}

function group<T>(matches: T[], dateOf: (item: T) => string): SearchGroup<T> {
  const time = (item: T) => new Date(dateOf(item)).getTime();
  return {
    total: matches.length,
    items: [...matches].sort((a, b) => time(b) - time(a)).slice(0, SEARCH_MAX_PER_TYPE),
  };
}

/** Les données sont déjà lues sous RLS ; seules les actus publiées restent cherchables. */
export function searchAll({ news, submissions }: SearchData, query: string): SearchResults {
  const term = normalizeText(query.trim());
  return {
    news: group(
      news.filter(
        (n) => n.status === "publiée" && (contains(n.title, term) || contains(n.body, term)),
      ),
      newsPublishedAt,
    ),
    submissions: group(
      submissions.filter((s) => contains(s.content, term)),
      (s) => s.created_at,
    ),
  };
}

/** Texte normalisé et, pour chacun de ses caractères, sa position dans le texte d'origine. */
function withOffsets(text: string) {
  let normalized = "";
  const offsets: number[] = [];
  let index = 0;
  for (const char of text) {
    const part = normalizeText(char);
    normalized += part;
    for (let i = 0; i < part.length; i++) offsets.push(index);
    index += char.length;
  }
  offsets.push(index);
  return { normalized, offsets };
}

/** Occurrences du terme, en positions du texte d'origine (accents et casse conservés). */
function findMatches(text: string, term: string) {
  const { normalized, offsets } = withOffsets(text);
  const matches: { start: number; end: number }[] = [];
  let at = normalized.indexOf(term);
  while (at !== -1) {
    matches.push({ start: offsets[at], end: offsets[at + term.length] });
    at = normalized.indexOf(term, at + term.length);
  }
  return matches;
}

/** Découpe un texte autour du terme cherché, pour le surligner. */
export function highlightParts(text: string, query: string): TextPart[] {
  const parts: TextPart[] = [];
  let cursor = 0;
  for (const { start, end } of findMatches(text, normalizeText(query.trim()))) {
    if (start > cursor) parts.push({ text: text.slice(cursor, start), match: false });
    parts.push({ text: text.slice(start, end), match: true });
    cursor = end;
  }
  if (cursor < text.length) parts.push({ text: text.slice(cursor), match: false });
  return parts;
}

/** Extrait centré sur la première occurrence du terme. */
export function excerptAround(text: string, query: string) {
  const first = findMatches(text, normalizeText(query.trim()))[0];
  const start = first?.start ?? 0;
  const end = first?.end ?? 0;
  // Coupe aux espaces les plus proches, pour ne pas tronquer un mot.
  const before = text.indexOf(" ", Math.max(0, start - EXCERPT_RADIUS));
  const after = text.lastIndexOf(" ", end + EXCERPT_RADIUS);
  const from = start > EXCERPT_RADIUS && before !== -1 && before < start ? before + 1 : 0;
  const to = end + EXCERPT_RADIUS < text.length && after >= end ? after : text.length;
  return `${from > 0 ? "…" : ""}${text.slice(from, to)}${to < text.length ? "…" : ""}`;
}

export function matchesTerm(text: string, query: string) {
  return contains(text, normalizeText(query.trim()));
}
