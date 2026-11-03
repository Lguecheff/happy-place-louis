import { useEffect, useMemo, useRef, useState } from "react";
import { toast } from "sonner";
import { DsButton, DsIconButton, DsPopover } from "@/components/ds";
import { ReaderDialog } from "@/components/reader-dialog";
import type { AppNotification, Blocker, Submission } from "@/lib/dashboard";
import { NotificationPanel } from "./NotificationPanel";
import {
  arrivalAnnouncement,
  bellLabel,
  formatNotificationDate,
  isBlockerNotification,
  visibleNotifications,
} from "./notification-utils";

const ANNOUNCEMENT_MS = 5_000;

/** Annonce ce qui arrive après le premier chargement ; le texte est effacé pour que la même annonce soit relue. */
function useArrivalAnnouncement(notifications: AppNotification[] | undefined) {
  const known = useRef<Set<string> | null>(null);
  const [announcement, setAnnouncement] = useState("");

  useEffect(() => {
    if (!notifications) return;
    const seen = known.current;
    known.current = new Set(notifications.map((n) => n.id));
    const fresh = seen ? notifications.filter((n) => !seen.has(n.id)) : [];
    if (fresh.length > 0) setAnnouncement(arrivalAnnouncement(fresh));
  }, [notifications]);

  useEffect(() => {
    if (!announcement) return;
    const timer = setTimeout(() => setAnnouncement(""), ANNOUNCEMENT_MS);
    return () => clearTimeout(timer);
  }, [announcement]);

  return announcement;
}

/** Cloche de l'en-tête et son panneau ; une notification ouvre le suivi de sa demande ou son point bloquant. */
export function NotificationBell({
  notifications,
  onMarkRead,
  onMarkAllRead,
  loadSubmission,
  onOpenSubmission,
  loadBlocker = async () => null,
  onOpenBlocker = () => {},
}: {
  /** Sans valeur tant que le premier chargement n'est pas terminé. */
  notifications: AppNotification[] | undefined;
  onMarkRead: (id: string) => void;
  onMarkAllRead: () => void;
  /** Renvoie `null` si la demande n'est plus lisible. */
  loadSubmission: (id: string) => Promise<Submission | null>;
  /** Ouvre le suivi de la demande, comme « Voir le suivi ». */
  onOpenSubmission: (submission: Submission) => void;
  /** Renvoie `null` si le point bloquant n'existe plus. */
  loadBlocker?: (id: string) => Promise<Blocker | null>;
  /** Ouvre le point bloquant dans sa fenêtre de lecture (US7). */
  onOpenBlocker?: (blocker: Blocker) => void;
}) {
  const [open, setOpen] = useState(false);
  const [unavailable, setUnavailable] = useState<AppNotification | null>(null);
  const bellRef = useRef<HTMLButtonElement>(null);
  const announcement = useArrivalAnnouncement(notifications);
  const visible = useMemo(() => visibleNotifications(notifications ?? []), [notifications]);
  const unread = visible.filter((n) => !n.read_at).length;

  async function openNotification(notification: AppNotification) {
    setOpen(false);
    if (!notification.read_at) onMarkRead(notification.id);
    try {
      if (isBlockerNotification(notification)) {
        const { blocker_id: id } = notification;
        const blocker = id ? await loadBlocker(id) : null;
        if (blocker) onOpenBlocker(blocker);
        else setUnavailable(notification);
        return;
      }
      const { submission_id: id } = notification;
      const submission = id ? await loadSubmission(id) : null;
      if (submission) onOpenSubmission(submission);
      else setUnavailable(notification);
    } catch (e) {
      toast.error((e as Error).message);
    }
  }

  function focusBell(event: Event) {
    event.preventDefault();
    bellRef.current?.focus();
  }

  return (
    <>
      <DsPopover
        open={open}
        onOpenChange={setOpen}
        title="Notifications"
        trigger={
          <DsIconButton
            ref={bellRef}
            icon="notifications"
            label={bellLabel(unread)}
            count={unread}
          />
        }
        action={
          unread > 0 && (
            <DsButton variant="link" onClick={onMarkAllRead}>
              Tout marquer comme lu
            </DsButton>
          )
        }
      >
        <NotificationPanel notifications={visible} onSelect={openNotification} />
      </DsPopover>
      <p role="status" className="sr-only">
        {announcement}
      </p>
      {unavailable && (
        <ReaderDialog
          title={
            isBlockerNotification(unavailable)
              ? "Point bloquant indisponible"
              : "Demande indisponible"
          }
          subtitle={formatNotificationDate(unavailable.created_at)}
          onClose={() => setUnavailable(null)}
          onCloseAutoFocus={focusBell}
        >
          <p className="font-body-md text-body-md text-on-surface">
            {isBlockerNotification(unavailable)
              ? "Ce point bloquant n'est plus disponible."
              : "Cette demande n'est plus disponible."}
          </p>
        </ReaderDialog>
      )}
    </>
  );
}
