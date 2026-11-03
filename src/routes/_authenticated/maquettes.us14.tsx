import { createFileRoute } from "@tanstack/react-router";
import { useState } from "react";
import { toast } from "sonner";
import { BrandHeader } from "@/components/brand-header";
import { DS_INPUT, DsField } from "@/components/ds";
import { NotificationBell } from "@/components/notifications/NotificationBell";
import {
  DEFAULT_CHANNELS,
  notificationKindsFor,
  type NotificationChannel,
  type PreferenceKind,
  type PreferenceValues,
} from "@/components/notifications/notification-kinds";
import { OverviewHeader } from "@/components/overview/OverviewHeader";
import { GlobalSearch } from "@/components/search/GlobalSearch";
import {
  SubmissionThreadView,
  sortSteps,
  type ThreadStep,
} from "@/components/submission-status-thread";
import type { AppNotification, Submission } from "@/lib/dashboard";

export const Route = createFileRoute("/_authenticated/maquettes/us14")({
  head: () => ({
    meta: [{ title: "Happy Place · Maquette des alertes de changement d'état" }],
  }),
  component: Us14Mockup,
});

// ---------------------------------------------------------------------------
// Données factices (fictif)
// ---------------------------------------------------------------------------

const MINUTE_MS = 60_000;
const DAY_MS = 24 * 60 * MINUTE_MS;
const SAVE_DELAY_MS = 400;
const SUBMISSION_ID = "s1";

const CONTENT =
  "Ajouter un tableau de bord des temps de réponse du support, par équipe et par semaine (fictif)";
const EXCERPT = `${CONTENT.slice(0, 59)}…`;
const GONTRAN = "Gontran Martin (fictif)";
const KESHA = "Kesha Diallo (fictif)";
const LEA = "Léa Petit (fictif)";

const ago = (ms: number) => new Date(Date.now() - ms).toISOString();

type Step = Omit<ThreadStep, "id" | "changed_by_email" | "rejection_note"> & {
  rejection_note?: string | null;
};

function step(i: number, s: Step): ThreadStep {
  return {
    id: `t${i}`,
    changed_by_email: s.changed_by_name ? "fictif@test.invalid" : null,
    rejection_note: null,
    ...s,
  };
}

const CREATED: Step = {
  old_status: null,
  new_status: "en attente",
  changed_by_name: GONTRAN,
  is_automatic: false,
  rejection_category: null,
  changed_at: ago(400 * DAY_MS),
};

type MockState = {
  value: string;
  label: string;
  note: string;
  status: string;
  rejection?: { category: string; note: string };
  /** Autrice d'une demande que Gontran suit sans l'avoir faite ; sans valeur, c'est la sienne. */
  author?: string;
  steps: Step[];
  /** Notifications de la plus ancienne à la plus récente ; la dernière est non lue. */
  alerts: { message: string; actor: string; at: string }[];
  preferences?: boolean;
};

const STATES: MockState[] = [
  {
    value: "validee",
    label: "Validée",
    status: "validée",
    note: "Kesha valide la demande : la cloche de Gontran s'allume sans recharger. Le clic ouvre la demande et son fil dans la même fenêtre.",
    steps: [
      CREATED,
      {
        ...CREATED,
        old_status: "en attente",
        new_status: "validée",
        changed_by_name: KESHA,
        changed_at: ago(5 * MINUTE_MS),
      },
    ],
    alerts: [
      {
        message: `Ta demande a été validée : « ${EXCERPT} »`,
        actor: KESHA,
        at: ago(5 * MINUTE_MS),
      },
    ],
  },
  {
    value: "refusee",
    label: "Refusée avec catégorie",
    status: "refusée",
    rejection: {
      category: "doublon",
      note: "Déjà demandé par l'équipe Support en septembre (fictif).",
    },
    note: "La catégorie de refus figure dans la notification ; la raison se lit dans la demande et dans son fil.",
    steps: [
      CREATED,
      {
        ...CREATED,
        old_status: "en attente",
        new_status: "refusée",
        changed_by_name: KESHA,
        rejection_category: "doublon",
        rejection_note: "Déjà demandé par l'équipe Support en septembre (fictif).",
        changed_at: ago(12 * MINUTE_MS),
      },
    ],
    alerts: [
      {
        message: `Ta demande a été refusée (doublon) : « ${EXCERPT} »`,
        actor: KESHA,
        at: ago(12 * MINUTE_MS),
      },
    ],
  },
  {
    value: "cloturee",
    label: "Clôturée automatiquement",
    status: "clôturée",
    note: "Un an après la validation, la clôture est faite par le système : la notification affiche « Automatique » à la place d'un nom.",
    steps: [
      CREATED,
      {
        ...CREATED,
        old_status: "en attente",
        new_status: "validée",
        changed_by_name: KESHA,
        changed_at: ago(366 * DAY_MS),
      },
      {
        ...CREATED,
        old_status: "validée",
        new_status: "clôturée",
        changed_by_name: null,
        is_automatic: true,
        changed_at: ago(3 * 60 * MINUTE_MS),
      },
    ],
    alerts: [
      {
        message: `Ta demande a été clôturée : « ${EXCERPT} »`,
        actor: "Automatique",
        at: ago(3 * 60 * MINUTE_MS),
      },
    ],
  },
  {
    value: "attente",
    label: "Repassée en attente",
    status: "en attente",
    note: "Kesha revient sur son refus : chaque étape du fil a créé sa notification, la plus récente en haut.",
    steps: [
      CREATED,
      {
        ...CREATED,
        old_status: "en attente",
        new_status: "refusée",
        changed_by_name: KESHA,
        rejection_category: "à clarifier",
        rejection_note: "Précise le périmètre des équipes concernées (fictif).",
        changed_at: ago(2 * DAY_MS),
      },
      {
        ...CREATED,
        old_status: "refusée",
        new_status: "en attente",
        changed_by_name: KESHA,
        changed_at: ago(2 * MINUTE_MS),
      },
    ],
    alerts: [
      {
        message: `Ta demande a été refusée (à clarifier) : « ${EXCERPT} »`,
        actor: KESHA,
        at: ago(2 * DAY_MS),
      },
      {
        message: `Ta demande est repassée en attente : « ${EXCERPT} »`,
        actor: KESHA,
        at: ago(2 * MINUTE_MS),
      },
    ],
  },
  {
    value: "suivie",
    label: "Demande suivie (pas la sienne)",
    status: "validée",
    author: LEA,
    note: "Gontran suit la demande de Léa sans en être l'auteur (US15) : le texte nomme l'autrice, et l'alerte dépend de la ligne « Changement d'état des demandes que je suis ».",
    steps: [
      { ...CREATED, changed_by_name: LEA },
      {
        ...CREATED,
        old_status: "en attente",
        new_status: "validée",
        changed_by_name: KESHA,
        changed_at: ago(20 * MINUTE_MS),
      },
    ],
    alerts: [
      {
        message: `La demande de ${LEA} a été validée : « ${EXCERPT} »`,
        actor: KESHA,
        at: ago(20 * MINUTE_MS),
      },
    ],
  },
  {
    value: "preferences",
    label: "Préférences (case verrouillée)",
    status: "validée",
    preferences: true,
    note: "Ouvre le menu du profil, puis « Préférences » : « Changement d'état de mes demandes » a la case « Dans l'app » cochée et verrouillée ; « Changement d'état des demandes que je suis » reste modifiable.",
    steps: [],
    alerts: [],
  },
];

function notificationsFor(state: MockState): AppNotification[] {
  return state.alerts.map((a, i) => ({
    id: `${state.value}-${i}`,
    kind: state.author ? "changement_statut_suivi" : "changement_statut",
    submission_id: SUBMISSION_ID,
    blocker_id: null,
    message: `${a.message} (fictif)`,
    actor_name: a.actor,
    created_at: a.at,
    read_at: i < state.alerts.length - 1 ? a.at : null,
  }));
}

function mockSubmission(state: MockState): Submission {
  return {
    id: SUBMISSION_ID,
    author_name: state.author ?? GONTRAN,
    team: "Product",
    content: CONTENT,
    status: state.status,
    created_at: CREATED.changed_at,
    rejection_category: state.rejection?.category ?? null,
    rejection_note: state.rejection?.note ?? null,
  };
}

// ---------------------------------------------------------------------------
// Présentation
// ---------------------------------------------------------------------------

function Us14Mockup() {
  const [stateValue, setStateValue] = useState(STATES[0].value);
  const state = STATES.find((s) => s.value === stateValue) ?? STATES[0];
  const [notifications, setNotifications] = useState(() => notificationsFor(state));
  const [values, setValues] = useState<PreferenceValues>({});
  const [threadOf, setThreadOf] = useState<Submission | null>(null);

  function changeState(value: string) {
    const next = STATES.find((s) => s.value === value) ?? STATES[0];
    setStateValue(next.value);
    setNotifications(notificationsFor(next));
    setValues({});
  }

  function markRead(id: string) {
    const now = new Date().toISOString();
    setNotifications((ns) => ns.map((n) => (n.id === id ? { ...n, read_at: now } : n)));
  }

  function markAllRead() {
    const now = new Date().toISOString();
    setNotifications((ns) => ns.map((n) => ({ ...n, read_at: n.read_at ?? now })));
  }

  async function savePreference(
    kind: PreferenceKind,
    channel: NotificationChannel,
    checked: boolean,
  ) {
    await new Promise((resolve) => setTimeout(resolve, SAVE_DELAY_MS));
    setValues((v) => ({ ...v, [kind]: { ...(v[kind] ?? DEFAULT_CHANNELS), [channel]: checked } }));
  }

  return (
    <div className="bg-background text-on-surface font-body-md min-h-screen flex flex-col">
      <BrandHeader>
        <OverviewHeader
          isAdmin={false}
          name={GONTRAN}
          role="collaborateur"
          exporting={false}
          onExport={() => toast.info("Non branché dans la maquette (fictif).")}
          preferences={{
            kinds: notificationKindsFor("collaborateur"),
            values,
            onChange: savePreference,
          }}
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
            <NotificationBell
              key={state.value}
              notifications={notifications}
              onMarkRead={markRead}
              onMarkAllRead={markAllRead}
              loadSubmission={async () => mockSubmission(state)}
              onOpenSubmission={setThreadOf}
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
              onChange={(e) => changeState(e.target.value)}
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
        <div className="space-y-xs">
          <h1 className="font-headline-lg text-headline-lg text-primary wrap-anywhere">
            Bonjour Gontran (fictif)
          </h1>
          <p className="font-body-md text-body-md text-on-surface-variant">
            Voici ce qui demande ton attention aujourd'hui.
          </p>
        </div>
      </main>
      {threadOf && (
        <SubmissionThreadView
          content={threadOf.content}
          team={threadOf.team}
          steps={sortSteps(state.steps.map((s, i) => step(i, s)))}
          onClose={() => setThreadOf(null)}
        />
      )}
    </div>
  );
}
