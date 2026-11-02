import { DsBadge } from "@/components/ds";
import { audienceLabel, type NewsAudienceValue } from "@/lib/news-audience";

/** Puce du public d'une actu publiée, dans le fil et la fenêtre de lecture. */
export function NewsAudienceBadge({
  value,
  className,
}: {
  value: NewsAudienceValue;
  className?: string;
}) {
  return (
    <DsBadge icon={value.audience === "entreprise" ? "public" : "group"} className={className}>
      <span className="sr-only">Public : </span>
      {audienceLabel(value)}
    </DsBadge>
  );
}
