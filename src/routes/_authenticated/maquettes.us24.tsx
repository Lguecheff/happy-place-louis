import { createFileRoute } from "@tanstack/react-router";
import { useRef, useState, type ReactNode } from "react";
import { toast } from "sonner";
import { BrandHeader } from "@/components/brand-header";
import {
  DS_INPUT,
  DsAvatar,
  DsButton,
  DsField,
  DsListItem,
  DsSection,
  DsShowMore,
  SHOW_MORE_NEWS,
  SHOW_MORE_REQUESTS,
  useShowMore,
  type DsShowMoreNoun,
} from "@/components/ds";
import { DS_FOCUS } from "@/components/ds/focus";
import { SubmissionPreview } from "@/components/expandable-card";
import { LongWaitBadge } from "@/components/overview/LongWaitBadge";
import { OverviewHeader } from "@/components/overview/OverviewHeader";
import { TodayStrip } from "@/components/overview/TodayStrip";
import { pendingSince } from "@/components/overview/overview-utils";
import { StatusChip } from "@/components/submission-status-thread";
import { SubmissionReader } from "@/components/submission-reader";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { timeAgo, type Submission } from "@/lib/dashboard";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/_authenticated/maquettes/us24")({
  head: () => ({
    meta: [{ title: "Happy Place · Maquette du voir plus" }],
  }),
  component: Us24Mockup,
});

// ---------------------------------------------------------------------------
// Données factices (fictif).
// ---------------------------------------------------------------------------

const DAY_MS = 86_400_000;
const ago = (days: number) => new Date(Date.now() - days * DAY_MS).toISOString();

type Viewer = { key: string; name: string; role: "collaborateur" | "manager" };
const VIEWERS: Viewer[] = [
  { key: "gontran", name: "Gontran (fictif)", role: "collaborateur" },
  { key: "kesha", name: "Kesha (fictif)", role: "manager" },
];

type MockNews = { id: string; title: string; author: string; published_at: string };

const NEWS_TITLES = [
  "Nouvelle offre de formation",
  "Arrivée de deux consultantes",
  "Résultats du trimestre",
  "Déménagement du pôle Data",
  "Séminaire d'équipe en juin",
  "Nouveau process de congés",
  "Bilan de la journée portes ouvertes",
  "Mise à jour de la charte",
  "Lancement du mentorat",
  "Retour sur le salon RH",
];
const AUTHORS = ["Kesha (fictif)", "Sam Martin (fictif)", "Léa Bernard (fictif)"];
const PEOPLE = ["Amina Diallo (fictif)", "Hugo Martin (fictif)", "Léa Bernard (fictif)"];
const TEAMS = ["Data", "Product", "Ops"];
const STATUSES = ["en attente", "validée", "refusée", "clôturée"];
const IDEAS = [
  "Ajouter un export CSV au tableau des KPI",
  "Ouvrir un créneau mensuel de questions avec l'équipe Product",
  "Partager le planning des formations dans les actus",
  "Documenter la source du taux de placement",
  "Revoir l'ordre des étapes d'accueil",
  "Créer un canal pour les retours clients",
];

function makeNews(count: number): MockNews[] {
  return Array.from({ length: count }, (_, i) => ({
    id: `n${i + 1}`,
    title: `${NEWS_TITLES[i % NEWS_TITLES.length]} n° ${i + 1} (fictif)`,
    author: AUTHORS[i % AUTHORS.length],
    published_at: ago(i * 3 + 1),
  }));
}

function makeRequest(i: number, author: string, status: string, prefix: string): Submission {
  return {
    id: `${prefix}${i + 1}`,
    author_name: author,
    team: TEAMS[i % TEAMS.length],
    content: `${IDEAS[i % IDEAS.length]} : demande n° ${i + 1} (fictif).`,
    status,
    created_at: ago(i * 4 + 1),
  };
}

const mineOf = (count: number) =>
  Array.from({ length: count }, (_, i) =>
    makeRequest(i, "Gontran (fictif)", STATUSES[i % STATUSES.length], "g"),
  );
const queueOf = (count: number) =>
  Array.from({ length: count }, (_, i) =>
    makeRequest(i, PEOPLE[i % PEOPLE.length], "en attente", "q"),
  );
const managedOf = (count: number) =>
  Array.from({ length: count }, (_, i) =>
    makeRequest(i, PEOPLE[i % PEOPLE.length], STATUSES[i % STATUSES.length], "m"),
  );
const KESHA_MINE = Array.from({ length: 2 }, (_, i) =>
  makeRequest(i, "Kesha (fictif)", "en attente", "k"),
);

type MockState = {
  value: string;
  label: string;
  note: string;
  news: number;
  requests: number;
  /** Les listes s'ouvrent entièrement dépliées. */
  expanded?: boolean;
  /** Le premier « Voir plus » échoue, « Réessayer » réussit. */
  failing?: boolean;
};

const STATES: MockState[] = [
  {
    value: "25-actus",
    label: "25 actus",
    note: "« Publiées récemment » montre 4 actus, puis 10 de plus par clic (4, 14, 24, 25). Après un clic, le focus va sur la première actu ajoutée et « 10 actus ajoutées » est annoncé.",
    news: 25,
    requests: 3,
  },
  {
    value: "3-actus",
    label: "3 actus (pas de bouton)",
    note: "Liste plus courte que la première tranche : pas de bouton, la mention « 3 sur 3 affichées » reste.",
    news: 3,
    requests: 3,
  },
  {
    value: "23-demandes",
    label: "23 demandes",
    note: "« Mes demandes » (et, pour Kesha, « À traiter » et « Gérées ») montre 10 demandes, puis 10 de plus par clic (10, 20, 23). « À traiter » garde la plus ancienne en premier. 4 actus pile : pas de bouton.",
    news: 4,
    requests: 23,
  },
  {
    value: "tout",
    label: "Tout affiché",
    note: "Toutes les listes sont dépliées : « 25 sur 25 affichées », « 23 sur 23 affichées », plus de bouton.",
    news: 25,
    requests: 23,
    expanded: true,
  },
  {
    value: "erreur",
    label: "Erreur de chargement",
    note: "Cas où la suite se charge depuis la base : « Chargement… » pendant l'attente (1 seconde ici), puis « Impossible de charger la suite. » et « Réessayer », qui reçoit le focus. Réessayer réussit.",
    news: 25,
    requests: 23,
    failing: true,
  },
];

const notWired = () => toast.info("Non branché dans la maquette (fictif).");

const TAB = cn(
  "min-h-11 rounded-none border-b-2 border-transparent px-sm font-label-md text-sm",
  "data-[state=active]:border-primary data-[state=active]:bg-transparent data-[state=active]:text-primary data-[state=active]:shadow-none",
  DS_FOCUS,
);
const SUBTITLE = "font-label-md text-label-md normal-case tracking-normal text-on-surface-variant";

// ---------------------------------------------------------------------------
// Tranches : DsShowMore et useShowMore, plus un faux chargement pour l'état d'erreur.
// ---------------------------------------------------------------------------

/** useShowMore, avec un chargement simulé (1 seconde) qui échoue la première fois si `failing`. */
function useMockList({
  total,
  first,
  noun,
  expanded,
  failing,
}: {
  total: number;
  first: number;
  noun: DsShowMoreNoun;
  expanded?: boolean;
  failing?: boolean;
}) {
  const list = useShowMore({ total, first: expanded ? Number.POSITIVE_INFINITY : first, noun });
  const [pending, setPending] = useState(false);
  const [error, setError] = useState(false);
  const failed = useRef(false);

  function onMore() {
    if (!failing) return list.more();
    setError(false);
    setPending(true);
    window.setTimeout(() => {
      setPending(false);
      if (failed.current) return list.more();
      failed.current = true;
      setError(true);
    }, 1000);
  }

  return { ...list, pending, error, onMore };
}

type MockList = ReturnType<typeof useMockList>;

function MockShowMore({ list, label }: { list: MockList; label: string }) {
  return (
    <DsShowMore
      shown={list.shown}
      total={list.total}
      announce={list.announce}
      pending={list.pending}
      error={list.error}
      label={label}
      onMore={list.onMore}
    />
  );
}

function TrancheList({
  list,
  className,
  children,
}: {
  list: MockList;
  className?: string;
  children: (index: number) => ReactNode;
}) {
  return (
    <div className={className}>
      {Array.from({ length: list.shown }, (_, i) => (
        <div key={i} {...list.itemProps(i)}>
          {children(i)}
        </div>
      ))}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Lignes : mêmes compositions que NewsSection et RequestsSection.
// ---------------------------------------------------------------------------

function MyRow({ s, onRead }: { s: Submission; onRead: () => void }) {
  return (
    <DsListItem
      title={<StatusChip status={s.status} />}
      meta={`${s.team} · Créée ${timeAgo(s.created_at)}`}
      actions={
        <DsButton variant="link" aria-haspopup="dialog" onClick={notWired}>
          Voir le détail
        </DsButton>
      }
    >
      <LongWaitBadge submission={s} />
      <SubmissionPreview content={s.content} onOpen={onRead} />
    </DsListItem>
  );
}

function PendingRow({ s, onRead }: { s: Submission; onRead: () => void }) {
  return (
    <DsListItem
      leading={<DsAvatar name={s.author_name} />}
      title={s.author_name}
      meta={s.team}
      actions={
        <>
          <DsButton variant="confirm" icon="check" onClick={notWired}>
            Valider
          </DsButton>
          <DsButton aria-haspopup="dialog" onClick={notWired}>
            Refuser
          </DsButton>
          <DsButton variant="link" aria-haspopup="dialog" onClick={notWired}>
            Voir le détail
          </DsButton>
        </>
      }
    >
      <LongWaitBadge submission={s} />
      <SubmissionPreview content={s.content} onOpen={onRead} />
    </DsListItem>
  );
}

function ManagedCard({ s, onRead }: { s: Submission; onRead: () => void }) {
  return (
    <div className="min-w-0 space-y-xs border border-outline-variant bg-surface-container-lowest p-sm">
      <StatusChip status={s.status} />
      <p className="font-label-md text-label-md text-on-surface-variant wrap-anywhere">
        <span className="font-bold text-primary">{s.author_name}</span> · {s.team}
      </p>
      <LongWaitBadge submission={s} />
      <SubmissionPreview content={s.content} onOpen={onRead} />
    </div>
  );
}

// ---------------------------------------------------------------------------

function Lists({ state, viewer }: { state: MockState; viewer: Viewer }) {
  const canReview = viewer.role === "manager";
  const [tab, setTab] = useState(canReview ? "a-traiter" : "mes-demandes");
  const [reading, setReading] = useState<Submission | null>(null);
  const [news, setNews] = useState(() => makeNews(state.news));
  const [mine, setMine] = useState(() => (canReview ? KESHA_MINE : mineOf(state.requests)));
  const [queue, setQueue] = useState(() => queueOf(state.requests));
  const managed = managedOf(state.requests);
  // La plus ancienne en premier : c'est celle à traiter d'abord.
  const sortedQueue = [...queue].sort((a, b) => pendingSince(a).localeCompare(pendingSince(b)));

  const common = { expanded: state.expanded, failing: state.failing };
  const newsT = useMockList({ total: news.length, first: 4, noun: SHOW_MORE_NEWS, ...common });
  const mineT = useMockList({ total: mine.length, first: 10, noun: SHOW_MORE_REQUESTS, ...common });
  const queueT = useMockList({
    total: queue.length,
    first: 10,
    noun: SHOW_MORE_REQUESTS,
    ...common,
  });
  const managedT = useMockList({
    total: managed.length,
    first: 10,
    noun: SHOW_MORE_REQUESTS,
    ...common,
  });

  function simulateUpdate() {
    const n = Date.now();
    setNews((l) => [
      {
        id: `new${n}`,
        title: "Actu arrivée en direct (fictif)",
        author: AUTHORS[0],
        published_at: new Date().toISOString(),
      },
      ...l,
    ]);
    const s = makeRequest(0, viewer.name, "en attente", `new${n}-`);
    setMine((l) => [
      {
        ...s,
        created_at: new Date().toISOString(),
        content: "Demande arrivée en direct (fictif).",
      },
      ...l,
    ]);
    setQueue((l) => [
      ...l,
      {
        ...s,
        author_name: PEOPLE[0],
        created_at: new Date().toISOString(),
        content: "Demande arrivée en direct (fictif).",
      },
    ]);
    toast.info(
      "Une actu et une demande sont arrivées (fictif). Les listes dépliées restent dépliées.",
    );
  }

  return (
    <>
      <div className="flex justify-end">
        <DsButton variant="link" onClick={simulateUpdate}>
          Simuler une mise à jour en direct (fictif)
        </DsButton>
      </div>
      <div className="flex flex-wrap items-start gap-md">
        <div className="flex min-w-0 flex-[999_1_620px] flex-col gap-md">
          <DsSection id="demandes" title="Demandes">
            <Tabs value={tab} onValueChange={setTab}>
              <TabsList className="h-auto w-full flex-wrap justify-start gap-x-xs rounded-none border-b border-outline-variant bg-transparent p-0">
                {canReview && (
                  <TabsTrigger value="a-traiter" className={TAB}>
                    À traiter ({queue.length})
                  </TabsTrigger>
                )}
                <TabsTrigger value="mes-demandes" className={TAB}>
                  Mes demandes
                </TabsTrigger>
                {canReview && (
                  <TabsTrigger value="gerees" className={TAB}>
                    Gérées
                  </TabsTrigger>
                )}
              </TabsList>
              {canReview && (
                <TabsContent value="a-traiter" className="mt-md space-y-xs">
                  <TrancheList list={queueT} className="space-y-xs">
                    {(i) => (
                      <PendingRow s={sortedQueue[i]} onRead={() => setReading(sortedQueue[i])} />
                    )}
                  </TrancheList>
                  <MockShowMore list={queueT} label="Voir plus de demandes à traiter" />
                </TabsContent>
              )}
              <TabsContent value="mes-demandes" className="mt-md space-y-xs">
                <TrancheList list={mineT} className="space-y-xs">
                  {(i) => <MyRow s={mine[i]} onRead={() => setReading(mine[i])} />}
                </TrancheList>
                <MockShowMore list={mineT} label="Voir plus de mes demandes" />
              </TabsContent>
              {canReview && (
                <TabsContent value="gerees" className="mt-md space-y-xs">
                  <h3 className={cn(SUBTITLE, "mb-md")}>Suivi des demandes</h3>
                  <TrancheList list={managedT} className="grid gap-xs md:grid-cols-2">
                    {(i) => <ManagedCard s={managed[i]} onRead={() => setReading(managed[i])} />}
                  </TrancheList>
                  <MockShowMore list={managedT} label="Voir plus de demandes gérées" />
                </TabsContent>
              )}
            </Tabs>
          </DsSection>
          <DsSection id="actus" title="Actualités du cabinet">
            <div className="space-y-xs">
              <h3 className={SUBTITLE}>Publiées récemment</h3>
              <TrancheList list={newsT} className="space-y-xs">
                {(i) => (
                  <DsListItem
                    icon="article"
                    title={news[i].title}
                    meta={`Publiée ${timeAgo(news[i].published_at)} · Par ${news[i].author}`}
                    onClick={notWired}
                  />
                )}
              </TrancheList>
              <MockShowMore list={newsT} label="Voir plus d'actus" />
            </div>
          </DsSection>
        </div>
      </div>
      <SubmissionReader submission={reading} onClose={() => setReading(null)} hideAttachment />
    </>
  );
}

function Us24Mockup() {
  const [stateValue, setStateValue] = useState(STATES[0].value);
  const [viewerKey, setViewerKey] = useState(VIEWERS[0].key);
  const state = STATES.find((s) => s.value === stateValue) ?? STATES[0];
  const viewer = VIEWERS.find((v) => v.key === viewerKey) ?? VIEWERS[0];
  const canReview = viewer.role === "manager";

  return (
    <div className="bg-background text-on-surface font-body-md min-h-screen flex flex-col">
      <BrandHeader>
        <OverviewHeader
          isAdmin={false}
          name={viewer.name}
          role={viewer.role}
          exporting={false}
          onExport={notWired}
          search={null}
        />
      </BrandHeader>
      <main className="flex-grow w-full max-w-interface mx-auto p-sm md:p-md space-y-md">
        <div className="flex flex-wrap items-end gap-sm border border-dashed border-outline-variant p-sm">
          <DsField id="maquette-etat" label="Maquette (fictif)" className="w-full md:w-64">
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
          <DsField id="maquette-vue" label="Vue (fictif)" className="w-full md:w-56">
            <select
              id="maquette-vue"
              className={DS_INPUT}
              value={viewer.key}
              onChange={(e) => setViewerKey(e.target.value)}
            >
              {VIEWERS.map((v) => (
                <option key={v.key} value={v.key}>
                  {v.name}
                </option>
              ))}
            </select>
          </DsField>
          <p className="min-w-0 flex-1 basis-64 font-body-sm text-body-sm text-on-surface">
            {state.note}
          </p>
        </div>

        <div className="flex flex-wrap items-end justify-between gap-sm">
          <div className="min-w-0 space-y-xs">
            <h1 className="font-headline-lg text-headline-lg text-primary wrap-anywhere">
              Bonjour {viewer.name}
            </h1>
            <p className="font-body-md text-body-md text-on-surface-variant">
              Voici ce qui demande ton attention aujourd'hui.
            </p>
          </div>
          <div className="flex flex-wrap gap-xs">
            <DsButton variant={canReview ? "secondary" : "primary"} onClick={notWired}>
              Faire une demande
            </DsButton>
            {canReview && (
              <DsButton variant="primary" icon="add" onClick={notWired}>
                Publier une actu
              </DsButton>
            )}
          </div>
        </div>

        <TodayStrip
          canReview={canReview}
          pending={
            canReview
              ? queueOf(state.requests)
              : mineOf(state.requests).filter((s) => s.status === "en attente")
          }
          blockers={[]}
          drafts={0}
          publishedCount={canReview ? 2 : undefined}
        />

        <Lists key={`${state.value}-${viewer.key}`} state={state} viewer={viewer} />
      </main>
    </div>
  );
}
