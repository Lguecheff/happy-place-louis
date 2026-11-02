import { useEffect, useMemo, useRef, useState } from "react";
import { toast } from "sonner";
import { DsButton, DsIconButton, DsPopover } from "@/components/ds";
import { ReaderDialog } from "@/components/reader-dialog";
import { SubmissionReader } from "@/components/submission-reader";
import type { Submission } from "@/lib/dashboard";
import { NotificationPanel } from "./NotificationPanel";
import {
  arrivalAnnouncement,
  bellLabel,
  formatNotificationDate,
  visibleNotifications,
  type AppNotification,
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

/** Cloche de l'en-tête, son panneau et la lecture de la demande, en lecture seule. */
export function NotificationBell({
  notifications,
  onMarkRead,
  onMarkAllRead,
  loadSubmission,
}: {
  /** Sans valeur tant que le premier chargement n'est pas terminé. */
  notifications: AppNotification[] | undefined;
  onMarkRead: (id: string) => void;
  onMarkAllRead: () => void;
  /** Renvoie `null` si la demande n'est plus lisible. */
  loadSubmission: (id: string) => Promise<Submission | null>;
}) {
  const [open, setOpen] = useState(false);
  const [reading, setReading] = useState<Submission | null>(null);
  const [unavailable, setUnavailable] = useState<AppNotification | null>(null);
  const bellRef = useRef<HTMLButtonElement>(null);
  const announcement = useArrivalAnnouncement(notifications);
  const visible = useMemo(() => visibleNotifications(notifications ?? []), [notifications]);
  const unread = visible.filter((n) => !n.read_at).length;

  async function openNotification(notification: AppNotification) {
    setOpen(false);
    if (!notification.read_at) onMarkRead(notification.id);
    try {
      const { submission_id: id } = notification;
      const submission = id ? await loadSubmission(id) : null;
      if (submission) setReading(submission);
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
      <SubmissionReader
        submission={reading}
        onClose={() => setReading(null)}
        onCloseAutoFocus={focusBell}
      />
      {unavailable && (
        <ReaderDialog
          title="Demande indisponible"
          subtitle={formatNotificationDate(unavailable.created_at)}
          onClose={() => setUnavailable(null)}
          onCloseAutoFocus={focusBell}
        >
          <p className="font-body-md text-body-md text-on-surface">
            Cette demande n'est plus disponible.
          </p>
        </ReaderDialog>
      )}
    </>
  );
}
