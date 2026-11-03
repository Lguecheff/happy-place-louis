import { createFileRoute } from "@tanstack/react-router";
import { useRef, useState } from "react";
import { toast } from "sonner";
import { BlockerReader } from "@/components/blocker-reader";
import { BrandHeader } from "@/components/brand-header";
import { DS_INPUT, DsField, DsListItem } from "@/components/ds";
import {
  BlockersSection,
  BlockerTitle,
  type OpenBlocker,
} from "@/components/overview/BlockersSection";
import { OverviewHeader } from "@/components/overview/OverviewHeader";
import { formatDay, statusLabel } from "@/components/overview/overview-utils";
import { ReaderDialog } from "@/components/reader-dialog";
import { GlobalSearch } from "@/components/search/GlobalSearch";
import type { Blocker } from "@/lib/dashboard";

export const Route = createFileRoute("/_authenticated/maquettes/us19")({
  head: () => ({
    meta: [{ title: "Happy Place · Maquette de la lecture d'un point bloquant" }],
  }),
  component: Us19Mockup,
});

// ---------------------------------------------------------------------------
// Données factices (fictif) : la liste et la fenêtre sont les vrais composants.
// ---------------------------------------------------------------------------

const HOUR_MS = 60 * 60_000;
const DAY_MS = 24 * HOUR_MS;
const ago = (ms: number) => new Date(Date.now() - ms).toISOString();

/** Équipe de Gontran : elle passe en premier dans « Data +2 ». */
const VIEWER_TEAMS = ["Data"];

const CONTRACTS: Blocker = {
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
};

const ATS: Blocker = {
  id: "b2",
  title: "Accès au nouvel ATS en attente (fictif)",
  description: "Les comptes des recruteurs ne sont pas encore créés (fictif).",
  teams: ["Data", "Opérations", "Product"],
  severity: "warning",
  status: "EN COURS",
  created_at: ago(20 * DAY_MS),
  updated_at: ago(DAY_MS + 5 * HOUR_MS),
  impact:
    "Continue à suivre tes candidats dans l'ancien outil : rien n'est perdu, la reprise sera faite pour toi (fictif).",
};

const ONBOARDING: Blocker = {
  id: "b3",
  title: "Parcours d'accueil des nouveaux arrivants à revoir (fictif)",
  description: null,
  teams: ["Data"],
  severity: "info",
  status: "SURVEILLANCE",
  created_at: ago(30 * DAY_MS),
  updated_at: ago(3 * HOUR_MS),
  impact: "Rien à faire de ton côté pour l'instant (fictif).",
};

const ARCHIVED: Blocker[] = [
  {
    id: "a1",
    title: "Panne de la signature électronique (fictif)",
    description:
      "Le prestataire a rétabli le service ; les contrats en attente sont partis (fictif).",
    teams: [],
    severity: "critical",
    status: "RÉSOLU",
    created_at: ago(40 * DAY_MS),
    updated_at: ago(9 * DAY_MS),
    impact: "Vérifie que tes contrats de la semaine du 20 sont bien signés (fictif).",
  },
  {
    id: "a2",
    title: "Export des feuilles de temps indisponible (fictif)",
    description: "Corrigé par l'équipe Tech (fictif).",
    teams: ["Data", "Relation clients"],
    severity: "warning",
    status: "RÉSOLU",
    created_at: ago(60 * DAY_MS),
    updated_at: ago(25 * DAY_MS),
    impact: null,
  },
];

type MockState = {
  value: string;
  label: string;
  note: string;
  blockers: Blocker[];
  admin?: boolean;
};

const STATES: MockState[] = [
  {
    value: "impact",
    label: "Point avec impact",
    note: "Clique sur un point bloquant (ou Tab puis Entrée) : sa fenêtre affiche les équipes concernées et le bloc « Ce que ça change pour toi ». Échap la ferme et rend le focus au point.",
    blockers: [CONTRACTS, ATS, ONBOARDING],
  },
  {
    value: "sans-impact",
    label: "Point sans impact",
    note: "L'admin n'a rien saisi dans « Ce que ça change pour toi » : le bloc n'apparaît pas dans la fenêtre.",
    blockers: [CONTRACTS, ATS, ONBOARDING].map((b) => ({ ...b, impact: null })),
  },
  {
    value: "archive",
    label: "Point archivé",
    note: "Clique sur « Voir l'archive », puis sur un point résolu : il s'ouvre de la même façon, avec « Archivé ». Échap ferme la fenêtre du point, puis l'archive.",
    blockers: [CONTRACTS, ATS, ONBOARDING],
  },
  {
    value: "admin",
    label: "Vue admin (sélecteur de statut)",
    note: "Le sélecteur de statut reste sous le point, hors du bouton : le changer n'ouvre pas la fenêtre. Le formulaire (équipes, « Ce que ça change pour toi ») est dans « Gérer les données > Points bloquants ».",
    blockers: [CONTRACTS, ATS, ONBOARDING],
    admin: true,
  },
];

const notWired = () => toast.info("Non branché dans la maquette (fictif).");

function Us19Mockup() {
  const [stateValue, setStateValue] = useState(STATES[0].value);
  const state = STATES.find((s) => s.value === stateValue) ?? STATES[0];
  const [blockers, setBlockers] = useState(state.blockers);
  const [archiveOpen, setArchiveOpen] = useState(false);
  const [reading, setReading] = useState<Blocker | null>(null);
  const trigger = useRef<HTMLElement | null>(null);
  const myTeams = state.admin ? [] : VIEWER_TEAMS;

  function changeState(value: string) {
    const next = STATES.find((s) => s.value === value) ?? STATES[0];
    setStateValue(next.value);
    setBlockers(next.blockers);
    setArchiveOpen(false);
    setReading(null);
  }

  function changeStatus(id: string, status: string) {
    const now = new Date().toISOString();
    setBlockers((bs) => bs.map((b) => (b.id === id ? { ...b, status, updated_at: now } : b)));
    toast.success(`Statut changé : ${statusLabel(status)} (fictif)`);
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
          isAdmin={!!state.admin}
          name={state.admin ? "Olivia Laurent (fictif)" : "Gontran (fictif)"}
          role={state.admin ? "admin" : "collaborateur"}
          exporting={false}
          onExport={notWired}
          search={
            <GlobalSearch
              source={{
                data: { news: [], submissions: [], blockers, metrics: [] },
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
              onChange={(e) => changeState(e.target.value)}
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
            {state.admin ? "Bonjour Olivia (fictif)" : "Bonjour Gontran (fictif)"}
          </h1>
          <p className="font-body-md text-body-md text-on-surface-variant">
            Voici ce qui demande ton attention aujourd'hui.
          </p>
        </div>
        <div className="max-w-lg">
          <BlockersSection
            blockers={{ data: blockers, isError: false }}
            myTeams={myTeams}
            canEdit={!!state.admin}
            onOpen={open}
            onStatusChange={changeStatus}
            onOpenArchive={() => setArchiveOpen(true)}
          />
        </div>
      </main>
      {/* BlockerArchive lit la base : même présentation, avec des points résolus fictifs. */}
      {archiveOpen && (
        <ReaderDialog
          title="Archive des points bloquants"
          subtitle="Points résolus, du plus récent au plus ancien"
          onClose={() => setArchiveOpen(false)}
        >
          <div className="space-y-xs">
            {ARCHIVED.map((b) => (
              <DsListItem
                key={b.id}
                title={<BlockerTitle blocker={b} myTeams={myTeams} />}
                meta={`Mis à jour le ${formatDay(b.updated_at)}`}
                opensDialog
                onClick={(e) => open(b, e.currentTarget)}
              />
            ))}
          </div>
        </ReaderDialog>
      )}
      <BlockerReader
        blocker={reading}
        onClose={() => setReading(null)}
        onCloseAutoFocus={focusTrigger}
      />
    </div>
  );
}
