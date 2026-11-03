import { DsKpiDefinition, DsKpiTile } from "@/components/ds";
import { ReaderDialog } from "@/components/reader-dialog";
import { formatMetricValue, metricTrend, type Metric } from "@/lib/dashboard";

/** Fenêtre de lecture d'un KPI (lecture seule). */
export function MetricReader({
  metric: m,
  onClose,
  onCloseAutoFocus,
}: {
  metric: Metric | null;
  onClose: () => void;
  onCloseAutoFocus?: (event: Event) => void;
}) {
  if (!m) return null;
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
      />
      <DsKpiDefinition definition={m.definition} impact={m.impact} />
    </ReaderDialog>
  );
}
