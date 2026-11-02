import * as DialogPrimitive from "@radix-ui/react-dialog";
import { createFileRoute } from "@tanstack/react-router";
import { useRef, useState, type RefObject } from "react";
import { flushSync } from "react-dom";
import { toast } from "sonner";
import { BrandHeader } from "@/components/brand-header";
import { DS_INPUT, DsButton, DsEmptyState, DsField, DsListItem, DsSection } from "@/components/ds";
import { formatExactDate } from "@/components/expandable-card";
import { NewsAudienceBadge } from "@/components/news/NewsAudienceBadge";
import { NewsAudienceField } from "@/components/news/NewsAudienceField";
import { NewsImage, NewsLinks, NewsMediaEditor } from "@/components/news-media";
import { ConfirmDialog } from "@/components/overview/ConfirmDialog";
import { TodayStrip } from "@/components/overview/TodayStrip";
import {
  daysSince,
  formatDay,
  formatDays,
  myDrafts,
  newsPublishedAt,
  publishedThisMonth,
} from "@/components/overview/overview-utils";
import { timeAgo, type News } from "@/lib/dashboard";
import {
  audienceError,
  audienceSentence,
  emptyAudience,
  type NewsAudienceValue,
} from "@/lib/news-audience";
import { emptyMedia, linkErrors, toNewsLinks, type MediaDraft } from "@/lib/news-media";

export const Route = createFileRoute("/_authenticated/maquettes/us08")({
  head: () => ({
    meta: [{ title: "Happy Place · Maquette du public d'une actu" }],
  }),
  component: Us08Mockup,
});

// ---------------------------------------------------------------------------
// Données factices (fictif)
// ---------------------------------------------------------------------------

type Scenario = "une" | "deux" | "aucune" | "erreur" | "confirmation" | "publiee";
type MockNews = News & NewsAudienceValue;

const KESHA = "kesha@fictif.test";
const SUBTITLE = "font-label-md text-label-md normal-case tracking-normal text-on-surface-variant";

const SCENARIOS: { value: Scenario; label: string; teams: string[]; hint: string }[] = [
  {
    value: "une",
    label: "Manager d'une équipe",
    teams: ["Product"],
    hint: "Rien n'est présélectionné. « Mon équipe » désigne Product, en lecture. Tu peux enregistrer le brouillon sans public.",
  },
  {
    value: "deux",
    label: "Manager de 2 équipes",
    teams: ["Marketing", "Product"],
    hint: "Choisis « Mon équipe » : les cases à cocher s'affichent, sans aucune case présélectionnée. Publier sans case cochée affiche un message.",
  },
  {
    value: "aucune",
    label: "Manager sans équipe",
    teams: [],
    hint: "« Mon équipe » est désactivé et une phrase l'explique. Il reste « Toute l'entreprise ».",
  },
  {
    value: "erreur",
    label: "Erreur : public manquant",
    teams: ["Product"],
    hint: "Rien n'est publié. Le message s'efface dès que tu choisis un public.",
  },
  {
    value: "confirmation",
    label: "Confirmation de publication",
    teams: ["Marketing", "Product"],
    hint: "La confirmation reprend le public. Annule et choisis « Toute l'entreprise » pour voir l'autre phrase.",
  },
  {
    value: "publiee",
    label: "Actu publiée (puce)",
    teams: ["Marketing", "Product"],
    hint: "La puce s'affiche dans « Publiées récemment » et dans la fenêtre de lecture : ouvre une actu pour la voir.",
  },
];

const DAY_MS = 86_400_000;
const daysAgo = (days: number) => new Date(Date.now() - days * DAY_MS).toISOString();

function mockNews(
  id: string,
  days: number,
  title: string,
  status: string,
  value: NewsAudienceValue,
): MockNews {
  const at = daysAgo(days);
  return {
    id,
    title: title && `${title} (fictif)`,
    body: "Texte de l'actu (fictif).",
    author: "Kesha (fictif)",
    author_email: KESHA,
    status,
    created_at: at,
    updated_at: at,
    published_at: status === "publiée" ? at : null,
    links: [],
    ...value,
  };
}

function newsFor(scenario: Scenario): MockNews[] {
  const company: NewsAudienceValue = { audience: "entreprise", teams: [] };
  const published = [
    mockNews("p1", 1, "Bienvenue aux nouvelles recrues", "publiée", {
      audience: "équipe",
      teams: ["Marketing", "Product"],
    }),
    mockNews("p2", 12, "Résultats du trimestre", "publiée", company),
  ];
  if (scenario === "publiee") return published;
  const draftAudience =
    scenario === "confirmation"
      ? { audience: "équipe" as const, teams: ["Marketing", "Product"] }
      : emptyAudience();
  return [mockNews("b1", 2, "Nouveau partenariat école", "brouillon", draftAudience), ...published];
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

function MockReader({ news: n, onClose }: { news: MockNews | null; onClose: () => void }) {
  return (
    <DialogPrimitive.Root open={!!n} onOpenChange={(o) => !o && onClose()}>
      <DialogPrimitive.Portal>
        <DialogPrimitive.Overlay className="fixed inset-0 z-50 bg-black/50" />
        {n && (
          <DialogPrimitive.Content className="fixed z-50 inset-0 md:inset-auto md:left-1/2 md:top-1/2 md:-translate-x-1/2 md:-translate-y-1/2 w-full md:w-[min(48rem,calc(100vw-2rem))] h-dvh md:h-auto md:max-h-[85vh] flex flex-col bg-surface-container-lowest border border-outline shadow-lg focus:outline-none">
            <div className="flex items-start justify-between gap-sm border-b border-outline-variant p-md">
              <div className="min-w-0 space-y-xs">
                <DialogPrimitive.Title className="font-headline-sm text-headline-sm text-primary wrap-anywhere">
                  {n.title}
                </DialogPrimitive.Title>
                <DialogPrimitive.Description className={SUBTITLE}>
                  Publiée le {formatExactDate(newsPublishedAt(n))} · Par {n.author}
                </DialogPrimitive.Description>
                <NewsAudienceBadge value={n} />
              </div>
              <DialogPrimitive.Close
                aria-label="Fermer"
                className="inline-flex size-11 shrink-0 items-center justify-center text-on-surface-variant hover:text-primary focus:outline-none focus-visible:ring-2 focus-visible:ring-primary"
              >
                <span aria-hidden="true" className="material-symbols-outlined">
                  close
                </span>
              </DialogPrimitive.Close>
            </div>
            <div className="flex-1 overflow-y-auto p-md space-y-md">
              {n.image_path && <NewsImage path={n.image_path} alt={n.title} />}
              {n.body && (
                <p className="font-body-md text-body-md text-on-surface whitespace-pre-line wrap-anywhere">
                  {n.body}
                </p>
              )}
              <NewsLinks links={n.links} />
            </div>
          </DialogPrimitive.Content>
        )}
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  );
}

function MockNewsSection({
  scenario,
  teams,
  news,
  onNewsChange,
  composerOpen,
  onComposerOpenChange,
  titleRef,
  onRead,
}: {
  scenario: Scenario;
  teams: string[];
  news: MockNews[];
  onNewsChange: (news: MockNews[]) => void;
  composerOpen: boolean;
  onComposerOpenChange: (open: boolean) => void;
  titleRef: RefObject<HTMLInputElement | null>;
  onRead: (n: MockNews) => void;
}) {
  const firstDraft = news.find((n) => n.status === "brouillon") ?? null;
  const [editing, setEditing] = useState<MockNews | null>(firstDraft);
  const [title, setTitle] = useState(firstDraft?.title ?? "");
  const [body, setBody] = useState(firstDraft?.body ?? "");
  const [media, setMedia] = useState<MediaDraft>(emptyMedia);
  const [audience, setAudience] = useState<NewsAudienceValue>(() => ({
    audience: firstDraft?.audience ?? null,
    teams: firstDraft?.teams ?? [],
  }));
  const [titleError, setTitleError] = useState<string | undefined>();
  const [audienceErr, setAudienceErr] = useState(
    scenario === "erreur" ? audienceError(emptyAudience()) : undefined,
  );
  const [confirmPublish, setConfirmPublish] = useState(scenario === "confirmation");
  const audienceInput = useRef<HTMLInputElement>(null);
  const drafts = myDrafts(news, KESHA) as MockNews[];
  const published = news
    .filter((n) => n.status === "publiée")
    .sort((a, b) => newsPublishedAt(b).localeCompare(newsPublishedAt(a)));

  function closeComposer() {
    setEditing(null);
    setTitle("");
    setBody("");
    setMedia(emptyMedia());
    setAudience(emptyAudience());
    setTitleError(undefined);
    setAudienceErr(undefined);
    onComposerOpenChange(false);
  }

  function startEditing(n: MockNews) {
    setEditing(n);
    setTitle(n.title);
    setBody(n.body ?? "");
    setAudience({ audience: n.audience, teams: n.teams });
    setTitleError(undefined);
    setAudienceErr(undefined);
    flushSync(() => onComposerOpenChange(true));
    titleRef.current?.focus();
  }

  function applyDraft() {
    const fields = {
      title: title.trim(),
      body,
      links: toNewsLinks(media.links),
      updated_at: daysAgo(0),
      ...audience,
    };
    if (editing) return news.map((n) => (n.id === editing.id ? { ...n, ...fields } : n));
    return [{ ...mockNews(crypto.randomUUID(), 0, "", "brouillon", audience), ...fields }, ...news];
  }

  function save(e: React.FormEvent) {
    e.preventDefault();
    if (!title.trim() && !body.trim()) {
      setTitleError("Saisis un titre ou un texte.");
      return;
    }
    onNewsChange(applyDraft());
    toast.success("Brouillon enregistré (fictif)");
    closeComposer();
  }

  function publish() {
    const noTitle = !title.trim();
    const missing = audienceError(audience);
    setTitleError(noTitle ? "Ajoute un titre pour publier." : undefined);
    setAudienceErr(missing);
    if (noTitle) titleRef.current?.focus();
    else if (missing) audienceInput.current?.focus();
    else setConfirmPublish(true);
  }

  function confirm() {
    const at = daysAgo(0);
    onNewsChange(
      applyDraft().map((n) =>
        n.id === editing?.id ? { ...n, status: "publiée", published_at: at } : n,
      ),
    );
    toast.success("Actualité publiée (fictif)");
    setConfirmPublish(false);
    closeComposer();
  }

  return (
    <DsSection id="actus" title="Actualités du cabinet">
      <DsButton
        icon="edit"
        aria-expanded={composerOpen}
        aria-controls="redacteur-actu"
        className="w-full"
        onClick={() => onComposerOpenChange(!composerOpen)}
      >
        Rédiger une actualité
      </DsButton>
      <form
        id="redacteur-actu"
        hidden={!composerOpen}
        className="space-y-md"
        onSubmit={save}
        noValidate
      >
        <DsField id="actu-titre" label="Titre" error={titleError}>
          <input
            id="actu-titre"
            ref={titleRef}
            type="text"
            className={DS_INPUT}
            placeholder="Saisis un titre…"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
          />
        </DsField>
        <DsField id="actu-contenu" label="Contenu">
          <textarea
            id="actu-contenu"
            rows={4}
            className={DS_INPUT}
            placeholder="Rédige l'actualité…"
            value={body}
            onChange={(e) => setBody(e.target.value)}
          />
        </DsField>
        <NewsMediaEditor
          value={media}
          onChange={setMedia}
          linkErrs={linkErrors(media.links)}
          title={title}
        />
        <NewsAudienceField
          id="actu-public"
          teams={teams}
          value={audience}
          error={audienceErr}
          firstInputRef={audienceInput}
          onChange={(value) => {
            setAudience(value);
            setAudienceErr(undefined);
          }}
        />
        <div className="flex flex-wrap items-center justify-end gap-xs">
          {editing && (
            <DsButton variant="link" onClick={closeComposer}>
              Annuler
            </DsButton>
          )}
          <DsButton type="submit">Enregistrer le brouillon</DsButton>
          {editing && (
            <DsButton variant="confirm" onClick={publish}>
              Publier
            </DsButton>
          )}
        </div>
      </form>
      <div className="space-y-xs">
        <h3 className={SUBTITLE}>Mes brouillons</h3>
        {drafts.length === 0 && <DsEmptyState>Aucun brouillon en cours.</DsEmptyState>}
        {drafts.map((n) => (
          <DsListItem
            key={n.id}
            icon="draft"
            title={n.title || <span className="italic">Sans titre</span>}
            meta={`Créé le ${formatDay(n.created_at)} · ${formatDays(daysSince(n.created_at))}`}
            onClick={() => startEditing(n)}
          />
        ))}
      </div>
      <div className="space-y-xs">
        <h3 className={SUBTITLE}>Publiées récemment</h3>
        {published.map((n) => (
          <DsListItem
            key={n.id}
            icon="article"
            title={n.title}
            meta={
              <>
                <span className="block">
                  Publiée {timeAgo(newsPublishedAt(n))} · Par {n.author}
                </span>
                <NewsAudienceBadge value={n} className="mt-xs" />
              </>
            }
            onClick={() => onRead(n)}
          />
        ))}
      </div>
      <ConfirmDialog
        open={confirmPublish}
        title={`Publier « ${title.trim()} » ?`}
        description={audienceSentence(audience)}
        confirmLabel="Publier"
        onCancel={() => setConfirmPublish(false)}
        onConfirm={confirm}
      />
    </DsSection>
  );
}

function Us08Mockup() {
  const [scenario, setScenario] = useState<Scenario>("une");
  const [news, setNews] = useState(() => newsFor("une"));
  const [composerOpen, setComposerOpen] = useState(true);
  const [reading, setReading] = useState<MockNews | null>(null);
  const composerTitle = useRef<HTMLInputElement>(null);

  const current = SCENARIOS.find((s) => s.value === scenario) ?? SCENARIOS[0];

  const changeScenario = (value: Scenario) => {
    setScenario(value);
    setNews(newsFor(value));
    setComposerOpen(value !== "publiee");
  };

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
          <p className="min-w-0 flex-1 basis-64 font-body-sm text-body-sm text-on-surface-variant">
            {current.hint}
          </p>
        </div>

        <div className="flex flex-wrap items-end justify-between gap-sm">
          <div className="min-w-0 space-y-xs">
            <h1 className="font-headline-lg text-headline-lg text-primary">Bonjour Kesha</h1>
            <p className="font-body-md text-body-md text-on-surface-variant">
              Voici ce qui demande ton attention aujourd'hui.
            </p>
          </div>
          <div className="flex flex-wrap gap-xs">
            <DsButton onClick={() => toast.info("Non branché dans la maquette (fictif).")}>
              Faire une demande
            </DsButton>
            <DsButton variant="primary" icon="add" onClick={openComposer}>
              Publier une actu
            </DsButton>
          </div>
        </div>

        <TodayStrip
          canReview
          pending={[]}
          blockers={[]}
          drafts={myDrafts(news, KESHA).length}
          publishedCount={publishedThisMonth(news, KESHA)}
        />

        <div className="flex flex-wrap items-start gap-md">
          <div className="flex min-w-0 flex-[999_1_620px] flex-col gap-md">
            <ModulePlaceholder id="demandes" title="Demandes" />
            <MockNewsSection
              key={scenario}
              scenario={scenario}
              teams={current.teams}
              news={news}
              onNewsChange={setNews}
              composerOpen={composerOpen}
              onComposerOpenChange={setComposerOpen}
              titleRef={composerTitle}
              onRead={setReading}
            />
          </div>
          <div className="flex min-w-0 flex-[1_1_380px] flex-col gap-md">
            <ModulePlaceholder id="blocages" title="Points bloquants" />
            <ModulePlaceholder id="indicateurs" title="Indicateurs" />
          </div>
        </div>
      </main>
      <MockReader news={reading} onClose={() => setReading(null)} />
    </div>
  );
}
