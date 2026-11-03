import { DS_INPUT, DsField } from "@/components/ds";

export const KPI_TEXT_MAX = 200;

/** Champ de texte court avec compteur (textes d'un KPI, impact d'un point bloquant). */
export function KpiTextField({
  id,
  label,
  value,
  max = KPI_TEXT_MAX,
  hint,
  error,
  onChange,
}: {
  id: string;
  label: string;
  value: string;
  max?: number;
  /** Phrase d'aide après le compteur. */
  hint?: string;
  error?: string;
  onChange: (value: string) => void;
}) {
  return (
    <DsField id={id} label={label} error={error}>
      <textarea
        id={id}
        rows={3}
        maxLength={max}
        aria-describedby={`${id}-compte`}
        className={DS_INPUT}
        value={value}
        onChange={(e) => onChange(e.target.value)}
      />
      <p
        id={`${id}-compte`}
        className="font-label-md text-label-md normal-case tracking-normal text-on-surface-variant"
      >
        {value.length}/{max} caractères{hint && ` · ${hint}`}
      </p>
    </DsField>
  );
}
