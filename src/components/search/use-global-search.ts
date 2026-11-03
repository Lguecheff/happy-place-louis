import { useQuery } from "@tanstack/react-query";
import { useMemo } from "react";
import type { AppRole } from "@/lib/auth";
import {
  fetchAllBlockers,
  fetchMetrics,
  fetchNews,
  fetchSearchableSubmissions,
  type Submission,
} from "@/lib/dashboard";

/** Données de la barre de recherche, lues sous RLS, et droit de lire une pièce jointe. */
export function useGlobalSearch({
  role,
  email,
  managerTeams,
  ownTeam,
}: {
  role: AppRole;
  email: string;
  managerTeams: string[];
  /** Équipe d'un collaborateur, pour confirmer une demande de son équipe. */
  ownTeam?: string | null;
}) {
  const news = useQuery({ queryKey: ["news"], queryFn: fetchNews, retry: false });
  const submissions = useQuery({
    queryKey: ["submissions", "searchable"],
    queryFn: fetchSearchableSubmissions,
    retry: false,
  });
  const blockers = useQuery({
    queryKey: ["blockers", "all"],
    queryFn: fetchAllBlockers,
    retry: false,
  });
  const metrics = useQuery({ queryKey: ["metrics"], queryFn: fetchMetrics, retry: false });

  const data = useMemo(
    () =>
      news.data && submissions.data && blockers.data && metrics.data
        ? {
            news: news.data,
            submissions: submissions.data,
            blockers: blockers.data,
            metrics: metrics.data,
          }
        : undefined,
    [news.data, submissions.data, blockers.data, metrics.data],
  );

  // Même règle que la politique de stockage : une demande validée se lit, son PDF non.
  const canReadAttachment = (s: Submission) =>
    role === "admin" ||
    s.submitted_by_email?.toLowerCase() === email.toLowerCase() ||
    (role === "manager" && managerTeams.includes(s.team));

  // « Confirmer à jour » (US21) : même règle que public.confirm_submission_up_to_date.
  const canConfirmSubmission = (s: Submission) =>
    role === "admin" ||
    s.submitted_by_email?.toLowerCase() === email.toLowerCase() ||
    (role === "manager" && managerTeams.includes(s.team)) ||
    (role === "collaborateur" && !!ownTeam && ownTeam === s.team);

  return {
    source: {
      data,
      isError: news.isError || submissions.isError || blockers.isError || metrics.isError,
      isLoading: news.isLoading || submissions.isLoading || blockers.isLoading || metrics.isLoading,
    },
    canReadAttachment,
    canConfirmSubmission,
  };
}
