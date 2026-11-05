import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useMemo } from "react";
import {
  fetchMyMailAddress,
  fetchMyNotificationPreferences,
  saveMyMailAddress,
  saveNotificationPreference,
} from "@/lib/dashboard";
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
  const address = useQuery({
    queryKey: ["notification_mail_address", recipient],
    queryFn: () => fetchMyMailAddress(recipient),
    enabled: !!recipient,
  });

  const values = useMemo<PreferenceValues>(
    () =>
      Object.fromEntries(
        (preferences.data ?? []).map((p) => [p.kind, { in_app: p.in_app, by_email: p.by_email }]),
      ),
    [preferences.data],
  );

  // Adresse illisible : le champ reste vide plutôt que de masquer toutes les préférences.
  if (!preferences.data || address.isPending) return undefined;
  return {
    kinds: notificationKindsFor(role),
    values,
    onChange: async (kind, channel, checked) => {
      await saveNotificationPreference(recipient, kind, channel, checked);
      await qc.invalidateQueries({ queryKey: ["notification_preferences", recipient] });
    },
    address: {
      value: address.data ?? "",
      onSave: async (next) => {
        const saved = await saveMyMailAddress(next);
        qc.setQueryData(["notification_mail_address", recipient], saved);
      },
    },
  };
}
