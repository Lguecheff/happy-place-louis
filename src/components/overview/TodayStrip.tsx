import { DsCount, DsStatTile } from "@/components/ds";
import type { Blocker, Submission } from "@/lib/dashboard";
import {
  NEWS_MONTHLY_TARGET,
  daysSince,
  formatDays,
  pendingSince,
  plural,
} from "@/components/overview/overview-utils";

function oldest(dates: string[]) {
  return dates.reduce<number>((max, iso) => Math.max(max, daysSince(iso)), 0);
}

function waitHint(pending: Submission[]) {
  return `La plus ancienne attend depuis ${formatDays(oldest(pending.map(pendingSince)))}`;
}

export function TodayStrip({
  canReview,
  pending,
  blockers,
  drafts,
  publishedCount,
}: {
  canReview: boolean;
  pending: Submission[] | undefined;
  blockers: Blocker[] | undefined;
  drafts: number;
  /** Sans valeur, l'indice des actus du mois n'est pas affiché. */
  publishedCount?: number;
}) {
  const waiting = pending?.length ?? 0;
  const critical = blockers?.filter((b) => b.severity === "critical") ?? [];
  const heading = canReview ? "À traiter" : "En cours";
  const total = waiting + critical.length + drafts;

  return (
    <section aria-labelledby="a-traiter-titre" className="space-y-sm">
      <h2
        id="a-traiter-titre"
        className="flex items-center gap-xs font-headline-sm text-headline-sm text-primary"
      >
        {heading}
        {canReview && pending && blockers && (
          <DsCount
            value={total}
            label={`${total} ${plural(total, "élément")} à traiter : ${waiting} ${plural(waiting, "demande")} en attente, ${critical.length} ${plural(critical.length, "point")} ${plural(critical.length, "bloquant")} ${plural(critical.length, "critique")} et ${drafts} ${plural(drafts, "brouillon")} à publier`}
          />
        )}
      </h2>
      <div className="grid gap-md md:grid-cols-3">
        {canReview ? (
          <>
            <DsStatTile
              value={pending ? waiting : "—"}
              label={`${plural(waiting, "demande")} en attente`}
              hint={pending && (waiting ? waitHint(pending) : "Aucune demande ne t'attend.")}
              href="#demandes"
              linkLabel="Voir les demandes"
            />
            <DsStatTile
              tone={critical.length ? "alert" : "default"}
              value={blockers ? critical.length : "—"}
              label={`${plural(critical.length, "point")} ${plural(critical.length, "bloquant")} ${plural(critical.length, "critique")}`}
              hint={
                blockers &&
                (critical.length
                  ? `Sans mise à jour depuis ${formatDays(oldest(critical.map((b) => b.updated_at)))}`
                  : "Aucun point critique en cours.")
              }
              href="#blocages"
              linkLabel="Voir les points bloquants"
            />
            <DsStatTile
              value={drafts}
              label={`${plural(drafts, "brouillon")} à publier`}
              hint={
                publishedCount === undefined
                  ? undefined
                  : `${publishedCount} sur ${NEWS_MONTHLY_TARGET} actus publiées ce mois-ci`
              }
              href="#actus"
              linkLabel="Voir les brouillons"
            />
          </>
        ) : (
          <DsStatTile
            value={pending ? waiting : "—"}
            label={`${plural(waiting, "demande")} en cours`}
            hint={pending && (waiting ? waitHint(pending) : "Tu n'as aucune demande en cours.")}
            href="#demandes"
            linkLabel="Voir mes demandes"
          />
        )}
      </div>
    </section>
  );
}
