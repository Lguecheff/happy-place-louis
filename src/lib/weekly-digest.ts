/**
 * Résumé hebdomadaire : formats partagés par la carte de /manage et sa maquette.
 * L'envoi planifié (pg_cron « weekly-digest ») part le lundi à 07:00 UTC :
 * 08:00 à Paris l'hiver, 09:00 l'été.
 */

export type DigestMode = "manuel" | "planifié";
/** « ignoré » : aucun destinataire, rien n'a été transmis. */
export type DigestStatus = "en attente" | "transmis" | "ignoré";

export type LastDigest = {
  created_at: string;
  mode: DigestMode;
  recipients_count: number;
  status: DigestStatus;
  sent_by_name: string | null;
};

export type DigestSendResult = {
  recipients: number;
  /** false : la ligne est enregistrée mais attend le webhook (secret absent). */
  transmitted: boolean;
};

const PARIS = "Europe/Paris";
const DIGEST_WEEKDAY = 1; // lundi
const DIGEST_HOUR_UTC = 7;
/** Bouton désactivé après un envoi, pour éviter un double envoi. */
export const DIGEST_COOLDOWN_MS = 60_000;

export const people = (n: number) => `${n} ${n > 1 ? "personnes" : "personne"}`;

/** « lundi 9 novembre à 08:00 » : prochain lundi 07:00 UTC, affiché à l'heure de Paris. */
export function nextDigestLabel(now: Date = new Date()) {
  let days = (DIGEST_WEEKDAY - now.getUTCDay() + 7) % 7;
  if (days === 0 && now.getUTCHours() >= DIGEST_HOUR_UTC) days = 7;
  const at = new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + days, DIGEST_HOUR_UTC),
  );
  const day = new Intl.DateTimeFormat("fr-FR", {
    timeZone: PARIS,
    weekday: "long",
    day: "numeric",
    month: "long",
  }).format(at);
  const time = new Intl.DateTimeFormat("fr-FR", {
    timeZone: PARIS,
    hour: "2-digit",
    minute: "2-digit",
  }).format(at);
  return `${day} à ${time}`;
}

/** « jeudi 5 novembre 2026 à 08:00 », heure de Paris. */
export function digestDateLabel(iso: string) {
  const at = new Date(iso);
  const day = new Intl.DateTimeFormat("fr-FR", {
    timeZone: PARIS,
    weekday: "long",
    day: "numeric",
    month: "long",
    year: "numeric",
  }).format(at);
  const time = new Intl.DateTimeFormat("fr-FR", {
    timeZone: PARIS,
    hour: "2-digit",
    minute: "2-digit",
  }).format(at);
  return `${day} à ${time}`;
}
