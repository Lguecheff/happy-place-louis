import { createFileRoute } from "@tanstack/react-router";
import { useState } from "react";
import { toast } from "sonner";
import { BrandHeader } from "@/components/brand-header";
import { DS_INPUT, DsField } from "@/components/ds";
import { NotificationBell } from "@/components/notifications/NotificationBell";
import {
  DEFAULT_CHANNELS,
  notificationKindsFor,
  type AppRole,
  type NotificationChannel,
  type PreferenceKind,
  type PreferenceValues,
} from "@/components/notifications/notification-kinds";
import { OverviewHeader } from "@/components/overview/OverviewHeader";
import { GlobalSearch } from "@/components/search/GlobalSearch";
import type { AppNotification } from "@/lib/dashboard";

export const Route = createFileRoute("/_authenticated/maquettes/us13")({
  head: () => ({
    meta: [{ title: "Happy Place · Maquette des préférences de notification" }],
  }),
  component: Us13Mockup,
});

// ---------------------------------------------------------------------------
// Données factices (fictif)
// ---------------------------------------------------------------------------

const MINUTE_MS = 60_000;
const SAVE_DELAY_MS = 400;

const managerNotifications = (): AppNotification[] => [
  {
    id: "n1",
    kind: "nouvelle_demande",
    submission_id: "n1",
    message: "Nouvelle demande de Gontran Martin (Product) (fictif)",
    created_at: new Date(Date.now() - 5 * MINUTE_MS).toISOString(),
    read_at: null,
  },
];

const STATES: {
  value: string;
  label: string;
  role: AppRole;
  name: string;
  failing?: boolean;
  note: string;
}[] = [
  {
    value: "manager",
    label: "Manager",
    role: "manager",
    name: "Kesha",
    note: "Ouvre la cloche, puis « Préférences » : deux lignes, toutes les cases cochées par défaut. Chaque clic s'enregistre et le confirme en bas de la fenêtre.",
  },
  {
    value: "collaborateur",
    label: "Collaborateur",
    role: "collaborateur",
    name: "Gontran",
    note: "Un collaborateur ne voit que « Résumé hebdomadaire », avec la seule case « Par mail ».",
  },
  {
    value: "admin",
    label: "Admin (aucune ligne)",
    role: "admin",
    name: "Admin",
    note: "Avant l'US16, aucune ligne n'est ouverte à un admin : la fenêtre affiche un message à la place.",
  },
  {
    value: "erreur",
    label: "Erreur d'enregistrement",
    role: "manager",
    name: "Kesha",
    failing: true,
    note: "Chaque clic échoue : la case revient à son état précédent et un message s'affiche sous la ligne.",
  },
];

// ---------------------------------------------------------------------------
// Présentation
// ---------------------------------------------------------------------------

function Us13Mockup() {
  const [stateValue, setStateValue] = useState(STATES[0].value);
  const [values, setValues] = useState<PreferenceValues>({});
  const state = STATES.find((s) => s.value === stateValue) ?? STATES[0];

  function changeState(value: string) {
    setStateValue(value);
    setValues({});
  }

  async function savePreference(
    kind: PreferenceKind,
    channel: NotificationChannel,
    checked: boolean,
  ) {
    await new Promise((resolve) => setTimeout(resolve, SAVE_DELAY_MS));
    if (state.failing) throw new Error("Échec simulé (fictif).");
    setValues((v) => ({ ...v, [kind]: { ...(v[kind] ?? DEFAULT_CHANNELS), [channel]: checked } }));
  }

  return (
    <div className="bg-background text-on-surface font-body-md min-h-screen flex flex-col">
      <BrandHeader>
        <OverviewHeader
          isAdmin={state.role === "admin"}
          name={`${state.name} (fictif)`}
          role={state.role}
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
              notifications={state.role === "manager" ? managerNotifications() : []}
              onMarkRead={() => {}}
              onMarkAllRead={() => {}}
              loadSubmission={async () => null}
              preferences={{
                kinds: notificationKindsFor(state.role),
                values,
                onChange: savePreference,
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
            Bonjour {state.name} (fictif)
          </h1>
          <p className="font-body-md text-body-md text-on-surface-variant">
            Voici ce qui demande ton attention aujourd'hui.
          </p>
        </div>
      </main>
    </div>
  );
}
