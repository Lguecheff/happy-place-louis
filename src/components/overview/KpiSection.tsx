import * as DialogPrimitive from "@radix-ui/react-dialog";
import { useState } from "react";
import { DS_INPUT, DsButton, DsField, DsIcon, DsKpiTile, DsSection } from "@/components/ds";
import { DS_FOCUS } from "@/components/ds/focus";
import { TREND_LABELS, deltaText, formatMetricValue, type Metric } from "@/lib/dashboard";
import { cn } from "@/lib/utils";

/** La vue `metrics_with_trend` renvoie `updated_at`, que le type Metric ne déclare pas. */
type DatedMetric = Metric & { updated_at?: string | null };

const DIRECTIONS = { hausse: "up", baisse: "down", stable: "flat" } as const;

function tileProps(metric: DatedMetric | undefined, onHelp: () => void) {
  if (!metric) return { value: "—", onHelp };
  // Le symbole de TREND_LABELS est remplacé par la flèche de la tuile.
  const trend = TREND_LABELS[metric.trend].replace(/^\S+\s/, "");
  const delta = deltaText(metric);
  return {
    value: formatMetricValue(metric.value, metric.unit),
    trend: delta ? `${trend} · ${delta}` : trend,
    trendDirection: DIRECTIONS[metric.trend],
    updatedAt: metric.updated_at ?? undefined,
    onHelp,
  };
}

export function KpiSection({
  metrics,
  canEditNps,
  savingNps,
  onSaveNps,
}: {
  metrics: { data?: Metric[]; isError: boolean };
  canEditNps: boolean;
  savingNps: boolean;
  onSaveNps: (value: number) => void;
}) {
  const [nps, setNps] = useState("");
  const [help, setHelp] = useState<string | null>(null);
  const metric = (key: string) => metrics.data?.find((m) => m.key === key);
  const npsMetric = metric("nps");
  const npsValue = nps !== "" ? nps : (npsMetric?.value ?? "");

  return (
    <DsSection id="indicateurs" title="Indicateurs">
      {metrics.isError && (
        <p className="font-body-sm text-body-sm text-error">Les indicateurs sont indisponibles.</p>
      )}
      <div className="grid gap-sm sm:grid-cols-2">
        <DsKpiTile
          label="Taux de placement"
          {...tileProps(metric("training_kpi"), () => setHelp("Taux de placement"))}
        />
        <DsKpiTile
          label="Missions actives"
          {...tileProps(metric("active_users"), () => setHelp("Missions actives"))}
        />
        <DsKpiTile
          className="sm:col-span-2"
          label={npsMetric?.label ?? "NPS candidats"}
          {...tileProps(npsMetric, () => setHelp(npsMetric?.label ?? "NPS candidats"))}
        >
          {canEditNps && (
            <form
              className="flex flex-wrap items-end gap-xs"
              onSubmit={(e) => {
                e.preventDefault();
                onSaveNps(Number(npsValue || 0));
              }}
            >
              <DsField
                id="nps-candidats"
                label="Modifier le NPS candidats"
                className="flex-1 basis-32"
              >
                <input
                  id="nps-candidats"
                  type="number"
                  className={DS_INPUT}
                  value={npsValue}
                  onChange={(e) => setNps(e.target.value)}
                />
              </DsField>
              <DsButton type="submit" pending={savingNps}>
                Mettre à jour
              </DsButton>
            </form>
          )}
        </DsKpiTile>
      </div>
      <DialogPrimitive.Root open={!!help} onOpenChange={(o) => !o && setHelp(null)}>
        <DialogPrimitive.Portal>
          <DialogPrimitive.Overlay className="fixed inset-0 z-50 bg-black/50" />
          <DialogPrimitive.Content className="fixed left-1/2 top-1/2 z-50 w-[min(28rem,calc(100vw-2rem))] -translate-x-1/2 -translate-y-1/2 space-y-sm border border-outline bg-surface-container-lowest p-md focus:outline-none">
            <div className="flex items-start justify-between gap-sm">
              <DialogPrimitive.Title className="font-headline-sm text-headline-sm text-primary">
                {help}
              </DialogPrimitive.Title>
              <DialogPrimitive.Close
                aria-label="Fermer"
                className={cn(
                  "inline-flex size-11 shrink-0 items-center justify-center text-on-surface-variant hover:text-primary",
                  DS_FOCUS,
                )}
              >
                <DsIcon name="close" />
              </DialogPrimitive.Close>
            </div>
            <DialogPrimitive.Description className="font-body-md text-body-md text-on-surface">
              [définition à valider]
            </DialogPrimitive.Description>
          </DialogPrimitive.Content>
        </DialogPrimitive.Portal>
      </DialogPrimitive.Root>
    </DsSection>
  );
}
