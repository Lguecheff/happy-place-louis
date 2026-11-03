import { formatDay, plural } from "@/components/overview/overview-utils";
import type { AppNotification } from "@/lib/dashboard";

const MINUTE_MS = 60_000;
const HOUR_MS = 60 * MINUTE_MS;
const DAY_MS = 24 * HOUR_MS;
const RETENTION_DAYS = 30;

/** Type de l'US16. Comparé en texte tant que la migration n'a pas ajouté la valeur à l'enum. */
export const BLOCKER_REVIEW_KIND = "point_bloquant_a_revoir";

/** Notification liée à un point bloquant ; son `blocker_id` est vide si le point a été supprimé. */
export function isBlockerNotification(notification: Pick<AppNotification, "kind">) {
  return (notification.kind as string) === BLOCKER_REVIEW_KIND;
}

/** De la plus récente à la plus ancienne, 30 jours maximum. */
export function visibleNotifications(notifications: AppNotification[]) {
  const oldest = Date.now() - RETENTION_DAYS * DAY_MS;
  return notifications
    .filter((n) => new Date(n.created_at).getTime() >= oldest)
    .sort((a, b) => b.created_at.localeCompare(a.created_at));
}

export function bellLabel(unread: number) {
  return `Notifications, ${unread} ${plural(unread, "non lue")}`;
}

/** « il y a 5 min », puis la date au-delà de 24 h. */
export function formatNotificationDate(iso: string) {
  const diff = Date.now() - new Date(iso).getTime();
  if (diff >= DAY_MS) return formatDay(iso);
  if (diff >= HOUR_MS) return `il y a ${Math.floor(diff / HOUR_MS)} h`;
  if (diff >= MINUTE_MS) return `il y a ${Math.floor(diff / MINUTE_MS)} min`;
  return "à l'instant";
}

/** Texte lu par les lecteurs d'écran à l'arrivée de nouvelles notifications. */
export function arrivalAnnouncement(fresh: AppNotification[]) {
  return fresh.length === 1
    ? `Nouvelle notification : ${fresh[0].message}`
    : `${fresh.length} nouvelles notifications`;
}
