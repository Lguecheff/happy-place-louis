import { DsKpiDefinition, DsKpiTile } from "@/components/ds";
import { VerifyMetricButton } from "@/components/overview/KpiSection";
import { isVerified, metricAlert } from "@/components/overview/overview-utils";
import { ReaderDialog } from "@/components/reader-dialog";
import { formatMetricValue, metricTrend, type Metric } from "@/lib/dashboard";

/** Fenêtre de lecture d'un KPI (lecture seule). */
export function MetricReader({
  metric: m,
  onClose,
  onCloseAutoFocus,
  onVerify,
  verifying,
}: {
  metric: Metric | null;
  onClose: () => void;
  onCloseAutoFocus?: (event: Event) => void;
  /** Admin et manager ; sans valeur, pas de bouton « Marquer comme vérifié ». */
  onVerify?: () => void;
  verifying?: boolean;
}) {
  if (!m) return null;
  const alert = metricAlert(m);
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
        alert={alert}
        verified={isVerified(m)}
      >
        {onVerify && alert && <VerifyMetricButton pending={verifying} onVerify={onVerify} />}
      </DsKpiTile>
      <DsKpiDefinition definition={m.definition} impact={m.impact} />
    </ReaderDialog>
  );
}
