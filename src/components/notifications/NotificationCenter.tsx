import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect } from "react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import {
  fetchMyNotifications,
  fetchReadableSubmission,
  markAllNotificationsRead,
  markNotificationRead,
  type Submission,
} from "@/lib/dashboard";
import { NotificationBell } from "./NotificationBell";

/** Cloche branchée sur les notifications de `email`, lues sous RLS et tenues à jour en temps réel. */
export function NotificationCenter({
  email,
  canReadAttachment,
}: {
  email: string;
  canReadAttachment?: (submission: Submission) => boolean;
}) {
  const recipient = email.toLowerCase();
  const qc = useQueryClient();

  const notifications = useQuery({
    queryKey: ["notifications", recipient],
    queryFn: () => fetchMyNotifications(recipient),
    // Rattrape ce qui a été manqué pendant une coupure du temps réel.
    refetchOnWindowFocus: true,
  });

  useEffect(() => {
    const refresh = () => qc.invalidateQueries({ queryKey: ["notifications", recipient] });
    const channel = supabase
      .channel(`notifications:${recipient}`)
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "notifications",
          filter: `recipient_email=eq.${recipient}`,
        },
        refresh,
      )
      .subscribe((status) => {
        if (status === "SUBSCRIBED") refresh();
      });
    return () => {
      supabase.removeChannel(channel);
    };
  }, [qc, recipient]);

  const refreshAfter = {
    onSuccess: () => qc.invalidateQueries({ queryKey: ["notifications", recipient] }),
    onError: (e: unknown) => toast.error((e as Error).message),
  };
  const markRead = useMutation({ mutationFn: markNotificationRead, ...refreshAfter });
  const markAllRead = useMutation({
    mutationFn: () => markAllNotificationsRead(recipient),
    ...refreshAfter,
  });

  return (
    <NotificationBell
      notifications={notifications.data}
      onMarkRead={(id) => markRead.mutate(id)}
      onMarkAllRead={() => markAllRead.mutate()}
      loadSubmission={fetchReadableSubmission}
      canReadAttachment={canReadAttachment}
    />
  );
}
