import { useRef, useState, type RefObject } from "react";
import { flushSync } from "react-dom";
import { toast } from "sonner";
import {
  DS_INPUT,
  DsBadge,
  DsButton,
  DsEmptyState,
  DsField,
  DsListItem,
  DsSection,
} from "@/components/ds";
import { NewsAudienceBadge } from "@/components/news/NewsAudienceBadge";
import { NewsAudienceField } from "@/components/news/NewsAudienceField";
import { NewsMediaEditor } from "@/components/news-media";
import { ConfirmDialog } from "@/components/overview/ConfirmDialog";
import {
  NEWS_MONTHLY_TARGET,
  daysSince,
  formatDay,
  formatDays,
  myDrafts,
  newsPublishedAt,
} from "@/components/overview/overview-utils";
import { timeAgo, type News } from "@/lib/dashboard";
import {
  audienceError,
  audienceSentence,
  editableAudience,
  emptyAudience,
  type NewsAudienceValue,
} from "@/lib/news-audience";
import {
  emptyMedia,
  linkErrors,
  mediaFromNews,
  toNewsLinks,
  type MediaDraft,
  type NewsLink,
} from "@/lib/news-media";

const RECENT_NEWS = 4;
const SUBTITLE = "font-label-md text-label-md normal-case tracking-normal text-on-surface-variant";

export type DraftInput = {
  id?: string;
  title: string;
  body: string;
  links: NewsLink[];
  media: MediaDraft;
  audience: NewsAudienceValue;
};

function MonthlyProgress({ count }: { count: number }) {
  const percent = Math.min(count / NEWS_MONTHLY_TARGET, 1) * 100;
  const reached = count >= NEWS_MONTHLY_TARGET;
  const text = `${count} sur ${NEWS_MONTHLY_TARGET} publiées ce mois-ci`;
  return (
    <div className="space-y-xs">
      <div
        role="progressbar"
        aria-label="Actus publiées ce mois-ci"
        aria-valuemin={0}
        aria-valuemax={NEWS_MONTHLY_TARGET}
        aria-valuenow={Math.min(count, NEWS_MONTHLY_TARGET)}
        aria-valuetext={reached ? `${text}, cible atteinte` : text}
        className="h-2 w-full bg-surface-container-high"
      >
        <div className="h-full bg-secondary" style={{ width: `${percent}%` }} />
      </div>
      <div className="flex flex-wrap items-center justify-between gap-xs">
        <p className="font-body-sm text-body-sm text-on-surface-variant">{text}</p>
        {reached && (
          <DsBadge variant="status" icon="check">
            Cible atteinte
          </DsBadge>
        )}
      </div>
    </div>
  );
}

export function NewsSection({
  canWrite,
  email,
  news,
  audienceTeams,
  audienceScope,
  audienceTeamsNotice,
  publishedCount,
  composerOpen,
  onComposerOpenChange,
  titleRef,
  saving,
  publishing,
  removing,
  onSave,
  onPublish,
  onRemove,
  onRead,
}: {
  canWrite: boolean;
  email: string;
  news: { data?: News[]; isError: boolean; isLoading: boolean };
  /** Équipes que l'auteur peut cibler. */
  audienceTeams: string[];
  audienceScope?: "mine" | "all";
  /** Sans valeur, les équipes sont disponibles ; sinon, explique pourquoi elles ne le sont pas. */
  audienceTeamsNotice?: string;
  /** Sans valeur, le compteur du mois n'est pas affiché. */
  publishedCount?: number;
  composerOpen: boolean;
  onComposerOpenChange: (open: boolean) => void;
  titleRef: RefObject<HTMLInputElement | null>;
  saving: boolean;
  publishing: boolean;
  removing: boolean;
  onSave: (input: DraftInput, onSaved: () => void) => void;
  /** Enregistre les modifications du rédacteur, puis publie. */
  onPublish: (input: DraftInput & { id: string }, onPublished: () => void) => void;
  onRemove: (n: News) => void;
  onRead: (n: News) => void;
}) {
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [editing, setEditing] = useState<News | null>(null);
  const [media, setMedia] = useState<MediaDraft>(emptyMedia);
  const [showLinkErrs, setShowLinkErrs] = useState(false);
  const [audience, setAudience] = useState<NewsAudienceValue>(emptyAudience);
  const [titleError, setTitleError] = useState<string | undefined>();
  const [audienceErr, setAudienceErr] = useState<string | undefined>();
  const audienceInput = useRef<HTMLInputElement>(null);
  const [confirmPublish, setConfirmPublish] = useState(false);
  const [removeTarget, setRemoveTarget] = useState<News | null>(null);
  const linkErrs = showLinkErrs ? linkErrors(media.links) : {};
  const drafts = myDrafts(news.data ?? [], email);
  const published = (news.data?.filter((n) => n.status === "publiée") ?? []).sort((a, b) =>
    newsPublishedAt(b).localeCompare(newsPublishedAt(a)),
  );

  function reset() {
    setEditing(null);
    setTitle("");
    setBody("");
    setMedia(emptyMedia());
    setAudience(emptyAudience());
    setShowLinkErrs(false);
    setTitleError(undefined);
    setAudienceErr(undefined);
  }

  function startEditing(n: News) {
    setEditing(n);
    setTitle(n.title);
    setBody(n.body ?? "");
    setMedia(mediaFromNews(n));
    setAudience(
      editableAudience({ audience: n.audience ?? null, teams: n.teams ?? [] }, audienceTeams),
    );
    setShowLinkErrs(false);
    setTitleError(undefined);
    setAudienceErr(undefined);
    flushSync(() => onComposerOpenChange(true));
    titleRef.current?.focus();
  }

  function closeComposer() {
    reset();
    onComposerOpenChange(false);
  }

  function draftInput(): DraftInput {
    return {
      id: editing?.id,
      title: title.trim(),
      body,
      links: toNewsLinks(media.links),
      media,
      audience,
    };
  }

  function linksAreValid(action: string) {
    setShowLinkErrs(true);
    if (!Object.keys(linkErrors(media.links)).length) return true;
    toast.error(`Corrige les liens invalides avant ${action}.`);
    return false;
  }

  function save(e: React.FormEvent) {
    e.preventDefault();
    if (!title.trim() && !body.trim()) {
      setTitleError("Saisis un titre ou un texte.");
      return;
    }
    setTitleError(undefined);
    if (!linksAreValid("d'enregistrer")) return;
    onSave(draftInput(), closeComposer);
  }

  function publish() {
    const noTitle = !title.trim();
    const missing = audienceError(audience);
    setTitleError(noTitle ? "Ajoute un titre pour publier." : undefined);
    setAudienceErr(missing);
    if (noTitle) titleRef.current?.focus();
    else if (missing) audienceInput.current?.focus();
    else if (linksAreValid("de publier")) setConfirmPublish(true);
  }

  return (
    <DsSection id="actus" title="Actualités du cabinet">
      {canWrite && publishedCount !== undefined && <MonthlyProgress count={publishedCount} />}
      {canWrite && (
        <>
          <DsButton
            icon="edit"
            aria-expanded={composerOpen}
            aria-controls="redacteur-actu"
            className="w-full"
            onClick={() => onComposerOpenChange(!composerOpen)}
          >
            Rédiger une actualité
          </DsButton>
          <form
            id="redacteur-actu"
            hidden={!composerOpen}
            className="space-y-md"
            onSubmit={save}
            noValidate
          >
            <DsField id="actu-titre" label="Titre" error={titleError}>
              <input
                id="actu-titre"
                ref={titleRef}
                type="text"
                className={DS_INPUT}
                placeholder="Saisis un titre…"
                value={title}
                onChange={(e) => setTitle(e.target.value)}
              />
            </DsField>
            <DsField id="actu-contenu" label="Contenu">
              <textarea
                id="actu-contenu"
                rows={4}
                className={DS_INPUT}
                placeholder="Rédige l'actualité…"
                value={body}
                onChange={(e) => setBody(e.target.value)}
              />
            </DsField>
            <NewsMediaEditor
              value={media}
              onChange={setMedia}
              linkErrs={linkErrs}
              disabled={saving}
              title={title}
            />
            <NewsAudienceField
              id="actu-public"
              teams={audienceTeams}
              scope={audienceScope}
              teamsNotice={audienceTeamsNotice}
              value={audience}
              error={audienceErr}
              disabled={saving}
              firstInputRef={audienceInput}
              onChange={(value) => {
                setAudience(value);
                setAudienceErr(undefined);
              }}
            />
            <div className="flex flex-wrap items-center justify-end gap-xs">
              {editing && (
                <>
                  <DsButton
                    variant="link"
                    className="mr-auto text-error"
                    disabled={removing}
                    onClick={() => setRemoveTarget(editing)}
                  >
                    Supprimer
                  </DsButton>
                  <DsButton variant="link" onClick={closeComposer}>
                    Annuler
                  </DsButton>
                </>
              )}
              <DsButton type="submit" pending={saving}>
                {saving ? "Enregistrement…" : "Enregistrer le brouillon"}
              </DsButton>
              {editing && (
                <DsButton
                  variant="confirm"
                  pending={publishing}
                  disabled={saving}
                  onClick={publish}
                >
                  Publier
                </DsButton>
              )}
            </div>
          </form>
          <div className="space-y-xs">
            <h3 className={SUBTITLE}>Mes brouillons</h3>
            {news.data && drafts.length === 0 && (
              <DsEmptyState>Aucun brouillon en cours.</DsEmptyState>
            )}
            {drafts.map((n) => (
              <DsListItem
                key={n.id}
                icon="draft"
                title={n.title || <span className="italic">Sans titre</span>}
                meta={`Créé le ${formatDay(n.created_at)} · ${formatDays(daysSince(n.created_at))}`}
                onClick={() => startEditing(n)}
              />
            ))}
          </div>
        </>
      )}
      <div className="space-y-xs">
        <h3 className={SUBTITLE}>Publiées récemment</h3>
        {news.isLoading && (
          <p className="font-body-sm text-body-sm text-on-surface-variant">Chargement…</p>
        )}
        {news.isError && (
          <p className="font-body-sm text-body-sm text-error">Les actualités sont indisponibles.</p>
        )}
        {news.data && published.length === 0 && (
          <DsEmptyState>Aucune actu publiée pour le moment.</DsEmptyState>
        )}
        {published.slice(0, RECENT_NEWS).map((n) => (
          <DsListItem
            key={n.id}
            icon="article"
            title={n.title}
            meta={
              <>
                <span className="block">
                  Publiée {timeAgo(newsPublishedAt(n))} · Par {n.author}
                </span>
                <NewsAudienceBadge news={n} className="mt-xs" />
              </>
            }
            onClick={() => onRead(n)}
          />
        ))}
      </div>
      <ConfirmDialog
        open={confirmPublish}
        title={`Publier « ${title.trim()} » ?`}
        description={audienceSentence(audience)}
        confirmLabel="Publier"
        onCancel={() => setConfirmPublish(false)}
        onConfirm={() => {
          if (editing) onPublish({ ...draftInput(), id: editing.id }, closeComposer);
          setConfirmPublish(false);
        }}
      />
      <ConfirmDialog
        open={!!removeTarget}
        danger
        title={`Supprimer le brouillon « ${removeTarget?.title || "Sans titre"} » ?`}
        description="Tu ne pourras pas le récupérer."
        confirmLabel="Supprimer"
        onCancel={() => setRemoveTarget(null)}
        onConfirm={() => {
          if (removeTarget) onRemove(removeTarget);
          setRemoveTarget(null);
          closeComposer();
        }}
      />
    </DsSection>
  );
}
