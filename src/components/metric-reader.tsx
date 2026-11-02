import { DsKpiTile } from "@/components/ds";
import { formatDay } from "@/components/overview/overview-utils";
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
      subtitle={`Mis à jour le ${formatDay(m.updated_at)}`}
      onClose={onClose}
      onCloseAutoFocus={onCloseAutoFocus}
    >
      <DsKpiTile
        label="Valeur actuelle"
        value={formatMetricValue(m.value, m.unit)}
        {...metricTrend(m)}
      />
    </ReaderDialog>
  );
}
