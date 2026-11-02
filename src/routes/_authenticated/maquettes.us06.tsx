import { createFileRoute } from "@tanstack/react-router";
import { useState } from "react";
import { toast } from "sonner";
import { BrandHeader } from "@/components/brand-header";
import { DS_INPUT, DsButton, DsField, DsSection } from "@/components/ds";
import { OverviewHeader } from "@/components/overview/OverviewHeader";
import { GlobalSearch } from "@/components/search/GlobalSearch";
import type { SearchData } from "@/components/search/search-utils";
import type { AppRole } from "@/lib/auth";
import type { News, Submission } from "@/lib/dashboard";

export const Route = createFileRoute("/_authenticated/maquettes/us06")({
  head: () => ({
    meta: [{ title: "Happy Place · Maquette de la barre de recherche" }],
  }),
  component: Us06Mockup,
});

// ---------------------------------------------------------------------------
// Données factices (fictif)
// ---------------------------------------------------------------------------

type Scenario = "court" | "resultats" | "aucun" | "limite" | "admin";

const DAY_MS = 86_400_000;
const daysAgo = (days: number) => new Date(Date.now() - days * DAY_MS).toISOString();

function news(id: string, days: number, title: string, body: string, status = "publiée"): News {
  const at = daysAgo(days);
  return {
    id,
    title: `${title} (fictif)`,
    body,
    author: "Kesha (fictif)",
    author_email: "kesha@fictif.test",
    status,
    created_at: at,
    updated_at: at,
    published_at: status === "publiée" ? at : null,
    links: [],
  };
}

function submission(id: string, days: number, content: string, status: string): Submission {
  return {
    id,
    author_name: "Gontran (fictif)",
    team: "Delivery Paris",
    content,
    status,
    created_at: daysAgo(days),
    ...(status === "refusée"
      ? { rejection_category: "Hors périmètre", rejection_note: "Motif du refus (fictif)." }
      : {}),
  };
}

const BASE: SearchData = {
  news: [
    news(
      "n1",
      2,
      "Bienvenue aux nouvelles recrues de l'équipe Delivery",
      "Trois consultants nous rejoignent ce mois-ci.",
    ),
    news(
      "n2",
      9,
      "Retour sur le séminaire d'automne",
      "Un grand merci à toute l'équipe organisatrice pour ces deux jours à Lyon, et à chaque intervenant pour son temps.",
    ),
    news("n3", 20, "Nouvelle offre cadre IT", "Un poste de directeur technique à pourvoir."),
  ],
  submissions: [
    submission("s1", 1, "Ajouter une salle calme pour l'Équipe support le vendredi.", "en attente"),
    submission(
      "s2",
      12,
      "Mettre en place un rituel d'accueil pour chaque nouvelle personne qui rejoint une equipe, avec un parrain désigné dès le premier jour.",
      "validée",
    ),
    submission("s3", 30, "Financer un afterwork d'équipe chaque trimestre.", "refusée"),
    submission("s4", 60, "Revoir les horaires d'astreinte de l'équipe.", "clôturée"),
  ],
};

const LIMITE: SearchData = {
  news: Array.from({ length: 23 }, (_, i) =>
    news(`l${i}`, i + 1, `Point mission n° ${i + 1}`, "Avancement hebdomadaire."),
  ),
  submissions: Array.from({ length: 20 }, (_, i) =>
    submission(`d${i}`, i + 1, `Demande de suivi de la mission n° ${i + 1}.`, "validée"),
  ),
};

// (fictif) Un admin lit les brouillons de tout le monde : ils arrivent dans les données, pas dans les résultats.
const ADMIN: SearchData = {
  ...BASE,
  news: [
    ...BASE.news,
    news("b1", 1, "Budget formation 2027", "Brouillon de Sam, jamais affiché.", "brouillon"),
    news("b2", 3, "Budget des événements", "Brouillon de l'admin, écarté aussi.", "brouillon"),
    news("n4", 15, "Budget formation 2026 reconduit", "Les inscriptions sont ouvertes."),
  ],
};

const SCENARIOS: {
  value: Scenario;
  label: string;
  query: string;
  data: SearchData;
  role: AppRole;
  name: string;
  hint: string;
}[] = [
  {
    value: "court",
    label: "Moins de 3 caractères",
    query: "éq",
    data: BASE,
    role: "collaborateur",
    name: "Gontran",
    hint: "Rien n'est cherché. Ajoute une lettre : les résultats s'affichent.",
  },
  {
    value: "resultats",
    label: "Résultats",
    query: "equipe",
    data: BASE,
    role: "collaborateur",
    name: "Gontran",
    hint: "« equipe » trouve « équipe » et « Équipe ». Flèches, Entrée pour lire, Échap pour fermer.",
  },
  {
    value: "aucun",
    label: "Aucun résultat",
    query: "parking",
    data: BASE,
    role: "collaborateur",
    name: "Gontran",
    hint: "Le mot cherché est repris dans le message.",
  },
  {
    value: "limite",
    label: "20 résultats (limite)",
    query: "mission",
    data: LIMITE,
    role: "collaborateur",
    name: "Gontran",
    hint: "23 actus trouvées, 20 listées et la mention s'affiche. 20 demandes trouvées, pas de mention.",
  },
  {
    value: "admin",
    label: "Admin (brouillons écartés)",
    query: "budget",
    data: ADMIN,
    role: "admin",
    name: "Claire",
    hint: "Les données contiennent 2 brouillons sur le budget : seule l'actu publiée ressort.",
  },
];

// ---------------------------------------------------------------------------
// Présentation
// ---------------------------------------------------------------------------

function ModulePlaceholder({ id, title }: { id: string; title: string }) {
  return (
    <DsSection id={id} title={title} className="bg-surface-container">
      <p className="font-body-sm text-body-sm text-on-surface-variant">
        Module existant, non modifié (fictif).
      </p>
    </DsSection>
  );
}

function Us06Mockup() {
  const [scenario, setScenario] = useState<Scenario>("resultats");
  const current = SCENARIOS.find((s) => s.value === scenario) ?? SCENARIOS[0];

  return (
    <div className="bg-background text-on-surface font-body-md min-h-screen flex flex-col">
      <BrandHeader>
        <OverviewHeader
          isAdmin={current.role === "admin"}
          name={`${current.name} (fictif)`}
          role={current.role}
          exporting={false}
          onExport={() => toast.info("Non branché dans la maquette (fictif).")}
          search={
            <GlobalSearch
              key={scenario}
              source={{ data: current.data, isError: false, isLoading: false }}
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

        <div className="flex flex-wrap items-end justify-between gap-sm">
          <div className="min-w-0 space-y-xs">
            <h1 className="font-headline-lg text-headline-lg text-primary">
              Bonjour {current.name}
            </h1>
            <p className="font-body-md text-body-md text-on-surface-variant">
              Voici ce qui demande ton attention aujourd'hui.
            </p>
          </div>
          <DsButton
            variant="primary"
            onClick={() => toast.info("Non branché dans la maquette (fictif).")}
          >
            Faire une demande
          </DsButton>
        </div>

        <div className="flex flex-wrap items-start gap-md">
          <div className="flex min-w-0 flex-[999_1_620px] flex-col gap-md">
            <ModulePlaceholder id="demandes" title="Demandes" />
            <ModulePlaceholder id="actus" title="Actualités" />
          </div>
          <div className="flex min-w-0 flex-[1_1_380px] flex-col gap-md">
            <ModulePlaceholder id="blocages" title="Points bloquants" />
            <ModulePlaceholder id="indicateurs" title="Indicateurs" />
          </div>
        </div>
      </main>
    </div>
  );
}
