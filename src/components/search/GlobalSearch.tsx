import { Command as CommandPrimitive } from "cmdk";
import { useEffect, useMemo, useRef, useState, type KeyboardEvent, type ReactNode } from "react";
import { DS_INPUT, DsBadge, DsIcon } from "@/components/ds";
import { NewsReader } from "@/components/news-reader";
import { formatDay, newsPublishedAt, plural } from "@/components/overview/overview-utils";
import { SubmissionReader } from "@/components/submission-reader";
import { StatusChip } from "@/components/submission-status-thread";
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandItem,
  CommandList,
} from "@/components/ui/command";
import type { News, Submission } from "@/lib/dashboard";
import { cn } from "@/lib/utils";
import {
  SEARCH_MAX_PER_TYPE,
  SEARCH_MIN_LENGTH,
  excerptAround,
  highlightParts,
  isSearchable,
  matchesTerm,
  searchAll,
  type SearchData,
} from "./search-utils";

const DEBOUNCE_MS = 250;

export type SearchSource = { data?: SearchData; isError: boolean; isLoading: boolean };

function Highlighted({ text, query }: { text: string; query: string }) {
  return highlightParts(text, query).map((part, i) =>
    part.match ? (
      <mark key={i} className="bg-secondary-fixed font-semibold text-on-surface">
        {part.text}
      </mark>
    ) : (
      part.text
    ),
  );
}

function GroupHeading({ label, total }: { label: string; total: number }) {
  return (
    <span className="block px-sm pb-1 pt-xs font-label-md text-label-md normal-case tracking-normal text-on-surface-variant">
      {label} ({total})
      {total > SEARCH_MAX_PER_TYPE && ` · ${SEARCH_MAX_PER_TYPE} premiers résultats affichés`}
    </span>
  );
}

function ResultRow({
  value,
  icon,
  title,
  excerpt,
  meta,
  status,
  onSelect,
}: {
  value: string;
  icon: string;
  title: ReactNode;
  excerpt?: ReactNode;
  meta: string;
  status: ReactNode;
  onSelect: () => void;
}) {
  return (
    <CommandItem
      value={value}
      onSelect={onSelect}
      className={cn(
        "min-h-11 cursor-pointer items-start gap-sm rounded-none px-sm py-xs",
        "data-[selected=true]:bg-surface-container data-[selected=true]:outline-2 data-[selected=true]:-outline-offset-2 data-[selected=true]:outline-primary",
      )}
    >
      <DsIcon name={icon} className="shrink-0 text-on-surface-variant" />
      <span className="min-w-0 flex-1">
        <span className="block font-body-md text-body-md text-primary wrap-anywhere">{title}</span>
        {excerpt && (
          <span className="block font-body-sm text-body-sm text-on-surface wrap-anywhere">
            {excerpt}
          </span>
        )}
        <span className="block font-body-sm text-body-sm text-on-surface-variant">{meta}</span>
      </span>
      <span className="shrink-0">{status}</span>
    </CommandItem>
  );
}

/** Barre de recherche de l'en-tête. Le filtre se fait ici, sur les données lues sous RLS. */
export function GlobalSearch({
  source,
  canReadAttachment,
  defaultQuery = "",
  className,
}: {
  source: SearchSource;
  /** Sans valeur, la pièce jointe d'une demande est proposée à tout le monde. */
  canReadAttachment?: (submission: Submission) => boolean;
  /** Terme déjà saisi à l'ouverture de la page (panneau ouvert et champ actif). */
  defaultQuery?: string;
  className?: string;
}) {
  const [query, setQuery] = useState(defaultQuery);
  const [term, setTerm] = useState(defaultQuery);
  const [open, setOpen] = useState(!!defaultQuery);
  const [selected, setSelected] = useState("");
  const [readingNews, setReadingNews] = useState<News | null>(null);
  const [readingSubmission, setReadingSubmission] = useState<Submission | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const timer = setTimeout(() => setTerm(query), DEBOUNCE_MS);
    return () => clearTimeout(timer);
  }, [query]);

  const { data, isError, isLoading } = source;
  const searchable = isSearchable(term);
  const results = useMemo(
    () => (searchable && data ? searchAll(data, term) : null),
    [data, searchable, term],
  );
  const total = results ? results.news.total + results.submissions.total : 0;
  const firstValue = results?.news.items[0]
    ? `actu-${results.news.items[0].id}`
    : results?.submissions.items[0]
      ? `demande-${results.submissions.items[0].id}`
      : "";

  // cmdk ne filtre plus : la première ligne doit être choisie ici à chaque nouvelle liste.
  useEffect(() => setSelected(firstValue), [firstValue]);

  const panelOpen = open && !!query.trim();
  const trimmedTerm = term.trim();
  let message = "";
  if (!searchable) message = `Saisis au moins ${SEARCH_MIN_LENGTH} caractères`;
  else if (isError) message = "La recherche n'est pas disponible pour le moment.";
  else if (isLoading) message = "Recherche en cours…";
  else if (results && total === 0) message = `Aucun résultat pour « ${trimmedTerm} »`;

  function onKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    if (event.key === "Escape" && panelOpen) {
      event.preventDefault();
      setOpen(false);
    } else if (!panelOpen && (event.key === "Enter" || event.key === "ArrowUp")) {
      event.preventDefault();
    } else if (!panelOpen && event.key === "ArrowDown") {
      event.preventDefault();
      setOpen(true);
    }
  }

  function focusInput(event: Event) {
    event.preventDefault();
    inputRef.current?.focus();
  }

  function openNews(news: News) {
    setOpen(false);
    setReadingNews(news);
  }

  function openSubmission(submission: Submission) {
    setOpen(false);
    setReadingSubmission(submission);
  }

  return (
    <>
      <Command
        role="search"
        label="Rechercher dans Happy Place"
        shouldFilter={false}
        loop
        value={selected}
        onValueChange={setSelected}
        onKeyDown={onKeyDown}
        onBlur={(e) => {
          if (!e.currentTarget.contains(e.relatedTarget)) setOpen(false);
        }}
        className={cn(
          "relative h-auto min-w-0 flex-1 overflow-visible rounded-none bg-transparent",
          className,
        )}
      >
        <DsIcon
          name="search"
          className="pointer-events-none absolute left-sm top-1/2 -translate-y-1/2 text-on-surface-variant"
        />
        <CommandPrimitive.Input
          ref={inputRef}
          autoFocus={!!defaultQuery}
          value={query}
          onValueChange={(value) => {
            setQuery(value);
            setOpen(true);
          }}
          onClick={() => setOpen(true)}
          placeholder="Rechercher une actu ou une demande"
          className={cn(DS_INPUT, "truncate pl-10")}
        />
        <div
          // Un clic dans le panneau ne doit pas retirer le focus du champ.
          onMouseDown={(e) => e.preventDefault()}
          hidden={!panelOpen}
          className="absolute left-0 top-full z-40 mt-xs w-full min-w-[min(32rem,calc(100vw-1.5rem))] border border-outline bg-surface-container-lowest xl:left-auto xl:right-0"
        >
          <CommandList className="max-h-[min(28rem,70vh)]">
            <CommandEmpty className="p-sm font-body-md text-body-md text-on-surface-variant wrap-anywhere">
              {message}
            </CommandEmpty>
            {results && results.news.total > 0 && (
              <CommandGroup
                heading={<GroupHeading label="Actus" total={results.news.total} />}
                className="p-0"
              >
                {results.news.items.map((n) => (
                  <ResultRow
                    key={n.id}
                    value={`actu-${n.id}`}
                    icon="article"
                    title={<Highlighted text={n.title} query={term} />}
                    excerpt={
                      n.body && !matchesTerm(n.title, term) ? (
                        <Highlighted text={excerptAround(n.body, term)} query={term} />
                      ) : undefined
                    }
                    meta={`Actu · ${formatDay(newsPublishedAt(n))}`}
                    status={<DsBadge variant="status">Publiée</DsBadge>}
                    onSelect={() => openNews(n)}
                  />
                ))}
              </CommandGroup>
            )}
            {results && results.submissions.total > 0 && (
              <CommandGroup
                heading={<GroupHeading label="Demandes" total={results.submissions.total} />}
                className="p-0"
              >
                {results.submissions.items.map((s) => (
                  <ResultRow
                    key={s.id}
                    value={`demande-${s.id}`}
                    icon="inbox"
                    title={<Highlighted text={excerptAround(s.content, term)} query={term} />}
                    meta={`Demande · ${formatDay(s.created_at)}`}
                    status={<StatusChip status={s.status} />}
                    onSelect={() => openSubmission(s)}
                  />
                ))}
              </CommandGroup>
            )}
          </CommandList>
        </div>
        <p role="status" className="sr-only">
          {panelOpen && (message || `${total} ${plural(total, "résultat")}`)}
        </p>
      </Command>
      <NewsReader
        news={readingNews}
        onClose={() => setReadingNews(null)}
        onCloseAutoFocus={focusInput}
      />
      <SubmissionReader
        submission={readingSubmission}
        hideAttachment={!!readingSubmission && canReadAttachment?.(readingSubmission) === false}
        onClose={() => setReadingSubmission(null)}
        onCloseAutoFocus={focusInput}
      />
    </>
  );
}
