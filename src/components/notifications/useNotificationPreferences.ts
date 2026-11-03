import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useMemo } from "react";
import { fetchMyNotificationPreferences, saveNotificationPreference } from "@/lib/dashboard";
import { notificationKindsFor, type AppRole, type PreferenceValues } from "./notification-kinds";
import type { NotificationPreferencesProps } from "./NotificationPreferences";

/** Préférences de `email`, lues et enregistrées sous RLS. Sans valeur tant qu'elles ne sont pas chargées. */
export function useNotificationPreferences(
  email: string,
  role: AppRole,
): Omit<NotificationPreferencesProps, "onClose" | "onCloseAutoFocus"> | undefined {
  const recipient = email.toLowerCase();
  const qc = useQueryClient();
  const preferences = useQuery({
    queryKey: ["notification_preferences", recipient],
    queryFn: () => fetchMyNotificationPreferences(recipient),
    enabled: !!recipient,
  });

  const values = useMemo<PreferenceValues>(
    () =>
      Object.fromEntries(
        (preferences.data ?? []).map((p) => [p.kind, { in_app: p.in_app, by_email: p.by_email }]),
      ),
    [preferences.data],
  );

  if (!preferences.data) return undefined;
  return {
    kinds: notificationKindsFor(role),
    values,
    onChange: async (kind, channel, checked) => {
      await saveNotificationPreference(recipient, kind, channel, checked);
      await qc.invalidateQueries({ queryKey: ["notification_preferences", recipient] });
    },
  };
}
