import { createFileRoute } from "@tanstack/react-router";
import { useState } from "react";
import { toast } from "sonner";
import { BrandHeader } from "@/components/brand-header";
import { DS_INPUT, DsField } from "@/components/ds";
import { OverviewHeader } from "@/components/overview/OverviewHeader";
import { GlobalSearch } from "@/components/search/GlobalSearch";
import type { SearchData } from "@/components/search/search-utils";
import type { Blocker, Metric, News, Submission } from "@/lib/dashboard";

export const Route = createFileRoute("/_authenticated/maquettes/us07")({
  head: () => ({
    meta: [{ title: "Happy Place · Maquette des points bloquants et KPI dans la recherche" }],
  }),
  component: Us07Mockup,
});

// ---------------------------------------------------------------------------
// Données factices (fictif), reprises du seed
// ---------------------------------------------------------------------------

type Scenario = "resultats" | "resolu" | "aucun" | "court";

const DAY_MS = 86_400_000;
const daysAgo = (days: number) => new Date(Date.now() - days * DAY_MS).toISOString();

function news(id: string, days: number, title: string, body: string): News {
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
  };
}

function submission(id: string, days: number, content: string, status: string): Submission {
  return {
    id,
    author_name: "Gontran (fictif)",
    team: "Delivery Paris",
    content: `${content} (fictif)`,
    status,
    created_at: daysAgo(days),
  };
}

function blocker(
  id: string,
  days: number,
  title: string,
  description: string,
  severity: string,
  status: string,
  updatedDays = days,
): Blocker {
  return {
    id,
    title: `${title} (fictif)`,
    description,
    department: "OPÉRATIONS",
    severity,
    status,
    created_at: daysAgo(days),
    updated_at: daysAgo(updatedDays),
  };
}

function metric(
  key: string,
  days: number,
  label: string,
  value: number,
  unit: string | null,
  trend: Metric["trend"],
  delta: number | null,
): Metric {
  return {
    key,
    label: `${label} (fictif)`,
    value,
    unit,
    trend,
    previous_value: delta === null ? null : value - delta,
    delta,
    updated_at: daysAgo(days),
  };
}

const DATA: SearchData = {
  news: [
    news(
      "n1",
      3,
      "Nouvelle grille d'entretien pour les candidats Data",
      "Elle s'applique à toutes les missions ouvertes dès lundi.",
    ),
    news("n2", 14, "Retour sur le séminaire d'automne", "Merci à toute l'équipe organisatrice."),
  ],
  submissions: [
    submission("s1", 2, "Relancer les candidats sans réponse au bout de cinq jours.", "en attente"),
    submission("s2", 21, "Ajouter un créneau de questions pour les nouvelles recrues.", "validée"),
  ],
  blockers: [
    blocker(
      "b1",
      6,
      "Délai de validation des tests techniques",
      "Le retour client dépasse actuellement cinq jours et entraîne la perte de candidats en phase finale.",
      "critical",
      "OUVERT",
      1,
    ),
    blocker(
      "b2",
      12,
      "Pénurie de profils DevSecOps seniors",
      "Trois mandats prioritaires ouverts depuis plus de 30 jours avec peu de candidats disponibles en Île-de-France.",
      "critical",
      "EN COURS",
    ),
    blocker(
      "b3",
      17,
      "Faible taux de réponse sur les profils Data",
      "Le taux de réponse aux approches directes est passé sous 18 % sur les Data Engineers seniors.",
      "warning",
      "SURVEILLANCE",
    ),
    blocker(
      "b4",
      30,
      "Import des candidatures dans l'ATS",
      "Les dossiers actifs ont été repris et contrôlés dans le nouvel outil de suivi.",
      "warning",
      "RÉSOLU",
      9,
    ),
  ],
  metrics: [
    metric("training_kpi", 8, "Taux de placement", 40.6, "%", "hausse", 2.1),
    metric("active_users", 8, "Missions actives", 34.2, null, "baisse", -1.5),
    metric("nps", 5, "NPS candidats", 71, null, "stable", null),
    metric("absenteeism", 12, "Taux de réponse candidats", 27.8, "%", "baisse", -3.4),
    metric("turnover", 15, "Délai moyen de recrutement", 31, "j", "hausse", 2),
  ],
};

const SCENARIOS: { value: Scenario; label: string; query: string; hint: string }[] = [
  {
    value: "resultats",
    label: "Résultats des 4 groupes",
    query: "candidat",
    hint: "Les 4 groupes s'affichent dans l'ordre, du plus récent au plus ancien. Flèches, Entrée pour lire, Échap pour fermer. Essaie aussi « reponse » : les accents sont ignorés.",
  },
  {
    value: "resolu",
    label: "Point bloquant résolu (archive)",
    query: "import",
    hint: "Absent de la vue d'ensemble, le point résolu reste trouvable et porte la mention « Archivé ». Entrée ouvre sa vue de lecture.",
  },
  {
    value: "aucun",
    label: "Aucun résultat",
    query: "parking",
    hint: "Le mot cherché est repris dans le message.",
  },
  {
    value: "court",
    label: "Moins de 3 caractères",
    query: "ca",
    hint: "Rien n'est cherché. Ajoute une lettre : les résultats s'affichent.",
  },
];

// ---------------------------------------------------------------------------
// Présentation
// ---------------------------------------------------------------------------

function Us07Mockup() {
  const [scenario, setScenario] = useState<Scenario>("resultats");
  const current = SCENARIOS.find((s) => s.value === scenario) ?? SCENARIOS[0];

  return (
    <div className="bg-background text-on-surface font-body-md min-h-screen flex flex-col">
      <BrandHeader>
        <OverviewHeader
          isAdmin={false}
          name="Gontran (fictif)"
          role="collaborateur"
          exporting={false}
          onExport={() => toast.info("Non branché dans la maquette (fictif).")}
          search={
            <GlobalSearch
              key={scenario}
              source={{ data: DATA, isError: false, isLoading: false }}
              defaultQuery={current.query}
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
              value={scenario}
              onChange={(e) => setScenario(e.target.value as Scenario)}
            >
              {SCENARIOS.map((s) => (
                <option key={s.value} value={s.value}>
                  {s.label}
                </option>
              ))}
            </select>
          </DsField>
          <p className="min-w-0 flex-1 basis-64 font-body-sm text-body-sm text-on-surface-variant">
            {current.hint}
          </p>
        </div>
      </main>
    </div>
  );
}
