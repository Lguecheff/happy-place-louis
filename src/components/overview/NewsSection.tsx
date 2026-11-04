import { useImperativeHandle, useRef, useState, type ReactNode, type RefObject } from "react";
import { flushSync } from "react-dom";
import { toast } from "sonner";
import { ErrorSummary } from "@/components/manage/crud-ui";
import {
  DS_INPUT,
  DsBadge,
  DsButton,
  DsEmptyState,
  DsField,
  DsListItem,
  DsSaveStatus,
  DsSection,
  DsShowMore,
  SHOW_MORE_NEWS,
  useShowMore,
} from "@/components/ds";
import { NewsAudienceBadge } from "@/components/news/NewsAudienceBadge";
import { NewsAudienceField } from "@/components/news/NewsAudienceField";
import {
  NewsTemplatePicker,
  type NewsTemplatePickerInitial,
} from "@/components/news/NewsTemplatePicker";
import {
  NewsAiWriter,
  type NewsAiFormat,
  type NewsAiWriterInitial,
} from "@/components/news/NewsAiWriter";
import type { AiGenerate } from "@/lib/news-ai";
import { useAutosaveDraft, type AutosaveFn } from "@/components/news/use-autosave-draft";
import { NewsMediaEditor } from "@/components/news-media";
import { ConfirmDialog } from "@/components/overview/ConfirmDialog";
import {
  NEWS_MONTHLY_TARGET,
  daysSince,
  formatDay,
  formatDays,
  myDrafts,
  newsModifiedAt,
  newsPublishedAt,
} from "@/components/overview/overview-utils";
import { isNewsUnchanged, timeAgo, type News } from "@/lib/dashboard";
import { newsContentSchema, validate, type FieldErrors } from "@/lib/manage-schemas";
import {
  audienceError,
  audienceSentence,
  editableAudience,
  emptyAudience,
  publishedAudience,
  type NewsAudienceValue,
} from "@/lib/news-audience";
import {
  emptyMedia,
  linkErrors,
  mediaFromNews,
  toNewsLinks,
  type LinkDraft,
  type MediaDraft,
  type NewsLink,
} from "@/lib/news-media";
import { bracketErrors } from "@/lib/news-templates";

/** Première tranche de « Publiées récemment » ; chaque « Voir plus » en ajoute 10 (US24). */
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

/** Ce que l'enregistrement automatique envoie : tout sauf l'image, qui reste au bouton « Enregistrer le brouillon ». */
export type AutosaveInput = Omit<DraftInput, "id" | "media">;

/** Les liens encore invalides restent dans le rédacteur, sans être enregistrés. */
function autosaveInput(
  title: string,
  body: string,
  links: LinkDraft[],
  audience: NewsAudienceValue,
): AutosaveInput {
  const errs = linkErrors(links);
  const valid = links.filter((_, i) => !(i in errs));
  return { title: title.trim(), body, links: toNewsLinks(valid), audience };
}

const EMPTY_AUTOSAVE = autosaveInput("", "", [], emptyAudience());
const isAutosaveEmpty = (v: AutosaveInput) => !v.title && !v.body.trim();

/** Ouvre le rédacteur sur une actu publiée depuis l'extérieur de la section (fenêtre de lecture). */
export type NewsSectionHandle = {
  editPublished: (n: News) => void;
  /** Ouvre un nouveau brouillon prérempli (US26, « Rédiger » sur une idée). */
  startDraft: (draft: { title: string; body: string }) => Promise<boolean>;
  /** Ouvre le rédacteur et la fenêtre des modèles (US26, « Partir d'un modèle »). */
  openTemplates: () => Promise<void>;
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
  editRef,
  savingEdit = false,
  onSaveEdit,
  onAutosave,
  initialDraft,
  initialTemplatePicker,
  aiWriter,
  ideas,
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
  editRef?: RefObject<NewsSectionHandle | null>;
  savingEdit?: boolean;
  /** Enregistre la modification d'une actu publiée, qui reste publiée. */
  onSaveEdit?: (input: DraftInput & { id: string }, onSaved: () => void) => void;
  /** Enregistrement automatique d'un brouillon (sans valeur, il est désactivé). */
  onAutosave?: AutosaveFn<AutosaveInput>;
  /** Contenu de départ d'un nouveau brouillon (maquettes). */
  initialDraft?: { title: string; body: string };
  /** Fenêtre des modèles ouverte au départ (maquettes). */
  initialTemplatePicker?: NewsTemplatePickerInitial;
  /** « Rédiger avec l'IA » (US27) ; sans valeur, le bouton n'apparaît pas. */
  aiWriter?: { generate: AiGenerate; initial?: NewsAiWriterInitial; format?: NewsAiFormat };
  /** Bloc « Idées de sujets » (US26), managers seulement ; placé sous le compteur du mois. */
  ideas?: ReactNode;
}) {
  const [title, setTitle] = useState(initialDraft?.title ?? "");
  const [body, setBody] = useState(initialDraft?.body ?? "");
  const [editing, setEditing] = useState<News | null>(null);
  const [media, setMedia] = useState<MediaDraft>(emptyMedia);
  const [showLinkErrs, setShowLinkErrs] = useState(false);
  const [audience, setAudience] = useState<NewsAudienceValue>(emptyAudience);
  const [titleError, setTitleError] = useState<string | undefined>();
  const [bodyError, setBodyError] = useState<string | undefined>();
  const [audienceErr, setAudienceErr] = useState<string | undefined>();
  const [editErrors, setEditErrors] = useState<FieldErrors>({});
  const audienceInput = useRef<HTMLInputElement>(null);
  const bodyRef = useRef<HTMLTextAreaElement>(null);
  const [confirmPublish, setConfirmPublish] = useState(false);
  /** La fenêtre des modèles se rouvre en remontant le sélecteur (US26). */
  const [picker, setPicker] = useState({ key: 0, initial: initialTemplatePicker });
  const [removeTarget, setRemoveTarget] = useState<News | null>(null);
  const linkErrs = showLinkErrs ? linkErrors(media.links) : {};
  const editingPublished = editing?.status === "publiée";
  const busy = saving || savingEdit;
  const autosaveOn =
    !!onAutosave && composerOpen && !editingPublished && !saving && !publishing && !removing;
  const autosave = useAutosaveDraft({
    value: autosaveInput(title, body, media.links, audience),
    isEmpty: isAutosaveEmpty,
    // Le rédacteur s'ouvre sur un nouveau brouillon : un contenu de départ reste à enregistrer.
    baseline: EMPTY_AUTOSAVE,
    save: (value, id) => onAutosave!(value, id),
    enabled: autosaveOn,
  });
  const drafts = myDrafts(news.data ?? [], email);
  const published = (news.data?.filter((n) => n.status === "publiée") ?? []).sort((a, b) =>
    newsPublishedAt(b).localeCompare(newsPublishedAt(a)),
  );
  const recent = useShowMore({ total: published.length, first: RECENT_NEWS, noun: SHOW_MORE_NEWS });

  function reset() {
    setEditing(null);
    setTitle("");
    setBody("");
    setMedia(emptyMedia());
    setAudience(emptyAudience());
    setShowLinkErrs(false);
    setTitleError(undefined);
    setBodyError(undefined);
    setAudienceErr(undefined);
    setEditErrors({});
    autosave.reset(EMPTY_AUTOSAVE);
  }

  useImperativeHandle(editRef, () => ({
    editPublished: (n) => void openNews(n),
    startDraft: async (draft) => {
      if (!(await leaveDraft())) return false;
      reset();
      setTitle(draft.title);
      setBody(draft.body);
      flushSync(() => onComposerOpenChange(true));
      titleRef.current?.focus();
      return true;
    },
    openTemplates: async () => {
      if (!(await leaveDraft())) return;
      reset();
      flushSync(() => onComposerOpenChange(true));
      setPicker((p) => ({ key: p.key + 1, initial: {} }));
    },
  }));

  /** Enregistre d'abord le brouillon en cours. En cas d'échec, il reste ouvert et rien n'est perdu. */
  async function leaveDraft() {
    return !autosaveOn || (await autosave.flush());
  }

  async function openNews(n: News) {
    if (!(await leaveDraft())) return;
    // Brouillon créé par l'enregistrement automatique : le rédacteur a déjà sa dernière version.
    if (composerOpen && n.id === autosave.draftId()) {
      setEditing(n);
      return;
    }
    startEditing(n);
  }

  function startEditing(n: News) {
    const nextMedia = mediaFromNews(n);
    const saved = { audience: n.audience ?? null, teams: n.teams ?? [] };
    const nextAudience =
      n.status !== "publiée"
        ? editableAudience(saved, audienceTeams)
        : audienceTeamsNotice
          ? saved
          : publishedAudience(saved, audienceTeams);
    setEditing(n);
    setTitle(n.title);
    setBody(n.body ?? "");
    setMedia(nextMedia);
    setAudience(nextAudience);
    autosave.reset(
      autosaveInput(n.title, n.body ?? "", nextMedia.links, nextAudience),
      n.status !== "publiée" ? n.id : undefined,
    );
    setShowLinkErrs(false);
    setTitleError(undefined);
    setBodyError(undefined);
    setAudienceErr(undefined);
    setEditErrors({});
    flushSync(() => onComposerOpenChange(true));
    titleRef.current?.focus();
  }

  /** Après un enregistrement manuel, une publication ou une suppression : rien à enregistrer. */
  function done() {
    reset();
    onComposerOpenChange(false);
  }

  async function closeComposer() {
    if (await leaveDraft()) done();
  }

  /** Masquer le rédacteur garde son contenu, comme avant ; il est enregistré au passage. */
  async function toggleComposer() {
    if (composerOpen && !(await leaveDraft())) return;
    onComposerOpenChange(!composerOpen);
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

  /** Mêmes règles que /manage/news. */
  function contentErrors(status: "brouillon" | "publiée"): FieldErrors {
    const result = validate(newsContentSchema, { title, body, status });
    const errors = result.ok ? {} : result.errors;
    setTitleError(errors.title);
    setBodyError(errors.body);
    return errors;
  }

  async function save(e: React.FormEvent) {
    e.preventDefault();
    if (Object.keys(contentErrors("brouillon")).length) return;
    if (!linksAreValid("d'enregistrer")) return;
    // Attend l'enregistrement automatique en cours pour mettre à jour le même brouillon.
    const id = onAutosave ? await autosave.idle() : undefined;
    const input = draftInput();
    onSave({ ...input, id: id ?? input.id }, done);
  }

  /** Les crochets d'un modèle (US25) sont vérifiés ici, avant la confirmation de publication. */
  function publish() {
    const content = contentErrors("publiée");
    const brackets = bracketErrors(title, body);
    const titleErr = content.title ?? brackets.title;
    const bodyErr = content.body ?? brackets.body;
    setTitleError(titleErr);
    setBodyError(bodyErr);
    const missing = audienceError(audience);
    setAudienceErr(missing);
    if (titleErr) titleRef.current?.focus();
    else if (bodyErr) bodyRef.current?.focus();
    else if (missing) audienceInput.current?.focus();
    else if (linksAreValid("de publier")) setConfirmPublish(true);
  }

  /** Mêmes règles que la publication. En cas d'erreur, rien n'est envoyé : l'actu ne change pas. */
  function saveEdit(e: React.FormEvent) {
    e.preventDefault();
    if (!editing) return;
    const content = contentErrors("publiée");
    const missing = audienceError(audience);
    const badLinks = Object.keys(linkErrors(media.links)).length > 0;
    const errors = {
      ...content,
      ...(missing && { audience: missing }),
      ...(badLinks && { links: "Corrige les liens invalides." }),
      ...(media.rejectedImage && { image: media.rejectedImage }),
    };
    setAudienceErr(missing);
    setShowLinkErrs(true);
    setEditErrors(errors);
    if (Object.keys(content).length) titleRef.current?.focus();
    else if (missing) audienceInput.current?.focus();
    if (Object.keys(errors).length) return;
    const input = { ...draftInput(), id: editing.id };
    if (isNewsUnchanged(editing, input)) {
      toast.info("Aucune modification à enregistrer.");
      closeComposer();
      return;
    }
    onSaveEdit?.(input, done);
  }

  return (
    <DsSection id="actus" title="Actualités du cabinet">
      {canWrite && publishedCount !== undefined && <MonthlyProgress count={publishedCount} />}
      {canWrite && ideas}
      {canWrite && (
        <>
          {!editingPublished && (
            <DsButton
              icon="edit"
              aria-expanded={composerOpen}
              aria-controls="redacteur-actu"
              className="w-full"
              onClick={() => void toggleComposer()}
            >
              Rédiger une actualité
            </DsButton>
          )}
          <form
            id="redacteur-actu"
            hidden={!composerOpen}
            className="space-y-md"
            onSubmit={editingPublished ? saveEdit : save}
            noValidate
          >
            {editingPublished && (
              <div className="space-y-xs">
                <h3 className={SUBTITLE}>Modifier une actu publiée</h3>
                <p className="font-body-sm text-body-sm text-on-surface-variant">
                  Elle reste publiée. Sa date de publication et son auteur ne changent pas.
                </p>
                <ErrorSummary errors={editErrors} />
              </div>
            )}
            {!editingPublished && (
              <div className="flex flex-wrap gap-xs">
                <NewsTemplatePicker
                  key={picker.key}
                  hasText={!!title.trim() || !!body.trim()}
                  disabled={busy}
                  initial={picker.initial}
                  onApply={(t) => {
                    setTitle(t.title);
                    setBody(t.body);
                    setTitleError(undefined);
                    setBodyError(undefined);
                    titleRef.current?.focus();
                  }}
                />
                {aiWriter && (
                  <NewsAiWriter
                    hasText={!!title.trim() || !!body.trim()}
                    disabled={busy}
                    generate={aiWriter.generate}
                    initial={aiWriter.initial}
                    format={aiWriter.format}
                    onApply={(d) => {
                      setTitle(d.title);
                      setBody(d.body);
                      setTitleError(undefined);
                      setBodyError(undefined);
                      titleRef.current?.focus();
                    }}
                  />
                )}
              </div>
            )}
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
            <DsField id="actu-contenu" label="Contenu" error={bodyError}>
              <textarea
                id="actu-contenu"
                ref={bodyRef}
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
              disabled={busy}
              title={title}
            />
            <NewsAudienceField
              id="actu-public"
              teams={audienceTeams}
              scope={audienceScope}
              teamsNotice={audienceTeamsNotice}
              value={audience}
              error={audienceErr}
              disabled={busy}
              firstInputRef={audienceInput}
              onChange={(value) => {
                setAudience(value);
                setAudienceErr(undefined);
              }}
            />
            {onAutosave && !editingPublished && (
              <DsSaveStatus
                state={autosave.status.state}
                at={autosave.status.at}
                onRetry={() => void autosave.flush()}
              />
            )}
            <div className="flex flex-wrap items-center justify-end gap-xs">
              {editingPublished ? (
                <>
                  <DsButton variant="link" onClick={() => void closeComposer()}>
                    Annuler
                  </DsButton>
                  <DsButton type="submit" variant="confirm" pending={savingEdit}>
                    {savingEdit ? "Enregistrement…" : "Enregistrer les modifications"}
                  </DsButton>
                </>
              ) : (
                <>
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
                      <DsButton variant="link" onClick={() => void closeComposer()}>
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
                </>
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
                onClick={() => void openNews(n)}
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
        {published.slice(0, recent.shown).map((n, i) => {
          const modifiedAt = newsModifiedAt(n);
          return (
            <div key={n.id} {...recent.itemProps(i)}>
              <DsListItem
                icon="article"
                title={n.title}
                meta={
                  <>
                    <span className="block">
                      Publiée {timeAgo(newsPublishedAt(n))} · Par {n.author}
                      {modifiedAt && ` · Modifiée le ${formatDay(modifiedAt)}`}
                    </span>
                    <NewsAudienceBadge news={n} className="mt-xs" />
                  </>
                }
                onClick={() => onRead(n)}
              />
            </div>
          );
        })}
        {published.length > 0 && (
          <DsShowMore
            {...recent}
            label="Voir plus d'actus"
            onMore={recent.more}
            onLess={recent.less}
          />
        )}
      </div>
      <ConfirmDialog
        open={confirmPublish}
        title={`Publier « ${title.trim()} » ?`}
        description={audienceSentence(audience)}
        confirmLabel="Publier"
        onCancel={() => setConfirmPublish(false)}
        onConfirm={async () => {
          setConfirmPublish(false);
          if (!editing) return;
          // Aucun enregistrement automatique ne doit arriver après la publication.
          if (onAutosave) await autosave.idle();
          onPublish({ ...draftInput(), id: editing.id }, done);
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
          done();
        }}
      />
    </DsSection>
  );
}
