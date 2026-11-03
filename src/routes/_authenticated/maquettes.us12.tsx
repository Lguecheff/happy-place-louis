import { createFileRoute } from "@tanstack/react-router";
import { useRef, useState } from "react";
import { toast } from "sonner";
import { BrandHeader } from "@/components/brand-header";
import { DS_INPUT, DsButton, DsField } from "@/components/ds";
import { NotificationBell } from "@/components/notifications/NotificationBell";
import { arrivalAnnouncement } from "@/components/notifications/notification-utils";
import { OverviewHeader } from "@/components/overview/OverviewHeader";
import { GlobalSearch } from "@/components/search/GlobalSearch";
import type { AppNotification, Submission } from "@/lib/dashboard";

export const Route = createFileRoute("/_authenticated/maquettes/us12")({
  head: () => ({
    meta: [{ title: "Happy Place · Maquette du centre de notifications" }],
  }),
  component: Us12Mockup,
});

// ---------------------------------------------------------------------------
// Données factices (fictif)
// ---------------------------------------------------------------------------

const MINUTE_MS = 60_000;
const HOUR_MS = 60 * MINUTE_MS;
const DAY_MS = 24 * HOUR_MS;

const ago = (ms: number) => new Date(Date.now() - ms).toISOString();

const UNREADABLE_ID = "illisible";

function mockNotification(
  id: string,
  age: number,
  author: string,
  team: string,
  read = false,
  submission_id: string | null = id,
): AppNotification {
  const created_at = ago(age);
  return {
    id,
    kind: "nouvelle_demande",
    submission_id,
    message: `Nouvelle demande de ${author} (${team}) (fictif)`,
    created_at,
    read_at: read ? created_at : null,
    actor_name: null,
  };
}

const threeUnread = () => [
  mockNotification("n1", 5 * MINUTE_MS, "Gontran Martin", "Product"),
  mockNotification("n2", 3 * HOUR_MS, "Inès Roche", "Marketing"),
  mockNotification("n3", 20 * HOUR_MS, "Gontran Martin", "Product"),
  mockNotification("n4", 2 * DAY_MS, "Hugo Petit", "Marketing", true),
  mockNotification("n5", 6 * DAY_MS, "Inès Roche", "Marketing", true),
  mockNotification("n6", 21 * DAY_MS, "Gontran Martin", "Product", true),
];

const manyUnread = () =>
  Array.from({ length: 12 }, (_, i) =>
    mockNotification(`n${i + 1}`, (i + 1) * 2 * HOUR_MS, "Gontran Martin", "Product"),
  );

const allRead = () => threeUnread().map((n) => ({ ...n, read_at: n.read_at ?? n.created_at }));

const unavailable = () => [
  mockNotification("supprimee", 30 * MINUTE_MS, "Inès Roche", "Marketing", false, null),
  mockNotification("illisible", 2 * HOUR_MS, "Hugo Petit", "Marketing", false, UNREADABLE_ID),
  mockNotification("n3", DAY_MS * 2, "Gontran Martin", "Product", true),
];

const STATES = [
  {
    value: "non-lues",
    label: "Non lues (3)",
    build: threeUnread,
    note: "Ouvre la cloche : les 3 premières lignes portent « Non lue », une autre icône et un texte plus gras. Clique sur une ligne pour lire la demande.",
  },
  {
    value: "plus-de-9",
    label: "Plus de 9 non lues",
    build: manyUnread,
    note: "12 notifications non lues : la pastille affiche « 9+ », le libellé lu par les lecteurs d'écran donne le nombre exact.",
  },
  {
    value: "tout-lu",
    label: "Tout est lu",
    build: allRead,
    note: "Pas de pastille, pas de bouton « Tout marquer comme lu ».",
  },
  {
    value: "vide",
    label: "Aucune notification",
    build: () => [],
    note: "Ouvre la cloche : le panneau affiche « Aucune notification ».",
  },
  {
    value: "indisponible",
    label: "Demande plus disponible",
    build: unavailable,
    note: "La 1re ligne vise une demande supprimée, la 2e une demande que tu ne peux plus lire : même message, sans le contenu.",
  },
  {
    value: "arrivee",
    label: "Arrivée d'une notification",
    build: threeUnread,
    note: "Clique sur « Simuler une arrivée » : la pastille passe à 4 sans recharger, et le texte ci-dessous est lu par les lecteurs d'écran.",
  },
];

function mockSubmission(notification: AppNotification): Submission {
  return {
    id: notification.id,
    author_name: "Gontran Martin (fictif)",
    team: "Product",
    content: "Contenu de la demande (fictif).",
    status: "en attente",
    created_at: notification.created_at,
  };
}

// ---------------------------------------------------------------------------
// Présentation
// ---------------------------------------------------------------------------

function Us12Mockup() {
  const [stateValue, setStateValue] = useState(STATES[0].value);
  const [notifications, setNotifications] = useState(threeUnread);
  const [announced, setAnnounced] = useState("");
  const arrivals = useRef(0);

  const state = STATES.find((s) => s.value === stateValue) ?? STATES[0];

  function changeState(value: string) {
    setStateValue(value);
    setNotifications((STATES.find((s) => s.value === value) ?? STATES[0]).build());
    setAnnounced("");
  }

  function markRead(id: string) {
    const read_at = new Date().toISOString();
    setNotifications((list) => list.map((n) => (n.id === id ? { ...n, read_at } : n)));
  }

  function markAllRead() {
    const read_at = new Date().toISOString();
    setNotifications((list) => list.map((n) => ({ ...n, read_at: n.read_at ?? read_at })));
  }

  function simulateArrival() {
    arrivals.current += 1;
    const arrival = mockNotification(`arrivee-${arrivals.current}`, 0, "Gontran Martin", "Product");
    setNotifications((list) => [arrival, ...list]);
    setAnnounced(arrivalAnnouncement([arrival]));
  }

  async function loadSubmission(id: string) {
    if (id === UNREADABLE_ID) return null;
    const notification = notifications.find((n) => n.submission_id === id);
    return notification ? mockSubmission(notification) : null;
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
              loadSubmission={loadSubmission}
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
          <div className="min-w-0 flex-1 basis-64 space-y-1 font-body-sm text-body-sm text-on-surface-variant">
            <p className="text-on-surface">{state.note}</p>
            {announced && <p>Annonce aux lecteurs d'écran : « {announced} »</p>}
          </div>
          {state.value === "arrivee" && (
            <DsButton icon="add" onClick={simulateArrival}>
              Simuler une arrivée
            </DsButton>
          )}
        </div>
        <div className="space-y-xs">
          <h1 className="font-headline-lg text-headline-lg text-primary wrap-anywhere">
            Bonjour Kesha (fictif)
          </h1>
          <p className="font-body-md text-body-md text-on-surface-variant">
            Voici ce qui demande ton attention aujourd'hui.
          </p>
        </div>
      </main>
    </div>
  );
}
