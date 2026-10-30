import { useState, type RefObject } from "react";
import { flushSync } from "react-dom";
import { toast } from "sonner";
import { DS_INPUT, DsButton, DsEmptyState, DsField, DsListItem, DsSection } from "@/components/ds";
import { NewsMediaEditor } from "@/components/news-media";
import { ConfirmDialog } from "@/components/overview/ConfirmDialog";
import {
  NEWS_MONTHLY_TARGET,
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
  onRemove,
  onRead,
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
  onRemove: (n: News) => void;
  onRead: (n: News) => void;
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
  const drafts = news.data?.filter((n) => n.status === "brouillon") ?? [];
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

  function startEditing(n: News) {
    setEditing(n);
    setTitle(n.title);
    setBody(n.body ?? "");
    setMedia(mediaFromNews(n));
    setShowLinkErrs(false);
    setTitleError(undefined);
    flushSync(() => onComposerOpenChange(true));
    titleRef.current?.focus();
  }

  function save(e: React.FormEvent) {
    e.preventDefault();
    if (!title.trim()) {
      setTitleError("Saisis un titre.");
      return;
    }
    setTitleError(undefined);
    setShowLinkErrs(true);
    if (Object.keys(linkErrors(media.links)).length) {
      toast.error("Corrige les liens invalides avant d'enregistrer.");
      return;
    }
    onSave(
      { id: editing?.id, title: title.trim(), body, links: toNewsLinks(media.links), media },
      () => {
        reset();
        onComposerOpenChange(false);
      },
    );
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
                  <DsButton variant="link" onClick={reset}>
                    Annuler
                  </DsButton>
                </>
              )}
              <DsButton type="submit" pending={saving}>
                {saving ? "Enregistrement…" : "Enregistrer le brouillon"}
              </DsButton>
            </div>
          </form>
          <div className="space-y-xs">
            <h3 className={SUBTITLE}>Brouillon</h3>
            {news.data && drafts.length === 0 && (
              <p className="font-body-sm text-body-sm text-on-surface-variant">
                Aucun brouillon en cours.
              </p>
            )}
            {drafts.map((n) => {
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
        title={`Publier « ${publishTarget?.title} » ?`}
        description="Cette actu sera visible par tout le cabinet."
        confirmLabel="Publier"
        onCancel={() => setPublishTarget(null)}
        onConfirm={() => {
          if (publishTarget) onPublish(publishTarget);
          setPublishTarget(null);
        }}
      />
      <ConfirmDialog
        open={!!removeTarget}
        danger
        title={`Supprimer le brouillon « ${removeTarget?.title} » ?`}
        description="Tu ne pourras pas le récupérer."
        confirmLabel="Supprimer"
        onCancel={() => setRemoveTarget(null)}
        onConfirm={() => {
          if (removeTarget) onRemove(removeTarget);
          setRemoveTarget(null);
          reset();
          onComposerOpenChange(false);
        }}
      />
    </DsSection>
  );
}
