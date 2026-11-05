/**
 * Résumé hebdomadaire : formats partagés par la carte de /manage et sa maquette.
 * L'envoi planifié part le lundi à 08:00, heure de Paris.
 */

export type DigestMode = "manuel" | "planifié";
export type DigestStatus = "en attente" | "transmis";

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
const DIGEST_HOUR = 8;
/** Bouton désactivé après un envoi, pour éviter un double envoi. */
export const DIGEST_COOLDOWN_MS = 60_000;

export const people = (n: number) => `${n} ${n > 1 ? "personnes" : "personne"}`;

function parisParts(at: Date) {
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone: PARIS,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    hourCycle: "h23",
    weekday: "short",
  }).formatToParts(at);
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? "";
  const weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  return {
    year: Number(get("year")),
    month: Number(get("month")),
    day: Number(get("day")),
    hour: Number(get("hour")),
    weekday: weekdays.indexOf(get("weekday")),
  };
}

/** « lundi 9 novembre à 08:00 » : prochain lundi 08:00 à Paris (aujourd'hui si lundi avant 08:00). */
export function nextDigestLabel(now: Date = new Date()) {
  const p = parisParts(now);
  let days = (DIGEST_WEEKDAY - p.weekday + 7) % 7;
  if (days === 0 && p.hour >= DIGEST_HOUR) days = 7;
  // Calcul de calendrier seulement : midi UTC évite tout décalage de jour.
  const date = new Date(Date.UTC(p.year, p.month - 1, p.day + days, 12));
  const label = new Intl.DateTimeFormat("fr-FR", {
    timeZone: "UTC",
    weekday: "long",
    day: "numeric",
    month: "long",
  }).format(date);
  return `${label} à 0${DIGEST_HOUR}:00`;
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
