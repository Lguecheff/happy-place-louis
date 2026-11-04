import { newsPublishedAt } from "@/components/overview/overview-utils";
import type { Blocker, Metric, News, Submission } from "@/lib/dashboard";

export const SEARCH_MIN_LENGTH = 3;
export const SEARCH_MAX_PER_TYPE = 20;
const EXCERPT_RADIUS = 60;

export type SearchData = {
  news: News[];
  submissions: Submission[];
  blockers: Blocker[];
  metrics: Metric[];
};

export type SearchGroup<T> = {
  /** Nombre réel de résultats, même au-delà de la limite affichée. */
  total: number;
  items: T[];
};

export type SearchResults = {
  news: SearchGroup<News>;
  submissions: SearchGroup<Submission>;
  blockers: SearchGroup<Blocker>;
  metrics: SearchGroup<Metric>;
};

export type TextPart = { text: string; match: boolean };

export type SearchType = "tous" | "actus" | "demandes" | "blocages" | "kpi";
export type SearchPeriod = "tout" | "7" | "30";

/** Filtres de la recherche (US23) ; `teams` vide = toutes les équipes. */
export type SearchFilters = { type: SearchType; teams: string[]; period: SearchPeriod };

export const EMPTY_FILTERS: SearchFilters = { type: "tous", teams: [], period: "tout" };

export const SEARCH_TYPES: { value: SearchType; label: string }[] = [
  { value: "tous", label: "Tous" },
  { value: "actus", label: "Actus" },
  { value: "demandes", label: "Demandes" },
  { value: "blocages", label: "Points bloquants" },
  { value: "kpi", label: "KPI" },
];

export const SEARCH_PERIODS: { value: SearchPeriod; label: string }[] = [
  { value: "tout", label: "Tout" },
  { value: "7", label: "7 derniers jours" },
  { value: "30", label: "30 derniers jours" },
];

export function hasFilters({ type, teams, period }: SearchFilters) {
  return type !== EMPTY_FILTERS.type || teams.length > 0 || period !== EMPTY_FILTERS.period;
}

const DAY_MS = 86_400_000;

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

/**
 * Les données sont déjà lues sous RLS ; seules les actus publiées restent cherchables.
 * Les filtres (US23) ne font que retirer des résultats : ils ne donnent accès à rien de plus.
 */
export function searchAll(
  { news, submissions, blockers, metrics }: SearchData,
  query: string,
  { type, teams, period }: SearchFilters = EMPTY_FILTERS,
  now = Date.now(),
): SearchResults {
  const term = normalizeText(query.trim());
  const since = period === "tout" ? null : now - Number(period) * DAY_MS;
  // Période : date propre à chaque type (publication, création, dernière mise à jour).
  const inPeriod = (iso: string | null | undefined) =>
    since === null || (!!iso && new Date(iso).getTime() >= since);
  const shown = (t: SearchType) => type === "tous" || type === t;
  // Équipes choisies : on écarte seulement ce qui vise d'autres équipes. Les actus « Toute
  // l'entreprise », les points bloquants sans équipe et les KPI concernent tout le monde.
  const forTeams = (targets: string[]) =>
    !teams.length || !targets.length || targets.some((t) => teams.includes(t));
  return {
    news: group(
      news.filter(
        (n) =>
          shown("actus") &&
          n.status === "publiée" &&
          (contains(n.title, term) || contains(n.body, term)) &&
          inPeriod(newsPublishedAt(n)) &&
          forTeams(n.audience === "équipe" ? (n.teams ?? []) : []),
      ),
      newsPublishedAt,
    ),
    submissions: group(
      submissions.filter(
        (s) =>
          shown("demandes") &&
          contains(s.content, term) &&
          inPeriod(s.created_at) &&
          forTeams([s.team]),
      ),
      (s) => s.created_at,
    ),
    blockers: group(
      blockers.filter(
        (b) =>
          shown("blocages") &&
          (contains(b.title, term) || contains(b.description, term)) &&
          inPeriod(b.updated_at) &&
          forTeams(b.teams),
      ),
      (b) => b.created_at,
    ),
    metrics: group(
      metrics.filter((m) => shown("kpi") && contains(m.label, term) && inPeriod(m.updated_at)),
      (m) => m.updated_at,
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
