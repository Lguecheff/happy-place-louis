import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import { BrandHeader } from "@/components/brand-header";
import { DS_INPUT, DsField } from "@/components/ds";
import type { NewsAiImproverInitial } from "@/components/news/NewsAiImprover";
import type { AutosaveFn } from "@/components/news/use-autosave-draft";
import {
  NewsSection,
  type AutosaveInput,
  type DraftInput,
  type NewsSectionHandle,
} from "@/components/overview/NewsSection";
import { OverviewHeader } from "@/components/overview/OverviewHeader";
import { GlobalSearch } from "@/components/search/GlobalSearch";
import type { News } from "@/lib/dashboard";
import type { AiDraft, AiImprove, AiImproveAction, AiImproveResult } from "@/lib/news-ai";

export const Route = createFileRoute("/_authenticated/maquettes/us28")({
  head: () => ({
    meta: [{ title: "Happy Place · Maquette de l'aide de rédaction" }],
  }),
  component: Us28Mockup,
});

// ---------------------------------------------------------------------------
// Données factices (fictif). Aucun appel au service d'IA : réponses écrites ici.
// ---------------------------------------------------------------------------

const KESHA = { author: "Kesha (fictif)", author_email: "kesha@fictif.test" };

/** Texte écrit par Kesha, avec des fautes (fictif). */
const WRITTEN: AiDraft = {
  title: "Nouvel afterwork chaque premier jeudi du mois (fictif)",
  body: [
    "A partir de décembre, on organise un afterwork chaque premier jeudi du mois au bureau de Lyon, on commencera vers 18 h 30 et on finira quand on voudra, il y aura des boissons et des choses a grignoter (fictif).",
    "Si tu veut proposer une animation, un quizz ou une playlist, n'hésite pas a en parlé à ton manager, toutes les idée sont les bienvenus.",
  ].join("\n\n"),
};

const IMPROVED: Record<AiImproveAction, AiDraft> = {
  corriger: {
    title: "Nouvel afterwork chaque premier jeudi du mois (fictif)",
    body: [
      "À partir de décembre, on organise un afterwork chaque premier jeudi du mois au bureau de Lyon. On commencera vers 18 h 30 et on finira quand on voudra. Il y aura des boissons et des choses à grignoter (fictif).",
      "Si tu veux proposer une animation, un quiz ou une playlist, n'hésite pas à en parler à ton manager : toutes les idées sont les bienvenues.",
    ].join("\n\n"),
  },
  clarifier: {
    title: WRITTEN.title,
    body: [
      "Dès décembre, un afterwork a lieu chaque premier jeudi du mois au bureau de Lyon, à partir de 18 h 30. Boissons et grignotages sont prévus (fictif).",
      "Tu veux proposer une animation (quiz, playlist…) ? Parles-en à ton manager.",
    ].join("\n\n"),
  },
  raccourcir: {
    title: WRITTEN.title,
    body: "Afterwork chaque premier jeudi du mois au bureau de Lyon, dès 18 h 30, à partir de décembre. Une animation à proposer ? Parles-en à ton manager (fictif).",
  },
  rechauffer: {
    title: WRITTEN.title,
    body: [
      "Bonne nouvelle : dès décembre, on se retrouve chaque premier jeudi du mois au bureau de Lyon pour un afterwork convivial, à partir de 18 h 30. Boissons et petites choses à grignoter t'attendent (fictif) !",
      "Envie d'animer un quiz ou de choisir la playlist ? Parles-en à ton manager, on a hâte de voir tes propositions.",
    ].join("\n\n"),
  },
};

/** Actu publiée il y a 12 jours, ouverte en modification (US10). */
const PUBLISHED_AT = new Date(Date.now() - 12 * 86_400_000).toISOString();
const PUBLISHED: News = {
  id: "publiee-fictive",
  ...KESHA,
  ...WRITTEN,
  links: [],
  audience: "entreprise",
  teams: [],
  status: "publiée",
  created_at: PUBLISHED_AT,
  updated_at: PUBLISHED_AT,
  published_at: PUBLISHED_AT,
} as News;

type Kind = "brouillon" | "publiee";

type Scenario = {
  value: string;
  label: string;
  note: string;
  initial: NewsAiImproverInitial;
  answer: "ok" | "error";
};

const SCENARIOS: Scenario[] = [
  {
    value: "menu",
    label: "Menu",
    note: "Le menu propose quatre actions. Il reste grisé tant que le texte est vide. Choisis une action : la réponse factice arrive en 2 s.",
    initial: { phase: "menu" },
    answer: "ok",
  },
  {
    value: "avant-apres",
    label: "Avant / après",
    note: "« Corriger les fautes » montre le titre et le texte ; les autres actions, le texte seulement. Rien ne change sans « Remplacer ».",
    initial: { phase: "compare", action: "corriger", before: WRITTEN, after: IMPROVED.corriger },
    answer: "ok",
  },
  {
    value: "remplace",
    label: "Après remplacement (annulation possible)",
    note: "Le texte de l'IA est dans le formulaire. Le toast garde « Annuler » 10 secondes : il rétablit le texte d'avant. Il disparaît si tu modifies le texte entre-temps. Rechoisis cet état pour rejouer le toast.",
    initial: { phase: "replaced", before: WRITTEN, after: IMPROVED.corriger },
    answer: "ok",
  },
  {
    value: "erreur",
    label: "Erreur",
    note: "Le service n'a pas répondu ou a dépassé 20 s. Le formulaire n'est pas touché ; « Réessayer » relance la même action.",
    initial: { phase: "error", action: "clarifier", before: WRITTEN },
    answer: "error",
  },
];

const KINDS: { value: Kind; label: string }[] = [
  { value: "brouillon", label: "Brouillon" },
  { value: "publiee", label: "Actu publiée en modification" },
];

/** Comme la fonction ai-writer (improveNewsWithAi), sans appel réseau (fictif). */
function fakeImprove(answer: Scenario["answer"]): AiImprove {
  return ({ action }, signal) =>
    new Promise<AiImproveResult>((resolve, reject) => {
      signal.addEventListener("abort", () => reject(signal.reason));
      setTimeout(() => {
        if (answer !== "ok") return resolve({ ok: false, reason: answer });
        const d = IMPROVED[action];
        resolve({ ok: true, body: d.body, ...(action === "corriger" && { title: d.title }) });
      }, 2000);
    });
}

function Us28Mockup() {
  const [scenarioValue, setScenarioValue] = useState(SCENARIOS[0].value);
  const [kind, setKind] = useState<Kind>("brouillon");
  const [round, setRound] = useState(0);
  const scenario = SCENARIOS.find((s) => s.value === scenarioValue) ?? SCENARIOS[0];
  const [news, setNews] = useState<News[]>(kind === "publiee" ? [PUBLISHED] : []);
  const [composerOpen, setComposerOpen] = useState(true);
  const composerTitle = useRef<HTMLInputElement>(null);
  const section = useRef<NewsSectionHandle>(null);
  const [improve, setImprove] = useState(() => fakeImprove(scenario.answer));

  // Actu publiée : le rédacteur s'ouvre en modification, comme depuis la fenêtre de lecture.
  useEffect(() => {
    if (kind === "publiee") section.current?.editPublished(PUBLISHED);
  }, [kind, round]);

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

  function publish(input: DraftInput & { id: string }, onPublished: () => void) {
    writeDraft(input, input.id, "publiée");
    toast.success("Actu publiée (fictif)");
    onPublished();
  }

  /** US10 : seuls le contenu et updated_at changent ; la date de publication reste. */
  function saveEdit(input: DraftInput & { id: string }, onSaved: () => void) {
    const now = new Date().toISOString();
    setNews((list) =>
      list.map((n) =>
        n.id === input.id ? { ...n, title: input.title, body: input.body, updated_at: now } : n,
      ),
    );
    toast.success("Modifications enregistrées (fictif)");
    onSaved();
  }

  function restart(nextScenario: Scenario, nextKind: Kind) {
    toast.dismiss();
    setScenarioValue(nextScenario.value);
    setKind(nextKind);
    setImprove(() => fakeImprove(nextScenario.answer));
    setNews(nextKind === "publiee" ? [PUBLISHED] : []);
    setComposerOpen(true);
    setRound((r) => r + 1);
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
              onChange={(e) =>
                restart(SCENARIOS.find((s) => s.value === e.target.value) ?? SCENARIOS[0], kind)
              }
            >
              {SCENARIOS.map((s) => (
                <option key={s.value} value={s.value}>
                  {s.label}
                </option>
              ))}
            </select>
          </DsField>
          <DsField id="maquette-actu" label="Actu (fictif)" className="w-full md:w-72">
            <select
              id="maquette-actu"
              className={DS_INPUT}
              value={kind}
              onChange={(e) => restart(scenario, e.target.value as Kind)}
            >
              {KINDS.map((k) => (
                <option key={k.value} value={k.value}>
                  {k.label}
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
          key={`${scenario.value}-${kind}-${round}`}
          editRef={section}
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
          onSaveEdit={saveEdit}
          onRemove={(n) => setNews((list) => list.filter((x) => x.id !== n.id))}
          onRead={(n) => section.current?.editPublished(n)}
          onAutosave={autosave}
          initialDraft={kind === "brouillon" ? WRITTEN : undefined}
          aiImprover={{ improve, initial: scenario.initial }}
        />
      </main>
    </div>
  );
}
