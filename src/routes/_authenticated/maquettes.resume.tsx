import { createFileRoute } from "@tanstack/react-router";
import { useState } from "react";
import { BrandHeader } from "@/components/brand-header";
import { WeeklyDigestCard, type DigestStep } from "@/components/digest/WeeklyDigestCard";
import { DS_INPUT, DsField, DsSection } from "@/components/ds";
import { nextDigestLabel, type DigestSendResult, type LastDigest } from "@/lib/weekly-digest";

export const Route = createFileRoute("/_authenticated/maquettes/resume")({
  head: () => ({
    meta: [{ title: "Happy Place · Maquette du résumé hebdomadaire" }],
  }),
  component: DigestMockup,
});

// ---------------------------------------------------------------------------
// Données factices (fictif). Aucun appel à la base ni à Make.
// ---------------------------------------------------------------------------

const DELAY_MS = 800;
const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));
const BASE = "https://happy-place-louis.guecheff-louis.workers.dev";

const LAST_SCHEDULED: LastDigest = {
  created_at: "2026-11-02T07:00:00Z",
  mode: "planifié",
  recipients_count: 14,
  status: "transmis",
  sent_by_name: null,
};

type State = {
  value: string;
  label: string;
  note: string;
  last: LastDigest | null;
  count: number;
  initialStep?: DigestStep;
  /** Ce que renvoie l'envoi simulé ; une chaîne simule une erreur de la base. */
  outcome: DigestSendResult | string | "never";
};

const STATES: State[] = [
  {
    value: "jamais",
    label: "Jamais envoyé",
    note: "Aucun résumé n'a encore été envoyé. Clique sur « Envoyer le résumé maintenant » pour voir la confirmation.",
    last: null,
    count: 14,
    outcome: { recipients: 14, transmitted: true },
  },
  {
    value: "reussi",
    label: "Dernier envoi réussi",
    note: "Le résumé planifié de lundi est parti. Après un envoi, le bouton reste désactivé une minute.",
    last: LAST_SCHEDULED,
    count: 14,
    initialStep: { kind: "done", result: { recipients: 14, transmitted: true } },
    outcome: { recipients: 14, transmitted: true },
  },
  {
    value: "confirmation",
    label: "Confirmation",
    note: "La confirmation s'ouvre dans la carte, sans fenêtre du navigateur. Le nombre vient d'une fonction de comptage. Le focus passe sur la question ; « Annuler » le rend au bouton.",
    last: LAST_SCHEDULED,
    count: 14,
    initialStep: { kind: "confirm", count: 14 },
    outcome: { recipients: 14, transmitted: true },
  },
  {
    value: "en-cours",
    label: "Envoi en cours",
    note: "Les deux boutons sont désactivés pendant l'envoi ; « Envoi en cours… » est annoncé.",
    last: LAST_SCHEDULED,
    count: 14,
    initialStep: { kind: "sending", count: 14 },
    outcome: "never",
  },
  {
    value: "aucun",
    label: "Aucun destinataire",
    note: "Personne n'a d'adresse avec le résumé coché : la confirmation le dit, et l'envoi est seulement enregistré (0 personne, rien de transmis).",
    last: LAST_SCHEDULED,
    count: 0,
    initialStep: { kind: "confirm", count: 0 },
    outcome: { recipients: 0, transmitted: false },
  },
  {
    value: "webhook-absent",
    label: "Webhook absent (à valider)",
    note: "État ajouté, à valider : le secret Vault manque, la ligne reste « en attente ». Le message ne dit pas « envoyé ».",
    last: {
      ...LAST_SCHEDULED,
      created_at: "2026-11-05T14:12:00Z",
      mode: "manuel",
      sent_by_name: "Olivia (fictif)",
      status: "en attente",
    },
    count: 14,
    initialStep: { kind: "done", result: { recipients: 14, transmitted: false } },
    outcome: { recipients: 14, transmitted: false },
  },
  {
    value: "erreur",
    label: "Erreur",
    note: "La base a refusé l'envoi. Le message d'erreur s'affiche sous le bouton, qui reste actif pour réessayer.",
    last: LAST_SCHEDULED,
    count: 14,
    initialStep: {
      kind: "error",
      message: "Le résumé n'a pas pu être envoyé. Réessaie dans quelques minutes.",
    },
    outcome: "Le résumé n'a pas pu être envoyé. Réessaie dans quelques minutes.",
  },
];

/** Ce qui partirait à Make pour un envoi manuel le jeudi 5 novembre 2026 (fictif, 2 destinataires sur 14). */
const PAYLOAD = {
  digest_id: "3f1c0e7a-fictif",
  mode: "manuel",
  period_from: "2026-10-29T14:12:00+01:00",
  period_to: "2026-11-05T14:12:00+01:00",
  period_label: "du 29 octobre au 5 novembre 2026",
  week_number: 45,
  app_url: BASE,
  preferences_url: `${BASE}/?preferences`,
  global: {
    stats: {
      news_published: 5,
      submissions_created: 9,
      submissions_processed: 6,
      submissions_pending_over_7_days: 2,
      blockers_open: 4,
      blockers_critical_open: 1,
    },
    company_news: [
      {
        id: "a1-fictif",
        title: "Nouveaux horaires de l'accueil (fictif)",
        excerpt: "À partir du 9 novembre, l'accueil ouvre à 8 h 30 et ferme à 18 h (fictif).",
        author: "Olivia (fictif)",
        published_at: "2026-11-03T09:40:00+01:00",
        url: `${BASE}/?actu=a1-fictif`,
      },
    ],
    validated_submissions: [
      {
        id: "d1-fictif",
        excerpt: "Ajouter un créneau de réservation des salles le vendredi après-midi (fictif).",
        team: "Product",
        author_name: "Gontran Martin (fictif)",
        url: `${BASE}/?demande=d1-fictif`,
      },
    ],
    open_blockers: [
      {
        id: "p1-fictif",
        title: "Accès au nouvel outil de planning en attente (fictif)",
        severity: "critical",
        status: "EN COURS",
        teams: ["Product", "Data"],
        days_without_update: 6,
        url: `${BASE}/?point=p1-fictif`,
      },
    ],
    company_news_html:
      '<p style="margin:0 0 12px;color:#2b2a30"><a href="…/?actu=a1-fictif" style="font-family:Georgia,serif;color:#2b2a30">Nouveaux horaires de l&#39;accueil (fictif)</a><br>À partir du 9 novembre… (fictif)</p>',
    open_blockers_html:
      '<p style="margin:0 0 12px;color:#2b2a30"><a href="…/?point=p1-fictif" style="font-family:Georgia,serif;color:#2b2a30">Accès au nouvel outil de planning en attente (fictif)</a><br>Critique · En cours · Product, Data · sans mise à jour depuis 6 jours</p>',
  },
  recipients: [
    {
      to_address: "kesha.durand@exemple.fr",
      to_name: "Kesha (fictif)",
      role: "manager",
      teams: ["Product"],
      team_news: [
        {
          id: "a2-fictif",
          title: "Rétro de sprint déplacée à jeudi (fictif)",
          excerpt: "La rétro du sprint 14 aura lieu jeudi à 15 h, salle Lovelace (fictif).",
          author: "Kesha (fictif)",
          published_at: "2026-11-02T11:05:00+01:00",
          url: `${BASE}/?actu=a2-fictif`,
        },
      ],
      my_submissions: [],
      pending_in_my_teams: [
        {
          id: "d2-fictif",
          excerpt: "Prévoir un écran de plus en salle Hopper (fictif).",
          author_name: "Gontran Martin (fictif)",
          created_at: "2026-10-26T10:00:00+01:00",
          url: `${BASE}/?demande=d2-fictif`,
        },
      ],
      news_this_month: 1,
      team_news_html:
        '<p style="margin:0 0 12px;color:#2b2a30"><a href="…/?actu=a2-fictif" style="font-family:Georgia,serif;color:#2b2a30">Rétro de sprint déplacée à jeudi (fictif)</a><br>La rétro du sprint 14… (fictif)</p>',
      my_submissions_html: "",
    },
    {
      to_address: "gontran.martin@exemple.fr",
      to_name: "Gontran (fictif)",
      role: "collaborateur",
      teams: ["Product"],
      team_news: [],
      my_submissions: [
        {
          id: "d1-fictif",
          excerpt: "Ajouter un créneau de réservation des salles le vendredi après-midi (fictif).",
          new_status: "validée",
          changed_at: "2026-11-04T16:20:00+01:00",
          url: `${BASE}/?demande=d1-fictif`,
        },
      ],
      team_news_html: "",
      my_submissions_html:
        '<p style="margin:0 0 12px;color:#2b2a30"><a href="…/?demande=d1-fictif" style="font-family:Georgia,serif;color:#2b2a30">Ajouter un créneau de réservation…</a><br>Validée le 4 novembre (fictif)</p>',
    },
  ],
};

// ---------------------------------------------------------------------------
// Présentation
// ---------------------------------------------------------------------------

function DigestMockup() {
  const [stateValue, setStateValue] = useState(STATES[0].value);
  const [round, setRound] = useState(0);
  const state = STATES.find((s) => s.value === stateValue) ?? STATES[0];

  async function send(): Promise<DigestSendResult> {
    if (state.outcome === "never") return new Promise<DigestSendResult>(() => {});
    await wait(DELAY_MS);
    if (typeof state.outcome === "string") throw new Error(state.outcome);
    return state.outcome;
  }

  return (
    <div className="bg-background text-on-surface font-body-md min-h-screen flex flex-col">
      <BrandHeader />
      <main className="flex-grow w-full max-w-interface mx-auto p-sm md:p-md space-y-md">
        <div className="flex flex-wrap items-end gap-sm border border-dashed border-outline-variant p-sm">
          <DsField id="maquette-etat" label="Maquette (fictif)" className="w-full md:w-72">
            <select
              id="maquette-etat"
              className={DS_INPUT}
              value={state.value}
              onChange={(e) => {
                setStateValue(e.target.value);
                setRound((r) => r + 1);
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
            Maquette (fictif), vue Olivia (admin) : {state.note}
          </p>
        </div>

        <div className="space-y-xs">
          <p className="font-label-md text-label-md text-on-surface-variant">/manage</p>
          <h1 className="font-headline-lg text-headline-lg text-primary">Gestion des données</h1>
          <p className="font-body-sm text-body-sm text-on-surface-variant">
            La carte se place au-dessus des onglets, visible quel que soit l'onglet ouvert (à
            valider).
          </p>
        </div>

        <WeeklyDigestCard
          key={round}
          nextLabel={nextDigestLabel()}
          last={state.last}
          initialStep={state.initialStep}
          loadCount={async () => {
            await wait(DELAY_MS / 2);
            return state.count;
          }}
          send={send}
        />

        <DsSection id="apercu-json" title="JSON envoyé à Make (fictif)">
          <p className="font-body-sm text-body-sm text-on-surface-variant">
            Un seul appel par envoi : Make rédige l'insight une fois à partir de « global », puis
            envoie un mail par entrée de « recipients ». Aperçu réservé à la maquette.
          </p>
          <pre
            tabIndex={0}
            aria-label="JSON envoyé à Make (fictif)"
            className="max-h-[32rem] overflow-auto border border-outline-variant bg-surface-container p-sm font-body-sm text-body-sm text-on-surface whitespace-pre"
          >
            {JSON.stringify(PAYLOAD, null, 2)}
          </pre>
        </DsSection>
      </main>
    </div>
  );
}
