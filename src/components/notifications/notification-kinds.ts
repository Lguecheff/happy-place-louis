import type { Database } from "@/integrations/supabase/types";

export type AppRole = Database["public"]["Enums"]["app_role"];
export type NotificationChannel = "in_app" | "by_email";

export type PreferenceKind = Database["public"]["Enums"]["notification_kind"];

export type NotificationKindDef = {
  kind: PreferenceKind;
  label: string;
  /** Rôles qui voient la ligne dans les préférences. */
  roles: AppRole[];
  /** Canaux proposés, dans l'ordre d'affichage. */
  channels: NotificationChannel[];
  /** Canaux affichés cochés et non modifiables. */
  locked?: NotificationChannel[];
  /** Phrase sous une case verrouillée ; « Toujours activé » sans valeur. */
  lockedHint?: string;
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
    kind: "changement_statut",
    label: "Changement d'état de mes demandes",
    roles: ["collaborateur", "manager"],
    channels: ["in_app", "by_email"],
    // La base ignore « Dans l'app » décoché pour l'auteur (US14).
    locked: ["in_app"],
    lockedHint: "Toujours active pour tes propres demandes.",
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

/** Ce que fait chaque canal, affiché sous sa case. */
export const CHANNEL_HINTS: Record<NotificationChannel, string> = {
  in_app: "Une alerte dans la cloche, en haut de l'écran",
  by_email: "Un mail envoyé à ton adresse",
};

export type ChannelValues = Record<NotificationChannel, boolean>;
/** Valeurs enregistrées par type ; un type absent vaut les valeurs par défaut. */
export type PreferenceValues = Partial<Record<PreferenceKind, ChannelValues>>;

export const DEFAULT_CHANNELS: ChannelValues = { in_app: true, by_email: true };

export function notificationKindsFor(role: AppRole) {
  return NOTIFICATION_KINDS.filter((k) => k.roles.includes(role));
}
