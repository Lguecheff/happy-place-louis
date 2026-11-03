import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { DsButton, DsIcon } from "@/components/ds";
import { fetchMyFollow, setMyFollow } from "@/lib/dashboard";
import type { AppRole } from "./notification-kinds";

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

/** Suivi de `submissionId` par `email`, lu et modifié sous RLS ; le bouton change sans attendre la base. */
export function SubmissionFollow({
  submissionId,
  email,
  role,
}: {
  submissionId: string;
  email: string;
  role: AppRole;
}) {
  const qc = useQueryClient();
  const isAdmin = role === "admin";
  const key = ["submission_followers", submissionId, email.toLowerCase()];
  const follow = useQuery({
    queryKey: key,
    queryFn: () => fetchMyFollow(submissionId, email),
    enabled: !isAdmin && !!email,
  });
  const change = useMutation({
    mutationFn: (next: boolean) => setMyFollow(submissionId, email, next),
    onMutate: async (next) => {
      await qc.cancelQueries({ queryKey: key });
      const previous = qc.getQueryData<string | null>(key);
      qc.setQueryData(key, next ? "volontaire" : null);
      return { previous };
    },
    onError: (_error, _next, context) => {
      qc.setQueryData(key, context?.previous ?? null);
      toast.error("Impossible de modifier le suivi de la demande.");
    },
    onSettled: () => qc.invalidateQueries({ queryKey: key }),
  });

  if (isAdmin || follow.isLoading || follow.isError) return null;
  return (
    <FollowButton
      source={(follow.data ?? null) as FollowSource | null}
      pending={change.isPending}
      onChange={(next) => change.mutate(next)}
    />
  );
}
