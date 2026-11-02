import { createFileRoute } from "@tanstack/react-router";
import { useRef, useState } from "react";
import { flushSync } from "react-dom";
import { toast } from "sonner";
import { BrandHeader } from "@/components/brand-header";
import { DS_INPUT, DsButton, DsField, DsSection } from "@/components/ds";
import { NewsReader } from "@/components/news-reader";
import { NewsSection } from "@/components/overview/NewsSection";
import { OverviewHeader } from "@/components/overview/OverviewHeader";
import { TodayStrip } from "@/components/overview/TodayStrip";
import { myDrafts, plural, publishedThisMonth } from "@/components/overview/overview-utils";
import { GlobalSearch } from "@/components/search/GlobalSearch";
import type { AppRole } from "@/lib/auth";
import type { News } from "@/lib/dashboard";
import type { NewsAudienceValue } from "@/lib/news-audience";

export const Route = createFileRoute("/_authenticated/maquettes/us09")({
  head: () => ({
    meta: [{ title: "Happy Place · Maquette des actus selon le public" }],
  }),
  component: Us09Mockup,
});

// ---------------------------------------------------------------------------
// Données factices (fictif)
// ---------------------------------------------------------------------------

const TEAM_A = "Product";
const TEAM_B = "Marketing";
const OTHER_TEAM = "Legal";

/** Nombre d'actus de « Publiées récemment » (RECENT_NEWS dans NewsSection). */
const FEED_LIMIT = 4;

const SOPHIE = { author: "Sophie (fictif)", author_email: "sophie@fictif.test" };
const KARIM = { author: "Karim (fictif)", author_email: "karim@fictif.test" };
const CLAIRE = { author: "Claire (fictif)", author_email: "claire@fictif.test" };

type Profile = {
  value: string;
  label: string;
  name: string;
  email: string;
  role: AppRole;
  teams: string[];
};

const PROFILES: Profile[] = [
  {
    value: "gontran",
    label: "Gontran (équipe A)",
    name: "Gontran",
    email: "gontran@fictif.test",
    role: "collaborateur",
    teams: [TEAM_A],
  },
  {
    value: "manager-a",
    label: "Manager de l'équipe A",
    name: "Sophie",
    email: SOPHIE.author_email,
    role: "manager",
    teams: [TEAM_A],
  },
  {
    value: "manager-b",
    label: "Manager de l'équipe B",
    name: "Karim",
    email: KARIM.author_email,
    role: "manager",
    teams: [TEAM_B],
  },
  {
    value: "admin",
    label: "Admin",
    name: "Claire",
    email: CLAIRE.author_email,
    role: "admin",
    teams: [],
  },
];

const DAY_MS = 86_400_000;
const daysAgo = (days: number) => new Date(Date.now() - days * DAY_MS).toISOString();

function mockNews(
  id: string,
  days: number,
  title: string,
  who: typeof SOPHIE,
  value: NewsAudienceValue,
): News {
  const at = daysAgo(days);
  return {
    id,
    title: `${title} (fictif)`,
    body: "Texte de l'actu (fictif).",
    ...who,
    status: "publiée",
    created_at: at,
    updated_at: at,
    published_at: at,
    links: [],
    ...value,
  };
}

const COMPANY: NewsAudienceValue = { audience: "entreprise", teams: [] };

// Une actu de chaque équipe cible aussi une 3e équipe : elle reste visible par chacune d'elles.
const NEWS: News[] = [
  mockNews("a1", 0, "Point d'étape de l'équipe", SOPHIE, { audience: "équipe", teams: [TEAM_A] }),
  mockNews("b1", 1, "Calendrier des campagnes", KARIM, { audience: "équipe", teams: [TEAM_B] }),
  mockNews("e1", 3, "Résultats du trimestre", CLAIRE, COMPANY),
  mockNews("a2", 5, "Atelier commun avec le juridique", SOPHIE, {
    audience: "équipe",
    teams: [OTHER_TEAM, TEAM_A],
  }),
  mockNews("b2", 8, "Nouvelle charte de marque", KARIM, {
    audience: "équipe",
    teams: [OTHER_TEAM, TEAM_B],
  }),
  mockNews("e2", 12, "Séminaire d'automne", CLAIRE, COMPANY),
];

/** Même règle que celle prévue côté base : le fil et la recherche ne reçoivent que ce résultat. */
function canRead(n: News, { role, email, teams }: Profile) {
  if (role === "admin" || n.author_email === email) return true;
  if (n.status !== "publiée") return false;
  return n.audience === "entreprise" || (n.teams ?? []).some((t) => teams.includes(t));
}

// ---------------------------------------------------------------------------
// Présentation
// ---------------------------------------------------------------------------

function ModulePlaceholder({ id, title }: { id: string; title: string }) {
  return (
    <DsSection id={id} title={title} className="bg-surface-container">
      <p className="font-body-sm text-body-sm text-on-surface-variant">
        Module existant, non modifié (fictif).
      </p>
    </DsSection>
  );
}

function notWired() {
  toast.info("Non branché dans la maquette (fictif).");
}

function Us09Mockup() {
  const [profileValue, setProfileValue] = useState(PROFILES[0].value);
  const [composerOpen, setComposerOpen] = useState(false);
  const [reading, setReading] = useState<News | null>(null);
  const composerTitle = useRef<HTMLInputElement>(null);

  const profile = PROFILES.find((p) => p.value === profileValue) ?? PROFILES[0];
  const isAdmin = profile.role === "admin";
  const canReview = profile.role !== "collaborateur";
  const visible = NEWS.filter((n) => canRead(n, profile));
  const hidden = NEWS.length - visible.length;
  const beyondFeed = visible.length - FEED_LIMIT;
  const publishedCount =
    profile.role === "manager" ? publishedThisMonth(visible, profile.email) : undefined;

  const changeProfile = (value: string) => {
    setProfileValue(value);
    setComposerOpen(false);
    setReading(null);
  };

  const openComposer = () => {
    flushSync(() => setComposerOpen(true));
    composerTitle.current?.focus();
  };

  return (
    <div className="bg-background text-on-surface font-body-md min-h-screen flex flex-col">
      <BrandHeader>
        <OverviewHeader
          isAdmin={isAdmin}
          name={`${profile.name} (fictif)`}
          role={profile.role}
          exporting={false}
          onExport={notWired}
          search={
            <GlobalSearch
              key={profile.value}
              source={{
                data: { news: visible, submissions: [], blockers: [], metrics: [] },
                isError: false,
                isLoading: false,
              }}
            />
          }
        />
      </BrandHeader>
      <main className="flex-grow w-full max-w-interface mx-auto p-sm md:p-md space-y-md">
        <div className="flex flex-wrap items-end gap-sm border border-dashed border-outline-variant p-sm">
          <DsField id="maquette-profil" label="Voir en tant que" className="w-full md:w-72">
            <select
              id="maquette-profil"
              className={DS_INPUT}
              value={profile.value}
              onChange={(e) => changeProfile(e.target.value)}
            >
              {PROFILES.map((p) => (
                <option key={p.value} value={p.value}>
                  {p.label}
                </option>
              ))}
            </select>
          </DsField>
          <div className="min-w-0 flex-1 basis-64 space-y-1 font-body-sm text-body-sm text-on-surface-variant">
            <p role="status" className="text-on-surface">
              Maquette (fictif) : {visible.length} {plural(visible.length, "actu")}{" "}
              {plural(visible.length, "visible")}, {hidden} {plural(hidden, "masquée")}.
            </p>
            <p>
              Équipe A = {TEAM_A}, équipe B = {TEAM_B}. Cherche « fictif » dans la barre de
              recherche : aucune actu masquée n'en sort.
            </p>
            {beyondFeed > 0 && (
              <p>
                Le fil s'arrête aux {FEED_LIMIT} plus récentes : {beyondFeed} autres actus visibles
                se trouvent par la recherche.
              </p>
            )}
          </div>
        </div>

        <div className="flex flex-wrap items-end justify-between gap-sm">
          <div className="min-w-0 space-y-xs">
            <h1 className="font-headline-lg text-headline-lg text-primary">
              Bonjour {profile.name}
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
              <DsButton variant="primary" icon="add" onClick={openComposer}>
                Publier une actu
              </DsButton>
            )}
          </div>
        </div>

        <TodayStrip
          canReview={canReview}
          pending={[]}
          blockers={[]}
          drafts={myDrafts(visible, profile.email).length}
          publishedCount={publishedCount}
        />

        <div className="flex flex-wrap items-start gap-md">
          <div className="flex min-w-0 flex-[999_1_620px] flex-col gap-md">
            <ModulePlaceholder id="demandes" title="Demandes" />
            <NewsSection
              key={profile.value}
              canWrite={canReview}
              email={profile.email}
              news={{ data: visible, isError: false, isLoading: false }}
              audienceTeams={isAdmin ? [OTHER_TEAM, TEAM_B, TEAM_A] : profile.teams}
              audienceScope={isAdmin ? "all" : "mine"}
              publishedCount={publishedCount}
              composerOpen={composerOpen}
              onComposerOpenChange={setComposerOpen}
              titleRef={composerTitle}
              saving={false}
              publishing={false}
              removing={false}
              onSave={notWired}
              onPublish={notWired}
              onRemove={notWired}
              onRead={setReading}
            />
          </div>
          <div className="flex min-w-0 flex-[1_1_380px] flex-col gap-md">
            <ModulePlaceholder id="blocages" title="Points bloquants" />
            <ModulePlaceholder id="indicateurs" title="Indicateurs" />
          </div>
        </div>
      </main>
      <NewsReader news={reading} onClose={() => setReading(null)} />
    </div>
  );
}
