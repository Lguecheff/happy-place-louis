import { createFileRoute } from "@tanstack/react-router";
import { useRef, useState } from "react";
import { toast } from "sonner";
import { BrandHeader } from "@/components/brand-header";
import { DS_INPUT, DsField } from "@/components/ds";
import type { NewsAiWriterInitial } from "@/components/news/NewsAiWriter";
import type { AutosaveFn } from "@/components/news/use-autosave-draft";
import {
  NewsSection,
  type AutosaveInput,
  type DraftInput,
} from "@/components/overview/NewsSection";
import { OverviewHeader } from "@/components/overview/OverviewHeader";
import { GlobalSearch } from "@/components/search/GlobalSearch";
import type { News } from "@/lib/dashboard";
import type { AiDraft, AiGenerate, AiResult, AiTone } from "@/lib/news-ai";

export const Route = createFileRoute("/_authenticated/maquettes/us27")({
  head: () => ({
    meta: [{ title: "Happy Place · Maquette de la rédaction par IA" }],
  }),
  component: Us27Mockup,
});

// ---------------------------------------------------------------------------
// Données factices (fictif). Aucun appel au service d'IA : réponses écrites ici.
// ---------------------------------------------------------------------------

const KESHA = { author: "Kesha (fictif)", author_email: "kesha@fictif.test" };
const PROMPT = "On lance un afterwork chaque premier jeudi du mois, au bureau de Lyon (fictif).";

const FAKE_DRAFTS: Record<AiTone, AiDraft> = {
  informatif: {
    title: "Un afterwork chaque premier jeudi du mois (fictif)",
    body: [
      "À partir de [mois de démarrage], un afterwork se tient chaque premier jeudi du mois au bureau de Lyon, de [heure de début] à [heure de fin].",
      "L'objectif : se retrouver entre équipes, hors des sujets du quotidien.",
      "Pour t'inscrire ou proposer une animation, écris à [prénom de l'organisateur].",
    ].join("\n\n"),
  },
  chaleureux: {
    title: "Rendez-vous chaque premier jeudi pour l'afterwork ! (fictif)",
    body: [
      "Bonne nouvelle : on se retrouve désormais chaque premier jeudi du mois au bureau de Lyon pour un afterwork convivial, dès [heure de début].",
      "C'est l'occasion de croiser les autres équipes et de partager un moment ensemble.",
      "Une idée d'animation ? [prénom de l'organisateur] t'attend !",
    ].join("\n\n"),
  },
  court: {
    title: "Afterwork : chaque premier jeudi du mois (fictif)",
    body: "Afterwork au bureau de Lyon chaque premier jeudi du mois, dès [heure de début]. Contact : [prénom de l'organisateur].",
  },
};

const EXISTING = {
  title: "Afterwork de rentrée (fictif)",
  body: "On organise un afterwork, les détails arrivent bientôt (fictif).",
};

type Scenario = {
  value: string;
  label: string;
  note: string;
  draft?: { title: string; body: string };
  ai: NewsAiWriterInitial;
  /** Réponse factice du serveur ; « hang » ne répond jamais (délai dépassé à 20 s). */
  answer: "ok" | "error" | "limit" | "hang";
};

const SCENARIOS: Scenario[] = [
  {
    value: "consigne",
    label: "Consigne",
    note: "Décris ton sujet (10 à 500 caractères), choisis un ton puis « Proposer un texte » : la réponse factice arrive en 2 s.",
    ai: {},
    answer: "ok",
  },
  {
    value: "chargement",
    label: "Chargement",
    note: "La génération est en cours. Le chargement est annoncé aux lecteurs d'écran ; « Annuler » revient à la consigne. Sans réponse, l'erreur s'affiche au bout de 20 s.",
    ai: { phase: "loading", prompt: PROMPT, tone: "chaleureux" },
    answer: "hang",
  },
  {
    value: "apercu",
    label: "Aperçu",
    note: "Le formulaire contient déjà un texte : « Utiliser ce texte » demande une confirmation avant de le remplacer. « Régénérer » propose une autre version.",
    draft: EXISTING,
    ai: { phase: "preview", prompt: PROMPT, tone: "informatif", draft: FAKE_DRAFTS.informatif },
    answer: "ok",
  },
  {
    value: "erreur",
    label: "Erreur ou délai dépassé",
    note: "Le service n'a pas répondu. La consigne et le texte du formulaire sont gardés.",
    draft: EXISTING,
    ai: { phase: "error", prompt: PROMPT, tone: "informatif" },
    answer: "error",
  },
  {
    value: "limite",
    label: "Limite du jour atteinte",
    note: "20 générations aujourd'hui (partagées avec l'US28) : le serveur refuse la suivante.",
    ai: { phase: "limit", prompt: PROMPT, tone: "court" },
    answer: "limit",
  },
];

/** Comme la future fonction serveur, sans appel réseau (fictif). */
function fakeGenerate(answer: Scenario["answer"]): AiGenerate {
  let round = 0;
  return ({ tone }, signal) =>
    new Promise<AiResult>((resolve, reject) => {
      signal.addEventListener("abort", () => reject(signal.reason));
      if (answer === "hang") return;
      setTimeout(() => {
        if (answer !== "ok") return resolve({ ok: false, reason: answer });
        round += 1;
        const d = FAKE_DRAFTS[tone];
        resolve({ ok: true, ...d, title: round > 1 ? `${d.title} · version ${round}` : d.title });
      }, 2000);
    });
}

function Us27Mockup() {
  const [scenarioValue, setScenarioValue] = useState(SCENARIOS[0].value);
  const scenario = SCENARIOS.find((s) => s.value === scenarioValue) ?? SCENARIOS[0];
  const [news, setNews] = useState<News[]>([]);
  const [composerOpen, setComposerOpen] = useState(true);
  const composerTitle = useRef<HTMLInputElement>(null);
  const [generate, setGenerate] = useState(() => fakeGenerate(scenario.answer));

  function writeDraft(input: AutosaveInput, id: string | undefined, status = "brouillon") {
    const now = new Date().toISOString();
    const fields = { title: input.title, body: input.body, links: input.links, ...input.audience };
    const published = status === "publiée" ? { published_at: now } : {};
    if (id) {
      setNews((list) =>
        list.map((n) =>
          n.id === id ? { ...n, ...fields, ...published, status, updated_at: now } : n,
        ),
      );
      return id;
    }
    const created = `brouillon-${crypto.randomUUID()}`;
    const draft: News = {
      id: created,
      ...KESHA,
      ...fields,
      status,
      created_at: now,
      updated_at: now,
      published_at: null,
    };
    setNews((list) => [draft, ...list]);
    return created;
  }

  const autosave: AutosaveFn<AutosaveInput> = async (input, id) => {
    await new Promise((resolve) => setTimeout(resolve, 600));
    return writeDraft(input, id);
  };

  function saveDraft(input: DraftInput, onSaved: () => void) {
    writeDraft(input, input.id);
    toast.success("Brouillon enregistré (fictif)");
    onSaved();
  }

  function publish(input: DraftInput, onPublished: () => void) {
    writeDraft(input, input.id, "publiée");
    toast.success("Actu publiée (fictif)");
    onPublished();
  }

  function chooseScenario(value: string) {
    const next = SCENARIOS.find((s) => s.value === value) ?? SCENARIOS[0];
    setScenarioValue(next.value);
    setGenerate(() => fakeGenerate(next.answer));
    setNews([]);
    setComposerOpen(true);
  }

  return (
    <div className="bg-background text-on-surface font-body-md min-h-screen flex flex-col">
      <BrandHeader>
        <OverviewHeader
          isAdmin={false}
          name="Kesha (fictif)"
          role="manager"
          exporting={false}
          onExport={() => toast.info("Non branché dans la maquette (fictif).")}
          search={
            <GlobalSearch
              source={{
                data: { news, submissions: [], blockers: [], metrics: [] },
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
              value={scenario.value}
              onChange={(e) => chooseScenario(e.target.value)}
            >
              {SCENARIOS.map((s) => (
                <option key={s.value} value={s.value}>
                  {s.label}
                </option>
              ))}
            </select>
          </DsField>
          <p
            role="status"
            className="min-w-0 flex-1 basis-64 font-body-sm text-body-sm text-on-surface"
          >
            Maquette (fictif) : {scenario.note}
          </p>
        </div>
        <NewsSection
          key={scenario.value}
          canWrite
          email={KESHA.author_email}
          news={{ data: news, isError: false, isLoading: false }}
          audienceTeams={["Marketing", "Product"]}
          audienceScope="mine"
          composerOpen={composerOpen}
          onComposerOpenChange={setComposerOpen}
          titleRef={composerTitle}
          saving={false}
          publishing={false}
          removing={false}
          onSave={saveDraft}
          onPublish={publish}
          onRemove={(n) => setNews((list) => list.filter((x) => x.id !== n.id))}
          onRead={() => {}}
          onAutosave={autosave}
          initialDraft={scenario.draft}
          aiWriter={{ generate, initial: scenario.ai }}
        />
      </main>
    </div>
  );
}
