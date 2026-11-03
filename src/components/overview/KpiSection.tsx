import * as DialogPrimitive from "@radix-ui/react-dialog";
import { useState } from "react";
import {
  DS_INPUT,
  DsButton,
  DsField,
  DsIcon,
  DsKpiDefinition,
  DsKpiTile,
  DsSection,
} from "@/components/ds";
import { DS_FOCUS } from "@/components/ds/focus";
import { formatMetricValue, metricTrend, type Metric } from "@/lib/dashboard";
import { cn } from "@/lib/utils";

type Help = { label: string; metric?: Metric };

function tileProps(metric: Metric | undefined, onHelp: () => void) {
  const definition = { definition: metric?.definition, impact: metric?.impact };
  if (!metric) return { value: "—", onHelp, definition };
  return {
    value: formatMetricValue(metric.value, metric.unit),
    ...metricTrend(metric),
    updatedAt: metric.updated_at,
    onHelp,
    definition,
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
  const [help, setHelp] = useState<Help | null>(null);
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
          {...tileProps(metric("training_kpi"), () =>
            setHelp({ label: "Taux de placement", metric: metric("training_kpi") }),
          )}
        />
        <DsKpiTile
          label="Missions actives"
          {...tileProps(metric("active_users"), () =>
            setHelp({ label: "Missions actives", metric: metric("active_users") }),
          )}
        />
        <DsKpiTile
          className="sm:col-span-2"
          label={npsMetric?.label ?? "NPS candidats"}
          {...tileProps(npsMetric, () =>
            setHelp({ label: npsMetric?.label ?? "NPS candidats", metric: npsMetric }),
          )}
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
                {help?.label}
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
            <DialogPrimitive.Description asChild>
              <div>
                <DsKpiDefinition
                  definition={help?.metric?.definition}
                  impact={help?.metric?.impact}
                />
              </div>
            </DialogPrimitive.Description>
          </DialogPrimitive.Content>
        </DialogPrimitive.Portal>
      </DialogPrimitive.Root>
    </DsSection>
  );
}
