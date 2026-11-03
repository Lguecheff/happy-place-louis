import { DsButton, DsIcon } from "@/components/ds";

/** D'où vient le suivi : l'auteur suit d'office, le manager de l'équipe aussi, les autres le choisissent. */
export type FollowSource = "auteur" | "manager" | "volontaire";

export type FollowButtonProps = {
  /** Source du suivi en cours ; `null` quand la personne ne suit pas la demande. */
  source: FollowSource | null;
  /** Un admin ne suit aucune demande : rien n'est affiché. */
  isAdmin?: boolean;
  /** Changement en cours : le bouton est occupé. */
  pending?: boolean;
  /** `true` pour suivre, `false` pour ne plus suivre. Jamais appelé pour l'auteur. */
  onChange: (follow: boolean) => void;
};

/**
 * Suivi d'une demande, dans la fenêtre de lecture.
 * L'auteur voit « Tu suis ta demande » à la place du bouton ; l'admin ne voit rien.
 */
export function FollowButton({ source, isAdmin, pending, onChange }: FollowButtonProps) {
  if (isAdmin) return null;

  if (source === "auteur") {
    return (
      <p className="inline-flex min-h-11 items-center gap-xs font-body-sm text-body-sm text-on-surface-variant">
        <DsIcon name="notifications_active" />
        Tu suis ta demande
      </p>
    );
  }

  const following = source !== null;
  return (
    <div className="flex flex-wrap items-center gap-xs">
      <DsButton
        icon={following ? "notifications_off" : "notifications"}
        pending={pending}
        onClick={() => onChange(!following)}
      >
        {following ? "Ne plus suivre" : "Suivre"}
      </DsButton>
      <p aria-live="polite" className="font-body-sm text-body-sm text-on-surface-variant">
        {source === "manager"
          ? "Tu la suis d'office : tu es manager de cette équipe."
          : following
            ? "Tu suis cette demande."
            : "Suis-la pour recevoir une alerte à chaque changement d'état."}
      </p>
    </div>
  );
}
