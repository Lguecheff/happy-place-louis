import type { Database } from "@/integrations/supabase/types";

export type AppRole = Database["public"]["Enums"]["app_role"];
export type NotificationChannel = "in_app" | "by_email";

// Phase 1 de l'US13 : 'resume_hebdo' n'est pas encore dans l'enum notification_kind.
export type PreferenceKind = Database["public"]["Enums"]["notification_kind"] | "resume_hebdo";

export type NotificationKindDef = {
  kind: PreferenceKind;
  label: string;
  /** Rôles qui voient la ligne dans les préférences. */
  roles: AppRole[];
  /** Canaux proposés, dans l'ordre d'affichage. */
  channels: NotificationChannel[];
  /** Canaux affichés cochés et non modifiables. */
  locked?: NotificationChannel[];
};

/** Catalogue unique des préférences : chaque US ajoute sa ligne ici, sans toucher au reste. */
export const NOTIFICATION_KINDS: NotificationKindDef[] = [
  {
    kind: "nouvelle_demande",
    label: "Nouvelle demande d'une de mes équipes",
    roles: ["manager"],
    channels: ["in_app", "by_email"],
  },
  {
    kind: "resume_hebdo",
    label: "Résumé hebdomadaire",
    roles: ["collaborateur", "manager"],
    channels: ["by_email"],
  },
];

export const CHANNEL_LABELS: Record<NotificationChannel, string> = {
  in_app: "Dans l'app",
  by_email: "Par mail",
};

export type ChannelValues = Record<NotificationChannel, boolean>;
/** Valeurs enregistrées par type ; un type absent vaut les valeurs par défaut. */
export type PreferenceValues = Partial<Record<PreferenceKind, ChannelValues>>;

export const DEFAULT_CHANNELS: ChannelValues = { in_app: true, by_email: true };

export function notificationKindsFor(role: AppRole) {
  return NOTIFICATION_KINDS.filter((k) => k.roles.includes(role));
}
