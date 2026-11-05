import { createFileRoute } from "@tanstack/react-router";
import { useState } from "react";
import { toast } from "sonner";
import { BlockerReader } from "@/components/blocker-reader";
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
import { ReaderDialog } from "@/components/reader-dialog";
import { GlobalSearch } from "@/components/search/GlobalSearch";
import { SubmissionReader } from "@/components/submission-reader";
import type { Blocker, Submission } from "@/lib/dashboard";

export const Route = createFileRoute("/_authenticated/maquettes/mails")({
  head: () => ({
    meta: [{ title: "Happy Place · Maquette du socle d'envoi des mails" }],
  }),
  component: MailsMockup,
});

// ---------------------------------------------------------------------------
// Données factices (fictif). Aucun appel à la base ni à Make.
// ---------------------------------------------------------------------------

const HOUR_MS = 3_600_000;
const DAY_MS = 24 * HOUR_MS;
const SAVE_DELAY_MS = 500;
const ago = (ms: number) => new Date(Date.now() - ms).toISOString();

/** Même règle que la contrainte prévue en base (phase 2) : une forme simple, sans espace. */
const ADDRESS_FORMAT = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const INVALID_ADDRESS =
  "Cette adresse n'est pas valide. Vérifie qu'elle a la forme prenom.nom@exemple.fr.";

const SUBMISSION: Submission = {
  id: "d-fictive",
  author_name: "Gontran Martin (fictif)",
  team: "Product",
  content:
    "Peut-on ajouter un créneau de réservation des salles le vendredi après-midi ? Le planning actuel s'arrête à 14 h et on doit souvent se rabattre sur la cafétéria pour les rétros (fictif).",
  status: "en attente",
  created_at: ago(2 * HOUR_MS),
  submitted_by_email: "gontran@fictif.test",
  attachment_name: null,
  attachment_path: null,
};

const BLOCKER: Blocker = {
  id: "p-fictif",
  title: "Accès au nouvel outil de planning en attente (fictif)",
  description: "Les comptes de l'équipe Product ne sont pas encore créés (fictif).",
  teams: ["Product"],
  severity: "warning",
  status: "EN COURS",
  created_at: ago(15 * DAY_MS),
  updated_at: ago(6 * DAY_MS),
  updated_by_name: "Admin (fictif)",
  reminded_at: ago(HOUR_MS),
  reminded_by_name: "Sam (fictif)",
  impact: "Continue à réserver tes salles dans l'ancien outil en attendant (fictif).",
};

type Unavailable = { title: string; text: string };

type State = {
  value: string;
  label: string;
  note: string;
  /** Adresse simulée dans la barre du navigateur. */
  url: string;
  preferences?: { saved: string; draft?: string };
  submission?: Submission;
  blocker?: Blocker;
  unavailable?: Unavailable;
};

const STATES: State[] = [
  {
    value: "sans-adresse",
    label: "Préférences sans adresse",
    note: "Le champ est vide par défaut, sous les lignes existantes. Sans adresse, aucun mail n'est préparé, même avec « Par mail » coché. Saisis une adresse et clique sur « Enregistrer l'adresse ».",
    url: "/?preferences",
    preferences: { saved: "" },
  },
  {
    value: "avec-adresse",
    label: "Préférences avec adresse",
    note: "L'adresse est enregistrée. Vide le champ et enregistre pour la retirer : un toast le confirme.",
    url: "/?preferences",
    preferences: { saved: "kesha.durand@exemple.fr" },
  },
  {
    value: "adresse-invalide",
    label: "Adresse invalide",
    note: "Clique sur « Enregistrer l'adresse » : la base refuse le format, l'erreur s'affiche sous le champ et le champ garde ta saisie.",
    url: "/?preferences",
    preferences: { saved: "", draft: "kesha.durand@exemple" },
  },
  {
    value: "lien-demande",
    label: "Lien vers une demande",
    note: "Le bouton du mail ouvre la vue d'accueil avec la demande. Après fermeture, le paramètre disparaît de l'adresse.",
    url: `/?demande=${SUBMISSION.id}`,
    submission: SUBMISSION,
  },
  {
    value: "lien-demande-supprimee",
    label: "Lien vers une demande supprimée",
    note: "La demande a été supprimée ou n'est plus lisible pour toi : la fenêtre reprend le message de la cloche.",
    url: "/?demande=d-supprimee",
    unavailable: { title: "Demande indisponible", text: "Cette demande n'est plus disponible." },
  },
  {
    value: "lien-point",
    label: "Lien vers un point bloquant",
    note: "Le mail de relance ouvre la fenêtre de lecture du point bloquant.",
    url: `/?point=${BLOCKER.id}`,
    blocker: BLOCKER,
  },
  {
    value: "autre-navigateur",
    label: "Lien ouvert dans un autre navigateur (proposition)",
    note: "Proposition, à valider : la session y est différente, et la base ne distingue pas une demande supprimée d'une demande invisible pour ce compte. Le message couvre donc les deux cas.",
    url: `/?demande=${SUBMISSION.id}`,
    unavailable: {
      title: "Demande indisponible",
      text: "Cette demande n'est plus disponible, ou tu ne peux pas la voir depuis ce navigateur. Si tu as reçu le lien par mail, ouvre-le dans le navigateur où tu utilises Happy Place d'habitude.",
    },
  },
];

// ---------------------------------------------------------------------------
// Présentation
// ---------------------------------------------------------------------------

function MailsMockup() {
  const [stateValue, setStateValue] = useState(STATES[0].value);
  const [round, setRound] = useState(0);
  const state = STATES.find((s) => s.value === stateValue) ?? STATES[0];
  const [values, setValues] = useState<PreferenceValues>({});
  const [address, setAddress] = useState(state.preferences?.saved ?? "");
  const [url, setUrl] = useState(state.url);
  const [preferencesOpen, setPreferencesOpen] = useState(!!state.preferences);
  const [reading, setReading] = useState<Submission | null>(state.submission ?? null);
  const [blocker, setBlocker] = useState<Blocker | null>(state.blocker ?? null);
  const [unavailable, setUnavailable] = useState<Unavailable | null>(state.unavailable ?? null);

  function changeState(value: string) {
    const next = STATES.find((s) => s.value === value) ?? STATES[0];
    toast.dismiss();
    setStateValue(next.value);
    setAddress(next.preferences?.saved ?? "");
    setUrl(next.url);
    setPreferencesOpen(!!next.preferences);
    setReading(next.submission ?? null);
    setBlocker(next.blocker ?? null);
    setUnavailable(next.unavailable ?? null);
    setRound((r) => r + 1);
  }

  /** Fermer la fenêtre ouverte par le lien retire le paramètre de l'adresse. */
  const closeLink = () => setUrl("/");

  async function savePreference(
    kind: PreferenceKind,
    channel: NotificationChannel,
    checked: boolean,
  ) {
    await new Promise((resolve) => setTimeout(resolve, SAVE_DELAY_MS));
    setValues((v) => ({ ...v, [kind]: { ...(v[kind] ?? DEFAULT_CHANNELS), [channel]: checked } }));
  }

  async function saveAddress(next: string) {
    await new Promise((resolve) => setTimeout(resolve, SAVE_DELAY_MS));
    if (next && !ADDRESS_FORMAT.test(next)) throw new Error(INVALID_ADDRESS);
    setAddress(next.toLowerCase());
  }

  return (
    <div className="bg-background text-on-surface font-body-md min-h-screen flex flex-col">
      <BrandHeader>
        <OverviewHeader
          key={round}
          isAdmin={false}
          name="Kesha (fictif)"
          role="manager"
          exporting={false}
          onExport={() => toast.info("Non branché dans la maquette (fictif).")}
          preferences={{
            kinds: notificationKindsFor("manager"),
            values,
            onChange: savePreference,
            address: {
              value: address,
              onSave: saveAddress,
              initialDraft: state.preferences?.draft,
            },
          }}
          preferencesOpen={preferencesOpen}
          onPreferencesOpenChange={(open) => {
            setPreferencesOpen(open);
            if (!open) closeLink();
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
              notifications={[]}
              onMarkRead={() => {}}
              onMarkAllRead={() => {}}
              loadSubmission={async () => null}
              onOpenSubmission={() => {}}
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
          <div className="min-w-0 flex-1 basis-64 space-y-xs">
            <p className="font-body-sm text-body-sm text-on-surface">
              Maquette (fictif) : {state.note}
            </p>
            <p role="status" className="font-label-md text-label-md text-on-surface-variant">
              Adresse simulée : <span className="wrap-anywhere text-on-surface">{url}</span>
            </p>
          </div>
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
      <SubmissionReader
        key={`demande-${round}`}
        submission={reading}
        onClose={() => {
          setReading(null);
          closeLink();
        }}
        statusActions={[
          { label: "Valider", onClick: () => toast.info("Non branché dans la maquette (fictif).") },
          {
            label: "Clôturer",
            onClick: () => toast.info("Non branché dans la maquette (fictif)."),
          },
        ]}
        onReject={() => toast.info("Non branché dans la maquette (fictif).")}
      />
      <BlockerReader
        blocker={blocker}
        onClose={() => {
          setBlocker(null);
          closeLink();
        }}
      />
      {unavailable && (
        <ReaderDialog
          title={unavailable.title}
          subtitle="Lien reçu par mail"
          onClose={() => {
            setUnavailable(null);
            closeLink();
          }}
        >
          <p className="font-body-md text-body-md text-on-surface">{unavailable.text}</p>
        </ReaderDialog>
      )}
    </div>
  );
}
