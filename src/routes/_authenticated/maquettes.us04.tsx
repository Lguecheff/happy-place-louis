import { createFileRoute } from "@tanstack/react-router";
import { useRef, useState } from "react";
import { flushSync } from "react-dom";
import { toast } from "sonner";
import { BrandHeader } from "@/components/brand-header";
import { DS_INPUT, DsButton, DsField, DsSection } from "@/components/ds";
import { NewsReader } from "@/components/news-reader";
import { NewsSection, type DraftInput } from "@/components/overview/NewsSection";
import { TodayStrip } from "@/components/overview/TodayStrip";
import { myDrafts, publishedThisMonth } from "@/components/overview/overview-utils";
import type { News } from "@/lib/dashboard";

export const Route = createFileRoute("/_authenticated/maquettes/us04")({
  head: () => ({
    meta: [{ title: "Happy Place · Maquette des brouillons" }],
  }),
  component: Us04Mockup,
});

// ---------------------------------------------------------------------------
// Données factices (fictif)
// ---------------------------------------------------------------------------

type Scenario = "quatre" | "sans-titre" | "aucun" | "admin" | "collaborateur";
type Variant = "open" | "open-publish";

const KESHA = "kesha@fictif.test";
const CLAIRE = "claire@fictif.test";
const SAM = "sam@fictif.test";

const SCENARIOS: { value: Scenario; label: string; name: string; email: string; hint: string }[] = [
  {
    value: "quatre",
    label: "4 brouillons",
    name: "Kesha",
    email: KESHA,
    hint: "Du plus ancien au plus récent. Publie un brouillon : la ligne disparaît et les compteurs baissent.",
  },
  {
    value: "sans-titre",
    label: "Brouillon sans titre",
    name: "Kesha",
    email: KESHA,
    hint: "Ouvre le brouillon sans titre et publie-le : le message s'affiche sous le champ Titre et rien n'est publié.",
  },
  {
    value: "aucun",
    label: "Aucun brouillon",
    name: "Kesha",
    email: KESHA,
    hint: "Le bloc reste en place et l'indique.",
  },
  {
    value: "admin",
    label: "Admin (seulement ses brouillons)",
    name: "Claire",
    email: CLAIRE,
    hint: "La base renvoie 5 brouillons à l'admin : les 3 de Sam et Kesha sont écartés, le compteur suit.",
  },
  {
    value: "collaborateur",
    label: "Collaborateur (bloc absent)",
    name: "Thomas",
    email: "thomas@fictif.test",
    hint: "Ni bloc, ni rédacteur, ni tuile de brouillons : il ne reste que les actus publiées.",
  },
];

const VARIANTS: { value: Variant; label: string; hint: string }[] = [
  {
    value: "open",
    label: "A : conforme à DESIGN.md",
    hint: "Ligne cliquable sans bouton : on publie depuis le rédacteur.",
  },
  {
    value: "open-publish",
    label: "B : DsListItem étendu",
    hint: "Ligne cliquable avec Publier à côté.",
  },
];

const DAY_MS = 86_400_000;
const daysAgo = (days: number) => new Date(Date.now() - days * DAY_MS).toISOString();

function draft(id: string, email: string, days: number, title: string, body: string): News {
  return {
    id,
    title: title && `${title} (fictif)`,
    body,
    author: `${email.split("@")[0]} (fictif)`,
    author_email: email,
    status: "brouillon",
    created_at: daysAgo(days),
    updated_at: daysAgo(days),
    links: [],
  };
}

function published(id: string, email: string, days: number, title: string): News {
  return {
    ...draft(id, email, days, title, "Texte de l'actu (fictif)."),
    status: "publiée",
    published_at: daysAgo(days),
  };
}

const PUBLISHED: News[] = [
  published("p1", KESHA, 0.5, "Bienvenue aux nouvelles recrues"),
  published("p2", CLAIRE, 40, "Résultats du trimestre"),
];

// (fictif) Brouillons volontairement dans le désordre : le bloc les trie.
function draftsFor(scenario: Scenario): News[] {
  const kesha = [
    draft("b1", KESHA, 5, "Nouveau partenariat école", "Texte du brouillon (fictif)."),
    draft("b2", KESHA, 21, "Retour sur le séminaire d'automne", "Texte du brouillon (fictif)."),
    draft("b3", KESHA, 0, "Point mensuel", ""),
    draft("b4", KESHA, 12, "Nouvelle offre cadre IT", "Texte du brouillon (fictif)."),
  ];
  if (scenario === "quatre") return kesha;
  if (scenario === "sans-titre") {
    return [draft("b5", KESHA, 9, "", "Notes pour le prochain point d'équipe (fictif)."), kesha[0]];
  }
  if (scenario === "admin") {
    return [
      draft("c1", CLAIRE, 3, "Charte des entretiens", "Texte du brouillon (fictif)."),
      draft("c2", CLAIRE, 15, "Calendrier des congés", "Texte du brouillon (fictif)."),
      draft("s1", SAM, 30, "Brouillon de Sam", "Texte du brouillon (fictif)."),
      kesha[1],
      kesha[3],
    ];
  }
  return [];
}

function newsFor(scenario: Scenario) {
  return [...draftsFor(scenario), ...PUBLISHED];
}

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

function Us04Mockup() {
  const [scenario, setScenario] = useState<Scenario>("quatre");
  const [variant, setVariant] = useState<Variant>("open");
  const [news, setNews] = useState(() => newsFor("quatre"));
  const [composerOpen, setComposerOpen] = useState(false);
  const [reading, setReading] = useState<News | null>(null);
  const composerTitle = useRef<HTMLInputElement>(null);

  const current = SCENARIOS.find((s) => s.value === scenario) ?? SCENARIOS[0];
  const currentVariant = VARIANTS.find((v) => v.value === variant) ?? VARIANTS[0];
  const canWrite = scenario !== "collaborateur";
  const publishedCount = publishedThisMonth(news, current.email);

  const changeScenario = (value: Scenario) => {
    setScenario(value);
    setNews(newsFor(value));
    setComposerOpen(false);
  };

  const applyDraft = (input: DraftInput, list: News[]) => {
    const fields = { title: input.title, body: input.body, updated_at: daysAgo(0) };
    if (input.id) return list.map((n) => (n.id === input.id ? { ...n, ...fields } : n));
    const created = draft(crypto.randomUUID(), current.email, 0, "", input.body);
    return [{ ...created, title: input.title }, ...list];
  };

  const publish = (id: string, list: News[]) =>
    list.map((n) => (n.id === id ? { ...n, status: "publiée", published_at: daysAgo(0) } : n));

  const openComposer = () => {
    flushSync(() => setComposerOpen(true));
    composerTitle.current?.focus();
  };

  return (
    <div className="bg-background text-on-surface font-body-md min-h-screen flex flex-col">
      <BrandHeader>
        <span className="font-label-md text-label-md normal-case tracking-normal text-on-surface-variant">
          Happy Place
        </span>
      </BrandHeader>
      <main className="flex-grow w-full max-w-interface mx-auto p-sm md:p-md space-y-md">
        <div className="flex flex-wrap items-end gap-sm border border-dashed border-outline-variant p-sm">
          <DsField id="maquette-etat" label="Maquette (fictif)" className="w-full md:w-72">
            <select
              id="maquette-etat"
              className={DS_INPUT}
              value={scenario}
              onChange={(e) => changeScenario(e.target.value as Scenario)}
            >
              {SCENARIOS.map((s) => (
                <option key={s.value} value={s.value}>
                  {s.label}
                </option>
              ))}
            </select>
          </DsField>
          <DsField id="maquette-ligne" label="Ligne (fictif)" className="w-full md:w-72">
            <select
              id="maquette-ligne"
              className={DS_INPUT}
              value={variant}
              onChange={(e) => setVariant(e.target.value as Variant)}
            >
              {VARIANTS.map((v) => (
                <option key={v.value} value={v.value}>
                  {v.label}
                </option>
              ))}
            </select>
          </DsField>
          <p className="min-w-0 flex-1 basis-64 font-body-sm text-body-sm text-on-surface-variant">
            {current.hint} {canWrite && currentVariant.hint}
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
          <div className="flex flex-wrap gap-xs">
            <DsButton
              variant={canWrite ? "secondary" : "primary"}
              onClick={() => toast.info("Non branché dans la maquette (fictif).")}
            >
              Faire une demande
            </DsButton>
            {canWrite && (
              <DsButton variant="primary" icon="add" onClick={openComposer}>
                Publier une actu
              </DsButton>
            )}
          </div>
        </div>

        <TodayStrip
          canReview={canWrite}
          pending={[]}
          blockers={[]}
          drafts={myDrafts(news, current.email).length}
          publishedCount={publishedCount}
        />

        <div className="flex flex-wrap items-start gap-md">
          <div className="flex min-w-0 flex-[999_1_620px] flex-col gap-md">
            <ModulePlaceholder id="demandes" title="Demandes" />
            <NewsSection
              key={scenario}
              canWrite={canWrite}
              isAdmin={scenario === "admin"}
              email={current.email}
              news={{ data: news, isError: false, isLoading: false }}
              publishedCount={publishedCount}
              composerOpen={composerOpen}
              onComposerOpenChange={setComposerOpen}
              titleRef={composerTitle}
              saving={false}
              publishing={false}
              removing={false}
              draftRows={variant}
              onSave={(input, onSaved) => {
                setNews((list) => applyDraft(input, list));
                toast.success("Brouillon enregistré (fictif)");
                onSaved();
              }}
              onPublish={(n) => {
                setNews((list) => publish(n.id, list));
                toast.success("Actualité publiée (fictif)");
              }}
              onPublishEdited={(input, onPublished) => {
                setNews((list) => publish(input.id ?? "", applyDraft(input, list)));
                toast.success("Actualité publiée (fictif)");
                onPublished();
              }}
              onRemove={(n) => {
                setNews((list) => list.filter((item) => item.id !== n.id));
                toast.success("Brouillon supprimé (fictif)");
              }}
              onRead={setReading}
            />
          </div>
          <div className="flex min-w-0 flex-[1_1_380px] flex-col gap-md">
            <ModulePlaceholder id="blocages" title="Points bloquants" />
            <ModulePlaceholder id="indicateurs" title="Indicateurs" />
          </div>
        </div>
      </main>
      <NewsReader news={reading} onClose={() => setReading(null)} />
    </div>
  );
}
