import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { toast } from "sonner";
import {
  DS_INPUT,
  DsBadge,
  DsButton,
  DsEmptyState,
  DsField,
  DsFreshness,
  DsListItem,
  DsStaleBadge,
} from "@/components/ds";
import { ConfirmDelete, ErrorSummary, Modal } from "@/components/manage/crud-ui";
import { metricSchema, validate, type FieldErrors } from "@/lib/manage-schemas";
import { KpiTextField } from "@/components/manage/kpi-text-field";
import { MetricHistory } from "@/components/manage/metric-history";
import { VerifyMetricButton } from "@/components/overview/KpiSection";
import { isVerified, metricStaleDays } from "@/components/overview/overview-utils";
import {
  createMetric,
  deleteMetric,
  fetchMetrics,
  deltaText,
  formatMetricValue,
  updateMetricRow,
  verifyMetric,
  TREND_LABELS,
  type Metric,
  type MetricInput,
} from "@/lib/dashboard";

export const Route = createFileRoute("/_authenticated/manage/metrics")({
  head: () => ({
    meta: [
      { title: "Gestion des indicateurs — Happy Place" },
      {
        name: "description",
        content: "Créez, modifiez et supprimez les indicateurs de Happy Place.",
      },
      { property: "og:title", content: "Gestion des indicateurs — Happy Place" },
      {
        property: "og:description",
        content: "Gérez les indicateurs de performance dans Happy Place.",
      },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: ManageMetrics,
});

type FormState = {
  key: string;
  label: string;
  value: string;
  unit: string;
  definition: string;
  impact: string;
  staleAfterDays: string;
};

const empty: FormState = {
  key: "",
  label: "",
  value: "",
  unit: "",
  definition: "",
  impact: "",
  staleAfterDays: "",
};

const orNull = (text: string) => (text.trim() === "" ? null : text);

/** Nombre saisi, ou NaN pour un champ vide ou invalide (le schéma l'explique). */
function toNumber(text: string) {
  const raw = text.trim().replace(",", ".");
  return raw === "" || Number.isNaN(Number(raw)) ? Number.NaN : Number(raw);
}

function thresholdLabel(days: number) {
  return `Seuil « à vérifier » : ${days} jour${days > 1 ? "s" : ""}`;
}

function ManageMetrics() {
  const qc = useQueryClient();
  const [form, setForm] = useState<FormState | null>(null);
  const [editing, setEditing] = useState<Metric | null>(null);
  const [errors, setErrors] = useState<FieldErrors>({});
  const [toDelete, setToDelete] = useState<Metric | null>(null);

  const list = useQuery({ queryKey: ["metrics"], queryFn: fetchMetrics, retry: false });
  const invalidate = () => qc.invalidateQueries({ queryKey: ["metrics"] });
  const onError = (e: unknown) => toast.error((e as Error).message);

  const save = useMutation({
    mutationFn: (input: MetricInput) =>
      editing ? updateMetricRow(editing.key, input) : createMetric(input),
    onSuccess: async () => {
      toast.success(editing ? "Indicateur modifié" : "Indicateur créé");
      close();
      await invalidate();
    },
    onError,
  });

  const remove = useMutation({
    mutationFn: (key: string) => deleteMetric(key),
    onSuccess: () => {
      toast.success("Indicateur supprimé");
      setToDelete(null);
      invalidate();
    },
    onError,
  });

  const verify = useMutation({
    mutationFn: (key: string) => verifyMetric(key),
    onSuccess: () => {
      toast.success("KPI marqué comme vérifié");
      invalidate();
    },
    onError,
  });

  function close() {
    setForm(null);
    setEditing(null);
    setErrors({});
  }

  function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!form) return;
    const candidate = {
      key: form.key,
      label: form.label,
      value: toNumber(form.value),
      unit: orNull(form.unit),
      definition: orNull(form.definition),
      impact: orNull(form.impact),
      stale_after_days: toNumber(form.staleAfterDays),
    };
    const res = validate(metricSchema, candidate);
    if (!res.ok) {
      setErrors(res.errors);
      return;
    }
    setErrors({});
    save.mutate(res.data);
  }

  return (
    <section className="space-y-md">
      <div className="flex flex-wrap items-center justify-between gap-sm">
        <h2 className="font-headline-sm text-headline-sm text-primary">
          Indicateurs ({list.data?.length ?? 0})
        </h2>
        <DsButton
          variant="primary"
          icon="add"
          aria-haspopup="dialog"
          onClick={() => {
            setEditing(null);
            setErrors({});
            setForm({ ...empty });
          }}
        >
          Créer un indicateur
        </DsButton>
      </div>

      {list.isLoading && (
        <p className="font-body-sm text-body-sm text-on-surface-variant">Chargement…</p>
      )}
      {list.isError && (
        <p className="font-body-sm text-body-sm text-error">
          Impossible de charger les indicateurs.
        </p>
      )}

      <div className="space-y-xs">
        {list.data?.map((m) => {
          const staleDays = metricStaleDays(m);
          return (
            <DsListItem
              key={m.key}
              icon="monitoring"
              title={`${m.label} — ${formatMetricValue(m.value, m.unit)}`}
              meta={[
                m.key,
                TREND_LABELS[m.trend],
                m.previous_value != null && deltaText(m),
                m.previous_value != null &&
                  `avant : ${formatMetricValue(m.previous_value, m.unit).replace(/%$/, " %")}`,
              ]
                .filter(Boolean)
                .join(" · ")}
              actions={
                <>
                  <DsButton
                    aria-haspopup="dialog"
                    onClick={() => {
                      setEditing(m);
                      setErrors({});
                      setForm({
                        key: m.key,
                        label: m.label,
                        value: String(m.value),
                        unit: m.unit ?? "",
                        definition: m.definition ?? "",
                        impact: m.impact ?? "",
                        staleAfterDays:
                          m.stale_after_days != null ? String(m.stale_after_days) : "",
                      });
                    }}
                  >
                    Modifier
                  </DsButton>
                  <DsButton aria-haspopup="dialog" onClick={() => setToDelete(m)}>
                    Supprimer
                  </DsButton>
                </>
              }
            >
              <span className="flex flex-wrap items-center gap-xs">
                {m.stale_after_days == null ? (
                  <DsBadge icon="edit_calendar">Seuil à définir</DsBadge>
                ) : (
                  <DsBadge>{thresholdLabel(m.stale_after_days)}</DsBadge>
                )}
                {staleDays != null && <DsStaleBadge days={staleDays} />}
                <DsFreshness at={m.updated_at} by={m.updated_by_name} verified={isVerified(m)} />
              </span>
              {staleDays != null && (
                <VerifyMetricButton
                  pending={verify.isPending && verify.variables === m.key}
                  onVerify={() => verify.mutate(m.key)}
                />
              )}
              <MetricHistory metricKey={m.key} unit={m.unit} />
            </DsListItem>
          );
        })}
        {list.data?.length === 0 && <DsEmptyState>Aucun indicateur.</DsEmptyState>}
      </div>

      {form && (
        <Modal title={editing ? "Modifier l'indicateur" : "Nouvel indicateur"} onClose={close}>
          <form onSubmit={submit} className="space-y-sm" noValidate>
            <ErrorSummary errors={errors} />
            <DsField id="kpi-cle" label="Clé technique" error={errors.key}>
              <input
                id="kpi-cle"
                className={DS_INPUT}
                value={form.key}
                disabled={!!editing}
                maxLength={40}
                placeholder="ex : taux_placement"
                onChange={(e) => setForm({ ...form, key: e.target.value })}
              />
            </DsField>
            <DsField id="kpi-libelle" label="Libellé" error={errors.label}>
              <input
                id="kpi-libelle"
                className={DS_INPUT}
                value={form.label}
                maxLength={60}
                onChange={(e) => setForm({ ...form, label: e.target.value })}
              />
            </DsField>
            <DsField id="kpi-valeur" label="Valeur" error={errors.value}>
              <input
                id="kpi-valeur"
                className={DS_INPUT}
                value={form.value}
                inputMode="decimal"
                onChange={(e) => setForm({ ...form, value: e.target.value })}
              />
            </DsField>
            <DsField id="kpi-unite" label="Unité (optionnel)" error={errors.unit}>
              <input
                id="kpi-unite"
                className={DS_INPUT}
                value={form.unit}
                maxLength={8}
                placeholder="%"
                onChange={(e) => setForm({ ...form, unit: e.target.value })}
              />
            </DsField>
            <DsField
              id="kpi-seuil"
              label="Seuil « à vérifier » (jours)"
              error={errors.stale_after_days}
            >
              <input
                id="kpi-seuil"
                type="number"
                inputMode="numeric"
                min={1}
                max={365}
                step={1}
                required
                aria-invalid={!!errors.stale_after_days}
                aria-describedby="kpi-seuil-aide"
                className={DS_INPUT}
                value={form.staleAfterDays}
                onChange={(e) => setForm({ ...form, staleAfterDays: e.target.value })}
              />
              <p
                id="kpi-seuil-aide"
                className="font-label-md text-label-md normal-case tracking-normal text-on-surface-variant"
              >
                Au-delà de ce nombre de jours sans mise à jour, le KPI porte le badge « À vérifier
                ».
              </p>
            </DsField>
            <KpiTextField
              id="kpi-definition"
              label="Ce que ça mesure"
              value={form.definition}
              error={errors.definition}
              onChange={(definition) => setForm({ ...form, definition })}
            />
            <KpiTextField
              id="kpi-impact"
              label="Ce que ça change pour toi"
              value={form.impact}
              error={errors.impact}
              onChange={(impact) => setForm({ ...form, impact })}
            />
            <p className="font-body-sm text-body-sm text-on-surface-variant">
              Un texte vide affiche « Définition à venir. ».
            </p>
            <div className="flex flex-wrap justify-end gap-xs pt-sm">
              <DsButton onClick={close}>Annuler</DsButton>
              <DsButton type="submit" variant="confirm" icon="check" pending={save.isPending}>
                Enregistrer
              </DsButton>
            </div>
          </form>
        </Modal>
      )}

      {toDelete && (
        <ConfirmDelete
          label={toDelete.label}
          pending={remove.isPending}
          onCancel={() => setToDelete(null)}
          onConfirm={() => remove.mutate(toDelete.key)}
        />
      )}
    </section>
  );
}
