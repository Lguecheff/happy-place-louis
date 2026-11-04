/**
 * Idées de sujets (US26) : calculées dans le navigateur à partir de données que la RLS
 * laisse déjà lire au manager. Aucune donnée n'est ajoutée : une idée ne fait que résumer
 * une demande validée, un point bloquant résolu ou un KPI en hausse des 30 derniers jours.
 */
import { formatMetricValue, type Blocker, type Metric } from "@/lib/dashboard";

export const IDEAS_MAX = 3;
export const IDEAS_WINDOW_DAYS = 30;
export const IDEA_EXCERPT = 80;
const DAY_MS = 24 * 60 * 60 * 1000;

export type NewsIdeaKind = "demande" | "point" | "kpi";

export type NewsIdea = {
  /** Clé stable : « demande:<id> », « point:<id> », « kpi:<clé>:<AAAA-MM-JJ> ». */
  key: string;
  kind: NewsIdeaKind;
  /** La phrase affichée, une seule. */
  sentence: string;
  meta: string;
  /** Date de l'événement (validation, résolution, mise à jour du KPI). */
  at: string;
  /** Ce que « Rédiger » met dans le brouillon : un titre proposé et le modèle le plus proche (US25). */
  draft: { title: string; templateId: string };
};

/** Demande validée : `validated_at` vient du fil des statuts (US1), pas de la date de création. */
export type ValidatedRequest = { id: string; team: string; content: string; validated_at: string };

const dayMonth = new Intl.DateTimeFormat("fr-FR", {
  timeZone: "Europe/Paris",
  day: "2-digit",
  month: "2-digit",
});
const isoDay = new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Paris" });

/** « JJ/MM », heure de Paris. */
export function formatDayMonth(iso: string) {
  return dayMonth.format(new Date(iso));
}

/**
 * Extrait d'au plus 80 caractères, coupé à la fin d'un mot, avec « … » s'il est coupé.
 * Les retours à la ligne deviennent des espaces.
 */
export function excerpt(text: string, max = IDEA_EXCERPT) {
  const flat = text.replace(/\s+/g, " ").trim();
  if (flat.length <= max) return flat;
  const cut = flat.slice(0, max - 1);
  const space = cut.lastIndexOf(" ");
  return `${(space > max / 2 ? cut.slice(0, space) : cut).trimEnd()}…`;
}

function teamsLabel(teams: string[]) {
  if (teams.length === 0) return "Toutes les équipes";
  return teams.length === 1 ? teams[0] : `${teams[0]} +${teams.length - 1}`;
}

export function requestIdea(r: ValidatedRequest): NewsIdea {
  return {
    key: `demande:${r.id}`,
    kind: "demande",
    sentence: `La demande « ${excerpt(r.content)} » a été validée le ${formatDayMonth(r.validated_at)}.`,
    meta: `Demande validée · ${r.team}`,
    at: r.validated_at,
    // L'extrait n'est pas repris dans le brouillon : l'actu peut partir à toute l'entreprise.
    draft: { title: `Ce qui change dans l'équipe ${r.team} : [sujet]`, templateId: "rappel" },
  };
}

/** Date de résolution : `updated_at`, faute d'historique des statuts des points bloquants. */
export function blockerIdea(b: Blocker): NewsIdea {
  return {
    key: `point:${b.id}`,
    kind: "point",
    sentence: `Le point bloquant « ${excerpt(b.title)} » a été résolu le ${formatDayMonth(b.updated_at)}.`,
    meta: `Point bloquant résolu · ${teamsLabel(b.teams)}`,
    at: b.updated_at,
    draft: { title: `Point bloquant résolu : ${excerpt(b.title)}`, templateId: "point-etape" },
  };
}

export function metricIdea(m: Metric): NewsIdea {
  return {
    key: `kpi:${m.key}:${isoDay.format(new Date(m.updated_at))}`,
    kind: "kpi",
    sentence: `Le KPI « ${m.label} » est en hausse : ${formatMetricValue(m.value, m.unit)} le ${formatDayMonth(m.updated_at)}.`,
    meta: "KPI en hausse",
    at: m.updated_at,
    draft: { title: `${m.label} en hausse : [ce qui l'explique]`, templateId: "point-etape" },
  };
}

/**
 * Les 3 idées proposées : la plus récente de chaque sorte, puis, s'il en manque une sorte,
 * les plus récentes qui restent. Les idées masquées ou déjà utilisées sont retirées.
 */
export function pickNewsIdeas(
  input: {
    requests: ValidatedRequest[];
    blockers: Blocker[];
    metrics: Metric[];
    /** Équipes du manager. */
    myTeams: string[];
    /** Clés masquées ou utilisées par ce manager. */
    dismissed: Set<string>;
  },
  now = Date.now(),
): NewsIdea[] {
  const recent = (iso: string) => now - new Date(iso).getTime() <= IDEAS_WINDOW_DAYS * DAY_MS;
  const byDate = (a: NewsIdea, b: NewsIdea) => b.at.localeCompare(a.at);
  const groups = [
    input.requests
      .filter((r) => input.myTeams.includes(r.team) && recent(r.validated_at))
      .map(requestIdea),
    input.blockers
      .filter(
        (b) =>
          b.status === "RÉSOLU" &&
          (b.teams.length === 0 || b.teams.some((t) => input.myTeams.includes(t))) &&
          recent(b.updated_at),
      )
      .map(blockerIdea),
    input.metrics.filter((m) => m.trend === "hausse" && recent(m.updated_at)).map(metricIdea),
  ].map((ideas) => ideas.filter((i) => !input.dismissed.has(i.key)).sort(byDate));

  const firsts = groups.flatMap((g) => g.slice(0, 1));
  const rest = groups.flatMap((g) => g.slice(1)).sort(byDate);
  return [...firsts.sort(byDate), ...rest].slice(0, IDEAS_MAX);
}
