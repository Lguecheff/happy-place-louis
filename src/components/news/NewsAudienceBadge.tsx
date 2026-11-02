import { DsBadge } from "@/components/ds";
import type { News } from "@/lib/dashboard";
import { audienceLabel } from "@/lib/news-audience";

/** Puce du public d'une actu publiée, dans le fil et la fenêtre de lecture. */
export function NewsAudienceBadge({
  news: { audience, teams = [] },
  className,
}: {
  news: Pick<News, "audience" | "teams">;
  className?: string;
}) {
  if (!audience) return null;
  return (
    <DsBadge icon={audience === "entreprise" ? "public" : "group"} className={className}>
      <span className="sr-only">Public : </span>
      {audienceLabel({ audience, teams })}
    </DsBadge>
  );
}
