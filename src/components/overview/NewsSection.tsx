import { useState, type RefObject } from "react";
import { flushSync } from "react-dom";
import { toast } from "sonner";
import { DS_INPUT, DsButton, DsEmptyState, DsField, DsListItem, DsSection } from "@/components/ds";
import { NewsMediaEditor } from "@/components/news-media";
import { ConfirmDialog } from "@/components/overview/ConfirmDialog";
import {
  NEWS_MONTHLY_TARGET,
  daysSince,
  formatDay,
  formatDays,
  myDrafts,
  newsPublishedAt,
  newsUpdatedAt,
  plural,
} from "@/components/overview/overview-utils";
import { timeAgo, type News } from "@/lib/dashboard";
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
const MISSING_TITLE = "Ajoute un titre pour publier.";

export type DraftInput = {
  id?: string;
  title: string;
  body: string;
  links: NewsLink[];
  media: MediaDraft;
};

function MonthlyProgress({ count }: { count: number }) {
  const percent = Math.min(count / NEWS_MONTHLY_TARGET, 1) * 100;
  return (
    <div className="space-y-xs">
      <div
        role="progressbar"
        aria-label="Actus publiées ce mois-ci"
        aria-valuemin={0}
        aria-valuemax={NEWS_MONTHLY_TARGET}
        aria-valuenow={Math.min(count, NEWS_MONTHLY_TARGET)}
        className="h-2 w-full bg-surface-container-high"
      >
        <div className="h-full bg-secondary" style={{ width: `${percent}%` }} />
      </div>
      <p className="font-body-sm text-body-sm text-on-surface-variant">
        {count} sur {NEWS_MONTHLY_TARGET} {plural(count, "publiée")} ce mois-ci
      </p>
    </div>
  );
}

export function NewsSection({
  canWrite,
  isAdmin,
  email,
  news,
  publishedCount,
  composerOpen,
  onComposerOpenChange,
  titleRef,
  saving,
  publishing,
  removing,
  onSave,
  onPublish,
  onPublishEdited,
  onRemove,
  onRead,
  draftRows,
}: {
  canWrite: boolean;
  isAdmin: boolean;
  email: string;
  news: { data?: News[]; isError: boolean; isLoading: boolean };
  publishedCount: number;
  composerOpen: boolean;
  onComposerOpenChange: (open: boolean) => void;
  titleRef: RefObject<HTMLInputElement | null>;
  saving: boolean;
  publishing: boolean;
  removing: boolean;
  onSave: (input: DraftInput, onSaved: () => void) => void;
  onPublish: (n: News) => void;
  /** Enregistre les modifications du rédacteur, puis publie. */
  onPublishEdited?: (input: DraftInput, onPublished: () => void) => void;
  onRemove: (n: News) => void;
  onRead: (n: News) => void;
  /**
   * Bloc « Mes brouillons » (US4, maquette) : `open` ouvre le rédacteur au clic sur la ligne,
   * `open-publish` y ajoute le bouton Publier. Sans cette prop, l'accueil reste inchangé.
   */
  draftRows?: "open" | "open-publish";
}) {
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [editing, setEditing] = useState<News | null>(null);
  const [media, setMedia] = useState<MediaDraft>(emptyMedia);
  const [showLinkErrs, setShowLinkErrs] = useState(false);
  const [titleError, setTitleError] = useState<string | undefined>();
  const [publishTarget, setPublishTarget] = useState<News | null>(null);
  const [removeTarget, setRemoveTarget] = useState<News | null>(null);
  const linkErrs = showLinkErrs ? linkErrors(media.links) : {};
  const drafts = draftRows
    ? myDrafts(news.data ?? [], email)
    : (news.data?.filter((n) => n.status === "brouillon") ?? []);
  const publishesEdited = !!publishTarget && publishTarget.id === editing?.id;
  const published = (news.data?.filter((n) => n.status === "publiée") ?? []).sort((a, b) =>
    newsPublishedAt(b).localeCompare(newsPublishedAt(a)),
  );

  function reset() {
    setEditing(null);
    setTitle("");
    setBody("");
    setMedia(emptyMedia());
    setShowLinkErrs(false);
    setTitleError(undefined);
  }

  function startEditing(n: News, error?: string) {
    setEditing(n);
    setTitle(n.title);
    setBody(n.body ?? "");
    setMedia(mediaFromNews(n));
    setShowLinkErrs(false);
    setTitleError(error);
    flushSync(() => onComposerOpenChange(true));
    titleRef.current?.focus();
  }

  function closeComposer() {
    reset();
    onComposerOpenChange(false);
  }

  function draftInput(): DraftInput {
    return { id: editing?.id, title: title.trim(), body, links: toNewsLinks(media.links), media };
  }

  function linksAreValid(action: string) {
    setShowLinkErrs(true);
    if (!Object.keys(linkErrors(media.links)).length) return true;
    toast.error(`Corrige les liens invalides avant ${action}.`);
    return false;
  }

  function save(e: React.FormEvent) {
    e.preventDefault();
    if (draftRows ? !title.trim() && !body.trim() : !title.trim()) {
      setTitleError(draftRows ? "Saisis un titre ou un texte." : "Saisis un titre.");
      return;
    }
    setTitleError(undefined);
    if (!linksAreValid("d'enregistrer")) return;
    onSave(draftInput(), closeComposer);
  }

  function publishEdited() {
    if (!editing) return;
    if (!title.trim()) {
      setTitleError(MISSING_TITLE);
      titleRef.current?.focus();
      return;
    }
    setTitleError(undefined);
    if (linksAreValid("de publier")) setPublishTarget(editing);
  }

  function publishRow(n: News) {
    if (n.id === editing?.id) publishEdited();
    else if (n.title.trim()) setPublishTarget(n);
    else startEditing(n, MISSING_TITLE);
  }

  return (
    <DsSection id="actus" title="Actualités du cabinet">
      {canWrite && <MonthlyProgress count={publishedCount} />}
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
                  <DsButton variant="link" onClick={draftRows ? closeComposer : reset}>
                    Annuler
                  </DsButton>
                </>
              )}
              <DsButton type="submit" pending={saving}>
                {saving ? "Enregistrement…" : "Enregistrer le brouillon"}
              </DsButton>
              {editing && draftRows && (
                <DsButton variant="confirm" disabled={publishing || saving} onClick={publishEdited}>
                  Publier
                </DsButton>
              )}
            </div>
          </form>
          <div className="space-y-xs">
            <h3 className={SUBTITLE}>{draftRows ? "Mes brouillons" : "Brouillon"}</h3>
            {news.data &&
              drafts.length === 0 &&
              (draftRows ? (
                <DsEmptyState>Aucun brouillon en cours.</DsEmptyState>
              ) : (
                <p className="font-body-sm text-body-sm text-on-surface-variant">
                  Aucun brouillon en cours.
                </p>
              ))}
            {drafts.map((n) => {
              if (draftRows) {
                return (
                  <DsListItem
                    key={n.id}
                    icon="draft"
                    title={n.title || <span className="italic">Sans titre</span>}
                    meta={`Créé le ${formatDay(n.created_at)} · ${formatDays(daysSince(n.created_at))}`}
                    onClick={() => startEditing(n)}
                    actions={
                      draftRows === "open-publish" && (
                        <DsButton
                          variant="confirm"
                          disabled={publishing}
                          onClick={() => publishRow(n)}
                        >
                          Publier
                        </DsButton>
                      )
                    }
                  />
                );
              }
              const allowed = isAdmin || (n.author_email ?? "").toLowerCase() === email;
              return (
                <DsListItem
                  key={n.id}
                  icon="draft"
                  title={n.title}
                  meta={`Modifié ${timeAgo(newsUpdatedAt(n))} · Par ${n.author}`}
                  actions={
                    allowed && (
                      <>
                        <DsButton variant="link" onClick={() => startEditing(n)}>
                          Modifier
                        </DsButton>
                        <DsButton
                          variant="confirm"
                          disabled={publishing}
                          onClick={() => setPublishTarget(n)}
                        >
                          Publier
                        </DsButton>
                      </>
                    )
                  }
                />
              );
            })}
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
            meta={`Publiée ${timeAgo(newsPublishedAt(n))} · Par ${n.author}`}
            onClick={() => onRead(n)}
          />
        ))}
      </div>
      <ConfirmDialog
        open={!!publishTarget}
        title={`Publier « ${publishesEdited ? title.trim() : publishTarget?.title} » ?`}
        description="Cette actu sera visible par tout le cabinet."
        confirmLabel="Publier"
        onCancel={() => setPublishTarget(null)}
        onConfirm={() => {
          if (publishesEdited) onPublishEdited?.(draftInput(), closeComposer);
          else if (publishTarget) onPublish(publishTarget);
          setPublishTarget(null);
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
