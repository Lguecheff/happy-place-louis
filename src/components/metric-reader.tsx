import { DsKpiDefinition, DsKpiTile } from "@/components/ds";
import { ConfirmUpToDate } from "@/components/overview/BlockersSection";
import { isConfirmed, metricStaleDays } from "@/components/overview/overview-utils";
import { ReaderDialog } from "@/components/reader-dialog";
import { formatMetricValue, metricTrend, type Metric } from "@/lib/dashboard";

/** Fenêtre de lecture d'un KPI (lecture seule). */
export function MetricReader({
  metric: m,
  onClose,
  onCloseAutoFocus,
  onConfirm,
  confirming,
}: {
  metric: Metric | null;
  onClose: () => void;
  onCloseAutoFocus?: (event: Event) => void;
  /** Admin et manager ; sans valeur, pas de bouton « Confirmer à jour ». */
  onConfirm?: () => void;
  confirming?: boolean;
}) {
  if (!m) return null;
  const staleDays = metricStaleDays(m);
  return (
    <ReaderDialog
      title={m.label}
      subtitle="Indicateur"
      onClose={onClose}
      onCloseAutoFocus={onCloseAutoFocus}
    >
      <DsKpiTile
        label="Valeur actuelle"
        value={formatMetricValue(m.value, m.unit)}
        {...metricTrend(m)}
        updatedAt={m.updated_at}
        updatedBy={m.updated_by_name}
        staleDays={staleDays}
        confirmed={isConfirmed(m)}
      >
        {onConfirm && staleDays != null && (
          <ConfirmUpToDate pending={confirming} onConfirm={onConfirm} />
        )}
      </DsKpiTile>
      <DsKpiDefinition definition={m.definition} impact={m.impact} />
    </ReaderDialog>
  );
}
