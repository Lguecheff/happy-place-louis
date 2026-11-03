import { createFileRoute } from "@tanstack/react-router";
import { supabase } from "@/integrations/supabase/client";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useRef, useState } from "react";
import { flushSync } from "react-dom";
import { toast } from "sonner";
import { BrandHeader } from "@/components/brand-header";
import { BlockerArchive } from "@/components/dashboard-extras";
import { DepartureNotices } from "@/components/departure-notices";
import { DsButton, toastUndo } from "@/components/ds";
import { DS_FOCUS } from "@/components/ds/focus";
import { rejectionErrorMessage } from "@/components/expandable-card";
import { NewsReader } from "@/components/news-reader";
import { NotificationCenter } from "@/components/notifications/NotificationCenter";
import { useNotificationPreferences } from "@/components/notifications/useNotificationPreferences";
import { BlockersSection } from "@/components/overview/BlockersSection";
import { KpiSection } from "@/components/overview/KpiSection";
import {
  NewsSection,
  type DraftInput,
  type NewsSectionHandle,
} from "@/components/overview/NewsSection";
import { OverviewHeader } from "@/components/overview/OverviewHeader";
import { RejectModal } from "@/components/overview/RejectModal";
import { RequestFormModal } from "@/components/overview/RequestFormModal";
import { RequestsSection } from "@/components/overview/RequestsSection";
import { TodayStrip } from "@/components/overview/TodayStrip";
import { GlobalSearch } from "@/components/search/GlobalSearch";
import { useGlobalSearch } from "@/components/search/use-global-search";
import {
  canEditPublishedNews,
  myDrafts,
  publishedThisMonth,
} from "@/components/overview/overview-utils";
import { StatusButtons, type Status } from "@/components/status-actions";
import { SubmissionReader } from "@/components/submission-reader";
import { SubmissionThreadModal } from "@/components/submission-status-thread";
import {
  fetchBlockers,
  fetchMetrics,
  fetchNews,
  fetchSelectableTeams,
  fetchSubmissions,
  fetchMySubmissions,
  exportMyRecentSubmissions,
  type News,
  type Submission,
  saveDraftNews,
  saveAndPublishDraftNews,
  deleteDraftNews,
  updatePublishedNews,
  reviewSubmission,
  submitIdea,
  updateBlockerStatus,
  updateMetric,
  type SubmissionInput,
} from "@/lib/dashboard";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/_authenticated/")({
  head: () => ({
    meta: [
      { title: "Happy Place — Actualités et vue d'ensemble" },
      {
        name: "description",
        content:
          "Pilotez les missions de recrutement IT et digital, les propositions des équipes, les alertes opérationnelles et les indicateurs du cabinet.",
      },
      { property: "og:title", content: "Happy Place — Vue d'ensemble" },
      {
        property: "og:description",
        content:
          "Suivez l'activité du cabinet, les missions de recrutement, les alertes et les indicateurs clés.",
      },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary_large_image" },
    ],
  }),
  component: ManagerSpace,
});

function ManagerSpace() {
  const qc = useQueryClient();
  const { role, email, user } = Route.useRouteContext();
  const isAdmin = role === "admin";
  const canReview = role === "admin" || role === "manager";
  const myEmail = (email ?? "").toLowerCase();
  const meta = (user?.user_metadata ?? {}) as Record<string, unknown>;
  const metaName =
    (typeof meta.full_name === "string" && meta.full_name) ||
    (typeof meta.name === "string" && meta.name) ||
    "";
  const profile = useQuery({
    queryKey: ["allowed_users", "mine", myEmail],
    enabled: !!myEmail,
    queryFn: async () => {
      const { data, error } = await supabase
        .from("allowed_users")
        .select("first_name, last_name")
        .eq("email", myEmail)
        .maybeSingle();
      if (error) throw error;
      return data;
    },
  });
  const firstName = profile.data?.first_name ?? "";
  const accountName = [firstName, profile.data?.last_name].filter(Boolean).join(" ") || metaName;
  const myName = metaName || myEmail;
  const composerTitle = useRef<HTMLInputElement>(null);
  const newsSection = useRef<NewsSectionHandle>(null);
  const [composerOpen, setComposerOpen] = useState(false);
  const [requestOpen, setRequestOpen] = useState(false);
  const myTeams = useQuery({
    queryKey: ["manager_teams", "mine", email],
    enabled: role === "manager" && !!email,
    queryFn: async () => {
      const { data, error } = await supabase
        .from("manager_teams")
        .select("team, allowed_users!inner(email)")
        .eq("allowed_users.email", (email ?? "").toLowerCase());
      if (error) throw error;
      return (data ?? []).map((t) => t.team).sort();
    },
  });
  const selectableTeams = useQuery({
    queryKey: ["teams", "selectable"],
    enabled: isAdmin,
    queryFn: fetchSelectableTeams,
  });
  const audienceTeams = isAdmin ? selectableTeams : myTeams;
  const search = useGlobalSearch({ role, email: myEmail, managerTeams: myTeams.data ?? [] });
  const notificationPreferences = useNotificationPreferences(myEmail, role);
  const [rejecting, setRejecting] = useState<Submission | null>(null);
  const [reading, setReading] = useState<Submission | null>(null);
  const [threadOf, setThreadOf] = useState<Submission | null>(null);
  const [threadEditable, setThreadEditable] = useState(false);
  const [readingNews, setReadingNews] = useState<News | null>(null);
  const [archiveOpen, setArchiveOpen] = useState(false);

  const news = useQuery({ queryKey: ["news"], queryFn: fetchNews, retry: false });
  const submissions = useQuery({
    queryKey: ["submissions"],
    queryFn: fetchSubmissions,
    retry: false,
  });
  const mine = useQuery({
    queryKey: ["submissions", "mine", email],
    queryFn: () => fetchMySubmissions(email ?? ""),
    enabled: !!email,
    retry: false,
  });
  const blockers = useQuery({ queryKey: ["blockers"], queryFn: fetchBlockers, retry: false });
  const metrics = useQuery({ queryKey: ["metrics"], queryFn: fetchMetrics, retry: false });
  const onError = (e: unknown) => toast.error((e as Error).message);

  const exportReport = useMutation({
    mutationFn: () => {
      if (!email) throw new Error("Ton adresse e-mail est indisponible.");
      return exportMyRecentSubmissions(email);
    },
    onSuccess: (count) => {
      if (count === 0) {
        toast.info("Aucune demande en attente ou validée sur les 30 derniers jours.");
        return;
      }
      toast.success(
        `${count} demande${count > 1 ? "s" : ""} exportée${count > 1 ? "s" : ""} au format CSV.`,
      );
    },
    onError,
  });

  const saveDraft = useMutation({
    mutationFn: saveDraftNews,
    onSuccess: () => {
      toast.success("Brouillon enregistré");
      qc.invalidateQueries({ queryKey: ["news"] });
    },
    onError,
  });

  const publishDraft = useMutation({
    mutationFn: saveAndPublishDraftNews,
    onSuccess: () => {
      toast.success("Actualité publiée");
      qc.invalidateQueries({ queryKey: ["news"] });
    },
    onError,
  });

  const editPublished = useMutation({
    mutationFn: updatePublishedNews,
    onSuccess: () => {
      toast.success("Actualité modifiée");
      qc.invalidateQueries({ queryKey: ["news"] });
    },
    onError,
  });

  const removeDraft = useMutation({
    mutationFn: (n: { id: string; image_path?: string | null }) =>
      deleteDraftNews(n.id, n.image_path),
    onSuccess: () => {
      toast.success("Brouillon supprimé");
      qc.invalidateQueries({ queryKey: ["news"] });
    },
    onError,
  });

  const review = useMutation({
    mutationFn: reviewSubmission,
    onSuccess: (_d, vars) => {
      if (vars.status === "refusée") {
        setRejecting(null);
        toast.success("Demande refusée");
      } else {
        setReading((r) => (r?.id === vars.id ? null : r));
      }
      if (vars.status === "validée") {
        toastUndo("Demande validée", () => review.mutate({ id: vars.id, status: "en attente" }));
      }
      qc.invalidateQueries({ queryKey: ["submissions"] });
    },
    onError: (e: unknown) => toast.error(rejectionErrorMessage(e)),
  });

  /** Changement de statut depuis le fil ou la liste : « refusée » passe par la fenêtre de motif. */
  function changeStatus(s: Submission, status: Status) {
    if (status === "refusée") startReject(s);
    else review.mutate({ id: s.id, status });
  }

  /** Comme dans « À traiter » : un manager change le statut des demandes de ses équipes. */
  function canChangeStatus(s: Submission) {
    return role === "manager" && (myTeams.data ?? []).includes(s.team);
  }

  function openThread(s: Submission, editable: boolean) {
    setThreadEditable(editable);
    setThreadOf(s);
  }

  function startReject(s: Submission) {
    setReading(null);
    setRejecting(s);
  }

  const submit = useMutation({
    mutationFn: ({ input, file }: { input: SubmissionInput; file: File | null }) =>
      submitIdea(
        {
          author_name: input.author_name,
          team: input.team,
          content: input.content,
        },
        file,
      ),
    onSuccess: () => {
      setRequestOpen(false);
      toast.success("Demande envoyée");
      qc.invalidateQueries({ queryKey: ["submissions"] });
    },
    onError: (e: unknown) => toast.error(rejectionErrorMessage(e)),
  });

  const setBlocker = useMutation({
    mutationFn: updateBlockerStatus,
    onSuccess: () => qc.invalidateQueries({ queryKey: ["blockers"] }),
    onError,
  });

  const saveMetric = useMutation({
    mutationFn: updateMetric,
    onSuccess: () => {
      toast.success("KPI mis à jour");
      qc.invalidateQueries({ queryKey: ["metrics"] });
    },
    onError,
  });

  const myBlockers = isAdmin
    ? blockers.data
    : blockers.data &&
      myTeams.data &&
      blockers.data.filter((b) => !b.team || myTeams.data.includes(b.team));
  // Managers seulement, et une fois les actus chargées : sinon le compteur afficherait un faux 0.
  const publishedCount =
    role === "manager" && news.data ? publishedThisMonth(news.data, myEmail) : undefined;
  const drafts = myDrafts(news.data ?? [], myEmail).length;

  function openComposer() {
    flushSync(() => setComposerOpen(true));
    composerTitle.current?.focus();
  }

  function saveNews(input: DraftInput, onSaved: () => void) {
    saveDraft.mutate({ ...input, author: myName, author_email: myEmail }, { onSuccess: onSaved });
  }

  function publishNews(input: DraftInput & { id: string }, onPublished: () => void) {
    publishDraft.mutate(
      { ...input, author: myName, author_email: myEmail },
      { onSuccess: onPublished },
    );
  }

  const canEditNews = (n: News) => canEditPublishedNews(n, role, myEmail);
  const editNews = (n: News) => newsSection.current?.editPublished(n);

  return (
    <div className="bg-background text-on-surface font-body-md min-h-screen flex flex-col">
      <a
        href="#contenu"
        className={cn(
          "sr-only focus-visible:not-sr-only focus-visible:absolute focus-visible:left-sm focus-visible:top-xs focus-visible:z-50 focus-visible:bg-primary focus-visible:px-md focus-visible:py-sm focus-visible:font-label-md focus-visible:text-sm focus-visible:text-on-primary",
          DS_FOCUS,
        )}
      >
        Aller au contenu
      </a>
      <BrandHeader>
        <OverviewHeader
          isAdmin={isAdmin}
          name={accountName || myEmail}
          role={role}
          exporting={exportReport.isPending}
          onExport={() => exportReport.mutate()}
          preferences={notificationPreferences}
          search={<GlobalSearch {...search} canEditNews={canEditNews} onEditNews={editNews} />}
          notifications={
            myEmail && (
              <NotificationCenter
                email={myEmail}
                onOpenSubmission={(s) => openThread(s, canChangeStatus(s))}
              />
            )
          }
        />
      </BrandHeader>
      <main
        id="contenu"
        tabIndex={-1}
        className="flex-grow w-full max-w-interface mx-auto p-sm md:p-md space-y-md focus:outline-none"
      >
        {email && <DepartureNotices email={email} />}
        <div className="flex flex-wrap items-end justify-between gap-sm">
          <div className="min-w-0 space-y-xs">
            <h1 className="font-headline-lg text-headline-lg text-primary wrap-anywhere">
              Bonjour{firstName || accountName ? ` ${firstName || accountName}` : ""}
            </h1>
            <p className="font-body-md text-body-md text-on-surface-variant">
              Voici ce qui demande ton attention aujourd'hui.
            </p>
          </div>
          <div className="flex flex-wrap gap-xs">
            <DsButton
              variant={canReview ? "secondary" : "primary"}
              aria-haspopup="dialog"
              onClick={() => setRequestOpen(true)}
            >
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
          pending={submissions.data}
          blockers={myBlockers}
          drafts={drafts}
          publishedCount={publishedCount}
        />

        <div className="flex flex-wrap items-start gap-md">
          <div className="flex min-w-0 flex-[999_1_620px] flex-col gap-md">
            <RequestsSection
              role={role}
              email={myEmail}
              managerTeams={myTeams.data ?? []}
              pending={submissions}
              mine={mine}
              busy={review.isPending}
              onValidate={(s) => review.mutate({ id: s.id, status: "validée" })}
              onReject={startReject}
              onThread={openThread}
              onRead={setReading}
              onChangeStatus={changeStatus}
            />
            <NewsSection
              editRef={newsSection}
              canWrite={canReview}
              email={myEmail}
              news={news}
              audienceTeams={audienceTeams.data ?? []}
              audienceScope={isAdmin ? "all" : "mine"}
              audienceTeamsNotice={
                audienceTeams.isLoading
                  ? "Chargement des équipes…"
                  : audienceTeams.isError
                    ? "Les équipes sont indisponibles."
                    : undefined
              }
              publishedCount={publishedCount}
              composerOpen={composerOpen}
              onComposerOpenChange={setComposerOpen}
              titleRef={composerTitle}
              saving={saveDraft.isPending}
              publishing={publishDraft.isPending}
              removing={removeDraft.isPending}
              onSave={saveNews}
              onPublish={publishNews}
              onRemove={(n) => removeDraft.mutate(n)}
              onRead={setReadingNews}
              savingEdit={editPublished.isPending}
              onSaveEdit={(input, onSaved) => editPublished.mutate(input, { onSuccess: onSaved })}
            />
          </div>
          <div className="flex min-w-0 flex-[1_1_380px] flex-col gap-md">
            <BlockersSection
              blockers={blockers}
              canEdit={isAdmin}
              onStatusChange={(id, status) => setBlocker.mutate({ id, status })}
              onOpenArchive={() => setArchiveOpen(true)}
            />
            <KpiSection
              metrics={metrics}
              canEditNps={isAdmin}
              savingNps={saveMetric.isPending}
              onSaveNps={(value) => saveMetric.mutate({ key: "nps", value })}
            />
          </div>
        </div>
      </main>
      <BlockerArchive open={archiveOpen} onClose={() => setArchiveOpen(false)} />
      {threadOf && !rejecting && (
        <SubmissionThreadModal
          submission={threadOf}
          actions={
            canReview && threadEditable
              ? (current) => (
                  <StatusButtons current={current} onPick={(st) => changeStatus(threadOf, st)} />
                )
              : undefined
          }
          onClose={() => setThreadOf(null)}
        />
      )}
      <NewsReader
        news={readingNews}
        onClose={() => setReadingNews(null)}
        onEdit={readingNews && canEditNews(readingNews) ? () => editNews(readingNews) : undefined}
      />
      <SubmissionReader
        submission={reading}
        onClose={() => setReading(null)}
        onReject={
          reading && canReview && reading.status !== "refusée"
            ? () => startReject(reading)
            : undefined
        }
        statusActions={
          reading && canReview
            ? (
                [
                  { status: "validée", label: "Valider" },
                  { status: "clôturée", label: "Clôturer" },
                  { status: "en attente", label: "Remettre en attente" },
                ] as const
              )
                .filter((a) => a.status !== reading.status)
                .map((a) => ({
                  label: a.label,
                  onClick: () => review.mutate({ id: reading.id, status: a.status }),
                }))
            : undefined
        }
        approving={review.isPending}
      />
      {rejecting && (
        <RejectModal
          submission={rejecting}
          pending={review.isPending}
          onCancel={() => setRejecting(null)}
          onSubmit={(reason) => review.mutate({ id: rejecting.id, status: "refusée", ...reason })}
        />
      )}
      {requestOpen && (
        <RequestFormModal
          role={role}
          teams={myTeams.data ?? []}
          defaultName={accountName}
          pending={submit.isPending}
          onCancel={() => setRequestOpen(false)}
          onSubmit={(input, file) => submit.mutate({ input, file })}
        />
      )}
    </div>
  );
}
