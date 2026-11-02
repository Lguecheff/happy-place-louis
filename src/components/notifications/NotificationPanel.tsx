import { DsBadge, DsEmptyState, DsListItem } from "@/components/ds";
import type { AppNotification } from "@/lib/dashboard";
import { cn } from "@/lib/utils";
import { formatNotificationDate } from "./notification-utils";

/** Contenu du panneau « Notifications » : une ligne cliquable par notification. */
export function NotificationPanel({
  notifications,
  onSelect,
}: {
  notifications: AppNotification[];
  onSelect: (notification: AppNotification) => void;
}) {
  if (notifications.length === 0) return <DsEmptyState>Aucune notification</DsEmptyState>;
  return (
    <ul className="space-y-xs">
      {notifications.map((n) => (
        <li key={n.id}>
          <DsListItem
            icon={n.read_at ? "drafts" : "mark_email_unread"}
            title={<span className={cn(!n.read_at && "font-semibold")}>{n.message}</span>}
            meta={
              <span className="flex flex-wrap items-center gap-xs">
                {!n.read_at && <DsBadge variant="status">Non lue</DsBadge>}
                {formatNotificationDate(n.created_at)}
              </span>
            }
            onClick={() => onSelect(n)}
          />
        </li>
      ))}
    </ul>
  );
}
