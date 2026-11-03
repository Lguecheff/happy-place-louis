import { DS_INPUT, DsField } from "@/components/ds";

export const KPI_TEXT_MAX = 200;

/** Champ de texte d'un KPI (« Ce que ça mesure », « Ce que ça change pour toi ») avec compteur. */
export function KpiTextField({
  id,
  label,
  value,
  error,
  onChange,
}: {
  id: string;
  label: string;
  value: string;
  error?: string;
  onChange: (value: string) => void;
}) {
  return (
    <DsField id={id} label={label} error={error}>
      <textarea
        id={id}
        rows={3}
        maxLength={KPI_TEXT_MAX}
        aria-describedby={`${id}-compte`}
        className={DS_INPUT}
        value={value}
        onChange={(e) => onChange(e.target.value)}
      />
      <p
        id={`${id}-compte`}
        className="font-label-md text-label-md normal-case tracking-normal text-on-surface-variant"
      >
        {value.length}/{KPI_TEXT_MAX} caractères
      </p>
    </DsField>
  );
}
