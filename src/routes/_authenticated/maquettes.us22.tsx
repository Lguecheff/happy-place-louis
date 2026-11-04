import { createFileRoute } from "@tanstack/react-router";
import { useState } from "react";
import { toast } from "sonner";
import { BrandHeader } from "@/components/brand-header";
import { DS_INPUT, DsAvatar, DsButton, DsField, DsListItem, DsSection } from "@/components/ds";
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

export const Route = createFileRoute("/_authenticated/maquettes/us22")({
  head: () => ({
    meta: [{ title: "Happy Place · Maquette du repère sans réponse" }],
  }),
  component: Us22Mockup,
});

// ---------------------------------------------------------------------------
// Données factices (fictif).
// ---------------------------------------------------------------------------

const DAY_MS = 86_400_000;
const ago = (days: number) => new Date(Date.now() - days * DAY_MS).toISOString();

type Viewer = { name: string; role: "collaborateur" | "manager" };
const GONTRAN: Viewer = { name: "Gontran (fictif)", role: "collaborateur" };
const KESHA: Viewer = { name: "Kesha (fictif)", role: "manager" };

function request(
  id: string,
  author: string,
  team: string,
  status: string,
  createdDays: number,
  content: string,
  changedDays?: number,
): Submission {
  return {
    id,
    author_name: author,
    team,
    content,
    status,
    created_at: ago(createdDays),
    pending_since: changedDays === undefined ? undefined : ago(changedDays),
  };
}

const G = "Gontran (fictif)";
const G5 = request(
  "g5",
  G,
  "Data",
  "en attente",
  5,
  "Ajouter un export CSV au tableau des KPI pour les revues mensuelles.\n\nAujourd'hui, je recopie les valeurs à la main avant chaque revue, ce qui prend une demi-heure et crée des erreurs.\n\nUn bouton d'export suffirait, avec les valeurs du mois et leur date de mise à jour (fictif).",
);
/** Créée il y a 60 jours, repassée en attente il y a 42 jours : le compteur part du changement. */
const G42 = request(
  "g42",
  G,
  "Data",
  "en attente",
  60,
  "Ouvrir un créneau mensuel de questions avec l'équipe Product. Aujourd'hui, chaque question passe par un message isolé et se perd vite.\n\nUn créneau fixe permettrait de regrouper les sujets, de garder une trace des réponses et d'éviter les relances au fil de l'eau.\n\nJe propose une heure le premier jeudi du mois, avec un ordre du jour partagé la veille (fictif).",
  42,
);
const GVALIDATED = request(
  "gv",
  G,
  "Data",
  "validée",
  80,
  "Partager le planning des formations du trimestre dans les actus (fictif).",
  70,
);

const QUEUE: Submission[] = [
  request(
    "k2",
    "Amina Diallo (fictif)",
    "Product",
    "en attente",
    2,
    "Revoir l'ordre des étapes d'accueil des nouveaux arrivants (fictif).",
  ),
  request(
    "k12",
    "Hugo Martin (fictif)",
    "Data",
    "en attente",
    12,
    "Documenter la source du taux de placement (fictif).",
  ),
  G42,
];

const MANAGED: Submission[] = [
  ...QUEUE,
  request(
    "m1",
    "Léa Bernard (fictif)",
    "Product",
    "validée",
    20,
    "Créer un canal pour les retours clients (fictif).",
    15,
  ),
  request(
    "m2",
    "Hugo Martin (fictif)",
    "Data",
    "refusée",
    50,
    "Changer d'outil de ticket (fictif).",
    45,
  ),
  request(
    "m3",
    "Amina Diallo (fictif)",
    "Product",
    "clôturée",
    120,
    "Mettre à jour la charte des réunions (fictif).",
    90,
  ),
];

type MockState = {
  value: string;
  label: string;
  note: string;
  viewer: Viewer;
  mine: Submission[];
};

const STATES: MockState[] = [
  {
    value: "attente-5",
    label: "Demande en attente depuis 5 jours",
    note: "Vue de Gontran, onglet « Mes demandes ». À 5 jours, la demande en attente n'affiche aucun repère (mention retirée) ; la demande validée non plus. La fenêtre de lecture s'ouvre toujours : « Voir plus » si le texte est coupé, « Lire la demande » sinon.",
    viewer: GONTRAN,
    mine: [G5, GVALIDATED],
  },
  {
    value: "attente-42",
    label: "Demande en attente depuis 42 jours",
    note: "Vue de Gontran. Créée il y a 60 jours, repassée en attente il y a 42 jours : le compteur part du dernier changement de statut. Au-delà de 7 jours, seul le badge « Plus de 7 jours » s'affiche, aussi dans la fenêtre de lecture.",
    viewer: GONTRAN,
    mine: [G42, GVALIDATED],
  },
  {
    value: "validee",
    label: "Demande validée (aucun repère)",
    note: "Vue de Gontran. Une demande validée, refusée ou clôturée n'affiche aucun repère, ni dans la liste ni dans la fenêtre de lecture.",
    viewer: GONTRAN,
    mine: [GVALIDATED],
  },
  {
    value: "file",
    label: "File À traiter",
    note: "Vue de Kesha (manager). La file « À traiter » met la plus ancienne en premier et porte le même badge au-delà de 7 jours, sans nombre de jours en deçà. L'onglet « Gérées » aussi, seulement sur les demandes en attente.",
    viewer: KESHA,
    mine: [],
  },
];

const notWired = () => toast.info("Non branché dans la maquette (fictif).");

const TAB = cn(
  "min-h-11 rounded-none border-b-2 border-transparent px-sm font-label-md text-sm",
  "data-[state=active]:border-primary data-[state=active]:bg-transparent data-[state=active]:text-primary data-[state=active]:shadow-none",
  DS_FOCUS,
);

// ---------------------------------------------------------------------------
// Lignes : mêmes compositions que RequestsSection, libellés de l'US22.
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

function Us22Mockup() {
  const [stateValue, setStateValue] = useState(STATES[0].value);
  const state = STATES.find((s) => s.value === stateValue) ?? STATES[0];
  const viewer = state.viewer;
  const canReview = viewer.role === "manager";
  const [tab, setTab] = useState(canReview ? "a-traiter" : "mes-demandes");
  const [reading, setReading] = useState<Submission | null>(null);

  const queue = [...QUEUE].sort((a, b) => pendingSince(a).localeCompare(pendingSince(b)));
  const pending = canReview ? QUEUE : state.mine.filter((s) => s.status === "en attente");

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
          <DsField id="maquette-etat" label="Maquette (fictif)" className="w-full md:w-72">
            <select
              id="maquette-etat"
              className={DS_INPUT}
              value={state.value}
              onChange={(e) => {
                const next = STATES.find((s) => s.value === e.target.value) ?? STATES[0];
                setStateValue(next.value);
                setTab(next.viewer.role === "manager" ? "a-traiter" : "mes-demandes");
                setReading(null);
              }}
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
          pending={pending}
          blockers={[]}
          drafts={0}
          publishedCount={canReview ? 2 : undefined}
        />

        <div className="flex flex-wrap items-start gap-md">
          <div className="flex min-w-0 flex-[999_1_620px] flex-col gap-md">
            <DsSection id="demandes" title="Demandes">
              <Tabs value={tab} onValueChange={setTab}>
                <TabsList className="h-auto w-full flex-wrap justify-start gap-x-xs rounded-none border-b border-outline-variant bg-transparent p-0">
                  {canReview && (
                    <TabsTrigger value="a-traiter" className={TAB}>
                      À traiter ({QUEUE.length})
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
                    {queue.map((s) => (
                      <PendingRow key={s.id} s={s} onRead={() => setReading(s)} />
                    ))}
                  </TabsContent>
                )}
                <TabsContent value="mes-demandes" className="mt-md space-y-xs">
                  {state.mine.length === 0 ? (
                    <p className="font-body-sm text-body-sm text-on-surface-variant">
                      Aucune demande dans cet état de la maquette (fictif).
                    </p>
                  ) : (
                    state.mine.map((s) => <MyRow key={s.id} s={s} onRead={() => setReading(s)} />)
                  )}
                </TabsContent>
                {canReview && (
                  <TabsContent value="gerees" className="mt-md">
                    <div className="grid gap-xs md:grid-cols-2">
                      {MANAGED.map((s) => (
                        <ManagedCard key={s.id} s={s} onRead={() => setReading(s)} />
                      ))}
                    </div>
                  </TabsContent>
                )}
              </Tabs>
            </DsSection>
          </div>
        </div>
      </main>
      <SubmissionReader submission={reading} onClose={() => setReading(null)} hideAttachment />
    </div>
  );
}
