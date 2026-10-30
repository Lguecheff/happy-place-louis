import { createFileRoute } from "@tanstack/react-router";
import { useState } from "react";
import { BrandHeader } from "@/components/brand-header";
import { ManageIcon } from "@/components/manage/crud-ui";
import {
  StatusChip,
  SubmissionThreadView,
  sortSteps,
  type ThreadStep,
} from "@/components/submission-status-thread";
import { REJECTION_CATEGORIES, type Submission } from "@/lib/dashboard";

export const Route = createFileRoute("/_authenticated/maquettes/us01")({
  head: () => ({
    meta: [{ title: "Happy Place — Maquette : fil du statut d'une demande" }],
  }),
  component: Us01Mockup,
});

// ---------------------------------------------------------------------------
// Données factices (fictif)
// ---------------------------------------------------------------------------

type Scenario =
  "validee" | "refusee" | "automatique" | "manager" | "corrige" | "supprime" | "creation";

const SCENARIOS: { value: Scenario; label: string }[] = [
  { value: "validee", label: "Validée" },
  { value: "refusee", label: "Refusée avec motif" },
  { value: "automatique", label: "Clôture automatique" },
  { value: "manager", label: "Clôturée par un manager" },
  { value: "corrige", label: "Statut corrigé par un manager" },
  { value: "supprime", label: "Utilisateur supprimé" },
  { value: "creation", label: "Création seule" },
];

const ME = "Gontran Lemaire"; // (fictif)

type MockRequest = Pick<Submission, "id" | "content" | "team" | "created_at">;

// (fictif) Les demandes de Gontran. La première suit le scénario choisi.
const MOCK_REQUESTS: MockRequest[] = [
  {
    id: "d1",
    content:
      "Proposer un point mensuel entre recruteurs et responsables d'équipe pour suivre les missions ouvertes.",
    team: "Recrutement IT",
    created_at: "2025-03-12T09:41:00+01:00",
  },
  {
    id: "d2",
    content:
      "Ajouter un modèle de compte rendu d'entretien partagé dans l'outil de suivi des candidatures.",
    team: "Recrutement Digital",
    created_at: "2026-09-28T14:05:00+02:00",
  },
  {
    id: "d3",
    content:
      "Regrouper les relances clients en un seul rappel hebdomadaire plutôt que plusieurs envois séparés.",
    team: "Relation clients",
    created_at: "2026-06-03T11:20:00+02:00",
  },
  {
    id: "d4",
    content:
      "Créer un salon de discussion dédié aux profils data pour partager les bonnes pratiques de sourcing.",
    team: "Recrutement IT",
    created_at: "2026-05-18T16:50:00+02:00",
  },
  {
    id: "d5",
    content: "Prévoir une salle de calme à l'étage pour les appels candidats sensibles.",
    team: "Services généraux",
    created_at: "2026-04-09T10:12:00+02:00",
  },
];

type Step = ThreadStep;

function step(
  id: string,
  changed_at: string,
  old_status: string | null,
  new_status: string,
  who: { name?: string; automatic?: boolean } = {},
  rejection?: { category: string; note: string },
): Step {
  return {
    id,
    changed_at,
    old_status,
    new_status,
    changed_by_name: who.name ?? null,
    changed_by_email: null,
    is_automatic: who.automatic ?? false,
    rejection_category: rejection?.category ?? null,
    rejection_note: rejection?.note ?? null,
  };
}

const CREATION_D1 = step("d1-0", "2025-03-12T09:41:00+01:00", null, "en attente", { name: ME });

// (fictif) Fil de la demande 1, selon le scénario du sélecteur. Ordre chronologique.
const SCENARIO_STEPS: Record<Scenario, Step[]> = {
  validee: [
    CREATION_D1,
    step("d1-1", "2025-03-14T17:03:00+01:00", "en attente", "validée", { name: "Camille Roussel" }),
  ],
  refusee: [
    CREATION_D1,
    step(
      "d1-1",
      "2025-03-14T17:03:00+01:00",
      "en attente",
      "refusée",
      { name: "Camille Roussel" },
      {
        category: REJECTION_CATEGORIES[0],
        note: "Le périmètre n'est pas assez précis : merci d'indiquer qui participerait et à quelle fréquence, puis de soumettre à nouveau.",
      },
    ),
  ],
  automatique: [
    CREATION_D1,
    step("d1-1", "2025-03-14T17:03:00+01:00", "en attente", "validée", { name: "Camille Roussel" }),
    // Clôture automatique : un an sans modification après la dernière étape.
    step("d1-2", "2026-03-14T17:03:00+01:00", "validée", "clôturée", { automatic: true }),
  ],
  // Erreur humaine : clôturée par erreur, puis corrigée en validée. Chaque changement reste dans le fil.
  corrige: [
    CREATION_D1,
    step("d1-1", "2025-03-14T17:03:00+01:00", "en attente", "validée", { name: "Camille Roussel" }),
    step("d1-2", "2025-03-14T17:05:00+01:00", "validée", "clôturée", { name: "Camille Roussel" }),
    step("d1-3", "2025-03-14T17:06:00+01:00", "clôturée", "validée", { name: "Camille Roussel" }),
  ],
  manager: [
    CREATION_D1,
    step("d1-1", "2025-03-14T17:03:00+01:00", "en attente", "validée", { name: "Camille Roussel" }),
    step("d1-2", "2025-11-06T11:27:00+01:00", "validée", "clôturée", { name: "Camille Roussel" }),
  ],
  supprime: [CREATION_D1, step("d1-1", "2025-03-14T17:03:00+01:00", "en attente", "validée")],
  creation: [CREATION_D1],
};

// (fictif) Fils fixes des autres demandes.
const FIXED_STEPS: Record<string, Step[]> = {
  d2: [step("d2-0", "2026-09-28T14:05:00+02:00", null, "en attente", { name: ME })],
  d3: [
    step("d3-0", "2026-06-03T11:20:00+02:00", null, "en attente", { name: ME }),
    step("d3-1", "2026-06-05T09:30:00+02:00", "en attente", "validée", { name: "Inès Marchand" }),
  ],
  d4: [
    step("d4-0", "2026-05-18T16:50:00+02:00", null, "en attente", { name: ME }),
    step(
      "d4-1",
      "2026-05-20T10:15:00+02:00",
      "en attente",
      "refusée",
      { name: "Inès Marchand" },
      {
        category: REJECTION_CATEGORIES[2],
        note: "Un salon équivalent existe déjà pour les profils data.",
      },
    ),
  ],
  d5: [
    step("d5-0", "2026-04-09T10:12:00+02:00", null, "en attente", { name: ME }),
    step(
      "d5-1",
      "2026-04-11T15:40:00+02:00",
      "en attente",
      "refusée",
      { name: "Camille Roussel" },
      {
        category: REJECTION_CATEGORIES[3],
        note: "Hors périmètre du dashboard : à voir avec les services généraux.",
      },
    ),
  ],
};

// ---------------------------------------------------------------------------
// Présentation
// ---------------------------------------------------------------------------

function stepsFor(id: string, scenario: Scenario): Step[] {
  const chrono = id === "d1" ? SCENARIO_STEPS[scenario] : (FIXED_STEPS[id] ?? []);
  return sortSteps(chrono);
}

function Us01Mockup() {
  const [scenario, setScenario] = useState<Scenario>("validee");
  const [openId, setOpenId] = useState<string | null>(null);

  const requests = MOCK_REQUESTS.map((r) => {
    const steps = stepsFor(r.id, scenario);
    return { ...r, steps, status: steps[0]?.new_status ?? "en attente" };
  });
  const open = requests.find((r) => r.id === openId) ?? null;

  return (
    <div className="bg-background text-on-surface font-body-md min-h-screen flex flex-col">
      <BrandHeader />
      <main className="flex-grow w-full max-w-interface mx-auto p-sm md:p-md space-y-md">
        <div className="flex flex-wrap items-center gap-xs border border-dashed border-outline-variant bg-surface px-sm py-xs">
          <label
            htmlFor="mockup-scenario"
            className="font-label-sm text-label-sm uppercase text-on-surface-variant"
          >
            Maquette (fictif)
          </label>
          <select
            id="mockup-scenario"
            value={scenario}
            onChange={(e) => setScenario(e.target.value as Scenario)}
            className="border border-outline-variant bg-card px-xs py-1 font-label-md text-label-md text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
          >
            {SCENARIOS.map((s) => (
              <option key={s.value} value={s.value}>
                {s.label}
              </option>
            ))}
          </select>
          <span className="font-body-sm text-body-sm text-on-surface-variant">
            Le scénario s'applique au fil de la première demande.
          </span>
        </div>

        <div className="space-y-sm mb-lg">
          <p className="font-label-sm text-label-sm text-on-surface-variant uppercase tracking-widest">
            Espace collaborateur · {ME}
          </p>
          <h1 className="font-headline-lg text-headline-lg text-primary">Mes demandes</h1>
        </div>

        <div className="bento-grid">
          <section
            aria-labelledby="mes-demandes-titre"
            className="col-span-12 min-w-0 bg-surface-container-lowest border border-outline-variant p-md"
          >
            <h2
              id="mes-demandes-titre"
              className="font-headline-sm text-headline-sm text-primary border-b border-outline-variant pb-sm mb-md"
            >
              Demandes soumises
            </h2>
            <ul className="space-y-xs">
              {requests.map((r) => (
                <li
                  key={r.id}
                  className="flex flex-col gap-sm border border-outline-variant bg-card p-sm md:flex-row md:items-center md:justify-between"
                >
                  <div className="min-w-0 space-y-xs">
                    <p className="font-body-md text-body-md text-on-surface wrap-anywhere line-clamp-2">
                      {r.content}
                    </p>
                    <p className="flex flex-wrap items-center gap-xs font-label-sm text-label-sm uppercase text-on-surface-variant">
                      <StatusChip status={r.status} />
                      <span>{r.team}</span>
                    </p>
                  </div>
                  <button
                    type="button"
                    aria-haspopup="dialog"
                    onClick={() => setOpenId(r.id)}
                    className="flex shrink-0 items-center justify-center gap-xs border border-outline bg-surface px-md py-xs font-label-md text-label-md uppercase text-primary hover:bg-surface-container focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
                  >
                    <ManageIcon name="history" /> Voir le fil
                  </button>
                </li>
              ))}
            </ul>
          </section>
        </div>
      </main>

      {open && (
        <SubmissionThreadView
          content={open.content}
          team={open.team}
          steps={open.steps}
          onClose={() => setOpenId(null)}
        />
      )}
    </div>
  );
}
