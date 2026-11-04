import { createFileRoute } from "@tanstack/react-router";
import { useState } from "react";
import { toast } from "sonner";
import { BrandHeader } from "@/components/brand-header";
import { DS_INPUT, DsButton, DsField } from "@/components/ds";
import { OverviewHeader } from "@/components/overview/OverviewHeader";
import { GlobalSearch } from "@/components/search/GlobalSearch";
import {
  EMPTY_FILTERS,
  type SearchData,
  type SearchFilters,
} from "@/components/search/search-utils";
import type { Blocker, Metric, News, Submission } from "@/lib/dashboard";
import type { NewsAudience } from "@/lib/news-audience";

export const Route = createFileRoute("/_authenticated/maquettes/us23")({
  head: () => ({
    meta: [{ title: "Happy Place · Maquette des filtres de recherche" }],
  }),
  component: Us23Mockup,
});

// ---------------------------------------------------------------------------
// Données factices (fictif)
// ---------------------------------------------------------------------------

const DAY_MS = 86_400_000;
const daysAgo = (days: number) => new Date(Date.now() - days * DAY_MS).toISOString();

/** Référentiel factice, sans « Admin » (comme le public des actus, US8). */
const TEAMS = ["Marketing", "Pôle Data et IA", "Product", "Relation clients"];

function news(
  id: string,
  days: number,
  title: string,
  body: string,
  audience: NewsAudience,
  teams: string[] = [],
): News {
  const at = daysAgo(days);
  return {
    id,
    title: `${title} (fictif)`,
    body,
    author: "Kesha (fictif)",
    author_email: "kesha@fictif.test",
    status: "publiée",
    created_at: at,
    updated_at: at,
    published_at: at,
    links: [],
    audience,
    teams,
  };
}

function submission(
  id: string,
  days: number,
  team: string,
  content: string,
  status: string,
): Submission {
  return {
    id,
    author_name: "Gontran (fictif)",
    team,
    content: `${content} (fictif)`,
    status,
    created_at: daysAgo(days),
  };
}

function blocker(
  id: string,
  createdDays: number,
  updatedDays: number,
  teams: string[],
  title: string,
  description: string,
): Blocker {
  return {
    id,
    title: `${title} (fictif)`,
    description,
    teams,
    severity: "warning",
    status: "OUVERT",
    created_at: daysAgo(createdDays),
    updated_at: daysAgo(updatedDays),
  };
}

function metric(key: string, days: number, label: string, value: number, unit: string): Metric {
  return {
    key,
    label: `${label} (fictif)`,
    value,
    unit,
    trend: "stable",
    previous_value: null,
    delta: null,
    updated_at: daysAgo(days),
    definition: null,
    impact: null,
  };
}

const DATA: SearchData = {
  news: [
    news(
      "n1",
      2,
      "Nouveau parcours d'onboarding Product",
      "Chaque arrivée a un binôme pendant deux semaines.",
      "équipe",
      ["Product"],
    ),
    news(
      "n2",
      10,
      "Onboarding : la checklist commune",
      "La même liste pour toutes les équipes, à partir de lundi.",
      "entreprise",
    ),
    news(
      "n4",
      5,
      "Onboarding Marketing : les outils de campagne",
      "Une demi-journée de prise en main pour chaque arrivée.",
      "équipe",
      ["Marketing"],
    ),
    news(
      "n3",
      40,
      "Retour sur l'onboarding de septembre",
      "Les arrivées de septembre ont noté leur première semaine.",
      "équipe",
      ["Marketing", "Product"],
    ),
  ],
  submissions: [
    submission("s1", 3, "Product", "Ajouter un binôme pendant l'onboarding.", "en attente"),
    submission("s2", 18, "Marketing", "Raccourcir l'onboarding des outils.", "validée"),
    submission("s3", 50, "Product", "Traduire le guide d'onboarding en anglais.", "validée"),
  ],
  blockers: [
    blocker(
      "b1",
      25,
      4,
      ["Product"],
      "Accès aux outils pendant l'onboarding",
      "Les comptes arrivent trois jours après la prise de poste.",
    ),
    blocker(
      "b2",
      12,
      12,
      [],
      "Onboarding retardé par le matériel",
      "Les ordinateurs portables sont livrés en retard, toutes équipes confondues.",
    ),
    blocker(
      "b3",
      60,
      35,
      ["Marketing"],
      "Salle d'onboarding indisponible",
      "La salle du 3e étage est réservée jusqu'à fin novembre.",
    ),
  ],
  metrics: [
    metric("onboarding_days", 6, "Durée moyenne d'onboarding", 9, "j"),
    metric("onboarding_nps", 20, "Satisfaction onboarding", 8.1, "/10"),
  ],
};

type State = {
  value: string;
  label: string;
  query: string;
  filters: SearchFilters;
  hint: string;
};

const STATES: State[] = [
  {
    value: "court",
    label: "Moins de 3 caractères",
    query: "on",
    filters: EMPTY_FILTERS,
    hint: "Les trois filtres sont visibles mais désactivés. Le message reste affiché. Ajoute une lettre : ils deviennent actifs. La croix vide le champ et les filtres.",
  },
  {
    value: "type",
    label: "Filtre Type",
    query: "onboarding",
    filters: { ...EMPTY_FILTERS, type: "demandes" },
    hint: "Type « Demandes » : seul le groupe Demandes reste, avec son compteur. Le total annoncé suit.",
  },
  {
    value: "equipe",
    label: "Filtre Équipe",
    query: "onboarding",
    filters: { ...EMPTY_FILTERS, teams: ["Product", "Relation clients"] },
    hint: "Équipes « Product » et « Relation clients » (« Product +1 ») : seul ce qui vise uniquement d'autres équipes disparaît (l'actu, la demande et le point du Marketing). L'actu « Toute l'entreprise », le point sans équipe et les KPI restent. Clique sur Équipe pour cocher ou décocher.",
  },
  {
    value: "periode",
    label: "Filtre Période",
    query: "onboarding",
    filters: { ...EMPTY_FILTERS, period: "7" },
    hint: "7 derniers jours : le point bloquant créé il y a 25 jours reste, car il a été mis à jour il y a 4 jours. Il est toujours rangé par date de création.",
  },
  {
    value: "aucun",
    label: "Aucun résultat avec ces filtres",
    query: "onboarding",
    filters: { ...EMPTY_FILTERS, type: "demandes", teams: ["Relation clients"] },
    hint: "Demandes de l'équipe « Relation clients » : aucune ne parle d'onboarding. « Effacer les filtres » remet Tous, Toutes, Tout et garde le mot cherché ; la croix vide aussi le mot.",
  },
];

const notWired = () => toast.info("Non branché dans la maquette (fictif).");

// ---------------------------------------------------------------------------
// Présentation
// ---------------------------------------------------------------------------

function Us23Mockup() {
  const [stateValue, setStateValue] = useState(STATES[0].value);
  const state = STATES.find((s) => s.value === stateValue) ?? STATES[0];

  return (
    <div className="bg-background text-on-surface font-body-md min-h-screen flex flex-col">
      <BrandHeader>
        <OverviewHeader
          isAdmin={false}
          name="Gontran (fictif)"
          role="collaborateur"
          exporting={false}
          onExport={notWired}
          search={
            <GlobalSearch
              key={state.value}
              source={{ data: DATA, isError: false, isLoading: false }}
              defaultQuery={state.query}
              teams={TEAMS}
              defaultFilters={state.filters}
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
              onChange={(e) => setStateValue(e.target.value)}
            >
              {STATES.map((s) => (
                <option key={s.value} value={s.value}>
                  {s.label}
                </option>
              ))}
            </select>
          </DsField>
          <p className="min-w-0 flex-1 basis-64 font-body-sm text-body-sm text-on-surface">
            {state.hint}
          </p>
        </div>

        <div className="flex flex-wrap items-end justify-between gap-sm">
          <div className="min-w-0 space-y-xs">
            <h1 className="font-headline-lg text-headline-lg text-primary wrap-anywhere">
              Bonjour Gontran (fictif)
            </h1>
            <p className="font-body-md text-body-md text-on-surface-variant">
              Voici ce qui demande ton attention aujourd'hui.
            </p>
          </div>
          <DsButton variant="primary" onClick={notWired}>
            Faire une demande
          </DsButton>
        </div>
      </main>
    </div>
  );
}
