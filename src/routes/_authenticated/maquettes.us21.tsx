import { createFileRoute } from "@tanstack/react-router";
import { useRef, useState } from "react";
import { toast } from "sonner";
import { BlockerReader } from "@/components/blocker-reader";
import { BrandHeader } from "@/components/brand-header";
import {
  DS_INPUT,
  DsBadge,
  DsButton,
  DsField,
  DsFreshness,
  DsListItem,
  DsSection,
  DsStaleBadge,
} from "@/components/ds";
import { BlockersSection, type OpenBlocker } from "@/components/overview/BlockersSection";
import { KpiSection, VerifyMetricButton } from "@/components/overview/KpiSection";
import { OverviewHeader } from "@/components/overview/OverviewHeader";
import {
  formatDay,
  hasMetricThresholds,
  isVerified,
  metricAlert,
  metricRangeLabel,
} from "@/components/overview/overview-utils";
import { GlobalSearch } from "@/components/search/GlobalSearch";
import {
  StatusChip,
  SubmissionThreadView,
  SubmissionUpToDate,
  verificationStep,
  type ThreadStep,
} from "@/components/submission-status-thread";
import { formatMetricValue, type Blocker, type Metric, type Submission } from "@/lib/dashboard";

export const Route = createFileRoute("/_authenticated/maquettes/us21")({
  head: () => ({
    meta: [{ title: "Happy Place · Maquette du signal à vérifier" }],
  }),
  component: Us21Mockup,
});

// ---------------------------------------------------------------------------
// Données factices (fictif) : les sections et les fenêtres sont les vrais composants.
// ---------------------------------------------------------------------------

const HOUR_MS = 60 * 60_000;
const DAY_MS = 24 * HOUR_MS;
const ago = (ms: number) => new Date(Date.now() - ms).toISOString();

const OLIVIA = "Olivia Laurent (fictif)";

type Viewer = {
  name: string;
  role: "collaborateur" | "manager" | "admin";
  teams: string[];
};
const GONTRAN: Viewer = { name: "Gontran (fictif)", role: "collaborateur", teams: ["Data"] };
const KESHA: Viewer = { name: "Kesha (fictif)", role: "manager", teams: ["Data", "Product"] };
const ADMIN: Viewer = { name: OLIVIA, role: "admin", teams: [] };

const BLOCKERS: Blocker[] = [
  {
    id: "b1",
    title: "Signature des contrats freelance bloquée (fictif)",
    description:
      "Le service juridique attend la nouvelle trame de contrat : trois missions ne peuvent pas démarrer (fictif).",
    teams: [],
    severity: "critical",
    status: "OUVERT",
    created_at: ago(12 * DAY_MS),
    updated_at: ago(5 * DAY_MS),
    updated_by_name: OLIVIA,
    impact: "Attends le feu vert avant de confirmer une date de démarrage (fictif).",
  },
  {
    id: "b2",
    title: "Accès au nouvel ATS en attente (fictif)",
    description: "Les comptes des recruteurs ne sont pas encore créés (fictif).",
    teams: ["Data", "Opérations", "Product"],
    severity: "warning",
    status: "EN COURS",
    created_at: ago(20 * DAY_MS),
    updated_at: ago(4 * DAY_MS + 2 * HOUR_MS),
    updated_by_name: OLIVIA,
    impact: null,
  },
  {
    id: "b3",
    title: "Parcours d'accueil des nouveaux arrivants à revoir (fictif)",
    description: null,
    teams: ["Data"],
    severity: "info",
    status: "SURVEILLANCE",
    created_at: ago(30 * DAY_MS),
    updated_at: ago(DAY_MS + 3 * HOUR_MS),
    updated_by_name: OLIVIA,
    impact: null,
  },
  {
    id: "b4",
    title: "Planning des astreintes non publié (fictif)",
    description: "L'équipe Opérations attend la validation du planning de décembre (fictif).",
    teams: ["Opérations"],
    severity: "warning",
    status: "OUVERT",
    created_at: ago(9 * DAY_MS),
    updated_at: ago(6 * DAY_MS),
    updated_by_name: OLIVIA,
    impact: null,
  },
];

const METRIC_TEXTS = {
  training_kpi: {
    definition: "Part des candidats placés en mission sur 30 jours (fictif).",
    impact: "S'il baisse, l'effort va aux candidats sans mission (fictif).",
  },
  active_users: {
    definition: "Missions en cours aujourd'hui (fictif).",
    impact: "Il montre la charge de suivi des managers (fictif).",
  },
  nps: {
    definition: "Note de recommandation des candidats, de −100 à +100 (fictif).",
    impact: "Il dit si les candidats recommandent Happy Place (fictif).",
  },
};

/**
 * `outDays` : depuis combien de jours « Missions actives » est sous son minimum (150) ; le seuil
 * de durée est de 7 jours.
 */
function metrics(outDays: number): Metric[] {
  return [
    {
      key: "training_kpi",
      label: "Taux de placement",
      value: 78.4,
      unit: "%",
      trend: "hausse",
      previous_value: 76.3,
      delta: 2.1,
      updated_at: ago(2 * DAY_MS),
      updated_by_name: OLIVIA,
      threshold_min: 60,
      threshold_max: 90,
      stale_after_days: 7,
      out_of_range_since: null,
      ...METRIC_TEXTS.training_kpi,
    },
    {
      key: "active_users",
      label: "Missions actives",
      value: 142,
      unit: null,
      trend: "baisse",
      previous_value: 150,
      delta: -8,
      updated_at: ago(12 * HOUR_MS),
      updated_by_name: "Automatique",
      threshold_min: 150,
      threshold_max: null,
      stale_after_days: 7,
      out_of_range_since: ago(outDays * DAY_MS),
      ...METRIC_TEXTS.active_users,
    },
    {
      key: "nps",
      label: "NPS candidats",
      value: 41,
      unit: null,
      trend: "stable",
      previous_value: 41,
      delta: 0,
      updated_at: ago(20 * DAY_MS),
      updated_by_name: OLIVIA,
      // KPI créé avant l'US21 : sans seuil, jamais de badge.
      threshold_min: null,
      threshold_max: null,
      stale_after_days: null,
      ...METRIC_TEXTS.nps,
    },
  ];
}

/** Demandes de Gontran : `pending_since` = dernier changement de statut (clôture automatique pour s1). */
const SUBMISSIONS: Submission[] = [
  {
    id: "s1",
    author_name: "Gontran (fictif)",
    team: "Data",
    content: "Partager le tableau de suivi des candidats avec l'équipe Opérations (fictif).",
    status: "clôturée",
    created_at: ago(800 * DAY_MS),
    pending_since: ago(400 * DAY_MS),
  },
  {
    id: "s2",
    author_name: "Gontran (fictif)",
    team: "Data",
    content: "Ajouter un rappel automatique avant chaque fin de mission (fictif).",
    status: "validée",
    created_at: ago(220 * DAY_MS),
    pending_since: ago(200 * DAY_MS),
  },
  {
    id: "s3",
    author_name: "Gontran (fictif)",
    team: "Data",
    content: "Regrouper les relances clients en un seul rappel hebdomadaire (fictif).",
    status: "en attente",
    created_at: ago(500 * DAY_MS),
  },
];

function steps(s: Submission): ThreadStep[] {
  const base = {
    changed_by_email: null,
    is_automatic: false,
    rejection_category: null,
    rejection_note: null,
  };
  const rows: ThreadStep[] = [
    {
      ...base,
      id: `${s.id}-0`,
      old_status: null,
      new_status: "en attente",
      changed_by_name: s.author_name,
      changed_at: s.created_at,
    },
  ];
  if (s.pending_since) {
    rows.push({
      ...base,
      id: `${s.id}-1`,
      old_status: "en attente",
      new_status: s.status,
      changed_by_name: s.status === "clôturée" ? null : KESHA.name,
      is_automatic: s.status === "clôturée",
      changed_at: s.pending_since,
    });
  }
  if (s.verified_at) {
    rows.push(
      verificationStep(
        { id: `${s.id}-v`, verified_by_name: GONTRAN.name, verified_at: s.verified_at },
        s.status,
      ),
    );
  }
  return rows.reverse();
}

type MockState = {
  value: string;
  label: string;
  note: string;
  viewer: Viewer;
  /** Jours sous le minimum pour « Missions actives » (voir `metrics`). */
  activeDays: number;
  /** Relances déjà faites à l'ouverture de l'état : id du point → auteur. */
  reminded?: Record<string, string>;
  /** KPI ou demandes déjà vérifiés à l'ouverture de l'état. */
  verified?: string[];
  /** Ce que montre la page : vue d'ensemble, Mes demandes, ou aperçu des seuils d'un KPI. */
  page?: "overview" | "requests" | "manage";
  /** Aperçu de la notification de relance reçue. */
  notification?: boolean;
};

const STATES: MockState[] = [
  {
    value: "point-collaborateur",
    label: "Point à vérifier (vue collaborateur)",
    note: "Vue de Gontran. Tout point non résolu sans mise à jour depuis plus de 3 jours porte « À vérifier », quelle que soit sa sévérité. Survole le badge, ou atteins-le avec Tab. Gontran ne change aucun statut et ne relance personne.",
    viewer: GONTRAN,
    activeDays: 3,
  },
  {
    value: "point-manager",
    label: "Point à vérifier (vue manager)",
    note: "Vue de Kesha (Data, Product). Elle change le statut des points qui la concernent : ses équipes et « Toutes les équipes ». « Relancer équipes » n'apparaît que sur le point des Opérations, qui ne la concerne pas. Essaie le bouton, ou change un statut : le badge disparaît.",
    viewer: KESHA,
    activeDays: 3,
  },
  {
    value: "point-admin",
    label: "Point à vérifier (vue admin)",
    note: "Vue d'Olivia (admin) : statut modifiable et « Relancer équipes » sur tous les points à vérifier. Point « Toutes les équipes » : seuls les managers sont relancés. Autres points : collaborateurs et managers des équipes du point. Une seule relance tant que le point n'a pas été modifié.",
    viewer: ADMIN,
    activeDays: 3,
  },
  {
    value: "relance-recue",
    label: "Relance reçue (vue collaborateur)",
    note: "Olivia a relancé les équipes du point ATS. Gontran (Data) reçoit la notification dans sa cloche, sans bouton ; un clic ouvre la fenêtre de lecture du point. La ligne affiche « Relancé le … par Olivia » pour tout le monde, jusqu'à la prochaine modification du point.",
    viewer: GONTRAN,
    activeDays: 3,
    reminded: { b2: OLIVIA },
    notification: true,
  },
  {
    value: "kpi-recent",
    label: "KPI hors plage depuis peu",
    note: "« Missions actives » (142) est sous son minimum de 150 depuis 3 jours ; son seuil de durée est de 7 jours : pas encore de badge. « Taux de placement » (78,4 %) est dans sa plage de 60 à 90 %. Le NPS n'a pas de seuil.",
    viewer: KESHA,
    activeDays: 3,
  },
  {
    value: "kpi-seuil",
    label: "KPI hors plage depuis trop longtemps",
    note: "« Missions actives » est sous 150 depuis 12 jours, plus que ses 7 jours : badge « À vérifier » et, pour Kesha (tous les KPI), « Marquer comme vérifié ». Survole le badge : « En dessous de 150 depuis 12 jours. Vérifie si c'est un souci ou une bonne nouvelle. ». Pas de couleur rouge ni verte : l'app ne sait pas si c'est bon ou mauvais.",
    viewer: KESHA,
    activeDays: 12,
  },
  {
    value: "kpi-verifie",
    label: "KPI vérifié",
    note: "Kesha a vérifié « Missions actives » : le badge disparaît et le compteur repart de la vérification. S'il reste sous 150 pendant 7 jours de plus, le badge revient. La mention devient « Vérifié il y a 2 minutes par Kesha » ; valeur et tendance ne changent pas.",
    viewer: KESHA,
    activeDays: 12,
    verified: ["active_users"],
  },
  {
    value: "kpi-seuils",
    label: "Seuils d'un KPI (Gérer les données)",
    note: "Aperçu de « Gérer les données > KPI » (admin) : chaque KPI affiche sa plage et sa durée, ou « Seuil à définir ». À la création : un minimum, un maximum, ou les deux, et une durée de 1 à 365 jours. Essaie d'enregistrer le formulaire vide, ou avec un minimum plus grand que le maximum.",
    viewer: ADMIN,
    activeDays: 12,
    page: "manage",
  },
  {
    value: "demande-ancienne",
    label: "Demande de plus d'un an (détail)",
    note: "Mes demandes de Gontran : chaque ligne s'ouvre sur « Détail de la demande ». Aucun badge dans la liste. Dans le détail, une demande clôturée sans mise à jour depuis plus d'un an porte « À vérifier » et le bouton « Confirmer à jour ». Ni la demande validée, ni celle en attente depuis 500 jours ne sont concernées.",
    viewer: GONTRAN,
    activeDays: 3,
    page: "requests",
  },
  {
    value: "demande-verifiee",
    label: "Demande vérifiée",
    note: "Gontran a confirmé sa demande clôturée : le badge disparaît, la mention devient « Vérifié … par Gontran » et le fil gagne une ligne « Vérifiée à jour ». Personne n'est notifié.",
    viewer: GONTRAN,
    activeDays: 3,
    page: "requests",
    verified: ["s1"],
  },
];

// ---------------------------------------------------------------------------
// Aperçu des seuils dans « Gérer les données > KPI » (admin)
// ---------------------------------------------------------------------------

type ThresholdForm = { min: string; max: string; days: string };

/** Mêmes règles que la base prévue en phase 2 : une borne au moins, min < max, 1 à 365 jours. */
function thresholdErrors({ min, max, days }: ThresholdForm) {
  const num = (t: string) => (t.trim() === "" ? null : Number(t.replace(",", ".")));
  const lo = num(min);
  const hi = num(max);
  const d = num(days);
  const errors: Partial<Record<keyof ThresholdForm, string>> = {};
  if (lo == null && hi == null) errors.min = "Indique un minimum, un maximum, ou les deux.";
  else if (lo != null && hi != null && lo >= hi)
    errors.max = "Le maximum doit être plus grand que le minimum.";
  if (lo != null && Number.isNaN(lo)) errors.min = "Indique un nombre.";
  if (hi != null && Number.isNaN(hi)) errors.max = "Indique un nombre.";
  if (d == null || !Number.isInteger(d) || d < 1 || d > 365)
    errors.days = "Indique un nombre entier de jours, de 1 à 365.";
  return errors;
}

function ManageThresholdsPreview({
  rows,
  onVerify,
}: {
  rows: Metric[];
  onVerify: (m: Metric) => void;
}) {
  const [form, setForm] = useState<ThresholdForm>({ min: "", max: "", days: "" });
  const [submitted, setSubmitted] = useState(false);
  const errors = submitted ? thresholdErrors(form) : {};
  const field = (key: keyof ThresholdForm, label: string, hint: string) => (
    <DsField id={`kpi-${key}`} label={label} error={errors[key]} className="flex-1 basis-40">
      <input
        id={`kpi-${key}`}
        inputMode="decimal"
        aria-invalid={!!errors[key]}
        aria-describedby={`kpi-${key}-aide`}
        className={DS_INPUT}
        value={form[key]}
        onChange={(e) => setForm({ ...form, [key]: e.target.value })}
      />
      <p
        id={`kpi-${key}-aide`}
        className="font-label-md text-label-md normal-case tracking-normal text-on-surface-variant"
      >
        {hint}
      </p>
    </DsField>
  );
  return (
    <>
      <DsSection id="gerer-kpi" title="Gérer les données > KPI (aperçu, vue admin)">
        <div className="space-y-xs">
          {rows.map((m) => {
            const alert = metricAlert(m);
            const days = m.stale_after_days ?? 0;
            return (
              <DsListItem
                key={m.key}
                icon="monitoring"
                title={`${m.label} — ${formatMetricValue(m.value, m.unit)}`}
                meta={`${m.key} (fictif)`}
                actions={<DsButton onClick={notWired}>Modifier</DsButton>}
              >
                <span className="flex flex-wrap items-center gap-xs">
                  {hasMetricThresholds(m) ? (
                    <DsBadge>
                      Plage : {metricRangeLabel(m)} · plus de {days} jour{days > 1 ? "s" : ""} hors
                      plage
                    </DsBadge>
                  ) : (
                    <DsBadge icon="edit_calendar">Seuil à définir</DsBadge>
                  )}
                  {alert && <DsStaleBadge days={alert.days} text={alert.text} />}
                  <DsFreshness at={m.updated_at} by={m.updated_by_name} verified={isVerified(m)} />
                </span>
                {alert && <VerifyMetricButton onVerify={() => onVerify(m)} />}
              </DsListItem>
            );
          })}
        </div>
      </DsSection>
      <DsSection id="nouveau-kpi" title="Nouvel indicateur (extrait du formulaire)">
        <form
          className="space-y-sm"
          noValidate
          onSubmit={(e) => {
            e.preventDefault();
            setSubmitted(true);
            if (Object.keys(thresholdErrors(form)).length === 0)
              toast.success("Seuils valides (fictif).");
          }}
        >
          <div className="flex flex-wrap items-start gap-xs">
            {field("min", "Seuil minimum (optionnel)", "Sous cette valeur, le compteur démarre.")}
            {field("max", "Seuil maximum (optionnel)", "Au-dessus, le compteur démarre aussi.")}
          </div>
          {field(
            "days",
            "Durée hors plage avant « À vérifier » (jours)",
            "Au-delà, le KPI porte le badge et le bouton « Marquer comme vérifié ».",
          )}
          <DsButton type="submit">Vérifier les champs</DsButton>
        </form>
      </DsSection>
    </>
  );
}

/** « Détail de la demande » sur données fictives : mêmes composants que le vrai détail. */
function MockDetail({
  submission: s,
  onConfirm,
  onClose,
}: {
  submission: Submission;
  onConfirm: () => void;
  onClose: () => void;
}) {
  const rows = steps(s);
  const last = rows[0];
  return (
    <SubmissionThreadView
      content={s.content}
      team={s.team}
      steps={rows}
      readOnly={false}
      upToDate={
        <SubmissionUpToDate
          status={s.status}
          updatedAt={last.changed_at}
          verifiedBy={last.kind === "verification" ? last.changed_by_name : undefined}
          onConfirm={onConfirm}
        />
      }
      onClose={onClose}
    />
  );
}

const notWired = () => toast.info("Non branché dans la maquette (fictif).");

/** Le point concerne le lecteur : une de ses équipes, ou toutes les équipes. */
const concerns = (viewer: Viewer, b: Blocker) =>
  b.teams.length === 0 || b.teams.some((t) => viewer.teams.includes(t));

// ---------------------------------------------------------------------------
// Présentation
// ---------------------------------------------------------------------------

function Us21Mockup() {
  const [stateValue, setStateValue] = useState(STATES[0].value);
  const state = STATES.find((s) => s.value === stateValue) ?? STATES[0];
  const viewer = state.viewer;
  const [initialAt] = useState(() => ago(2 * 60_000));
  /** Actions faites dans la maquette, effacées à chaque changement d'état. */
  const [verifiedAt, setVerifiedAt] = useState<Record<string, string>>({});
  const [remindedAt, setRemindedAt] = useState<Record<string, string>>({});
  const [statuses, setStatuses] = useState<Record<string, { status: string; at: string }>>({});
  const [reading, setReading] = useState<Blocker | null>(null);
  const [detail, setDetail] = useState<string | null>(null);
  const trigger = useRef<HTMLElement | null>(null);

  const verified: Record<string, string> = {
    ...Object.fromEntries((state.verified ?? []).map((id) => [id, initialAt])),
    ...verifiedAt,
  };
  const reminders: Record<string, { at: string; by: string }> = {
    ...Object.fromEntries(
      Object.entries(state.reminded ?? {}).map(([id, by]) => [id, { at: ago(DAY_MS), by }]),
    ),
    ...Object.fromEntries(
      Object.entries(remindedAt).map(([id, at]) => [id, { at, by: viewer.name }]),
    ),
  };

  const blockers = BLOCKERS.map((b) => {
    const changed = statuses[b.id];
    const row = changed
      ? { ...b, status: changed.status, updated_at: changed.at, updated_by_name: viewer.name }
      : b;
    const r = reminders[b.id];
    return r ? { ...row, reminded_at: r.at, reminded_by_name: r.by } : row;
  });
  const metricRows = metrics(state.activeDays).map((m) =>
    verified[m.key]
      ? {
          ...m,
          updated_at: verified[m.key],
          updated_by_name: viewer.name,
          verified_at: verified[m.key],
        }
      : m,
  );
  const submissions = SUBMISSIONS.map((s) =>
    verified[s.id] ? { ...s, verified_at: verified[s.id] } : s,
  );
  const readingRow = reading && (blockers.find((b) => b.id === reading.id) ?? null);
  const detailRow = submissions.find((s) => s.id === detail) ?? null;

  const isAdmin = viewer.role === "admin";
  const isManager = viewer.role === "manager";
  const canEdit = (b: Blocker) => isAdmin || (isManager && concerns(viewer, b));
  const canRemind = (b: Blocker) => isAdmin || (isManager && !concerns(viewer, b));

  function verify(id: string) {
    setVerifiedAt((v) => ({ ...v, [id]: new Date().toISOString() }));
    toast.success("Vérifié (fictif).");
  }

  function remind(b: Blocker) {
    setRemindedAt((r) => ({ ...r, [b.id]: new Date().toISOString() }));
    toast.success(
      b.teams.length === 0
        ? "Tous les managers ont été relancés (fictif)."
        : "Les équipes du point ont été relancées (fictif).",
    );
  }

  const open: OpenBlocker = (b, from) => {
    trigger.current = from;
    setReading(b);
  };

  function focusTrigger(event: Event) {
    event.preventDefault();
    trigger.current?.focus();
  }

  const page = state.page ?? "overview";

  return (
    <div className="bg-background text-on-surface font-body-md min-h-screen flex flex-col">
      <BrandHeader>
        <OverviewHeader
          isAdmin={isAdmin}
          name={viewer.name}
          role={viewer.role}
          exporting={false}
          onExport={notWired}
          search={
            <GlobalSearch
              key={state.value}
              source={{
                data: { news: [], submissions: [], blockers, metrics: metricRows },
                isError: false,
                isLoading: false,
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
              onChange={(e) => {
                setStateValue(e.target.value);
                setVerifiedAt({});
                setRemindedAt({});
                setStatuses({});
                setReading(null);
                setDetail(null);
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
        {page === "manage" && (
          <div className="flex max-w-lg flex-col gap-md">
            <ManageThresholdsPreview rows={metricRows} onVerify={(m) => verify(m.key)} />
          </div>
        )}
        {page === "requests" && (
          <div className="flex max-w-lg flex-col gap-md">
            <DsSection id="mes-demandes" title="Mes demandes">
              <div className="space-y-xs">
                {submissions.map((s) => (
                  <DsListItem
                    key={s.id}
                    title={<StatusChip status={s.status} />}
                    meta={`${s.team} · Créée le ${formatDay(s.created_at)}`}
                    opensDialog
                    onClick={() => setDetail(s.id)}
                  >
                    <p className="font-body-sm text-body-sm text-on-surface wrap-anywhere">
                      {s.content}
                    </p>
                  </DsListItem>
                ))}
              </div>
            </DsSection>
          </div>
        )}
        {page === "overview" && (
          <>
            <div className="space-y-xs">
              <h1 className="font-headline-lg text-headline-lg text-primary wrap-anywhere">
                Bonjour {viewer.name}
              </h1>
              <p className="font-body-md text-body-md text-on-surface-variant">
                Voici ce qui demande ton attention aujourd'hui.
              </p>
            </div>
            <div className="flex max-w-lg flex-col gap-md">
              {state.notification && (
                <DsSection id="cloche" title="Ta cloche (aperçu)">
                  <DsListItem
                    icon="campaign"
                    title={`${OLIVIA} te relance sur le point bloquant : ${BLOCKERS[1].title}`}
                    meta="Il y a 1 jour"
                    opensDialog
                    onClick={(e) => open(blockers[1], e.currentTarget)}
                  />
                </DsSection>
              )}
              <BlockersSection
                blockers={{ data: blockers, isError: false }}
                myTeams={viewer.teams}
                canEdit={canEdit}
                onOpen={open}
                onStatusChange={(id, status) =>
                  setStatuses((s) => ({ ...s, [id]: { status, at: new Date().toISOString() } }))
                }
                onOpenArchive={notWired}
                canRemind={canRemind}
                onRemind={remind}
              />
              <KpiSection
                key={state.value}
                metrics={{ data: metricRows, isError: false }}
                canEditNps={false}
                savingNps={false}
                onSaveNps={notWired}
                onVerify={isAdmin || isManager ? (m) => verify(m.key) : undefined}
              />
            </div>
          </>
        )}
      </main>
      <BlockerReader
        blocker={readingRow}
        onClose={() => setReading(null)}
        onCloseAutoFocus={focusTrigger}
      />
      {detailRow && (
        <MockDetail
          submission={detailRow}
          onConfirm={() => verify(detailRow.id)}
          onClose={() => setDetail(null)}
        />
      )}
    </div>
  );
}
