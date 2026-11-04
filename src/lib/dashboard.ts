import { loadBrowserLib } from "@/lib/browser-lib";
import type { Database, Json, Tables } from "@/integrations/supabase/types";
import type { NewsAudience, NewsAudienceValue } from "@/lib/news-audience";
import {
  applyNewsImage,
  mediaFromNews,
  removeNewsImageFile,
  saveWithNewsImage,
  toNewsLinks,
  type MediaDraft,
  type NewsLink,
} from "@/lib/news-media";
import { supabase } from "@/integrations/supabase/client";

export const db = supabase;

type Enums = Database["public"]["Enums"];


export type News = {
  id: string;
  title: string;
  body: string | null;
  author: string;
  author_email?: string | null;
  status: string;
  created_at: string;
  /** Renseignées par la base (migration 20261030100000_dates_actus). */
  updated_at?: string | null;
  published_at?: string | null;
  image_path?: string | null;
  links?: unknown;
  /** Vide tant que l'auteur d'un brouillon n'a pas choisi (migration 20261102090000_public_des_actus). */
  audience?: NewsAudience | null;
  teams?: string[];
};

export type Submission = {
  id: string;
  author_name: string;
  team: string;
  content: string;
  status: string;
  created_at: string;
  /** Dernier changement de statut d'une demande en attente, lu dans l'historique (`withPendingSince`). */
  pending_since?: string;
  rejection_category?: string | null;
  rejection_note?: string | null;
  submitted_by_email?: string | null;
  attachment_path?: string | null;
  attachment_name?: string | null;
  /** Dernière confirmation « à jour » (US21) ; son auteur est dans `submission_verifications`. */
  verified_at?: string | null;
};

export const REJECTION_CATEGORIES = [
  "à clarifier",
  "en désaccord avec les process",
  "doublon",
  "autre",
] as const;
export type RejectionCategory = (typeof REJECTION_CATEGORIES)[number];

export type Blocker = {
  id: string;
  title: string;
  description: string | null;
  /** Ancien pôle : ni saisi ni affiché depuis l'US19. */
  department?: string | null;
  /** Équipes concernées ; vide, le point concerne toutes les équipes. */
  teams: string[];
  /** « Ce que ça change pour toi », saisi par l'admin ; vide, le bloc n'apparaît pas. */
  impact?: string | null;
  severity: string;
  status: string;
  created_at: string;
  updated_at: string;
  /** Nom copié par la base à chaque modification (US20) ; vide pour les points plus anciens. */
  updated_by_name?: string | null;
  /** Dernière relance des équipes (US21) ; ne compte que si elle suit la dernière modification. */
  reminded_at?: string | null;
  reminded_by_name?: string | null;
};

export type Metric = {
  key: string;
  label: string;
  value: number;
  unit: string | null;
  trend: "hausse" | "baisse" | "stable";
  previous_value: number | null;
  delta: number | string | null;
  updated_at: string;
  /** Nom copié par la base à chaque modification (US20) ; vide pour les KPI plus anciens. */
  updated_by_name?: string | null;
  /**
   * Plage attendue (US21) : hors de [threshold_min, threshold_max] depuis plus de
   * stale_after_days jours, le KPI porte « À vérifier ». Sans seuil, jamais de badge.
   */
  threshold_min?: number | null;
  threshold_max?: number | null;
  stale_after_days?: number | null;
  /** Début de la période hors plage en cours, lu dans l'historique par la base ; vide dans la plage. */
  out_of_range_since?: string | null;
  /** Date du dernier « Marquer comme vérifié » (US21) ; égale à updated_at tant que rien n'a changé depuis. */
  verified_at?: string | null;
  /** « Ce que ça mesure » (US18). */
  definition: string | null;
  /** « Ce que ça change pour toi » (US18). */
  impact: string | null;
};

export const TREND_LABELS: Record<Metric["trend"], string> = {
  hausse: "▲ En hausse",
  baisse: "▼ En baisse",
  stable: "■ Stable",
};

const TREND_DIRECTIONS = { hausse: "up", baisse: "down", stable: "flat" } as const;

/** Tendance d'un KPI pour `DsKpiTile` : le symbole de TREND_LABELS cède la place à sa flèche. */
export function metricTrend(m: Metric) {
  const trend = TREND_LABELS[m.trend].replace(/^\S+\s/, "");
  const delta = deltaText(m);
  return {
    trend: delta ? `${trend} · ${delta}` : trend,
    trendDirection: TREND_DIRECTIONS[m.trend],
  };
}

export function deltaText(m: Pick<Metric, "delta" | "unit"> | undefined): string {
  if (!m || m.delta == null) return "";
  const delta = Number(m.delta);
  if (!Number.isFinite(delta) || delta === 0) return "";
  const abs = Math.abs(delta).toLocaleString("fr-FR", { maximumFractionDigits: 1 });
  const sign = delta > 0 ? "+" : "−";
  const suffix = m.unit === "%" ? " pts" : m.unit ? ` ${m.unit.trim()}` : "";
  return `${sign}${abs}${suffix}`;
}

/** Borne d'une plage : sans décimale inutile (« 60 % », « 150 »). */
export function formatThreshold(value: number, unit: string | null): string {
  const formatted = value.toLocaleString("fr-FR", { maximumFractionDigits: 1 });
  return unit === "%" ? `${formatted} %` : `${formatted}${unit ?? ""}`;
}

export function formatMetricValue(value: number | string, unit: string | null): string {
  const formatted = Number(value).toLocaleString("fr-FR", {
    minimumFractionDigits: unit === "%" ? 1 : 0,
    maximumFractionDigits: 1,
  });
  return `${formatted}${unit ?? ""}`;
}

function toNews({
  news_teams,
  ...news
}: Database["public"]["Tables"]["news"]["Row"] & { news_teams: { team: string }[] }): News {
  return { ...news, teams: news_teams.map((t) => t.team).sort() };
}

export async function fetchNews(): Promise<News[]> {
  const { data, error } = await db
    .from("news")
    .select("*, news_teams(team)")
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data ?? []).map(toNews);
}

/** Équipes qu'un admin peut cibler : tout le référentiel, sauf « Admin ». */
export async function fetchSelectableTeams() {
  const { data, error } = await db
    .from("teams")
    .select("name")
    .eq("is_reserved", false)
    .order("name");
  if (error) throw error;
  return data.map((t) => t.name);
}

async function saveNewsAudience(id: string, { audience, teams }: NewsAudienceValue) {
  const { error } = await db.rpc("save_news_audience", {
    _news_id: id,
    _audience: audience,
    _teams: teams,
  });
  if (error) throw error;
}

export type DraftNewsContent = {
  id?: string;
  title: string;
  body: string;
  author: string;
  author_email: string;
  links: NewsLink[];
  audience: NewsAudienceValue;
};

/**
 * Enregistrement automatique : crée le brouillon sans id, le met à jour avec un id,
 * et renvoie l'id. L'image n'est pas touchée (elle part avec « Enregistrer le brouillon »).
 */
export async function autosaveDraftNews(input: DraftNewsContent): Promise<string> {
  const payload = {
    title: input.title,
    body: input.body,
    author: input.author,
    author_email: input.author_email.toLowerCase(),
    status: "brouillon" as const,
    links: input.links as unknown as Json,
  };
  const { data, error } = input.id
    ? await db.from("news").update(payload).eq("id", input.id).select("id").single()
    : await db.from("news").insert(payload).select("id").single();
  if (error) throw error;
  await saveNewsAudience(data.id, input.audience);
  return data.id;
}

/** Enregistre le brouillon avec son image et renvoie son id. */
export async function saveDraftNews(input: DraftNewsContent & { media: MediaDraft }) {
  const id = await autosaveDraftNews(input);
  await applyNewsImage(id, input.media);
  return id;
}

export async function publishDraftNews(id: string) {
  const { data, error } = await db
    .from("news")
    .update({ status: "publiée" })
    .eq("id", id)
    .eq("status", "brouillon")
    .select("id");
  if (error) throw error;
  if (!data?.length) throw new Error("Vous n'avez pas le droit de publier cette actualité.");
}

/** Enregistre le brouillon ouvert dans le rédacteur, puis le publie. */
export async function saveAndPublishDraftNews(
  input: Parameters<typeof saveDraftNews>[0] & { id: string },
) {
  await saveDraftNews(input);
  await publishDraftNews(input.id);
}

export type PublishedNewsInput = {
  id: string;
  title: string;
  body: string;
  links: NewsLink[];
  media: MediaDraft;
  audience: NewsAudienceValue;
};

/** Modifie une actu publiée : elle reste publiée, avec le même auteur et la même date de publication. */
export async function updatePublishedNews(input: PublishedNewsInput) {
  const { id, title, body, links, media, audience } = input;
  await saveWithNewsImage(id, media, async (imagePath) => {
    const { error } = await db.rpc("save_published_news", {
      _news_id: id,
      _title: title,
      _body: body,
      _links: links as unknown as Json,
      _image_path: imagePath,
      _audience: audience.audience as NewsAudience,
      _teams: audience.teams,
    });
    if (error) throw error;
  });
}

/** Évite de marquer « Modifiée le » une actu enregistrée sans aucun changement. */
export function isNewsUnchanged(n: News, input: Omit<PublishedNewsInput, "id">) {
  const content = (
    title: string,
    body: string,
    links: NewsLink[],
    { audience, teams }: NewsAudienceValue,
  ) => JSON.stringify([title, body, links, audience, [...teams].sort()]);
  return (
    !input.media.file &&
    !input.media.removeExisting &&
    content(input.title.trim(), input.body.trim(), input.links, input.audience) ===
      content(n.title.trim(), (n.body ?? "").trim(), toNewsLinks(mediaFromNews(n).links), {
        audience: n.audience ?? null,
        teams: n.teams ?? [],
      })
  );
}

export async function deleteDraftNews(id: string, imagePath?: string | null) {
  await removeNewsImageFile(imagePath);
  const { data, error } = await db.from("news").delete().eq("id", id).select("id");
  if (error) throw error;
  if (!data?.length) throw new Error("Vous n'avez pas le droit de supprimer cette actualité.");
}

/**
 * Ajoute `pending_since` (dernier changement de statut) aux demandes en attente : `submissions`
 * n'a pas de date de mise à jour, l'historique note chaque changement de statut. La RLS de
 * l'historique suit celle des demandes : chacun lit l'historique des demandes qu'il voit.
 */
async function withPendingSince(submissions: Submission[]): Promise<Submission[]> {
  const ids = submissions.filter((s) => s.status === "en attente").map((s) => s.id);
  if (!ids.length) return submissions;
  const { data: history, error } = await db
    .from("submission_status_history")
    .select("submission_id, changed_at")
    .in("submission_id", ids)
    .order("changed_at", { ascending: true });
  if (error) throw error;
  const lastChange = new Map((history ?? []).map((h) => [h.submission_id, h.changed_at]));
  return submissions.map((s) =>
    lastChange.has(s.id) ? { ...s, pending_since: lastChange.get(s.id) } : s,
  );
}

export async function fetchSubmissions(): Promise<Submission[]> {
  const { data, error } = await db
    .from("submissions")
    .select("*")
    .eq("status", "en attente")
    .order("created_at", { ascending: false });
  if (error) throw error;
  return withPendingSince((data ?? []) as Submission[]);
}

/**
 * Demandes de tous statuts visibles du manager (ses équipes), pour corriger un statut.
 * Chargées en entier : l'onglet « Gérées » les affiche 10 par 10 (US24).
 */
export async function fetchManagedSubmissions(): Promise<Submission[]> {
  const { data, error } = await db
    .from("submissions")
    .select("*")
    .order("created_at", { ascending: false });
  if (error) throw error;
  return withPendingSince((data ?? []) as Submission[]);
}

/** Toutes les demandes que la RLS laisse lire, pour la recherche : ni filtre ni limite ici. */
export async function fetchSearchableSubmissions(): Promise<Submission[]> {
  const { data, error } = await db
    .from("submissions")
    .select("*")
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as Submission[];
}

/** Toutes mes demandes : « Mes demandes » les affiche 10 par 10 (US24). */
export async function fetchMySubmissions(email: string): Promise<Submission[]> {
  const { data, error } = await db
    .from("submissions")
    .select("*")
    .ilike("submitted_by_email", email)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return withPendingSince((data ?? []) as Submission[]);
}

function csvCell(value: string) {
  return `"${value.replaceAll('"', '""')}"`;
}

export async function exportMyRecentSubmissions(email: string): Promise<number> {
  const since = new Date();
  since.setDate(since.getDate() - 30);

  const { data, error } = await db
    .from("submissions")
    .select("created_at,author_name,submitted_by_email,team,content,status")
    .ilike("submitted_by_email", email)
    .in("status", ["en attente", "validée"])
    .gte("created_at", since.toISOString())
    .order("created_at", { ascending: false });
  if (error) throw error;

  const rows = data ?? [];
  if (rows.length === 0) return 0;

  const header = ["Date", "Auteur", "E-mail", "Équipe", "Question soumise", "Statut"];
  const csv = [
    header.map(csvCell).join(";"),
    ...rows.map((row) =>
      [
        new Date(row.created_at).toLocaleString("fr-FR"),
        row.author_name,
        row.submitted_by_email ?? "",
        row.team,
        row.content,
        row.status,
      ].map((value) => csvCell(String(value))).join(";"),
    ),
  ].join("\r\n");

  const blob = new Blob(["\uFEFF", csv], { type: "text/csv;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = `soumissions-30-jours-${new Date().toISOString().slice(0, 10)}.csv`;
  document.body.appendChild(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 10000);
  return rows.length;
}

export async function reviewSubmission(
  input:
    | { id: string; status: "en attente" | "validée" | "clôturée" }
    | { id: string; status: "refusée"; rejection_category: RejectionCategory; rejection_note: string },
) {
  const patch =
    input.status === "refusée"
      ? { status: input.status, rejection_category: input.rejection_category, rejection_note: input.rejection_note.trim() }
      : { status: input.status, rejection_category: null, rejection_note: null };
  const { error } = await db
    .from("submissions")
    .update(patch)
    .eq("id", input.id);
  if (error) throw error;
}

const BLOCKER_SELECT = "*, blocker_teams(team)";

function toBlocker({
  blocker_teams,
  ...blocker
}: Database["public"]["Tables"]["blockers"]["Row"] & {
  blocker_teams: { team: string }[];
}): Blocker {
  return { ...blocker, teams: blocker_teams.map((t) => t.team).sort((a, b) => a.localeCompare(b, "fr")) };
}

export async function fetchBlockers(): Promise<Blocker[]> {
  const { data, error } = await db
    .from("blockers")
    .select(BLOCKER_SELECT)
    .neq("status", "RÉSOLU")
    .order("updated_at", { ascending: false });
  if (error) throw error;
  return (data ?? []).map(toBlocker);
}

/** Point bloquant, résolu compris ; `null` s'il a été supprimé. */
export async function fetchBlocker(id: string): Promise<Blocker | null> {
  const { data, error } = await db
    .from("blockers")
    .select(BLOCKER_SELECT)
    .eq("id", id)
    .maybeSingle();
  if (error) throw error;
  return data && toBlocker(data);
}

/** Démo (US16) : fait comme si le point n'avait pas bougé depuis 4 jours et lance le passage quotidien. */
export async function simulateStaleBlocker(id: string): Promise<number> {
  const { data, error } = await supabase.rpc("simuler_point_bloquant_a_revoir", {
    _blocker_id: id,
  });
  if (error) throw error;
  return data;
}

export async function fetchResolvedBlockers(): Promise<Blocker[]> {
  const { data, error } = await db
    .from("blockers")
    .select(BLOCKER_SELECT)
    .eq("status", "RÉSOLU")
    .order("updated_at", { ascending: false });
  if (error) throw error;
  return (data ?? []).map(toBlocker);
}

export type ValidatedSubmission = Submission & { validated_at: string | null };

/** Demandes validées, toutes équipes (filtrées par les règles d'accès de la base). */
export async function fetchValidatedSubmissions(): Promise<ValidatedSubmission[]> {
  const { data, error } = await db
    .from("submissions")
    .select("*")
    .eq("status", "validée")
    .order("created_at", { ascending: false });
  if (error) throw error;
  const rows = (data ?? []) as Submission[];
  const dates = new Map<string, string>();
  if (rows.length) {
    // L'historique peut ne pas être lisible pour tous : dans ce cas, date de soumission.
    const { data: hist } = await db
      .from("submission_status_history")
      .select("submission_id, changed_at")
      .eq("new_status", "validée")
      .in("submission_id", rows.map((r) => r.id))
      .order("changed_at", { ascending: false });
    for (const h of hist ?? []) if (!dates.has(h.submission_id)) dates.set(h.submission_id, h.changed_at);
  }
  return rows
    .map((r) => ({ ...r, validated_at: dates.get(r.id) ?? null }))
    .sort((a, b) => (b.validated_at ?? b.created_at).localeCompare(a.validated_at ?? a.created_at));
}

/** Admin : tous les points ; manager : ceux qui le concernent (vérifié par la base). */
export async function updateBlockerStatus(input: { id: string; status: string }) {
  const { error } = await supabase.rpc("set_blocker_status", {
    _blocker_id: input.id,
    _status: input.status as Enums["blocker_status"],
  });
  if (error) throw error;
}

/** « Relancer équipes » (US21) : renvoie le nombre de personnes notifiées. */
export async function remindBlockerTeams(id: string): Promise<number> {
  const { data, error } = await supabase.rpc("remind_blocker_teams", { _blocker_id: id });
  if (error) throw error;
  return data;
}

export async function fetchMetrics(): Promise<Metric[]> {
  const { data, error } = await db.from("metrics_with_trend").select("*");
  if (error) throw error;
  return (data ?? []) as Metric[];
}

/** Démo (US21) : fait comme si le KPI était hors plage depuis sa durée + 1 jour ; renvoie ces jours. */
export async function simulateOutOfRangeMetric(key: string): Promise<number> {
  const { data, error } = await supabase.rpc("simuler_kpi_hors_plage", { _key: key });
  if (error) throw error;
  return data;
}

/** « Marquer comme vérifié » (US21) : admin et manager, vérifié par la base. */
export async function verifyMetric(key: string) {
  const { error } = await supabase.rpc("verify_metric", { _key: key });
  if (error) throw error;
}

export async function updateMetric(input: { key: string; value: number }) {
  const { error } = await db
    .from("metrics")
    .update({ value: input.value })
    .eq("key", input.key);
  if (error) throw error;
}

export function timeAgo(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime();
  const min = Math.round(diff / 60000);
  if (min < 1) return "à l'instant";
  if (min < 60) return `il y a ${min} minute${min > 1 ? "s" : ""}`;
  const h = Math.round(min / 60);
  if (h < 24) return `il y a ${h} heure${h > 1 ? "s" : ""}`;
  const days = Math.round(h / 24);
  return `il y a ${days} jour${days > 1 ? "s" : ""}`;
}

/* ============================================================
 * CRUD complet — news / submissions / blockers / metrics
 * ========================================================== */

export type NewsInput = { title: string; body: string; author: string; status: string; links?: NewsLink[] };
export type SubmissionInput = {
  author_name: string;
  team: string;
  content: string;
  status: string;
  rejection_category?: string | null;
  rejection_note?: string | null;
};
export type BlockerInput = {
  title: string;
  description: string;
  /** Vide : toutes les équipes. */
  teams: string[];
  impact: string;
  severity: string;
  status: string;
};
export type MetricInput = {
  key: string;
  label: string;
  value: number;
  unit: string | null;
  /** Plage attendue (US21) : au moins une borne, min < max. */
  threshold_min: number | null;
  threshold_max: number | null;
  /** Durée hors plage avant « À vérifier » (US21), de 1 à 365 jours. */
  stale_after_days: number;
  definition: string | null;
  impact: string | null;
};

export async function fetchAllNews(): Promise<News[]> {
  const { data, error } = await db
    .from("news")
    .select("*, news_teams(team)")
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data ?? []).map(toNews);
}

function newsRow(input: NewsInput) {
  return { ...input, links: (input.links ?? []) as unknown as Json, status: input.status as Enums["news_status"] };
}

/** Admin : crée un brouillon (pour obtenir son id), enregistre le public, l'image, puis publie. */
export async function createNews(
  input: NewsInput,
  audience: NewsAudienceValue,
  media?: MediaDraft,
) {
  const { data, error } = await db
    .from("news")
    .insert(newsRow({ ...input, status: "brouillon" }))
    .select("id")
    .single();
  if (error) throw error;
  await saveNewsAudience(data.id, audience);
  if (media) await applyNewsImage(data.id, media);
  if (input.status === "publiée") await publishDraftNews(data.id);
}

/** Admin : modifie un brouillon, et ne le publie qu'à la fin pour qu'il n'affiche pas « Modifiée le ». */
export async function updateNews(
  id: string,
  input: NewsInput,
  audience: NewsAudienceValue,
  media?: MediaDraft,
) {
  await saveNewsAudience(id, audience);
  const { error } = await db
    .from("news")
    .update(newsRow({ ...input, status: "brouillon" }))
    .eq("id", id);
  if (error) throw error;
  if (media) await applyNewsImage(id, media);
  if (input.status === "publiée") await publishDraftNews(id);
}

export async function deleteNews(id: string, imagePath?: string | null) {
  await removeNewsImageFile(imagePath);
  const { error } = await db.from("news").delete().eq("id", id);
  if (error) throw error;
}

export async function fetchAllSubmissions(): Promise<Submission[]> {
  const { data, error } = await db
    .from("submissions")
    .select("*")
    .order("created_at", { ascending: false });
  if (error) throw error;
  return withPendingSince((data ?? []) as Submission[]);
}

function submissionRow(input: SubmissionInput) {
  const rejected = input.status === "refusée";
  return {
    author_name: input.author_name,
    team: input.team,
    content: input.content,
    status: input.status as Enums["submission_status"],
    rejection_category: rejected ? ((input.rejection_category || null) as Enums["rejection_category"] | null) : null,
    rejection_note: rejected ? input.rejection_note?.trim() || null : null,
  };
}

export async function createSubmission(input: SubmissionInput) {
  const { error } = await db.from("submissions").insert(submissionRow(input));
  if (error) throw error;
}

export const ATTACHMENT_BUCKET = "submission-attachments";
export const MAX_ATTACHMENT_BYTES = 20 * 1024 * 1024;

export async function submitIdea(input: Omit<SubmissionInput, "status">, file?: File | null) {
  let attachment_path: string | null = null;
  let attachment_name: string | null = null;
  if (file) {
    if (file.type !== "application/pdf") throw new Error("Seuls les fichiers PDF sont acceptés.");
    if (file.size > MAX_ATTACHMENT_BYTES) throw new Error("Le fichier dépasse 20 Mo.");
    const { data: u } = await db.auth.getUser();
    if (!u.user) throw new Error("Session expirée");
    attachment_path = `${u.user.id}/${crypto.randomUUID()}.pdf`;
    attachment_name = file.name.slice(0, 200);
    const { error: upErr } = await db.storage
      .from(ATTACHMENT_BUCKET)
      .upload(attachment_path, file, { contentType: "application/pdf" });
    if (upErr) throw upErr;
  }
  const { error } = await db.from("submissions").insert({
    author_name: input.author_name, team: input.team, content: input.content, status: "en attente",
    attachment_path, attachment_name,
  });
  if (error) throw error;
}

export async function downloadAttachment(path: string, name: string | null) {
  const { data, error } = await db.storage.from(ATTACHMENT_BUCKET).createSignedUrl(path, 60, {
    download: name ?? true,
  });
  if (error) throw error;
  window.open(data.signedUrl, "_blank", "noopener");
}

export async function updateSubmission(id: string, input: SubmissionInput) {
  const { error } = await db.from("submissions").update(submissionRow(input)).eq("id", id);
  if (error) throw error;
}

export async function deleteSubmission(id: string) {
  const { error } = await db.from("submissions").delete().eq("id", id);
  if (error) throw error;
}

export async function fetchAllBlockers(): Promise<Blocker[]> {
  const { data, error } = await db
    .from("blockers")
    .select(BLOCKER_SELECT)
    .order("updated_at", { ascending: false });
  if (error) throw error;
  return (data ?? []).map(toBlocker);
}

function blockerRow({ teams: _teams, ...input }: BlockerInput) {
  return {
    ...input,
    impact: input.impact.trim() || null,
    severity: input.severity as Enums["blocker_severity"],
    status: input.status as Enums["blocker_status"],
  };
}

async function saveBlockerTeams(id: string, teams: string[]) {
  const { error } = await supabase.rpc("save_blocker_teams", { _blocker_id: id, _teams: teams });
  if (error) throw error;
}

export async function createBlocker(input: BlockerInput) {
  const { data, error } = await db.from("blockers").insert(blockerRow(input)).select("id").single();
  if (error) throw error;
  await saveBlockerTeams(data.id, input.teams);
}

export async function updateBlocker(id: string, input: BlockerInput) {
  const { error } = await db.from("blockers").update(blockerRow(input)).eq("id", id);
  if (error) throw error;
  await saveBlockerTeams(id, input.teams);
}

export async function deleteBlocker(id: string) {
  const { error } = await db.from("blockers").delete().eq("id", id);
  if (error) throw error;
}

export async function createMetric(input: MetricInput) {
  const { error } = await db.from("metrics").insert(input);
  if (error) throw error;
}

export async function updateMetricRow(key: string, input: MetricInput) {
  const { error } = await db.from("metrics").update(input).eq("key", key);
  if (error) throw error;
}

export async function deleteMetric(key: string) {
  const { error } = await db.from("metrics").delete().eq("key", key);
  if (error) throw error;
}

export type SubmissionStatusHistory = {
  id: string;
  submission_id: string;
  old_status: string | null;
  new_status: string;
  changed_by_email: string | null;
  changed_by_name: string | null;
  is_automatic: boolean;
  rejection_category: string | null;
  rejection_note: string | null;
  changed_at: string;
};

export async function fetchSubmissionHistory(submissionId: string): Promise<SubmissionStatusHistory[]> {
  const { data, error } = await supabase
    .from("submission_status_history")
    .select("*")
    .eq("submission_id", submissionId)
    .order("changed_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as SubmissionStatusHistory[];
}

export type SubmissionVerification = {
  id: string;
  submission_id: string;
  verified_by_name: string | null;
  verified_at: string;
};

/** Confirmations « à jour » d'une demande (US21), lues dans son détail. */
export async function fetchSubmissionVerifications(
  submissionId: string,
): Promise<SubmissionVerification[]> {
  const { data, error } = await supabase
    .from("submission_verifications")
    .select("id, submission_id, verified_by_name, verified_at")
    .eq("submission_id", submissionId)
    .order("verified_at", { ascending: false });
  if (error) throw error;
  return data ?? [];
}

/** « Confirmer à jour » une demande clôturée (US21) : droits vérifiés par la base, sans notification. */
export async function confirmSubmissionUpToDate(id: string) {
  const { error } = await supabase.rpc("confirm_submission_up_to_date", { _submission_id: id });
  if (error) throw error;
}

export type MetricHistoryPoint = { id: string; metric_key: string; value: number; recorded_at: string };

export async function fetchMetricHistory(key: string): Promise<MetricHistoryPoint[]> {
  const { data, error } = await supabase
    .from("metrics_history")
    .select("*")
    .eq("metric_key", key)
    .order("recorded_at", { ascending: false })
    .limit(50);
  if (error) throw error;
  return (data ?? []) as MetricHistoryPoint[];
}

/** Supprime du stockage les pièces jointes échues de la file. Renvoie supprimés et restants. */
export async function processAttachmentDeletionQueue(): Promise<{ deleted: number; remaining: number }> {
  const { data, error } = await supabase
    .from("attachment_deletion_queue")
    .select("id, path")
    .lte("delete_after", new Date().toISOString());
  if (error) throw error;
  const rows = data ?? [];
  if (rows.length === 0) return { deleted: 0, remaining: 0 };
  const { data: removed, error: rmError } = await supabase.storage
    .from("submission-attachments")
    .remove(rows.map((r) => r.path));
  if (rmError) {
    await supabase
      .from("attachment_deletion_queue")
      .update({ last_error: rmError.message })
      .in("id", rows.map((r) => r.id));
    return { deleted: 0, remaining: rows.length };
  }
  const removedSet = new Set((removed ?? []).map((o) => o.name));
  const done = rows.filter((r) => removedSet.has(r.path));
  const missing = rows.filter((r) => !removedSet.has(r.path));
  // Fichiers que remove() n'a pas renvoyés : vérifier s'ils existent encore dans le bucket.
  // S'ils sont déjà absents, ils sont considérés comme supprimés. Si l'appel `list`
  // échoue, on ne peut pas conclure : le fichier reste dans la file avec l'erreur.
  const stillThere: { id: string; path: string; errorMessage: string }[] = [];
  for (const r of missing) {
    const slash = r.path.lastIndexOf("/");
    const folder = slash >= 0 ? r.path.slice(0, slash) : "";
    const fileName = slash >= 0 ? r.path.slice(slash + 1) : r.path;
    const { data: listing, error: listError } = await supabase.storage
      .from("submission-attachments")
      .list(folder, { search: fileName, limit: 100 });
    if (listError) {
      stillThere.push({ id: r.id, path: r.path, errorMessage: listError.message });
    } else if ((listing ?? []).some((o) => o.name === fileName)) {
      stillThere.push({ id: r.id, path: r.path, errorMessage: "Fichier non supprimé par le stockage" });
    } else {
      done.push(r);
    }
  }
  if (done.length) {
    const donePaths = done.map((r) => r.path);
    const { error: linkError } = await supabase
      .from("submissions")
      .update({ attachment_path: null, attachment_name: null })
      .in("attachment_path", donePaths);
    if (linkError) throw linkError;
    const { error: delError } = await supabase
      .from("attachment_deletion_queue")
      .delete()
      .in("id", done.map((r) => r.id));
    if (delError) throw delError;
  }
  if (stillThere.length) {
    for (const r of stillThere) {
      await supabase
        .from("attachment_deletion_queue")
        .update({ last_error: r.errorMessage })
        .eq("id", r.id);
    }
  }
  return { deleted: done.length, remaining: stillThere.length };
}

export async function countAttachmentDeletionQueue(): Promise<number> {
  const { count, error } = await supabase
    .from("attachment_deletion_queue")
    .select("id", { count: "exact", head: true })
    .lte("delete_after", new Date().toISOString());
  if (error) throw error;
  return count ?? 0;
}

export type DepartureDocument = {
  submission_id: string;
  path: string;
  name: string | null;
  created_at: string;
  excerpt: string;
};

export type DepartureNotice = {
  id: string;
  departing_label: string;
  departure_date: string;
  kind: "préavis" | "sans préavis";
  documents: DepartureDocument[];
  created_at: string;
  reminder_at: string | null;
};

export async function fetchMyDepartureNotices(email: string): Promise<DepartureNotice[]> {
  const { data, error } = await supabase
    .from("departure_notices")
    .select("id, departing_label, departure_date, kind, documents, created_at, reminder_at")
    .eq("recipient_email", email.toLowerCase())
    .is("closed_at", null)
    .is("downloaded_at", null)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as unknown as DepartureNotice[];
}

export async function markDepartureNoticeDownloaded(id: string) {
  const { error } = await supabase.rpc("mark_departure_notice_downloaded", { _id: id });
  if (error) throw error;
}

export type AppNotification = Pick<
  Tables<"notifications">,
  | "id"
  | "kind"
  | "submission_id"
  | "blocker_id"
  | "message"
  | "created_at"
  | "read_at"
  | "actor_name"
>;

export async function fetchMyNotifications(email: string): Promise<AppNotification[]> {
  const { data, error } = await supabase
    .from("notifications")
    .select("id, kind, submission_id, blocker_id, message, created_at, read_at, actor_name")
    .eq("recipient_email", email.toLowerCase())
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data ?? [];
}

export async function markNotificationRead(id: string) {
  const { error } = await supabase
    .from("notifications")
    .update({ read_at: new Date().toISOString() })
    .eq("id", id);
  if (error) throw error;
}

export async function markAllNotificationsRead(email: string) {
  const { error } = await supabase
    .from("notifications")
    .update({ read_at: new Date().toISOString() })
    .eq("recipient_email", email.toLowerCase())
    .is("read_at", null);
  if (error) throw error;
}

export type NotificationPreference = Pick<
  Tables<"notification_preferences">,
  "kind" | "in_app" | "by_email"
>;

/** Seules les préférences modifiées ont une ligne : un type absent vaut « dans l'app » et « par mail ». */
export async function fetchMyNotificationPreferences(
  email: string,
): Promise<NotificationPreference[]> {
  const { data, error } = await supabase
    .from("notification_preferences")
    .select("kind, in_app, by_email")
    .eq("recipient_email", email.toLowerCase());
  if (error) throw error;
  return data ?? [];
}

/** Enregistre un seul canal ; à la création de la ligne, l'autre garde sa valeur par défaut. */
export async function saveNotificationPreference(
  email: string,
  kind: Database["public"]["Enums"]["notification_kind"],
  channel: "in_app" | "by_email",
  checked: boolean,
) {
  const { error } = await supabase
    .from("notification_preferences")
    .upsert(
      {
        recipient_email: email.toLowerCase(),
        kind,
        ...(channel === "in_app" ? { in_app: checked } : { by_email: checked }),
      },
      { onConflict: "recipient_email,kind" },
    );
  if (error) throw error;
}

/** Source du suivi de la demande par `email` (« auteur », « manager », « volontaire »), `null` sans suivi. */
export async function fetchMyFollow(submissionId: string, email: string): Promise<string | null> {
  const { data, error } = await supabase
    .from("submission_followers")
    .select("source")
    .eq("submission_id", submissionId)
    .eq("follower_email", email.toLowerCase())
    .maybeSingle();
  if (error) throw error;
  return data?.source ?? null;
}

/** La base refuse un admin, une demande illisible et la suppression d'un suivi d'auteur. */
export async function setMyFollow(submissionId: string, email: string, follow: boolean) {
  const follower_email = email.toLowerCase();
  const { error } = follow
    ? await supabase
        .from("submission_followers")
        .insert({ submission_id: submissionId, follower_email, source: "volontaire" })
    : await supabase
        .from("submission_followers")
        .delete()
        .eq("submission_id", submissionId)
        .eq("follower_email", follower_email);
  if (error) throw error;
}

/** `null` si la demande est supprimée ou si la RLS ne la laisse plus lire. */
export async function fetchReadableSubmission(id: string): Promise<Submission | null> {
  const { data, error } = await supabase.from("submissions").select("*").eq("id", id).maybeSingle();
  if (error) throw error;
  return data as Submission | null;
}

export async function downloadDepartureZip(notice: DepartureNotice) {
  const JSZip = await loadBrowserLib<typeof import("jszip")>("/vendor/jszip-3.10.2.min.js", "JSZip");
  const zip = new JSZip();
  const used = new Set<string>();
  for (const d of notice.documents) {
    const { data, error } = await supabase.storage.from("submission-attachments").download(d.path);
    if (error) throw error;
    const safe = d.excerpt.replace(/[\\/:*?"<>|\n\r]+/g, " ").trim().slice(0, 60) || "document";
    let name = `${d.created_at.slice(0, 10)} - ${safe}.pdf`;
    let i = 2;
    while (used.has(name)) name = `${d.created_at.slice(0, 10)} - ${safe} (${i++}).pdf`;
    used.add(name);
    zip.file(name, data);
  }
  const blob = await zip.generateAsync({ type: "blob" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = `documents - ${notice.departing_label}.zip`;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 10000);
}
