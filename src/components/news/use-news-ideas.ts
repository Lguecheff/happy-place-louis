import { useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { toastUndo } from "@/components/ds";
import { fetchResolvedBlockers, type Metric } from "@/lib/dashboard";
import {
  dismissIdea,
  fetchIdeaDismissals,
  fetchIdeaRequests,
  pickNewsIdeas,
  restoreIdea,
  type IdeaDismissalReason,
  type NewsIdea,
} from "@/lib/news-ideas";

/**
 * Idées de sujets d'un manager (US26). Les clés de requête suivent celles des demandes et des
 * points bloquants : une validation ou une résolution sur l'accueil rafraîchit les idées.
 */
export function useNewsIdeas({
  enabled,
  email,
  myTeams,
  metrics,
}: {
  enabled: boolean;
  email: string;
  myTeams: string[] | undefined;
  metrics: { data?: Metric[]; isLoading: boolean; isError: boolean };
}) {
  const qc = useQueryClient();
  const dismissalsKey = ["news-ideas", "dismissals", email];
  const requests = useQuery({
    queryKey: ["submissions", "ideas"],
    queryFn: () => fetchIdeaRequests(),
    enabled,
    retry: false,
  });
  const blockers = useQuery({
    queryKey: ["blockers", "resolved"],
    queryFn: fetchResolvedBlockers,
    enabled,
    retry: false,
  });
  const dismissals = useQuery({
    queryKey: dismissalsKey,
    queryFn: fetchIdeaDismissals,
    enabled,
    retry: false,
  });

  const sources = [requests, blockers, dismissals, metrics];
  const ready = !!(requests.data && blockers.data && dismissals.data && metrics.data && myTeams);
  const ideas: NewsIdea[] = ready
    ? pickNewsIdeas({
        requests: requests.data!,
        blockers: blockers.data!,
        metrics: metrics.data!,
        myTeams: myTeams!,
        dismissed: dismissals.data!,
      })
    : [];

  function setDismissed(update: (keys: Set<string>) => Set<string>) {
    qc.setQueryData<Set<string>>(dismissalsKey, (keys) => update(new Set(keys)));
  }

  /** Retire l'idée tout de suite ; si la base refuse, elle revient. */
  async function remove(idea: NewsIdea, reason: IdeaDismissalReason) {
    setDismissed((keys) => keys.add(idea.key));
    try {
      await dismissIdea(idea.key, reason);
    } catch (e) {
      toast.error((e as Error).message);
      qc.invalidateQueries({ queryKey: dismissalsKey });
      throw e;
    }
  }

  return {
    ideas,
    isLoading: enabled && !ready && !sources.some((q) => q.isError),
    isError: sources.some((q) => q.isError),
    async dismiss(idea: NewsIdea) {
      await remove(idea, "masquée");
      toastUndo("Idée masquée. Elle ne te sera plus proposée.", async () => {
        setDismissed((keys) => (keys.delete(idea.key), keys));
        try {
          await restoreIdea(idea.key);
        } catch (e) {
          toast.error((e as Error).message);
          qc.invalidateQueries({ queryKey: dismissalsKey });
        }
      });
    },
    /** « Rédiger » : l'idée sert à un brouillon et n'est plus proposée. */
    use: (idea: NewsIdea) => remove(idea, "utilisée"),
  };
}
