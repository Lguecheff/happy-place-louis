import { DsButton, DsEmptyState, DsListItem } from "@/components/ds";
import type { NewsIdea, NewsIdeaKind } from "@/lib/news-ideas";

const SUBTITLE = "font-label-md text-label-md normal-case tracking-normal text-on-surface-variant";

const IDEA_ICONS: Record<NewsIdeaKind, string> = {
  demande: "task_alt",
  point: "lock_open",
  kpi: "trending_up",
};

/**
 * « Idées de sujets » (US26), managers seulement : 3 idées au plus, chacune avec
 * « Rédiger » (brouillon prérempli) et « Masquer » (retirée pour ce manager).
 */
export function NewsIdeas({
  ideas,
  isLoading,
  isError,
  disabled,
  onWrite,
  onDismiss,
  onFromTemplate,
}: {
  ideas: NewsIdea[];
  isLoading?: boolean;
  isError?: boolean;
  disabled?: boolean;
  onWrite: (idea: NewsIdea) => void;
  onDismiss: (idea: NewsIdea) => void;
  onFromTemplate: () => void;
}) {
  return (
    <div className="space-y-xs">
      <h3 id="idees-sujets" className={SUBTITLE}>
        Idées de sujets
      </h3>
      {isLoading && (
        <p className="font-body-sm text-body-sm text-on-surface-variant">Chargement…</p>
      )}
      {isError && (
        <p className="font-body-sm text-body-sm text-error">Les idées sont indisponibles.</p>
      )}
      {!isLoading && !isError && ideas.length === 0 && (
        <DsEmptyState
          action={
            <DsButton
              variant="link"
              icon="description"
              disabled={disabled}
              onClick={onFromTemplate}
            >
              Partir d'un modèle
            </DsButton>
          }
        >
          Pas d'idée pour le moment.
        </DsEmptyState>
      )}
      {ideas.length > 0 && (
        <ul aria-labelledby="idees-sujets" className="space-y-xs">
          {ideas.map((idea) => (
            <li key={idea.key}>
              <DsListItem
                icon={IDEA_ICONS[idea.kind]}
                title={idea.sentence}
                meta={idea.meta}
                actions={
                  <>
                    <DsButton
                      variant="link"
                      aria-label={`Masquer : ${idea.sentence}`}
                      disabled={disabled}
                      onClick={() => onDismiss(idea)}
                    >
                      Masquer
                    </DsButton>
                    <DsButton
                      icon="edit"
                      aria-label={`Rédiger : ${idea.sentence}`}
                      disabled={disabled}
                      onClick={() => onWrite(idea)}
                    >
                      Rédiger
                    </DsButton>
                  </>
                }
              />
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
