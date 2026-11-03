import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { toast } from "sonner";
import {
  DS_INPUT,
  DsButton,
  DsChoice,
  DsChoiceGroup,
  DsEmptyState,
  DsField,
  DsListItem,
} from "@/components/ds";
import { ConfirmDelete, ErrorSummary, Modal } from "@/components/manage/crud-ui";
import { KpiTextField } from "@/components/manage/kpi-text-field";
import { severityLabel, statusLabel, teamsFull } from "@/components/overview/overview-utils";
import { supabase } from "@/integrations/supabase/client";
import {
  BLOCKER_IMPACT_MAX,
  blockerSchema,
  validate,
  type FieldErrors,
} from "@/lib/manage-schemas";
import {
  createBlocker,
  deleteBlocker,
  fetchAllBlockers,
  timeAgo,
  updateBlocker,
  type Blocker,
  type BlockerInput,
} from "@/lib/dashboard";

export const Route = createFileRoute("/_authenticated/manage/blockers")({
  head: () => ({
    meta: [
      { title: "Gestion des points bloquants — Happy Place" },
      {
        name: "description",
        content: "Créez, modifiez et supprimez les points bloquants dans Happy Place.",
      },
      { property: "og:title", content: "Gestion des points bloquants — Happy Place" },
      {
        property: "og:description",
        content: "Gérez les alertes opérationnelles des missions de recrutement dans Happy Place.",
      },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: ManageBlockers,
});

const severityLabels: Record<string, string> = {
  critical: "Critique",
  warning: "Avertissement",
  info: "Information",
};

const STATUSES = ["OUVERT", "EN COURS", "SURVEILLANCE", "RÉSOLU"];

/** `allTeams` : « Toutes les équipes » ; sinon `teams` liste les équipes cochées. */
type BlockerForm = BlockerInput & { allTeams: boolean };

const empty: BlockerForm = {
  title: "",
  description: "",
  allTeams: true,
  teams: [],
  impact: "",
  severity: "warning",
  status: "EN COURS",
};

function ManageBlockers() {
  const qc = useQueryClient();
  const [form, setForm] = useState<BlockerForm | null>(null);
  const [editing, setEditing] = useState<Blocker | null>(null);
  const [errors, setErrors] = useState<FieldErrors>({});
  const [toDelete, setToDelete] = useState<Blocker | null>(null);

  const list = useQuery({ queryKey: ["blockers", "all"], queryFn: fetchAllBlockers, retry: false });
  const teamsQuery = useQuery({
    queryKey: ["teams"],
    queryFn: async () => {
      const { data, error } = await supabase.from("teams").select("name, is_reserved");
      if (error) throw error;
      return data ?? [];
    },
  });
  const teams = (teamsQuery.data ?? [])
    .filter((t) => !t.is_reserved && t.name.toLowerCase() !== "admin")
    .map((t) => t.name)
    .sort((a, b) => a.localeCompare(b, "fr"));
  const invalidate = () => qc.invalidateQueries({ queryKey: ["blockers"] });
  const onError = (e: unknown) => toast.error((e as Error).message);

  const save = useMutation({
    mutationFn: (input: BlockerInput) =>
      editing ? updateBlocker(editing.id, input) : createBlocker(input),
    onSuccess: () => {
      toast.success(editing ? "Point bloquant modifié" : "Point bloquant créé");
      close();
      invalidate();
    },
    onError,
  });

  const remove = useMutation({
    mutationFn: (id: string) => deleteBlocker(id),
    onSuccess: () => {
      toast.success("Point bloquant supprimé");
      setToDelete(null);
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
    const { allTeams, ...input } = form;
    const res = validate(blockerSchema, { ...input, teams: allTeams ? [] : input.teams });
    const teamsError: FieldErrors =
      !allTeams && input.teams.length === 0 ? { teams: "Coche au moins une équipe." } : {};
    if (!res.ok || teamsError.teams) {
      setErrors({ ...(res.ok ? {} : res.errors), ...teamsError });
      return;
    }
    setErrors({});
    save.mutate(res.data);
  }

  return (
    <section className="space-y-md">
      <div className="flex flex-wrap items-center justify-between gap-sm">
        <h2 className="font-headline-sm text-headline-sm text-primary">
          Points bloquants ({list.data?.length ?? 0})
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
          Créer un point bloquant
        </DsButton>
      </div>

      {list.isLoading && (
        <p className="font-body-sm text-body-sm text-on-surface-variant">Chargement…</p>
      )}
      {list.isError && (
        <p className="font-body-sm text-body-sm text-error">
          Impossible de charger les points bloquants.
        </p>
      )}

      <div className="space-y-xs">
        {list.data?.map((b) => (
          <DsListItem
            key={b.id}
            icon="report"
            title={b.title}
            meta={[
              teamsFull(b.teams),
              severityLabels[b.severity] ?? severityLabel(b.severity),
              statusLabel(b.status),
              b.impact?.trim() ? "Impact saisi" : "Sans impact",
              `Modifié ${timeAgo(b.updated_at)}`,
            ].join(" · ")}
            actions={
              <>
                <DsButton
                  aria-haspopup="dialog"
                  onClick={() => {
                    setEditing(b);
                    setErrors({});
                    setForm({
                      title: b.title,
                      description: b.description ?? "",
                      allTeams: b.teams.length === 0,
                      teams: b.teams,
                      impact: b.impact ?? "",
                      severity: b.severity,
                      status: b.status,
                    });
                  }}
                >
                  Modifier
                </DsButton>
                <DsButton aria-haspopup="dialog" onClick={() => setToDelete(b)}>
                  Supprimer
                </DsButton>
              </>
            }
          />
        ))}
        {list.data?.length === 0 && <DsEmptyState>Aucun point bloquant.</DsEmptyState>}
      </div>

      {form && (
        <Modal
          title={editing ? "Modifier le point bloquant" : "Nouveau point bloquant"}
          onClose={close}
        >
          <form onSubmit={submit} className="space-y-sm" noValidate>
            <ErrorSummary errors={errors} />
            <DsField id="point-titre" label="Titre" error={errors.title}>
              <input
                id="point-titre"
                className={DS_INPUT}
                value={form.title}
                maxLength={160}
                onChange={(e) => setForm({ ...form, title: e.target.value })}
              />
            </DsField>
            <DsField id="point-description" label="Description" error={errors.description}>
              <textarea
                id="point-description"
                rows={4}
                className={DS_INPUT}
                value={form.description}
                maxLength={2000}
                onChange={(e) => setForm({ ...form, description: e.target.value })}
              />
            </DsField>
            <DsChoiceGroup id="point-equipes" legend="Équipes concernées" error={errors.teams}>
              <DsChoice
                name="point-equipes-choix"
                label="Toutes les équipes"
                checked={form.allTeams}
                onChange={() => setForm({ ...form, allTeams: true })}
              />
              <DsChoice
                name="point-equipes-choix"
                label="Certaines équipes"
                hint={
                  form.allTeams
                    ? undefined
                    : `${form.teams.length} cochée${form.teams.length > 1 ? "s" : ""}`
                }
                checked={!form.allTeams}
                onChange={() => setForm({ ...form, allTeams: false })}
              />
              {!form.allTeams && (
                <DsChoiceGroup legend="Équipes" className="pl-lg">
                  {teamsQuery.isError && (
                    <p className="font-body-sm text-body-sm text-error">
                      Les équipes sont indisponibles.
                    </p>
                  )}
                  {/* Une équipe déjà rattachée mais devenue réservée reste visible pour pouvoir la retirer. */}
                  {[...new Set([...teams, ...form.teams])]
                    .sort((a, b) => a.localeCompare(b, "fr"))
                    .map((team) => (
                      <DsChoice
                        key={team}
                        type="checkbox"
                        label={team}
                        checked={form.teams.includes(team)}
                        onChange={(e) =>
                          setForm({
                            ...form,
                            teams: e.target.checked
                              ? [...form.teams, team]
                              : form.teams.filter((t) => t !== team),
                          })
                        }
                      />
                    ))}
                </DsChoiceGroup>
              )}
            </DsChoiceGroup>
            <KpiTextField
              id="point-impact"
              label="Ce que ça change pour toi"
              max={BLOCKER_IMPACT_MAX}
              hint="Laisse vide si le point ne change rien pour les collaborateurs."
              value={form.impact}
              error={errors.impact}
              onChange={(impact) => setForm({ ...form, impact })}
            />
            <DsField id="point-severite" label="Sévérité" error={errors.severity}>
              <select
                id="point-severite"
                className={DS_INPUT}
                value={form.severity}
                onChange={(e) => setForm({ ...form, severity: e.target.value })}
              >
                <option value="critical">Critique</option>
                <option value="warning">Avertissement</option>
                <option value="info">Information</option>
              </select>
            </DsField>
            <DsField id="point-statut" label="Statut" error={errors.status}>
              <select
                id="point-statut"
                className={DS_INPUT}
                value={form.status}
                onChange={(e) => setForm({ ...form, status: e.target.value })}
              >
                {STATUSES.filter((st) => st !== "RÉSOLU" || editing).map((st) => {
                  const locked = st === "RÉSOLU" && form.status === "OUVERT";
                  return (
                    <option
                      key={st}
                      value={st}
                      disabled={locked}
                      title={locked ? "Passe d'abord par En cours" : undefined}
                    >
                      {statusLabel(st)}
                    </option>
                  );
                })}
              </select>
            </DsField>
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
          label={toDelete.title}
          pending={remove.isPending}
          onCancel={() => setToDelete(null)}
          onConfirm={() => remove.mutate(toDelete.id)}
        />
      )}
    </section>
  );
}
