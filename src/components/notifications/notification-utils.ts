import { formatDay, plural } from "@/components/overview/overview-utils";
import type { AppNotification } from "@/lib/dashboard";

const MINUTE_MS = 60_000;
const HOUR_MS = 60 * MINUTE_MS;
const DAY_MS = 24 * HOUR_MS;

/** Notification liée à un point bloquant (US16) ; son `blocker_id` est vide si le point a été supprimé. */
export function isBlockerNotification(notification: Pick<AppNotification, "kind">) {
  return notification.kind === "point_bloquant_a_revoir";
}

/** De la plus récente à la plus ancienne, sans limite de durée (plus de purge depuis l'US16). */
export function visibleNotifications(notifications: AppNotification[]) {
  return [...notifications].sort((a, b) => b.created_at.localeCompare(a.created_at));
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
