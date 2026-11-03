import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { BlockerReader } from "@/components/blocker-reader";
import { SubmissionThreadModal } from "@/components/submission-status-thread";
import { supabase } from "@/integrations/supabase/client";
import {
  fetchBlocker,
  fetchMyNotifications,
  fetchReadableSubmission,
  markAllNotificationsRead,
  markNotificationRead,
  type Blocker,
  type Submission,
} from "@/lib/dashboard";
import { NotificationBell } from "./NotificationBell";

/**
 * Cloche branchée sur les notifications de `email`, lues sous RLS et tenues à jour en temps réel.
 * Sans `onOpenSubmission`, une notification ouvre le suivi de sa demande en lecture seule ;
 * celle d'un point bloquant ouvre sa fenêtre de lecture (US7).
 */
export function NotificationCenter({
  email,
  onOpenSubmission,
}: {
  email: string;
  onOpenSubmission?: (submission: Submission) => void;
}) {
  const [threadOf, setThreadOf] = useState<Submission | null>(null);
  const [blocker, setBlocker] = useState<Blocker | null>(null);
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
    <>
      <NotificationBell
        notifications={notifications.data}
        onMarkRead={(id) => markRead.mutate(id)}
        onMarkAllRead={() => markAllRead.mutate()}
        loadSubmission={fetchReadableSubmission}
        onOpenSubmission={onOpenSubmission ?? setThreadOf}
        loadBlocker={fetchBlocker}
        onOpenBlocker={setBlocker}
      />
      {threadOf && (
        <SubmissionThreadModal submission={threadOf} onClose={() => setThreadOf(null)} />
      )}
      <BlockerReader blocker={blocker} onClose={() => setBlocker(null)} />
    </>
  );
}
