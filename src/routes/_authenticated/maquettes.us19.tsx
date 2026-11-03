import { createFileRoute } from "@tanstack/react-router";
import { useRef, useState } from "react";
import { toast } from "sonner";
import { BrandHeader } from "@/components/brand-header";
import {
  DS_INPUT,
  DsBadge,
  DsButton,
  DsChoice,
  DsChoiceGroup,
  DsField,
  DsFreshness,
  DsIcon,
  DsSection,
} from "@/components/ds";
import { DS_FOCUS } from "@/components/ds/focus";
import { Linkify } from "@/components/linkify";
import { BlockerBadges } from "@/components/overview/BlockersSection";
import { OverviewHeader } from "@/components/overview/OverviewHeader";
import {
  BLOCKER_STALE_DAYS,
  daysSince,
  formatDay,
  statusLabel,
} from "@/components/overview/overview-utils";
import { ReaderDialog } from "@/components/reader-dialog";
import { GlobalSearch } from "@/components/search/GlobalSearch";
import type { Blocker } from "@/lib/dashboard";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/_authenticated/maquettes/us19")({
  head: () => ({
    meta: [{ title: "Happy Place · Maquette de la lecture d'un point bloquant" }],
  }),
  component: Us19Mockup,
});

// ---------------------------------------------------------------------------
// Données factices (fictif)
// ---------------------------------------------------------------------------

const HOUR_MS = 60 * 60_000;
const DAY_MS = 24 * HOUR_MS;
const ago = (ms: number) => new Date(Date.now() - ms).toISOString();

/** Équipe de Gontran : elle passe en premier dans « Data +2 ». */
const VIEWER_TEAM = "Data";
const ALL_TEAMS = ["Data", "Direction recrutement", "Opérations", "Product", "Relation clients"];
const IMPACT_MAX = 300;

/**
 * Phase 2 : le pôle disparaît, `teams` (une ou plusieurs équipes, vide = toutes)
 * remplace `team`, et `impact` (300 caractères maximum) arrive.
 */
type MockBlocker = Omit<Blocker, "department" | "team"> & {
  teams: string[];
  impact: string | null;
};

const CONTRACTS: MockBlocker = {
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

const ATS: MockBlocker = {
  id: "b2",
  title: "Accès au nouvel ATS en attente (fictif)",
  description: "Les comptes des recruteurs ne sont pas encore créés (fictif).",
  teams: ["Opérations", "Product", "Data"],
  severity: "warning",
  status: "EN COURS",
  created_at: ago(20 * DAY_MS),
  updated_at: ago(DAY_MS + 5 * HOUR_MS),
  impact:
    "Continue à suivre tes candidats dans l'ancien outil : rien n'est perdu, la reprise sera faite pour toi (fictif).",
};

const ONBOARDING: MockBlocker = {
  id: "b3",
  title: "Parcours d'accueil des nouveaux arrivants à revoir (fictif)",
  description: null,
  teams: [VIEWER_TEAM],
  severity: "info",
  status: "SURVEILLANCE",
  created_at: ago(30 * DAY_MS),
  updated_at: ago(3 * HOUR_MS),
  impact: "Rien à faire de ton côté pour l'instant (fictif).",
};

const ARCHIVED: MockBlocker[] = [
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

/** BlockerBadges ne lit que la sévérité et le statut. */
const asBlocker = (b: MockBlocker): Blocker => ({ ...b, department: "", team: null });

const withoutImpact = (b: MockBlocker): MockBlocker => ({ ...b, impact: null });

type MockState = {
  value: string;
  label: string;
  note: string;
  blockers: MockBlocker[];
  admin?: boolean;
  form?: boolean;
};

const STATES: MockState[] = [
  {
    value: "impact",
    label: "Point avec impact",
    note: "Clique sur un point bloquant (ou Tab puis Entrée) : sa fenêtre affiche les équipes concernées et le bloc « Ce que ça change pour toi ». Échap la ferme et rend le focus au point. Dans la liste, « Data +2 » : ton équipe d'abord, puis le nombre d'autres équipes.",
    blockers: [CONTRACTS, ATS, ONBOARDING],
  },
  {
    value: "sans-impact",
    label: "Point sans impact",
    note: "L'admin n'a rien saisi dans « Ce que ça change pour toi » : le bloc n'apparaît pas dans la fenêtre.",
    blockers: [CONTRACTS, ATS, ONBOARDING].map(withoutImpact),
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
    note: "Le sélecteur de statut reste sous le point, hors du bouton : le changer n'ouvre pas la fenêtre. Résolu reste interdit depuis Ouvert. L'admin n'a pas d'équipe : la première équipe est la première par ordre alphabétique.",
    blockers: [CONTRACTS, ATS, ONBOARDING],
    admin: true,
  },
  {
    value: "formulaire",
    label: "Formulaire admin (équipes et impact)",
    note: "« Gérer les données > Points bloquants » : le pôle disparaît, l'admin choisit « Toutes les équipes » ou coche une ou plusieurs équipes, et saisit « Ce que ça change pour toi » (300 caractères maximum).",
    blockers: [ATS],
    admin: true,
    form: true,
  },
];

const BLOCKER_STATUSES = ["OUVERT", "EN COURS", "SURVEILLANCE", "RÉSOLU"];

const notWired = () => toast.info("Non branché dans la maquette (fictif).");

/** « Toutes les équipes », ou la première équipe (celle du lecteur si elle est concernée) et « +X ». */
function teamsSummary(teams: string[], mine: string | null) {
  if (teams.length === 0) return "Toutes les équipes";
  const sorted = [...teams].sort((a, b) => a.localeCompare(b, "fr"));
  const first = mine && sorted.includes(mine) ? mine : sorted[0];
  return teams.length > 1 ? `${first} +${teams.length - 1}` : first;
}

function teamsFull(teams: string[]) {
  if (teams.length === 0) return "Toutes les équipes";
  return [...teams].sort((a, b) => a.localeCompare(b, "fr")).join(", ");
}

// ---------------------------------------------------------------------------
// Proposition validée : ligne cliquable avec contrôles dessous (variante de DsListItem)
// ---------------------------------------------------------------------------

/**
 * Le haut de la ligne est un vrai bouton (Entrée, focus visible, flèche) ;
 * `children` passe dessous, hors du bouton, pour le sélecteur de statut.
 * Entre dans DsListItem (`onClick` + `children`) en phase 2.
 */
function ProposedOpenRow({
  title,
  meta,
  onClick,
  className,
  children,
}: {
  title: React.ReactNode;
  meta?: React.ReactNode;
  onClick: (trigger: HTMLButtonElement) => void;
  className?: string;
  children?: React.ReactNode;
}) {
  return (
    <div
      className={cn(
        "flex min-w-0 flex-col border border-outline-variant bg-surface-container-lowest",
        className,
      )}
    >
      <button
        type="button"
        aria-haspopup="dialog"
        onClick={(e) => onClick(e.currentTarget)}
        className={cn(
          "flex min-h-11 w-full min-w-0 items-center gap-sm p-sm text-left hover:bg-surface-container",
          DS_FOCUS,
        )}
      >
        <span className="min-w-0 flex-1">
          <span className="block font-body-md text-body-md text-primary wrap-anywhere">
            {title}
          </span>
          {meta && (
            <span className="block font-body-sm text-body-sm text-on-surface-variant wrap-anywhere">
              {meta}
            </span>
          )}
        </span>
        <DsIcon name="arrow_forward" className="shrink-0 text-primary" />
      </button>
      {children && <div className="space-y-xs px-sm pb-sm">{children}</div>}
    </div>
  );
}

function RowTitle({ blocker: b, mine }: { blocker: MockBlocker; mine: string | null }) {
  return (
    <>
      <span className="mb-xs flex flex-wrap items-center gap-xs">
        <BlockerBadges blocker={asBlocker(b)} />
        <DsBadge>{teamsSummary(b.teams, mine)}</DsBadge>
      </span>
      {b.title}
    </>
  );
}

// ---------------------------------------------------------------------------
// Présentation
// ---------------------------------------------------------------------------

function Us19Mockup() {
  const [stateValue, setStateValue] = useState(STATES[0].value);
  const state = STATES.find((s) => s.value === stateValue) ?? STATES[0];
  const [blockers, setBlockers] = useState(state.blockers);
  const [archiveOpen, setArchiveOpen] = useState(false);
  const [reading, setReading] = useState<MockBlocker | null>(null);
  const trigger = useRef<HTMLElement | null>(null);
  const mine = state.admin ? null : VIEWER_TEAM;

  function changeState(value: string) {
    const next = STATES.find((s) => s.value === value) ?? STATES[0];
    setStateValue(next.value);
    setBlockers(next.blockers);
    setArchiveOpen(false);
    setReading(null);
  }

  // Comme updateBlockerStatus : la base remplit updated_at.
  function changeStatus(id: string, status: string) {
    const now = new Date().toISOString();
    setBlockers((bs) => bs.map((b) => (b.id === id ? { ...b, status, updated_at: now } : b)));
    toast.success(`Statut changé : ${statusLabel(status)} (fictif)`);
  }

  function open(b: MockBlocker, from: HTMLElement) {
    trigger.current = from;
    setReading(b);
  }

  // Rend le focus au point bloquant qui a ouvert la fenêtre, dans la liste ou l'archive.
  function focusTrigger(event: Event) {
    event.preventDefault();
    trigger.current?.focus();
  }

  const rows = [...blockers].sort(
    (a, b) => Number(b.severity === "critical") - Number(a.severity === "critical"),
  );

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
                data: { news: [], submissions: [], blockers: [], metrics: [] },
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
        {state.form ? (
          <div className="max-w-lg">
            <BlockerFormPreview blocker={ATS} />
          </div>
        ) : (
          <>
            <div className="space-y-xs">
              <h1 className="font-headline-lg text-headline-lg text-primary wrap-anywhere">
                {state.admin ? "Bonjour Olivia (fictif)" : "Bonjour Gontran (fictif)"}
              </h1>
              <p className="font-body-md text-body-md text-on-surface-variant">
                Voici ce qui demande ton attention aujourd'hui.
              </p>
            </div>
            <div className="max-w-lg">
              <DsSection
                id="blocages"
                title="Points bloquants"
                action={
                  <DsButton
                    variant="link"
                    className="px-0"
                    aria-haspopup="dialog"
                    onClick={() => setArchiveOpen(true)}
                  >
                    Voir l'archive
                  </DsButton>
                }
              >
                <ul className="space-y-xs">
                  {rows.map((b) => {
                    const critical = b.severity === "critical";
                    const stale = critical && daysSince(b.updated_at) > BLOCKER_STALE_DAYS;
                    const selectId = `statut-point-${b.id}`;
                    return (
                      <li key={b.id}>
                        <ProposedOpenRow
                          className={critical ? "accent-bar" : undefined}
                          onClick={(el) => open(b, el)}
                          title={<RowTitle blocker={b} mine={mine} />}
                          meta={b.description}
                        >
                          <DsFreshness at={b.updated_at} stale={stale} />
                          {state.admin && (
                            <DsField id={selectId} label={`Changer le statut de ${b.title}`}>
                              <select
                                id={selectId}
                                className={DS_INPUT}
                                value={b.status}
                                onChange={(e) => changeStatus(b.id, e.target.value)}
                              >
                                {BLOCKER_STATUSES.map((status) => {
                                  const locked = status === "RÉSOLU" && b.status === "OUVERT";
                                  return (
                                    <option
                                      key={status}
                                      value={status}
                                      disabled={locked}
                                      title={locked ? "Passe d'abord par En cours" : undefined}
                                    >
                                      {statusLabel(status)}
                                    </option>
                                  );
                                })}
                              </select>
                            </DsField>
                          )}
                        </ProposedOpenRow>
                      </li>
                    );
                  })}
                </ul>
              </DsSection>
            </div>
          </>
        )}
      </main>
      {archiveOpen && (
        <ReaderDialog
          title="Archive des points bloquants"
          subtitle="Points résolus, du plus récent au plus ancien"
          onClose={() => setArchiveOpen(false)}
        >
          <ul className="space-y-xs">
            {ARCHIVED.map((b) => (
              <li key={b.id}>
                <ProposedOpenRow
                  onClick={(el) => open(b, el)}
                  title={<RowTitle blocker={b} mine={mine} />}
                  meta={`Mis à jour le ${formatDay(b.updated_at)}`}
                />
              </li>
            ))}
          </ul>
        </ReaderDialog>
      )}
      {reading && (
        <ReaderDialog
          title={reading.title}
          subtitle={`Créé le ${formatDay(reading.created_at)} · Dernière modification le ${formatDay(reading.updated_at)}`}
          onClose={() => setReading(null)}
          onCloseAutoFocus={focusTrigger}
        >
          <div className="flex flex-wrap items-center gap-xs">
            <BlockerBadges blocker={asBlocker(reading)} />
          </div>
          <dl>
            <dt className="font-label-md text-label-md normal-case tracking-normal text-on-surface-variant">
              {reading.teams.length > 1 ? "Équipes concernées" : "Équipe concernée"}
            </dt>
            <dd className="font-body-md text-body-md text-on-surface wrap-anywhere">
              {teamsFull(reading.teams)}
            </dd>
          </dl>
          {reading.description ? (
            <p className="font-body-md text-body-md text-on-surface whitespace-pre-line wrap-anywhere">
              <Linkify text={reading.description} />
            </p>
          ) : (
            <p className="font-body-md text-body-md text-on-surface-variant">Aucune description.</p>
          )}
          {reading.impact?.trim() && (
            <section
              aria-labelledby="point-impact"
              className="space-y-xs border border-outline-variant bg-surface-container p-sm"
            >
              <h3
                id="point-impact"
                className="flex items-center gap-xs font-label-md text-label-md normal-case tracking-normal text-on-surface-variant"
              >
                <DsIcon name="person" />
                Ce que ça change pour toi
              </h3>
              <p className="font-body-md text-body-md text-on-surface whitespace-pre-line wrap-anywhere">
                {reading.impact}
              </p>
            </section>
          )}
        </ReaderDialog>
      )}
    </div>
  );
}

/** Aperçu du formulaire admin (phase 2 : remplace le pôle et l'équipe unique de manage.blockers). */
function BlockerFormPreview({ blocker }: { blocker: MockBlocker }) {
  const [allTeams, setAllTeams] = useState(blocker.teams.length === 0);
  const [teams, setTeams] = useState(blocker.teams);
  const [impact, setImpact] = useState(blocker.impact ?? "");
  const teamsError = !allTeams && teams.length === 0 ? "Coche au moins une équipe." : undefined;

  function toggleTeam(team: string, checked: boolean) {
    setTeams((ts) => (checked ? [...ts, team] : ts.filter((t) => t !== team)));
  }

  return (
    <DsSection id="formulaire" title="Modifier le point bloquant">
      <form
        className="space-y-sm"
        noValidate
        onSubmit={(e) => {
          e.preventDefault();
          notWired();
        }}
      >
        <DsField id="point-titre" label="Titre">
          <input id="point-titre" className={DS_INPUT} defaultValue={blocker.title} />
        </DsField>
        <DsField id="point-description" label="Description">
          <textarea
            id="point-description"
            rows={3}
            className={DS_INPUT}
            defaultValue={blocker.description ?? ""}
          />
        </DsField>
        <DsChoiceGroup id="point-equipes" legend="Équipes concernées" error={teamsError}>
          <DsChoice
            name="point-equipes-choix"
            label="Toutes les équipes"
            checked={allTeams}
            onChange={() => setAllTeams(true)}
          />
          <DsChoice
            name="point-equipes-choix"
            label="Certaines équipes"
            hint={!allTeams ? `${teams.length} cochée${teams.length > 1 ? "s" : ""}` : undefined}
            checked={!allTeams}
            onChange={() => setAllTeams(false)}
          />
          {!allTeams && (
            <DsChoiceGroup legend="Équipes" className="pl-lg">
              {ALL_TEAMS.map((team) => (
                <DsChoice
                  key={team}
                  type="checkbox"
                  label={team}
                  checked={teams.includes(team)}
                  onChange={(e) => toggleTeam(team, e.target.checked)}
                />
              ))}
            </DsChoiceGroup>
          )}
        </DsChoiceGroup>
        <DsField id="point-impact" label="Ce que ça change pour toi">
          <textarea
            id="point-impact"
            rows={3}
            maxLength={IMPACT_MAX}
            aria-describedby="point-impact-compte"
            className={DS_INPUT}
            value={impact}
            onChange={(e) => setImpact(e.target.value)}
          />
          <p
            id="point-impact-compte"
            className="font-label-md text-label-md normal-case tracking-normal text-on-surface-variant"
          >
            {impact.length}/{IMPACT_MAX} caractères · Laisse vide si le point ne change rien pour
            les collaborateurs.
          </p>
        </DsField>
        <p className="font-body-sm text-body-sm text-on-surface-variant">
          Sévérité et statut : inchangés (fictif).
        </p>
        <div className="flex flex-wrap justify-end gap-xs">
          <DsButton onClick={notWired}>Annuler</DsButton>
          <DsButton type="submit" variant="primary">
            Enregistrer
          </DsButton>
        </div>
      </form>
    </DsSection>
  );
}
