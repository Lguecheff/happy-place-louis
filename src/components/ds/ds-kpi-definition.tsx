import { cn } from "@/lib/utils";

export const KPI_DEFINITION_EMPTY = "Définition à venir.";

export type DsKpiDefinitionTexts = {
  definition?: string | null;
  impact?: string | null;
};

/** « Ce que ça mesure » et « Ce que ça change pour toi » ; un texte vide affiche « Définition à venir. ». */
export function DsKpiDefinition({
  definition,
  impact,
  className,
}: DsKpiDefinitionTexts & { className?: string }) {
  const rows = [
    { title: "Ce que ça mesure", text: definition },
    { title: "Ce que ça change pour toi", text: impact },
  ];
  return (
    <dl className={cn("space-y-xs", className)}>
      {rows.map(({ title, text }) => (
        <div key={title}>
          <dt className="font-label-md text-label-md normal-case tracking-normal text-on-surface-variant">
            {title}
          </dt>
          <dd className="font-body-sm text-body-sm text-on-surface wrap-anywhere">
            {text?.trim() || KPI_DEFINITION_EMPTY}
          </dd>
        </div>
      ))}
    </dl>
  );
}
