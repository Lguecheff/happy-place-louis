import { createFileRoute } from "@tanstack/react-router";
import { useRef, useState } from "react";
import { toast } from "sonner";
import { BrandHeader } from "@/components/brand-header";
import { DS_INPUT, DsField } from "@/components/ds";
import { NewsReader } from "@/components/news-reader";
import {
  NewsSection,
  type DraftInput,
  type NewsSectionHandle,
} from "@/components/overview/NewsSection";
import { OverviewHeader } from "@/components/overview/OverviewHeader";
import { canEditPublishedNews } from "@/components/overview/overview-utils";
import { GlobalSearch } from "@/components/search/GlobalSearch";
import type { AppRole } from "@/lib/auth";
import type { News } from "@/lib/dashboard";
import type { NewsAudienceValue } from "@/lib/news-audience";

export const Route = createFileRoute("/_authenticated/maquettes/us10")({
  head: () => ({
    meta: [{ title: "Happy Place · Maquette de la modification d'une actu" }],
  }),
  component: Us10Mockup,
});

// ---------------------------------------------------------------------------
// Données factices (fictif)
// ---------------------------------------------------------------------------

const PRODUCT = "Product";
const MARKETING = "Marketing";
const ALL_TEAMS = [MARKETING, PRODUCT, "Legal"].sort();

const KESHA = { author: "Kesha (fictif)", author_email: "kesha@fictif.test" };
const KARIM = { author: "Karim (fictif)", author_email: "karim@fictif.test" };
const OLIVIA = { author: "Olivia (fictif)", author_email: "olivia@fictif.test" };
// Ce que la base écrit à la suppression d'un compte (private.anonymize_removed_user).
const REMOVED = { author: "Utilisateur supprimé (fictif)", author_email: "Utilisateur supprimé" };

type Profile = {
  value: string;
  label: string;
  name: string;
  email: string;
  role: AppRole;
  teams: string[];
  scope: "mine" | "all";
  note: string;
};

const OLIVIA_PROFILE = {
  name: "Olivia",
  email: OLIVIA.author_email,
  role: "admin",
  teams: ALL_TEAMS,
  scope: "all",
} as const;

const PROFILES: Profile[] = [
  {
    value: "kesha",
    label: "Kesha (auteure)",
    name: "Kesha",
    email: KESHA.author_email,
    role: "manager",
    teams: [MARKETING, PRODUCT],
    scope: "mine",
    note: "Ouvre « Point d'étape de l'équipe » : c'est la seule actu où tu vois « Modifier ».",
  },
  {
    value: "karim",
    label: "Autre manager (pas de bouton)",
    name: "Karim",
    email: KARIM.author_email,
    role: "manager",
    teams: [MARKETING],
    scope: "mine",
    note: "Ouvre « Point d'étape de l'équipe » : pas de bouton sur l'actu de Kesha. Le sien n'apparaît que sur « Calendrier des campagnes ».",
  },
  {
    value: "gontran",
    label: "Collaborateur (pas de bouton)",
    name: "Gontran",
    email: "gontran@fictif.test",
    role: "collaborateur",
    teams: [PRODUCT],
    scope: "mine",
    note: "Aucune actu ne propose « Modifier ».",
  },
  {
    value: "olivia",
    label: "Olivia (admin)",
    ...OLIVIA_PROFILE,
    note: "« Modifier » apparaît sur les 4 actus. L'auteur et la date de publication restent ceux d'origine.",
  },
  {
    value: "supprime",
    label: "Auteur supprimé (admin seulement)",
    ...OLIVIA_PROFILE,
    note: "Vu par Olivia. Ouvre « Séminaire d'automne » : son auteur n'a plus de compte, seul un admin voit « Modifier ». Vérifie avec les autres profils : aucun bouton sur cette actu.",
  },
];

const DAY_MS = 86_400_000;
const daysAgo = (days: number) => new Date(Date.now() - days * DAY_MS).toISOString();

function mockNews(
  id: string,
  days: number,
  title: string,
  who: Pick<News, "author" | "author_email">,
  value: NewsAudienceValue,
  extra: Partial<News> = {},
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
    ...extra,
  };
}

const COMPANY: NewsAudienceValue = { audience: "entreprise", teams: [] };
// Deux équipes : Karim (Marketing) et Gontran (Product) lisent aussi l'actu de Kesha.
const BOTH_TEAMS: NewsAudienceValue = { audience: "équipe", teams: [MARKETING, PRODUCT] };

const THREE_LINKS = [
  { url: "https://fictif.test/planning", label: "Planning (fictif)" },
  { url: "https://fictif.test/compte-rendu", label: "Compte rendu (fictif)" },
  { url: "https://fictif.test/equipe", label: "Équipe (fictif)" },
];

const NEWS: News[] = [
  mockNews("kesha", 1, "Point d'étape de l'équipe", KESHA, BOTH_TEAMS, { links: THREE_LINKS }),
  mockNews("karim", 3, "Calendrier des campagnes", KARIM, COMPANY),
  mockNews("olivia", 6, "Résultats du trimestre", OLIVIA, COMPANY, { updated_at: daysAgo(2) }),
  mockNews("supprime", 9, "Séminaire d'automne", REMOVED, BOTH_TEAMS),
];

// ---------------------------------------------------------------------------
// Présentation
// ---------------------------------------------------------------------------

function Us10Mockup() {
  const [profileValue, setProfileValue] = useState(PROFILES[0].value);
  const [news, setNews] = useState(NEWS);
  const [reading, setReading] = useState<News | null>(null);
  const [composerOpen, setComposerOpen] = useState(false);
  const composerTitle = useRef<HTMLInputElement>(null);
  const section = useRef<NewsSectionHandle>(null);

  const profile = PROFILES.find((p) => p.value === profileValue) ?? PROFILES[0];
  const canEditNews = (n: News) => canEditPublishedNews(n, profile.role, profile.email);
  const editNews = (n: News) => section.current?.editPublished(n);

  /** Comme la base : l'auteur, le statut et la date de publication ne sont pas touchés. */
  function saveEdit(input: DraftInput & { id: string }, onSaved: () => void) {
    const { id, title, body, links, audience } = input;
    const updated_at = new Date().toISOString();
    setNews((list) =>
      list.map((n) => (n.id === id ? { ...n, title, body, links, updated_at, ...audience } : n)),
    );
    toast.success("Actu modifiée (fictif)");
    onSaved();
  }

  return (
    <div className="bg-background text-on-surface font-body-md min-h-screen flex flex-col">
      <BrandHeader>
        <OverviewHeader
          isAdmin={profile.role === "admin"}
          name={`${profile.name} (fictif)`}
          role={profile.role}
          exporting={false}
          onExport={() => toast.info("Non branché dans la maquette (fictif).")}
          search={
            <GlobalSearch
              key={profile.value}
              canEditNews={canEditNews}
              onEditNews={editNews}
              source={{
                data: { news, submissions: [], blockers: [], metrics: [] },
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
              onChange={(e) => {
                setProfileValue(e.target.value);
                setReading(null);
                setComposerOpen(false);
              }}
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
              Maquette (fictif) : {profile.note}
            </p>
            <p>
              Pour tester une erreur : vide le titre, décoche toutes les équipes du public, ou
              choisis une image de plus de 5 Mo. Cherche « fictif » dans la barre de recherche : les
              mêmes droits s'appliquent, et une image enregistrée ne s'affiche pas ici.
            </p>
          </div>
        </div>
        <NewsSection
          key={profile.value}
          editRef={section}
          canWrite={profile.role !== "collaborateur"}
          email={profile.email}
          news={{ data: news, isError: false, isLoading: false }}
          audienceTeams={profile.teams}
          audienceScope={profile.scope}
          composerOpen={composerOpen}
          onComposerOpenChange={setComposerOpen}
          titleRef={composerTitle}
          saving={false}
          publishing={false}
          removing={false}
          onSave={() => toast.info("Non branché dans la maquette (fictif).")}
          onPublish={() => {}}
          onRemove={() => {}}
          onRead={setReading}
          onSaveEdit={saveEdit}
        />
      </main>
      <NewsReader
        news={reading}
        onClose={() => setReading(null)}
        onEdit={reading && canEditNews(reading) ? () => editNews(reading) : undefined}
      />
    </div>
  );
}
