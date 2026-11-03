import { createFileRoute } from "@tanstack/react-router";
import { useRef, useState } from "react";
import { toast } from "sonner";
import { BlockerReader } from "@/components/blocker-reader";
import { BrandHeader } from "@/components/brand-header";
import { DS_INPUT, DsField } from "@/components/ds";
import { BlockersSection, type OpenBlocker } from "@/components/overview/BlockersSection";
import { KpiSection } from "@/components/overview/KpiSection";
import { OverviewHeader } from "@/components/overview/OverviewHeader";
import { GlobalSearch } from "@/components/search/GlobalSearch";
import type { Blocker, Metric } from "@/lib/dashboard";

export const Route = createFileRoute("/_authenticated/maquettes/us20")({
  head: () => ({
    meta: [{ title: "Happy Place · Maquette de l'auteur des mises à jour" }],
  }),
  component: Us20Mockup,
});

// ---------------------------------------------------------------------------
// Données factices (fictif) : les sections et les fenêtres sont les vrais composants.
// ---------------------------------------------------------------------------

const HOUR_MS = 60 * 60_000;
const DAY_MS = 24 * HOUR_MS;
const ago = (ms: number) => new Date(Date.now() - ms).toISOString();

/** Équipes de Kesha. */
const VIEWER_TEAMS = ["Data", "Product"];

const OLIVIA = "Olivia Laurent (fictif)";
/** A quitté l'entreprise : son nom, copié à la modification, reste affiché. */
const SAM = "Sam Martin (fictif)";
const AUTO = "Automatique";

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
    updated_at: ago(4 * DAY_MS + 2 * HOUR_MS),
    impact:
      "Si tu as une mission freelance qui démarre ce mois-ci, attends le feu vert avant de confirmer la date au candidat (fictif).",
  },
  {
    id: "b2",
    title: "Accès au nouvel ATS en attente (fictif)",
    description: "Les comptes des recruteurs ne sont pas encore créés (fictif).",
    teams: ["Data", "Opérations", "Product"],
    severity: "warning",
    status: "EN COURS",
    created_at: ago(20 * DAY_MS),
    updated_at: ago(DAY_MS + 5 * HOUR_MS),
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
    updated_at: ago(3 * HOUR_MS),
    impact: "Rien à faire de ton côté pour l'instant (fictif).",
  },
];

const METRICS: Metric[] = [
  {
    key: "training_kpi",
    label: "Taux de placement",
    value: 78.4,
    unit: "%",
    trend: "hausse",
    previous_value: 76.3,
    delta: 2.1,
    updated_at: ago(2 * DAY_MS),
    definition:
      "Part des candidats accompagnés qui ont signé une mission dans les 30 derniers jours (fictif).",
    impact:
      "Il fixe les priorités de l'équipe : s'il baisse, l'effort va aux candidats sans mission (fictif).",
  },
  {
    key: "active_users",
    label: "Missions actives",
    value: 142,
    unit: null,
    trend: "baisse",
    previous_value: 150,
    delta: -8,
    updated_at: ago(DAY_MS),
    definition:
      "Nombre de missions en cours aujourd'hui, de la signature du contrat à la fin de la mission (fictif).",
    impact: "Il montre la charge de suivi de tes managers (fictif).",
  },
  {
    key: "nps",
    label: "NPS candidats",
    value: 41,
    unit: null,
    trend: "stable",
    previous_value: 41,
    delta: 0,
    updated_at: ago(5 * DAY_MS),
    definition:
      "Note de recommandation donnée par les candidats à la fin de leur mission, de −100 à +100 (fictif).",
    impact: "Il dit si les candidats recommandent Happy Place (fictif).",
  },
];

/** Auteur par point bloquant (b1, b2, b3) et par KPI (dans l'ordre de METRICS). */
type Authors = { blockers: (string | null)[]; metrics: (string | null)[] };

type MockState = {
  value: string;
  label: string;
  note: string;
  authors: Authors;
};

const STATES: MockState[] = [
  {
    value: "connu",
    label: "Auteur connu",
    note: "Chaque tuile et chaque point affiche « Mis à jour il y a N jours par <nom> ». Survole la mention, ou atteins-la avec Tab : la date complète s'affiche. Sam Martin a quitté l'entreprise : son nom, copié au moment de la modification, reste affiché. Clique sur un point, ou cherche « placement » : la fenêtre de lecture affiche la même mention. Les pages « Gérer les données > KPI » et « Points bloquants » affichent la même mention, sur les vraies données.",
    authors: { blockers: [OLIVIA, SAM, OLIVIA], metrics: [OLIVIA, SAM, OLIVIA] },
  },
  {
    value: "automatique",
    label: "Automatique",
    note: "Modification faite sans utilisateur connecté (tâche planifiée, script) : la base enregistre « Automatique » à la place du nom.",
    authors: { blockers: [AUTO, OLIVIA, AUTO], metrics: [AUTO, AUTO, OLIVIA] },
  },
  {
    value: "sans-auteur",
    label: "Donnée existante sans auteur",
    note: "KPI et points modifiés avant cette évolution : la base ne connaît pas l'auteur, la mention s'arrête à « Mis à jour il y a N jours ». Le NPS a été modifié depuis : il a un auteur.",
    authors: { blockers: [null, null, null], metrics: [null, null, OLIVIA] },
  },
];

const withAuthors = <T,>(rows: T[], names: (string | null)[]) =>
  rows.map((row, i) => ({ ...row, updated_by_name: names[i] }));

const notWired = () => toast.info("Non branché dans la maquette (fictif).");

// ---------------------------------------------------------------------------
// Présentation
// ---------------------------------------------------------------------------

function Us20Mockup() {
  const [stateValue, setStateValue] = useState(STATES[0].value);
  const state = STATES.find((s) => s.value === stateValue) ?? STATES[0];
  const blockers = withAuthors(BLOCKERS, state.authors.blockers);
  const metrics = withAuthors(METRICS, state.authors.metrics);
  const [reading, setReading] = useState<Blocker | null>(null);
  const trigger = useRef<HTMLElement | null>(null);

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
          name="Kesha (fictif)"
          role="manager"
          exporting={false}
          onExport={notWired}
          search={
            <GlobalSearch
              source={{
                data: { news: [], submissions: [], blockers, metrics },
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
        <div className="space-y-xs">
          <h1 className="font-headline-lg text-headline-lg text-primary wrap-anywhere">
            Bonjour Kesha (fictif)
          </h1>
          <p className="font-body-md text-body-md text-on-surface-variant">
            Voici ce qui demande ton attention aujourd'hui.
          </p>
        </div>
        <div className="flex max-w-lg flex-col gap-md">
          <BlockersSection
            blockers={{ data: blockers, isError: false }}
            myTeams={VIEWER_TEAMS}
            canEdit={false}
            onOpen={open}
            onStatusChange={notWired}
            onOpenArchive={notWired}
          />
          <KpiSection
            key={state.value}
            metrics={{ data: metrics, isError: false }}
            canEditNps={false}
            savingNps={false}
            onSaveNps={notWired}
          />
        </div>
      </main>
      <BlockerReader
        blocker={reading}
        onClose={() => setReading(null)}
        onCloseAutoFocus={focusTrigger}
      />
    </div>
  );
}
