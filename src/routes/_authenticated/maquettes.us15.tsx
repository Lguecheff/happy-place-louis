import { createFileRoute } from "@tanstack/react-router";
import { useState } from "react";
import { toast } from "sonner";
import { BrandHeader } from "@/components/brand-header";
import { DS_INPUT, DsField, DsListItem, DsSection } from "@/components/ds";
import { FollowButton, type FollowSource } from "@/components/notifications/FollowButton";
import { NotificationBell } from "@/components/notifications/NotificationBell";
import { notificationKindsFor, type AppRole } from "@/components/notifications/notification-kinds";
import { OverviewHeader } from "@/components/overview/OverviewHeader";
import { statusLabel } from "@/components/overview/overview-utils";
import { GlobalSearch } from "@/components/search/GlobalSearch";
import { SubmissionReader } from "@/components/submission-reader";
import { SubmissionThreadView, sortSteps } from "@/components/submission-status-thread";
import type { AppNotification, Submission } from "@/lib/dashboard";

export const Route = createFileRoute("/_authenticated/maquettes/us15")({
  head: () => ({
    meta: [{ title: "Happy Place · Maquette du suivi d'une demande" }],
  }),
  component: Us15Mockup,
});

// ---------------------------------------------------------------------------
// Données factices (fictif)
// ---------------------------------------------------------------------------

const MINUTE_MS = 60_000;
const DAY_MS = 24 * 60 * MINUTE_MS;
const SAVE_DELAY_MS = 400;

const GONTRAN = "Gontran Martin (fictif)";
const KESHA = "Kesha Diallo (fictif)";
const LEA = "Léa Petit (fictif)";
const SACHA = "Sacha Bernard (fictif)";

const ago = (ms: number) => new Date(Date.now() - ms).toISOString();

const CONTENT_GONTRAN =
  "Ajouter un tableau de bord des temps de réponse du support, par équipe et par semaine (fictif)";
const CONTENT_LEA =
  "Partager le calendrier des campagnes marketing avec les équipes produit chaque lundi (fictif)";
const EXCERPT_LEA = `${CONTENT_LEA.slice(0, 59)}…`;

type MockState = {
  value: string;
  label: string;
  note: string;
  role: AppRole;
  viewer: string;
  submission: Submission;
  /** Où se trouve la demande sur l'accueil. */
  section: string;
  /** Suivi au chargement de l'état. */
  source: FollowSource | null;
  /** La demande s'ouvre depuis une notification, dans la fenêtre « Suivi de la demande ». */
  fromNotification?: boolean;
};

const PENDING_GONTRAN: Submission = {
  id: "s1",
  author_name: GONTRAN,
  team: "Product",
  content: CONTENT_GONTRAN,
  status: "en attente",
  created_at: ago(2 * DAY_MS),
  rejection_category: null,
  rejection_note: null,
};

const VALIDATED_LEA: Submission = {
  id: "s2",
  author_name: LEA,
  team: "Marketing",
  content: CONTENT_LEA,
  status: "validée",
  created_at: ago(9 * DAY_MS),
  rejection_category: null,
  rejection_note: null,
};

const STATES: MockState[] = [
  {
    value: "manager",
    label: "Manager (suit d'office)",
    role: "manager",
    viewer: KESHA,
    submission: PENDING_GONTRAN,
    section: "Demandes à traiter",
    source: "manager",
    note: "Kesha suit d'office chaque demande de ses équipes, dès sa création. « Ne plus suivre » s'applique tout de suite ; « Suivre » la remet.",
  },
  {
    value: "autre-equipe",
    label: "Collaborateur, demande validée d'une autre équipe",
    role: "collaborateur",
    viewer: GONTRAN,
    submission: VALIDATED_LEA,
    section: "Demandes validées",
    source: null,
    note: "Gontran lit une demande validée de l'équipe Marketing : il peut la suivre. Si elle n'est plus lisible (clôturée, par exemple), il ne reçoit plus d'alerte.",
  },
  {
    value: "auteur",
    label: "Auteur",
    role: "collaborateur",
    viewer: GONTRAN,
    submission: PENDING_GONTRAN,
    section: "Mes demandes",
    source: "auteur",
    note: "L'auteur suit sa demande d'office et ne peut pas l'arrêter : la mention « Tu suis ta demande » remplace le bouton.",
  },
  {
    value: "admin",
    label: "Admin (pas de bouton)",
    role: "admin",
    viewer: SACHA,
    submission: VALIDATED_LEA,
    section: "Demandes",
    source: null,
    note: "Un admin lit toutes les demandes mais n'en suit aucune : pas de bouton ni de mention.",
  },
  {
    value: "notification",
    label: "Notification d'une demande suivie",
    role: "collaborateur",
    viewer: GONTRAN,
    submission: VALIDATED_LEA,
    section: "Demandes validées",
    source: "volontaire",
    fromNotification: true,
    note: "Gontran suit la demande de Léa : Kesha l'a validée, sa cloche s'allume. Le clic ouvre « Suivi de la demande » (choix de l'US14), avec le même bouton de suivi.",
  },
];

function notificationsFor(state: MockState): AppNotification[] {
  if (!state.fromNotification) return [];
  return [
    {
      id: `${state.value}-0`,
      kind: "changement_statut_suivi",
      submission_id: state.submission.id,
      message: `La demande de ${LEA} a été validée : « ${EXCERPT_LEA} » (fictif)`,
      actor_name: KESHA,
      created_at: ago(20 * MINUTE_MS),
      read_at: null,
    },
  ];
}

const THREAD_STEPS = sortSteps([
  {
    id: "t0",
    old_status: null,
    new_status: "en attente",
    changed_by_email: "fictif@test.invalid",
    changed_by_name: LEA,
    is_automatic: false,
    rejection_category: null,
    rejection_note: null,
    changed_at: VALIDATED_LEA.created_at,
  },
  {
    id: "t1",
    old_status: "en attente",
    new_status: "validée",
    changed_by_email: "fictif@test.invalid",
    changed_by_name: KESHA,
    is_automatic: false,
    rejection_category: null,
    rejection_note: null,
    changed_at: ago(20 * MINUTE_MS),
  },
]);

const notWired = () => toast.info("Non branché dans la maquette (fictif).");

// ---------------------------------------------------------------------------
// Présentation
// ---------------------------------------------------------------------------

function Us15Mockup() {
  const [stateValue, setStateValue] = useState(STATES[0].value);
  const state = STATES.find((s) => s.value === stateValue) ?? STATES[0];
  const [source, setSource] = useState<FollowSource | null>(state.source);
  const [pending, setPending] = useState(false);
  const [notifications, setNotifications] = useState(() => notificationsFor(state));
  const [reading, setReading] = useState<Submission | null>(null);
  const [threadOf, setThreadOf] = useState<Submission | null>(null);

  function changeState(value: string) {
    const next = STATES.find((s) => s.value === value) ?? STATES[0];
    setStateValue(next.value);
    setSource(next.source);
    setNotifications(notificationsFor(next));
    setReading(null);
    setThreadOf(null);
  }

  // Le manager qui arrête puis reprend le suivi devient un suivi volontaire.
  async function changeFollow(follow: boolean) {
    setPending(true);
    await new Promise((resolve) => setTimeout(resolve, SAVE_DELAY_MS));
    setSource(follow ? "volontaire" : null);
    setPending(false);
  }

  function markRead(id: string) {
    const now = new Date().toISOString();
    setNotifications((ns) => ns.map((n) => (n.id === id ? { ...n, read_at: now } : n)));
  }

  function markAllRead() {
    const now = new Date().toISOString();
    setNotifications((ns) => ns.map((n) => ({ ...n, read_at: n.read_at ?? now })));
  }

  const follow = (
    <FollowButton
      source={source}
      isAdmin={state.role === "admin"}
      pending={pending}
      onChange={changeFollow}
    />
  );
  const s = state.submission;
  const firstName = state.viewer.split(" ")[0];

  return (
    <div className="bg-background text-on-surface font-body-md min-h-screen flex flex-col">
      <BrandHeader>
        <OverviewHeader
          isAdmin={state.role === "admin"}
          name={state.viewer}
          role={state.role}
          exporting={false}
          onExport={notWired}
          preferences={
            state.role === "admin"
              ? undefined
              : {
                  kinds: notificationKindsFor(state.role),
                  values: {},
                  onChange: async () => {
                    notWired();
                  },
                }
          }
          search={
            <GlobalSearch
              source={{
                data: { news: [], submissions: [], blockers: [], metrics: [] },
                isError: false,
                isLoading: false,
              }}
            />
          }
          notifications={
            state.role === "admin" ? undefined : (
              <NotificationBell
                key={state.value}
                notifications={notifications}
                onMarkRead={markRead}
                onMarkAllRead={markAllRead}
                loadSubmission={async () => s}
                onOpenSubmission={setThreadOf}
              />
            )
          }
        />
      </BrandHeader>
      <main className="flex-grow w-full max-w-interface mx-auto p-sm md:p-md space-y-md">
        <div className="flex flex-wrap items-end gap-sm border border-dashed border-outline-variant p-sm">
          <DsField id="maquette-etat" label="Maquette (fictif)" className="w-full md:w-80">
            <select
              id="maquette-etat"
              className={DS_INPUT}
              value={state.value}
              onChange={(e) => changeState(e.target.value)}
            >
              {STATES.map((st) => (
                <option key={st.value} value={st.value}>
                  {st.label}
                </option>
              ))}
            </select>
          </DsField>
          <p className="min-w-0 flex-1 basis-64 font-body-sm text-body-sm text-on-surface">
            {state.note}
          </p>
        </div>
        <div className="space-y-xs">
          <h1 className="font-headline-lg text-headline-lg text-primary wrap-anywhere">
            Bonjour {firstName} (fictif)
          </h1>
          <p className="font-body-md text-body-md text-on-surface-variant">
            Voici ce qui demande ton attention aujourd'hui.
          </p>
        </div>
        <DsSection id="demandes" title={state.section}>
          <DsListItem
            icon="description"
            title={s.content}
            meta={`${s.author_name} · ${s.team} · ${statusLabel(s.status)}`}
            onClick={() => setReading(s)}
          />
        </DsSection>
      </main>
      <SubmissionReader submission={reading} onClose={() => setReading(null)} follow={follow} />
      {threadOf && (
        <SubmissionThreadView
          content={threadOf.content}
          team={threadOf.team}
          steps={THREAD_STEPS}
          follow={follow}
          onClose={() => setThreadOf(null)}
        />
      )}
    </div>
  );
}
