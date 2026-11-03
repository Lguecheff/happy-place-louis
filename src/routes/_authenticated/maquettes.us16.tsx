import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useRef, useState } from "react";
import { toast } from "sonner";
import { BlockerReader } from "@/components/blocker-reader";
import { BrandHeader } from "@/components/brand-header";
import {
  DS_INPUT,
  DsButton,
  DsEmptyState,
  DsField,
  DsFreshness,
  DsListItem,
  DsSection,
} from "@/components/ds";
import { NotificationBell } from "@/components/notifications/NotificationBell";
import { NotificationCenter } from "@/components/notifications/NotificationCenter";
import {
  DEFAULT_CHANNELS,
  notificationKindsFor,
  type NotificationChannel,
  type PreferenceKind,
  type PreferenceValues,
} from "@/components/notifications/notification-kinds";
import { useNotificationPreferences } from "@/components/notifications/useNotificationPreferences";
import { BlockersSection } from "@/components/overview/BlockersSection";
import { OverviewHeader } from "@/components/overview/OverviewHeader";
import { plural, statusLabel } from "@/components/overview/overview-utils";
import { GlobalSearch } from "@/components/search/GlobalSearch";
import {
  fetchBlockers,
  simulateStaleBlocker,
  type AppNotification,
  type Blocker,
} from "@/lib/dashboard";

export const Route = createFileRoute("/_authenticated/maquettes/us16")({
  head: () => ({
    meta: [{ title: "Happy Place · Points bloquants à revoir (maquette et simulation)" }],
  }),
  component: Us16Mockup,
});

// ---------------------------------------------------------------------------
// Données factices (fictif)
// ---------------------------------------------------------------------------

const HOUR_MS = 60 * 60_000;
const DAY_MS = 24 * HOUR_MS;
const SAVE_DELAY_MS = 400;
const VIEWER = "Olivia Laurent (fictif)";

const ago = (ms: number) => new Date(Date.now() - ms).toISOString();

const CONTRACTS: Blocker = {
  id: "b1",
  title: "Signature des contrats freelance bloquée (fictif)",
  description:
    "Le service juridique attend la nouvelle trame de contrat : trois missions ne peuvent pas démarrer (fictif).",
  department: "Juridique",
  teams: [],
  severity: "critical",
  status: "OUVERT",
  created_at: ago(12 * DAY_MS),
  updated_at: ago(4 * DAY_MS + 2 * HOUR_MS),
};

const ATS: Blocker = {
  id: "b2",
  title: "Accès au nouvel ATS en attente (fictif)",
  description: "Les comptes des recruteurs Data ne sont pas encore créés (fictif).",
  department: "Tech",
  teams: ["Data"],
  severity: "warning",
  status: "EN COURS",
  created_at: ago(20 * DAY_MS),
  updated_at: ago(6 * DAY_MS + 5 * HOUR_MS),
};

// Modifié hier : il ne déclenche rien.
const ONBOARDING: Blocker = {
  id: "b3",
  title: "Parcours d'accueil des nouveaux arrivants à revoir (fictif)",
  description: null,
  department: "RH",
  teams: [],
  severity: "info",
  status: "SURVEILLANCE",
  created_at: ago(30 * DAY_MS),
  updated_at: ago(DAY_MS),
};

const reviewMessage = (b: Blocker, days: number) =>
  `Point bloquant à revoir : ${b.title} (sans mise à jour depuis ${days} jours)`;

const reviewNotification = (
  id: string,
  blocker: Blocker,
  days: number,
  blockerId: string | null,
): AppNotification => ({
  id,
  kind: "point_bloquant_a_revoir",
  submission_id: null,
  blocker_id: blockerId,
  message: reviewMessage(blocker, days),
  // Passage quotidien de la nuit.
  created_at: ago(7 * HOUR_MS),
  read_at: null,
  actor_name: null,
});

type MockState = {
  value: string;
  label: string;
  note: string;
  blockers: Blocker[];
  notifications: AppNotification[];
  /** Vraies données : vraie cloche et simulation en base. */
  live?: boolean;
};

const STATES: MockState[] = [
  {
    value: "a-revoir",
    label: "2 points à revoir",
    note: "Ce matin, deux points non résolus n'avaient pas bougé depuis plus de 3 jours : la cloche en compte 2. Un clic ouvre le point dans sa fenêtre de lecture. Change un statut dans « Points bloquants » : en vrai, ce point ne renotifie que 3 jours plus tard.",
    blockers: [CONTRACTS, ATS, ONBOARDING],
    notifications: [
      reviewNotification("n1", CONTRACTS, 4, "b1"),
      reviewNotification("n2", ATS, 6, "b2"),
    ],
  },
  {
    value: "supprime",
    label: "Point supprimé",
    note: "« Accès au nouvel ATS » a été supprimé après la notification : elle reste dans la cloche avec son texte, mais un clic affiche « Ce point bloquant n'est plus disponible. ».",
    blockers: [CONTRACTS, ONBOARDING],
    notifications: [reviewNotification("n2", ATS, 6, null)],
  },
  {
    value: "preferences",
    label: "Préférences admin",
    note: "Ouvre le menu du profil, puis « Préférences » : une seule ligne, « Point bloquant à revoir », avec « Dans l'app » et « Par mail », cochées par défaut et modifiables.",
    blockers: [CONTRACTS, ATS, ONBOARDING],
    notifications: [],
  },
  {
    value: "simulation",
    label: "Simulation (vraies données)",
    note: "Pour la présentation : « Simuler 4 jours sans mise à jour » fait comme si le point n'avait pas bougé depuis 4 jours et lance le passage quotidien. La vraie cloche reçoit la notification en temps réel. Relancer sans modifier le point ne crée rien ; modifie-le d'abord.",
    blockers: [],
    notifications: [],
    live: true,
  },
];

const notWired = () => toast.info("Non branché dans la maquette (fictif).");

// ---------------------------------------------------------------------------
// Présentation
// ---------------------------------------------------------------------------

function Us16Mockup() {
  const { role, email } = Route.useRouteContext();
  const myEmail = (email ?? "").toLowerCase();
  const livePreferences = useNotificationPreferences(myEmail, role);
  const [stateValue, setStateValue] = useState(STATES[0].value);
  const state = STATES.find((s) => s.value === stateValue) ?? STATES[0];
  const [blockers, setBlockers] = useState(state.blockers);
  const [notifications, setNotifications] = useState(state.notifications);
  const [values, setValues] = useState<PreferenceValues>({});
  const [reading, setReading] = useState<Blocker | null>(null);
  const bellRef = useRef<HTMLDivElement>(null);

  function changeState(value: string) {
    const next = STATES.find((s) => s.value === value) ?? STATES[0];
    setStateValue(next.value);
    setBlockers(next.blockers);
    setNotifications(next.notifications);
    setValues({});
    setReading(null);
  }

  function markRead(id: string) {
    const now = new Date().toISOString();
    setNotifications((ns) => ns.map((n) => (n.id === id ? { ...n, read_at: now } : n)));
  }

  function markAllRead() {
    const now = new Date().toISOString();
    setNotifications((ns) => ns.map((n) => ({ ...n, read_at: n.read_at ?? now })));
  }

  // Comme updateBlockerStatus : l'app remplit updated_at, ce qui remet le compteur à zéro.
  function changeStatus(id: string, status: string) {
    const now = new Date().toISOString();
    setBlockers((bs) => bs.map((b) => (b.id === id ? { ...b, status, updated_at: now } : b)));
  }

  async function savePreference(
    kind: PreferenceKind,
    channel: NotificationChannel,
    checked: boolean,
  ) {
    await new Promise((resolve) => setTimeout(resolve, SAVE_DELAY_MS));
    setValues((v) => ({ ...v, [kind]: { ...(v[kind] ?? DEFAULT_CHANNELS), [channel]: checked } }));
  }

  // Rend le focus à la cloche à la fermeture de la fenêtre de lecture.
  function focusBell(event: Event) {
    event.preventDefault();
    bellRef.current?.querySelector("button")?.focus();
  }

  return (
    <div className="bg-background text-on-surface font-body-md min-h-screen flex flex-col">
      <BrandHeader>
        <OverviewHeader
          isAdmin
          name={state.live ? myEmail : VIEWER}
          role={state.live ? role : "admin"}
          exporting={false}
          onExport={notWired}
          preferences={
            state.live
              ? livePreferences
              : { kinds: notificationKindsFor("admin"), values, onChange: savePreference }
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
            state.live ? (
              myEmail && <NotificationCenter email={myEmail} />
            ) : (
              <div ref={bellRef} className="contents">
                <NotificationBell
                  key={state.value}
                  notifications={notifications}
                  onMarkRead={markRead}
                  onMarkAllRead={markAllRead}
                  loadSubmission={async () => null}
                  onOpenSubmission={() => {}}
                  loadBlocker={async (id) => blockers.find((b) => b.id === id) ?? null}
                  onOpenBlocker={setReading}
                />
              </div>
            )
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
            {state.live ? "Bonjour" : "Bonjour Olivia (fictif)"}
          </h1>
          <p className="font-body-md text-body-md text-on-surface-variant">
            Voici ce qui demande ton attention aujourd'hui.
          </p>
        </div>
        <div className="max-w-lg">
          {state.live ? (
            <Simulation isAdmin={role === "admin"} />
          ) : (
            <BlockersSection
              blockers={{ data: blockers, isError: false }}
              canEdit
              onStatusChange={changeStatus}
              onOpen={setReading}
              onOpenArchive={notWired}
            />
          )}
        </div>
      </main>
      <BlockerReader
        blocker={reading}
        onClose={() => setReading(null)}
        onCloseAutoFocus={focusBell}
      />
    </div>
  );
}

/** Simulation pour la présentation, sur les vrais points bloquants non résolus. */
function Simulation({ isAdmin }: { isAdmin: boolean }) {
  const qc = useQueryClient();
  const blockers = useQuery({ queryKey: ["blockers"], queryFn: fetchBlockers, enabled: isAdmin });
  const simulate = useMutation({
    mutationFn: simulateStaleBlocker,
    onSuccess: (count) => {
      if (count > 0)
        toast.success(`${count} ${plural(count, "notification")} ${plural(count, "créée")}`);
      else
        toast.info(
          "Aucune nouvelle notification : ce point a déjà été signalé depuis sa dernière modification, ou « Dans l'app » est décoché.",
        );
      qc.invalidateQueries({ queryKey: ["blockers"] });
    },
    onError: (e: unknown) => toast.error((e as Error).message),
  });

  return (
    <DsSection id="simulation" title="Simulation pour la présentation">
      {!isAdmin ? (
        <DsEmptyState>
          La simulation est réservée aux admins : change de rôle pour l'essayer.
        </DsEmptyState>
      ) : blockers.isError ? (
        <DsEmptyState>Les points bloquants sont indisponibles.</DsEmptyState>
      ) : blockers.data?.length === 0 ? (
        <DsEmptyState>Aucun point bloquant non résolu à simuler.</DsEmptyState>
      ) : (
        <ul className="space-y-xs">
          {blockers.data?.map((b) => (
            <li key={b.id}>
              <DsListItem
                icon="report"
                title={b.title}
                meta={statusLabel(b.status)}
                actions={
                  <DsButton
                    icon="fast_forward"
                    pending={simulate.isPending && simulate.variables === b.id}
                    disabled={simulate.isPending}
                    onClick={() => simulate.mutate(b.id)}
                  >
                    Simuler 4 jours sans mise à jour
                  </DsButton>
                }
              >
                <DsFreshness at={b.updated_at} />
              </DsListItem>
            </li>
          ))}
        </ul>
      )}
    </DsSection>
  );
}
