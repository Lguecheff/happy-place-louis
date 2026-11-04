import type { AppRole } from "@/lib/auth";
import {
  formatThreshold,
  type Blocker,
  type Metric,
  type News,
  type Submission,
} from "@/lib/dashboard";

/** Cible d'actus publiées par mois (North Star, décision du 2026-10-28). */
export const NEWS_MONTHLY_TARGET = 4;
/** Au-delà, une demande en attente porte le badge « Plus de 30 jours ». */
export const LONG_WAIT_DAYS = 30;
/** Au-delà, un point bloquant non résolu sans mise à jour porte le badge « À vérifier » (US21). */
export const BLOCKER_STALE_DAYS = 3;

const DAY_MS = 86_400_000;

/** Arrondi comme `timeAgo`, pour que les deux affichages donnent le même nombre de jours. */
export function daysSince(iso: string) {
  return Math.max(0, Math.round((Date.now() - new Date(iso).getTime()) / DAY_MS));
}

/** Jours sans mise à jour d'un point bloquant à vérifier ; null s'il est résolu ou récent. */
export function blockerStaleDays(b: Blocker) {
  if (b.status === "RÉSOLU") return null;
  const days = daysSince(b.updated_at);
  return days > BLOCKER_STALE_DAYS ? days : null;
}

/** Les seuils d'un KPI sont complets : une durée et au moins une borne. */
export function hasMetricThresholds(m: Metric) {
  return m.stale_after_days != null && (m.threshold_min != null || m.threshold_max != null);
}

/** Borne atteinte par la valeur actuelle (égale comprise), ou null dans la plage ou sans seuil. */
export function metricOutOfRange(m: Metric): "min" | "max" | null {
  if (!hasMetricThresholds(m)) return null;
  if (m.threshold_max != null && m.value >= m.threshold_max) return "max";
  if (m.threshold_min != null && m.value <= m.threshold_min) return "min";
  return null;
}

/** Plage d'un KPI en clair : « de 30 à 80 % », « 30 minimum », « 80 % maximum ». */
export function metricRangeLabel(m: Metric) {
  const min = m.threshold_min != null ? formatThreshold(m.threshold_min, m.unit) : null;
  const max = m.threshold_max != null ? formatThreshold(m.threshold_max, m.unit) : null;
  if (min && max) return `de ${min} à ${max}`;
  return min ? `${min} minimum` : `${max} maximum`;
}

/**
 * KPI hors de sa plage depuis plus de stale_after_days jours : badge « À vérifier ». Le compteur
 * part du franchissement, ou de la dernière vérification si elle est plus récente. `days` compte
 * depuis le franchissement, pour l'infobulle.
 */
export function metricAlert(m: Metric): { days: number; text: string } | null {
  const side = metricOutOfRange(m);
  if (!side || !m.out_of_range_since || m.stale_after_days == null) return null;
  const verified = m.verified_at && new Date(m.verified_at) > new Date(m.out_of_range_since);
  if (daysSince(verified ? (m.verified_at as string) : m.out_of_range_since) <= m.stale_after_days)
    return null;
  const days = daysSince(m.out_of_range_since);
  const bound =
    side === "max"
      ? `Au-dessus de ${formatThreshold(m.threshold_max as number, m.unit)}`
      : `En dessous de ${formatThreshold(m.threshold_min as number, m.unit)}`;
  return {
    days,
    text: `${bound} depuis ${days} jour${days > 1 ? "s" : ""}. Vérifie si c'est un souci ou une bonne nouvelle.`,
  };
}

/** Dernière modification d'un KPI = « Marquer comme vérifié » (même horodatage, posé par la base). */
export function isVerified(m: Metric) {
  return !!m.verified_at && m.verified_at === m.updated_at;
}

/** Relance encore valable : faite depuis la dernière modification du point. */
export function blockerReminded(b: Blocker) {
  return !!b.reminded_at && new Date(b.reminded_at) >= new Date(b.updated_at);
}

/** Au-delà, une demande clôturée porte le badge « À vérifier » dans son détail (US21). */
export const SUBMISSION_STALE_DAYS = 365;

/**
 * Jours sans mise à jour d'une demande clôturée au-delà d'un an ; null sinon. `updatedAt` :
 * dernier changement de statut ou dernière confirmation (lus dans son fil).
 */
export function submissionStaleDays(status: string, updatedAt: string) {
  if (status !== "clôturée") return null;
  const days = daysSince(updatedAt);
  return days > SUBMISSION_STALE_DAYS ? days : null;
}

export function formatDays(days: number) {
  return days === 0 ? "moins d'un jour" : `${days} jour${days > 1 ? "s" : ""}`;
}

export function plural(count: number, word: string) {
  return count > 1 ? `${word}s` : word;
}

/** Date d'où compte l'attente : dernier changement de statut, sinon création. */
export function pendingSince(s: Submission) {
  return s.pending_since ?? s.created_at;
}

const parisMonth = new Intl.DateTimeFormat("fr-FR", {
  timeZone: "Europe/Paris",
  year: "numeric",
  month: "2-digit",
});

/** Réservé aux actus publiées : la base renseigne toujours leur date de publication. */
export function newsPublishedAt(n: News) {
  return n.published_at as string;
}

/** Date de modification d'une actu publiée, absente si elle n'a pas changé depuis sa publication. */
export function newsModifiedAt({ updated_at, published_at }: News) {
  if (!updated_at || !published_at) return null;
  return new Date(updated_at) > new Date(published_at) ? updated_at : null;
}

/** Affichage seulement : la base applique la même règle (un admin, ou le manager auteur). */
export function canEditPublishedNews(n: News, role: AppRole | null, email: string) {
  if (n.status !== "publiée") return false;
  return (
    role === "admin" ||
    (role === "manager" && (n.author_email ?? "").toLowerCase() === email.toLowerCase())
  );
}

export function publishedThisMonth(news: News[], email: string) {
  const month = parisMonth.format(new Date());
  return news.filter(
    (n) =>
      n.status === "publiée" &&
      (n.author_email ?? "").toLowerCase() === email &&
      parisMonth.format(new Date(newsPublishedAt(n))) === month,
  ).length;
}

/** Brouillons dont le compte est l'auteur, du plus ancien au plus récent. */
export function myDrafts(news: News[], email: string) {
  return news
    .filter((n) => n.status === "brouillon" && (n.author_email ?? "").toLowerCase() === email)
    .sort((a, b) => a.created_at.localeCompare(b.created_at));
}

const parisDay = new Intl.DateTimeFormat("fr-FR", {
  timeZone: "Europe/Paris",
  day: "2-digit",
  month: "2-digit",
  year: "numeric",
});

/** Date au format JJ/MM/AAAA. */
export function formatDay(iso: string) {
  return parisDay.format(new Date(iso));
}

function sentenceCase(text: string) {
  const lower = text.toLocaleLowerCase("fr-FR");
  return lower.charAt(0).toLocaleUpperCase("fr-FR") + lower.slice(1);
}

/** Statut d'une demande ou d'un point bloquant, en casse normale (la base garde sa valeur). */
export const statusLabel = sentenceCase;

export function severityLabel(severity: string) {
  return severity === "critical" ? "Critique" : "À surveiller";
}

const byName = (a: string, b: string) => a.localeCompare(b, "fr");

/** Équipes d'un point bloquant en court : « Toutes les équipes », « Data » ou « Data +2 » (la mienne d'abord). */
export function teamsSummary(teams: string[], mine: string[] = []) {
  if (teams.length === 0) return "Toutes les équipes";
  const sorted = [...teams].sort(byName);
  const first = sorted.find((t) => mine.includes(t)) ?? sorted[0];
  return teams.length > 1 ? `${first} +${teams.length - 1}` : first;
}

/** Équipes d'un point bloquant en entier, par ordre alphabétique. */
export function teamsFull(teams: string[]) {
  return teams.length === 0 ? "Toutes les équipes" : [...teams].sort(byName).join(", ");
}
