import { useRef, useState } from "react";
import { AttachmentLink } from "@/components/attachment-link";
import { ManagedSubmissions, ValidatedSubmissions } from "@/components/dashboard-extras";
import {
  DsAvatar,
  DsBadge,
  DsButton,
  DsEmptyState,
  DsIcon,
  DsListItem,
  DsSection,
} from "@/components/ds";
import { DS_FOCUS } from "@/components/ds/focus";
import { SubmissionPreview } from "@/components/expandable-card";
import { Linkify } from "@/components/linkify";
import { LONG_WAIT_DAYS, daysSince, formatDays } from "@/components/overview/overview-utils";
import type { Status } from "@/components/status-actions";
import { StatusChip } from "@/components/submission-status-thread";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { timeAgo, type Submission } from "@/lib/dashboard";
import type { AppRole } from "@/lib/auth";
import { cn } from "@/lib/utils";

type RequestList = { data?: Submission[]; isError: boolean; isLoading: boolean };

const TAB = cn(
  "min-h-11 rounded-none border-b-2 border-transparent px-sm font-label-md text-sm",
  "data-[state=active]:border-primary data-[state=active]:bg-transparent data-[state=active]:text-primary data-[state=active]:shadow-none",
  DS_FOCUS,
);

function ListStatus({ query, error }: { query: RequestList; error: string }) {
  if (query.isLoading)
    return <p className="font-body-sm text-body-sm text-on-surface-variant">Chargement…</p>;
  if (query.isError) return <p className="font-body-sm text-body-sm text-error">{error}</p>;
  return null;
}

function PendingRow({
  submission: s,
  busy,
  onValidate,
  onReject,
  onThread,
  onRead,
}: {
  submission: Submission;
  busy: boolean;
  onValidate: () => void;
  onReject: () => void;
  onThread: () => void;
  onRead: () => void;
}) {
  const days = daysSince(s.created_at);
  return (
    <DsListItem
      leading={<DsAvatar name={s.author_name} />}
      title={s.author_name}
      meta={s.team}
      actions={
        <>
          <DsButton
            variant="confirm"
            icon="check"
            disabled={busy}
            onClick={onValidate}
            aria-label={`Valider la demande de ${s.author_name}`}
          >
            Valider
          </DsButton>
          <DsButton
            aria-haspopup="dialog"
            onClick={onReject}
            aria-label={`Refuser la demande de ${s.author_name}`}
          >
            Refuser
          </DsButton>
          <DsButton
            variant="link"
            aria-haspopup="dialog"
            onClick={onThread}
            aria-label={`Voir le suivi de la demande de ${s.author_name}`}
          >
            Voir le suivi
          </DsButton>
        </>
      }
    >
      <p className="flex flex-wrap items-center gap-xs font-body-sm text-body-sm text-on-surface-variant">
        <span className="inline-flex items-center gap-1">
          <DsIcon name="schedule" className="text-base" />
          En attente depuis {formatDays(days)}
        </span>
        {days > LONG_WAIT_DAYS && <DsBadge variant="watch">Plus de {LONG_WAIT_DAYS} jours</DsBadge>}
      </p>
      <SubmissionPreview content={s.content} onOpen={onRead} />
      <AttachmentLink path={s.attachment_path} name={s.attachment_name} />
    </DsListItem>
  );
}

function MyRequests({
  query,
  onThread,
  onRead,
}: {
  query: RequestList;
  onThread: (s: Submission) => void;
  onRead: (s: Submission) => void;
}) {
  return (
    <div className="space-y-xs">
      <ListStatus query={query} error="Tes demandes sont indisponibles." />
      {query.data?.length === 0 && <DsEmptyState>Tu n'as encore aucune demande.</DsEmptyState>}
      {query.data?.map((s) => (
        <DsListItem
          key={s.id}
          title={<StatusChip status={s.status} />}
          meta={`${s.team} · Créée ${timeAgo(s.created_at)}`}
          actions={
            <DsButton variant="link" aria-haspopup="dialog" onClick={() => onThread(s)}>
              Voir le suivi
            </DsButton>
          }
        >
          <SubmissionPreview content={s.content} onOpen={() => onRead(s)} />
          <AttachmentLink path={s.attachment_path} name={s.attachment_name} />
          {s.status === "refusée" && s.rejection_category && (
            <div className="bg-error-container p-xs font-body-sm text-body-sm text-on-error-container wrap-anywhere">
              <p className="font-bold">Motif : {s.rejection_category}</p>
              <p className="whitespace-pre-line">
                Raison : <Linkify text={s.rejection_note ?? ""} />
              </p>
            </div>
          )}
        </DsListItem>
      ))}
    </div>
  );
}

export function RequestsSection({
  role,
  email,
  managerTeams,
  pending,
  mine,
  busy,
  onValidate,
  onReject,
  onThread,
  onRead,
  onChangeStatus,
}: {
  role: AppRole;
  email: string;
  managerTeams: string[];
  pending: RequestList;
  mine: RequestList;
  busy: boolean;
  onValidate: (s: Submission) => void;
  onReject: (s: Submission) => void;
  onThread: (s: Submission, editable: boolean) => void;
  onRead: (s: Submission) => void;
  onChangeStatus: (s: Submission, status: Status) => void;
}) {
  const canReview = role === "admin" || role === "manager";
  const [tab, setTab] = useState(canReview ? "a-traiter" : "mes-demandes");
  const managedTab = useRef<HTMLButtonElement>(null);
  // La plus ancienne en premier : c'est celle à traiter d'abord.
  const queue = [...(pending.data ?? [])].sort((a, b) => a.created_at.localeCompare(b.created_at));

  return (
    <DsSection
      id="demandes"
      title={canReview ? "Demandes à traiter" : "Demandes"}
      action={
        canReview && (
          <DsButton
            variant="link"
            className="px-0"
            onClick={() => {
              setTab("gerees");
              managedTab.current?.focus();
            }}
          >
            {role === "admin"
              ? "Voir toutes les demandes"
              : "Voir toutes les demandes de mon équipe"}
          </DsButton>
        )
      }
    >
      <Tabs value={tab} onValueChange={setTab}>
        <TabsList className="h-auto w-full flex-wrap justify-start gap-x-xs rounded-none border-b border-outline-variant bg-transparent p-0">
          {canReview && (
            <TabsTrigger value="a-traiter" className={TAB}>
              À traiter{pending.data ? ` (${pending.data.length})` : ""}
            </TabsTrigger>
          )}
          <TabsTrigger value="mes-demandes" className={TAB}>
            Mes demandes
          </TabsTrigger>
          {canReview && (
            <TabsTrigger ref={managedTab} value="gerees" className={TAB}>
              Gérées
            </TabsTrigger>
          )}
          <TabsTrigger value="validees" className={TAB}>
            Validées
          </TabsTrigger>
        </TabsList>
        {canReview && (
          <TabsContent value="a-traiter" className="mt-md space-y-xs">
            <ListStatus query={pending} error="Les demandes sont indisponibles." />
            {pending.data?.length === 0 && <DsEmptyState>Aucune demande à traiter.</DsEmptyState>}
            {queue.map((s) => (
              <PendingRow
                key={s.id}
                submission={s}
                busy={busy}
                onValidate={() => onValidate(s)}
                onReject={() => onReject(s)}
                onThread={() => onThread(s, true)}
                onRead={() => onRead(s)}
              />
            ))}
          </TabsContent>
        )}
        <TabsContent value="mes-demandes" className="mt-md">
          <MyRequests query={mine} onThread={(s) => onThread(s, false)} onRead={onRead} />
        </TabsContent>
        {canReview && (
          <TabsContent value="gerees" className="mt-md">
            <ManagedSubmissions
              onRead={onRead}
              onThread={(s) => onThread(s, true)}
              onChangeStatus={onChangeStatus}
            />
          </TabsContent>
        )}
        <TabsContent value="validees" className="mt-md">
          <ValidatedSubmissions
            role={role}
            email={email}
            managerTeams={managerTeams}
            onRead={onRead}
          />
        </TabsContent>
      </Tabs>
    </DsSection>
  );
}
