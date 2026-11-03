import { createFileRoute } from "@tanstack/react-router";
import { useState } from "react";
import { toast } from "sonner";
import { BrandHeader } from "@/components/brand-header";
import { DS_INPUT, DsButton, DsField, DsKpiTile, DsSection } from "@/components/ds";
import { KpiSection } from "@/components/overview/KpiSection";
import { OverviewHeader } from "@/components/overview/OverviewHeader";
import { GlobalSearch } from "@/components/search/GlobalSearch";
import { formatMetricValue, metricTrend, type Metric } from "@/lib/dashboard";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/_authenticated/maquettes/us18")({
  head: () => ({
    meta: [{ title: "Happy Place · Maquette des définitions de KPI" }],
  }),
  component: Us18Mockup,
});

// ---------------------------------------------------------------------------
// Données factices (fictif)
// ---------------------------------------------------------------------------

const MAX_TEXT = 200;
const DAY_MS = 24 * 60 * 60_000;
const ago = (ms: number) => new Date(Date.now() - ms).toISOString();

type Texts = { definition: string; impact: string };

/** Textes proposés pour les 3 KPI existants, à valider par Louis avant la migration. */
const PROPOSED: Record<string, Texts> = {
  training_kpi: {
    definition:
      "Part des candidats accompagnés qui ont signé une mission dans les 30 derniers jours (fictif).",
    impact:
      "Il fixe les priorités de l'équipe : s'il baisse, l'effort va aux candidats sans mission, et tes demandes qui les aident passent en premier (fictif).",
  },
  active_users: {
    definition:
      "Nombre de missions en cours aujourd'hui, de la signature du contrat à la fin de la mission (fictif).",
    impact:
      "Il montre la charge de suivi : plus il monte, plus tes managers ont de missions à suivre, et plus une demande qui fait gagner du temps compte (fictif).",
  },
  nps: {
    definition:
      "Note de recommandation donnée par les candidats à la fin de leur mission, de −100 à +100 (fictif).",
    impact:
      "Il dit si les candidats recommandent Happy Place : une demande qui améliore leur accueil ou leur suivi le fait monter (fictif).",
  },
};

const BASE: Metric[] = [
  {
    key: "training_kpi",
    label: "Taux de placement",
    value: 78.4,
    unit: "%",
    trend: "hausse",
    previous_value: 76.3,
    delta: 2.1,
    updated_at: ago(2 * DAY_MS),
  },
  {
    key: "active_users",
    label: "Missions actives",
    value: 142,
    unit: null,
    trend: "baisse",
    previous_value: 150,
    delta: -8,
    updated_at: ago(DAY_MS),
  },
  {
    key: "nps",
    label: "NPS candidats",
    value: 41,
    unit: null,
    trend: "stable",
    previous_value: 41,
    delta: 0,
    updated_at: ago(5 * DAY_MS),
  },
];

const withTexts = (texts: Record<string, Partial<Texts>>) =>
  BASE.map((m) => ({ ...m, definition: null, impact: null, ...texts[m.key] }));

type MockState = {
  value: string;
  label: string;
  note: string;
  metrics: Metric[];
  /** Colonne étroite, comme sur un téléphone. */
  narrow?: boolean;
  admin?: boolean;
};

const STATES: MockState[] = [
  {
    value: "renseignes",
    label: "Textes renseignés",
    note: "Survole un libellé souligné en pointillés, ou atteins-le avec Tab : l'infobulle affiche les deux textes, Échap la ferme. « Comprendre cet indicateur » ouvre les mêmes textes dans une fenêtre. Cherche « placement » dans la barre de recherche : la vue de lecture les affiche aussi.",
    metrics: withTexts(PROPOSED),
  },
  {
    value: "vide",
    label: "Texte vide",
    note: "« Missions actives » n'a pas encore de « Ce que ça change pour toi », « NPS candidats » n'a aucun texte : chaque texte vide affiche « Définition à venir. », dans l'infobulle, la fenêtre et la recherche.",
    metrics: withTexts({
      training_kpi: PROPOSED.training_kpi,
      active_users: { definition: PROPOSED.active_users.definition },
    }),
  },
  {
    value: "tactile",
    label: "Écran tactile (sans survol)",
    note: "Sur un téléphone, le toucher n'ouvre pas l'infobulle : « Comprendre cet indicateur » suffit et ouvre la fenêtre avec les deux textes. Pour l'essayer vraiment, passe ton navigateur en mode téléphone.",
    metrics: withTexts(PROPOSED),
    narrow: true,
  },
  {
    value: "admin",
    label: "Formulaire admin",
    note: "Dans « Gérer les données > KPI », l'admin saisit les deux textes, 200 caractères maximum chacun. « Enregistrer les modifications » met à jour les tuiles ci-dessous (fictif). Ici, l'écran est vu par un admin.",
    metrics: withTexts(PROPOSED),
    admin: true,
  },
];

const notWired = () => toast.info("Non branché dans la maquette (fictif).");

// ---------------------------------------------------------------------------
// Présentation
// ---------------------------------------------------------------------------

function Us18Mockup() {
  const [stateValue, setStateValue] = useState(STATES[0].value);
  const state = STATES.find((s) => s.value === stateValue) ?? STATES[0];
  const [metrics, setMetrics] = useState(state.metrics);

  function changeState(value: string) {
    const next = STATES.find((s) => s.value === value) ?? STATES[0];
    setStateValue(next.value);
    setMetrics(next.metrics);
  }

  return (
    <div className="bg-background text-on-surface font-body-md min-h-screen flex flex-col">
      <BrandHeader>
        <OverviewHeader
          isAdmin={!!state.admin}
          name={state.admin ? "Olivia Laurent (fictif)" : "Gontran (fictif)"}
          role={state.admin ? "admin" : "collaborateur"}
          exporting={false}
          onExport={notWired}
          search={
            <GlobalSearch
              source={{
                data: { news: [], submissions: [], blockers: [], metrics },
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
            {state.admin ? "Bonjour Olivia (fictif)" : "Bonjour Gontran (fictif)"}
          </h1>
          <p className="font-body-md text-body-md text-on-surface-variant">
            Voici ce qui demande ton attention aujourd'hui.
          </p>
        </div>
        <div className={cn("grid gap-md", state.admin && "lg:grid-cols-2")}>
          {state.admin && (
            <AdminForm
              metrics={metrics}
              onSave={(key, texts) =>
                setMetrics((ms) => ms.map((m) => (m.key === key ? { ...m, ...texts } : m)))
              }
            />
          )}
          <div className={state.narrow ? "max-w-xs" : "max-w-lg"}>
            <KpiSection
              key={state.value}
              metrics={{ data: metrics, isError: false }}
              canEditNps={false}
              savingNps={false}
              onSaveNps={notWired}
            />
          </div>
        </div>
      </main>
    </div>
  );
}

/** Aperçu des deux champs ajoutés au formulaire de /manage/metrics. */
function AdminForm({
  metrics,
  onSave,
}: {
  metrics: Metric[];
  onSave: (key: string, texts: Texts) => void;
}) {
  const [key, setKey] = useState(metrics[0].key);
  const current = metrics.find((m) => m.key === key) ?? metrics[0];
  const [texts, setTexts] = useState<Texts>({
    definition: current.definition ?? "",
    impact: current.impact ?? "",
  });

  function choose(next: string) {
    const m = metrics.find((x) => x.key === next) ?? metrics[0];
    setKey(m.key);
    setTexts({ definition: m.definition ?? "", impact: m.impact ?? "" });
  }

  return (
    <DsSection id="formulaire-kpi" title="Modifier l'indicateur (fictif)">
      <form
        className="space-y-sm"
        onSubmit={(e) => {
          e.preventDefault();
          onSave(key, { definition: texts.definition.trim(), impact: texts.impact.trim() });
          toast.success("Indicateur modifié (fictif)");
        }}
      >
        <DsField id="kpi-choix" label="Indicateur">
          <select
            id="kpi-choix"
            className={DS_INPUT}
            value={key}
            onChange={(e) => choose(e.target.value)}
          >
            {metrics.map((m) => (
              <option key={m.key} value={m.key}>
                {m.label}
              </option>
            ))}
          </select>
        </DsField>
        <TextField
          id="kpi-definition"
          label="Ce que ça mesure"
          value={texts.definition}
          onChange={(definition) => setTexts((t) => ({ ...t, definition }))}
        />
        <TextField
          id="kpi-impact"
          label="Ce que ça change pour toi"
          value={texts.impact}
          onChange={(impact) => setTexts((t) => ({ ...t, impact }))}
        />
        <p className="font-body-sm text-body-sm text-on-surface-variant">
          Un champ vide affiche « Définition à venir. ».
        </p>
        <DsButton type="submit" variant="confirm" icon="check">
          Enregistrer les modifications
        </DsButton>
      </form>
      <DsKpiTile
        label={`Aperçu : ${current.label}`}
        value={formatMetricValue(current.value, current.unit)}
        {...metricTrend(current)}
        definition={texts}
      />
    </DsSection>
  );
}

function TextField({
  id,
  label,
  value,
  onChange,
}: {
  id: string;
  label: string;
  value: string;
  onChange: (value: string) => void;
}) {
  return (
    <DsField id={id} label={label}>
      <textarea
        id={id}
        rows={3}
        maxLength={MAX_TEXT}
        aria-describedby={`${id}-compte`}
        className={DS_INPUT}
        value={value}
        onChange={(e) => onChange(e.target.value)}
      />
      <p
        id={`${id}-compte`}
        className="font-label-md text-label-md normal-case tracking-normal text-on-surface-variant"
      >
        {value.length}/{MAX_TEXT} caractères
      </p>
    </DsField>
  );
}
