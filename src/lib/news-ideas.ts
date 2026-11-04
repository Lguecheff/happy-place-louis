/**
 * Idées de sujets (US26) : calculées dans le navigateur à partir de données que la RLS
 * laisse déjà lire au manager. Aucune donnée n'est ajoutée : une idée ne fait que résumer
 * une demande validée, un point bloquant résolu ou un KPI en hausse des 30 derniers jours.
 */
import { db, formatMetricValue, type Blocker, type Metric } from "@/lib/dashboard";
import { NEWS_TEMPLATES } from "@/lib/news-templates";

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

/** Brouillon de « Rédiger » : le titre proposé et le texte du modèle le plus proche (US25). */
export function ideaDraft(idea: NewsIdea) {
  const template = NEWS_TEMPLATES.find((t) => t.id === idea.draft.templateId);
  return { title: idea.draft.title, body: template?.body ?? "" };
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

// ---------------------------------------------------------------------------
// Données (US26) : lues sous RLS, rien de plus que ce que le manager lit déjà.
// ---------------------------------------------------------------------------

export type IdeaDismissalReason = "masquée" | "utilisée";

/**
 * Demandes validées dans les 30 derniers jours, encore validées ou déjà clôturées.
 * La date est celle du dernier passage à « validée » dans le fil des statuts (US1).
 */
export async function fetchIdeaRequests(now = Date.now()): Promise<ValidatedRequest[]> {
  const since = new Date(now - IDEAS_WINDOW_DAYS * DAY_MS).toISOString();
  const { data: history, error } = await db
    .from("submission_status_history")
    .select("submission_id, changed_at")
    .eq("new_status", "validée")
    .gte("changed_at", since)
    .order("changed_at", { ascending: true });
  if (error) throw error;
  const validatedAt = new Map((history ?? []).map((h) => [h.submission_id, h.changed_at]));
  if (!validatedAt.size) return [];
  const { data, error: subError } = await db
    .from("submissions")
    .select("id, team, content")
    .in("id", [...validatedAt.keys()])
    .in("status", ["validée", "clôturée"]);
  if (subError) throw subError;
  return (data ?? []).map((s) => ({ ...s, validated_at: validatedAt.get(s.id)! }));
}

export async function fetchIdeaDismissals(): Promise<Set<string>> {
  const { data, error } = await db.from("news_idea_dismissals").select("idea_key");
  if (error) throw error;
  return new Set((data ?? []).map((d) => d.idea_key));
}

/** Une idée déjà retirée le reste : un second ajout ne fait rien. */
export async function dismissIdea(key: string, reason: IdeaDismissalReason) {
  const { error } = await db
    .from("news_idea_dismissals")
    .upsert({ idea_key: key, reason }, { onConflict: "user_id,idea_key", ignoreDuplicates: true });
  if (error) throw error;
}

/** « Annuler » après « Masquer ». */
export async function restoreIdea(key: string) {
  const { error } = await db.from("news_idea_dismissals").delete().eq("idea_key", key);
  if (error) throw error;
}
