import { createFileRoute } from "@tanstack/react-router";
import { useRef, useState } from "react";
import { toast } from "sonner";
import { BlockerReader } from "@/components/blocker-reader";
import { BrandHeader } from "@/components/brand-header";
import {
  DS_INPUT,
  DsBadge,
  DsButton,
  DsField,
  DsFreshness,
  DsListItem,
  DsSection,
  DsStaleBadge,
} from "@/components/ds";
import {
  BlockersSection,
  ConfirmUpToDate,
  type OpenBlocker,
} from "@/components/overview/BlockersSection";
import { KpiSection } from "@/components/overview/KpiSection";
import { OverviewHeader } from "@/components/overview/OverviewHeader";
import { isConfirmed, metricStaleDays } from "@/components/overview/overview-utils";
import { GlobalSearch } from "@/components/search/GlobalSearch";
import { formatMetricValue, type Blocker, type Metric } from "@/lib/dashboard";

export const Route = createFileRoute("/_authenticated/maquettes/us21")({
  head: () => ({
    meta: [{ title: "Happy Place · Maquette du signal à vérifier" }],
  }),
  component: Us21Mockup,
});

// ---------------------------------------------------------------------------
// Données factices (fictif) : les sections et les fenêtres sont les vrais composants.
// ---------------------------------------------------------------------------

const HOUR_MS = 60 * 60_000;
const DAY_MS = 24 * HOUR_MS;
const ago = (ms: number) => new Date(Date.now() - ms).toISOString();

const OLIVIA = "Olivia Laurent (fictif)";
const KESHA = "Kesha (fictif)";

type Viewer = { name: string; role: "collaborateur" | "manager"; teams: string[] };
const GONTRAN: Viewer = { name: "Gontran (fictif)", role: "collaborateur", teams: ["Data"] };
const KESHA_VIEWER: Viewer = { name: KESHA, role: "manager", teams: ["Data", "Product"] };

const BLOCKERS: Blocker[] = [
  {
    id: "b1",
    title: "Signature des contrats freelance bloquée (fictif)",
    description:
      "Le service juridique attend la nouvelle trame de contrat : trois missions ne peuvent pas démarrer (fictif).",
    teams: [],
    severity: "critical",
    status: "OUVERT",
    created_at: ago(12 * DAY_MS),
    updated_at: ago(5 * DAY_MS),
    updated_by_name: OLIVIA,
    impact: "Attends le feu vert avant de confirmer une date de démarrage (fictif).",
  },
  {
    id: "b2",
    title: "Accès au nouvel ATS en attente (fictif)",
    description: "Les comptes des recruteurs ne sont pas encore créés (fictif).",
    teams: ["Data", "Opérations", "Product"],
    severity: "warning",
    status: "EN COURS",
    created_at: ago(20 * DAY_MS),
    updated_at: ago(4 * DAY_MS + 2 * HOUR_MS),
    updated_by_name: OLIVIA,
    impact: null,
  },
  {
    id: "b3",
    title: "Parcours d'accueil des nouveaux arrivants à revoir (fictif)",
    description: null,
    teams: ["Data"],
    severity: "info",
    status: "SURVEILLANCE",
    created_at: ago(30 * DAY_MS),
    updated_at: ago(DAY_MS + 3 * HOUR_MS),
    updated_by_name: OLIVIA,
    impact: null,
  },
  {
    id: "b4",
    title: "Planning des astreintes non publié (fictif)",
    description: "L'équipe Opérations attend la validation du planning de décembre (fictif).",
    teams: ["Opérations"],
    severity: "warning",
    status: "OUVERT",
    created_at: ago(9 * DAY_MS),
    updated_at: ago(6 * DAY_MS),
    updated_by_name: OLIVIA,
    impact: null,
  },
];

const METRIC_TEXTS = {
  training_kpi: {
    definition: "Part des candidats placés en mission sur 30 jours (fictif).",
    impact: "S'il baisse, l'effort va aux candidats sans mission (fictif).",
  },
  active_users: {
    definition: "Missions en cours aujourd'hui (fictif).",
    impact: "Il montre la charge de suivi des managers (fictif).",
  },
  nps: {
    definition: "Note de recommandation des candidats, de −100 à +100 (fictif).",
    impact: "Il dit si les candidats recommandent Happy Place (fictif).",
  },
};

/** `activeDays` : ancienneté de « Missions actives » (seuil 1 jour) selon l'état. */
function metrics(activeDays: number): Metric[] {
  return [
    {
      key: "training_kpi",
      label: "Taux de placement",
      value: 78.4,
      unit: "%",
      trend: "hausse",
      previous_value: 76.3,
      delta: 2.1,
      updated_at: ago(2 * DAY_MS),
      updated_by_name: OLIVIA,
      stale_after_days: 7,
      ...METRIC_TEXTS.training_kpi,
    },
    {
      key: "active_users",
      label: "Missions actives",
      value: 142,
      unit: null,
      trend: "baisse",
      previous_value: 150,
      delta: -8,
      updated_at: ago(activeDays * DAY_MS),
      updated_by_name: "Automatique",
      stale_after_days: 1,
      ...METRIC_TEXTS.active_users,
    },
    {
      key: "nps",
      label: "NPS candidats",
      value: 41,
      unit: null,
      trend: "stable",
      previous_value: 41,
      delta: 0,
      updated_at: ago(20 * DAY_MS),
      updated_by_name: OLIVIA,
      // KPI créé avant l'US21 : sans seuil, jamais de badge.
      stale_after_days: null,
      ...METRIC_TEXTS.nps,
    },
  ];
}

type MockState = {
  value: string;
  label: string;
  note: string;
  viewer: Viewer;
  activeDays: number;
  /** Points et KPI déjà confirmés par Kesha à l'ouverture de l'état. */
  confirmed?: string[];
  /** Affiche l'aperçu de « Gérer les données > KPI » (admin). */
  manage?: boolean;
};

const STATES: MockState[] = [
  {
    value: "point-collaborateur",
    label: "Point à vérifier (vue collaborateur)",
    note: "Vue de Gontran. Tout point non résolu sans mise à jour depuis plus de 3 jours porte « À vérifier », quelle que soit sa sévérité (ici un critique, deux à surveiller). Survole le badge, ou atteins-le avec Tab : « Sans mise à jour depuis N jours. L'information est peut-être dépassée. ». Gontran ne voit aucun bouton. Le badge apparaît aussi dans la recherche (cherche « fictif ») et dans la fenêtre de lecture.",
    viewer: GONTRAN,
    activeDays: 0.5,
  },
  {
    value: "point-manager",
    label: "Point à vérifier (vue manager, bouton)",
    note: "Vue de Kesha (Data, Product). « Confirmer à jour » apparaît sur le point de ses équipes (ATS). Pas de bouton sur le point des Opérations, ni sur le point « Toutes les équipes » : selon les critères, seul l'admin le confirme (point à trancher). Clique sur le bouton pour voir l'effet.",
    viewer: KESHA_VIEWER,
    activeDays: 0.5,
  },
  {
    value: "kpi-seuil",
    label: "KPI au-delà de son seuil",
    note: "« Missions actives » a un seuil d'1 jour et n'a pas bougé depuis 3 jours : badge et bouton pour Kesha (tous les KPI). « Taux de placement » (seuil 7 jours, mis à jour il y a 2 jours) n'a pas de badge. Le NPS n'a pas de seuil : pas de badge, même après 20 jours.",
    viewer: KESHA_VIEWER,
    activeDays: 3,
  },
  {
    value: "kpi-sans-seuil",
    label: "KPI sans seuil (Gérer les données)",
    note: "Aperçu de « Gérer les données > KPI » (réservé à l'admin) : un KPI sans seuil affiche « Seuil à définir ». Le seuil est obligatoire à la création : un entier de 1 à 365. L'aperçu montre le champ avec son message d'erreur.",
    viewer: KESHA_VIEWER,
    activeDays: 3,
    manage: true,
  },
  {
    value: "apres-confirmation",
    label: "Après confirmation",
    note: "Kesha a confirmé l'ATS et « Missions actives » : le badge disparaît, la mention devient « Confirmé à jour à l'instant par Kesha ». Les autres champs (statut, valeur, tendance) ne changent pas. Le compteur repart de zéro : l'alerte de l'US16 ne reviendra que dans 3 jours.",
    viewer: KESHA_VIEWER,
    activeDays: 3,
    confirmed: ["b2", "active_users"],
  },
];

/** La confirmation ne touche que la date, l'auteur et la date de confirmation. */
function confirmRow<T extends { updated_at: string }>(row: T, at: string) {
  return { ...row, updated_at: at, updated_by_name: KESHA, confirmed_at: at };
}

const notWired = () => toast.info("Non branché dans la maquette (fictif).");

// ---------------------------------------------------------------------------
// Aperçu de « Gérer les données > KPI » (admin)
// ---------------------------------------------------------------------------

function ManageMetricsPreview({
  rows,
  onConfirm,
}: {
  rows: Metric[];
  onConfirm: (m: Metric) => void;
}) {
  const [threshold, setThreshold] = useState("");
  const [submitted, setSubmitted] = useState(false);
  const n = Number(threshold);
  const error =
    submitted && !(Number.isInteger(n) && n >= 1 && n <= 365 && threshold.trim() !== "")
      ? "Indique un nombre entier de jours, de 1 à 365."
      : undefined;
  return (
    <>
      <DsSection id="gerer-kpi" title="Gérer les données > KPI (aperçu, vue admin)">
        <div className="space-y-xs">
          {rows.map((m) => {
            const staleDays = metricStaleDays(m);
            return (
              <DsListItem
                key={m.key}
                icon="monitoring"
                title={`${m.label} — ${formatMetricValue(m.value, m.unit)}`}
                meta={`${m.key} (fictif)`}
                actions={<DsButton onClick={notWired}>Modifier</DsButton>}
              >
                <span className="flex flex-wrap items-center gap-xs">
                  {m.stale_after_days == null ? (
                    <DsBadge icon="edit_calendar">Seuil à définir</DsBadge>
                  ) : (
                    <DsBadge>
                      Seuil « à vérifier » : {m.stale_after_days} jour
                      {m.stale_after_days > 1 ? "s" : ""}
                    </DsBadge>
                  )}
                  {staleDays != null && <DsStaleBadge days={staleDays} />}
                  <DsFreshness
                    at={m.updated_at}
                    by={m.updated_by_name}
                    confirmed={isConfirmed(m)}
                  />
                </span>
                {staleDays != null && <ConfirmUpToDate onConfirm={() => onConfirm(m)} />}
              </DsListItem>
            );
          })}
        </div>
      </DsSection>
      <DsSection id="nouveau-kpi" title="Nouvel indicateur (extrait du formulaire)">
        <form
          className="flex flex-wrap items-end gap-xs"
          noValidate
          onSubmit={(e) => {
            e.preventDefault();
            setSubmitted(true);
            if (Number.isInteger(n) && n >= 1 && n <= 365) toast.success("Seuil valide (fictif).");
          }}
        >
          <DsField
            id="kpi-seuil"
            label="Seuil « à vérifier » (jours)"
            error={error}
            className="flex-1 basis-48"
          >
            <input
              id="kpi-seuil"
              type="number"
              inputMode="numeric"
              min={1}
              max={365}
              step={1}
              required
              aria-invalid={!!error}
              className={DS_INPUT}
              value={threshold}
              onChange={(e) => setThreshold(e.target.value)}
            />
          </DsField>
          <DsButton type="submit">Vérifier le champ</DsButton>
        </form>
        <p className="mt-xs font-body-sm text-body-sm text-on-surface-variant">
          Au-delà de ce nombre de jours sans mise à jour, le KPI porte le badge « À vérifier ».
        </p>
      </DsSection>
    </>
  );
}

// ---------------------------------------------------------------------------
// Présentation
// ---------------------------------------------------------------------------

function Us21Mockup() {
  const [stateValue, setStateValue] = useState(STATES[0].value);
  const state = STATES.find((s) => s.value === stateValue) ?? STATES[0];
  const [initialAt] = useState(() => ago(2 * 60_000));
  /** Confirmations faites dans la maquette : id du point ou clé du KPI → date. */
  const [confirmedAt, setConfirmedAt] = useState<Record<string, string>>({});
  const [reading, setReading] = useState<Blocker | null>(null);
  const trigger = useRef<HTMLElement | null>(null);

  const isManager = state.viewer.role === "manager";
  const confirmations = {
    ...Object.fromEntries((state.confirmed ?? []).map((id) => [id, initialAt])),
    ...confirmedAt,
  };
  const at = (id: string) => confirmations[id] as string | undefined;
  const blockers = BLOCKERS.map((b) => (at(b.id) ? confirmRow(b, at(b.id)!) : b));
  const metricRows = metrics(state.activeDays).map((m) =>
    at(m.key) ? confirmRow(m, at(m.key)!) : m,
  );
  const readingRow = reading && (blockers.find((b) => b.id === reading.id) ?? null);

  // Manager : points dont une équipe est la sienne ; « Toutes les équipes » reste à l'admin.
  const canConfirmBlocker = (b: Blocker) =>
    isManager && b.teams.some((t) => state.viewer.teams.includes(t));

  function confirm(id: string) {
    setConfirmedAt((c) => ({ ...c, [id]: new Date().toISOString() }));
    toast.success("Confirmé à jour (fictif).");
  }

  const open: OpenBlocker = (b, from) => {
    trigger.current = from;
    setReading(b);
  };

  function focusTrigger(event: Event) {
    event.preventDefault();
    trigger.current?.focus();
  }

  return (
    <div className="bg-background text-on-surface font-body-md min-h-screen flex flex-col">
      <BrandHeader>
        <OverviewHeader
          isAdmin={false}
          name={state.viewer.name}
          role={state.viewer.role}
          exporting={false}
          onExport={notWired}
          search={
            <GlobalSearch
              key={state.value}
              source={{
                data: { news: [], submissions: [], blockers, metrics: metricRows },
                isError: false,
                isLoading: false,
              }}
            />
          }
        />
      </BrandHeader>
      <main className="flex-grow w-full max-w-interface mx-auto p-sm md:p-md space-y-md">
        <div className="flex flex-wrap items-end gap-sm border border-dashed border-outline-variant p-sm">
          <DsField id="maquette-etat" label="Maquette (fictif)" className="w-full md:w-72">
            <select
              id="maquette-etat"
              className={DS_INPUT}
              value={state.value}
              onChange={(e) => {
                setStateValue(e.target.value);
                setConfirmedAt({});
                setReading(null);
              }}
            >
              {STATES.map((s) => (
                <option key={s.value} value={s.value}>
                  {s.label}
                </option>
              ))}
            </select>
          </DsField>
          <p className="min-w-0 flex-1 basis-64 font-body-sm text-body-sm text-on-surface">
            {state.note}
          </p>
        </div>
        {state.manage ? (
          <div className="flex max-w-lg flex-col gap-md">
            <ManageMetricsPreview rows={metricRows} onConfirm={(m) => confirm(m.key)} />
          </div>
        ) : (
          <>
            <div className="space-y-xs">
              <h1 className="font-headline-lg text-headline-lg text-primary wrap-anywhere">
                Bonjour {state.viewer.name}
              </h1>
              <p className="font-body-md text-body-md text-on-surface-variant">
                Voici ce qui demande ton attention aujourd'hui.
              </p>
            </div>
            <div className="flex max-w-lg flex-col gap-md">
              <BlockersSection
                blockers={{ data: blockers, isError: false }}
                myTeams={state.viewer.teams}
                canEdit={false}
                onOpen={open}
                onStatusChange={notWired}
                onOpenArchive={notWired}
                canConfirm={canConfirmBlocker}
                onConfirm={(b) => confirm(b.id)}
              />
              <KpiSection
                key={state.value}
                metrics={{ data: metricRows, isError: false }}
                canEditNps={false}
                savingNps={false}
                onSaveNps={notWired}
                onConfirm={isManager ? (m) => confirm(m.key) : undefined}
              />
            </div>
          </>
        )}
      </main>
      <BlockerReader
        blocker={readingRow}
        onClose={() => setReading(null)}
        onCloseAutoFocus={focusTrigger}
        onConfirm={
          readingRow && canConfirmBlocker(readingRow) ? () => confirm(readingRow.id) : undefined
        }
      />
    </div>
  );
}
