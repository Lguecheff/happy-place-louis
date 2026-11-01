import type { News, Submission } from "@/lib/dashboard";

/** Cible d'actus publiées par mois (North Star, décision du 2026-10-28). */
export const NEWS_MONTHLY_TARGET = 4;
/** Au-delà, une demande en attente porte le badge « Plus de 30 jours ». */
export const LONG_WAIT_DAYS = 30;
/** Au-delà, un point bloquant critique sans mise à jour est signalé comme ancien. */
export const BLOCKER_STALE_DAYS = 7;

const DAY_MS = 86_400_000;

/** Arrondi comme `timeAgo`, pour que les deux affichages donnent le même nombre de jours. */
export function daysSince(iso: string) {
  return Math.max(0, Math.round((Date.now() - new Date(iso).getTime()) / DAY_MS));
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

/** `created_at` tient lieu de date tant que la migration des dates d'actus n'est pas appliquée. */
export function newsPublishedAt(n: News) {
  return n.published_at ?? n.created_at;
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
