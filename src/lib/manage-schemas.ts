import { z } from "zod";

// Le titre n'est obligatoire que pour publier : un brouillon demande un titre ou un texte.
const newsContent = z.object({
  title: z.string().trim().max(160, "160 caractères maximum"),
  body: z.string().trim().max(5000, "5000 caractères maximum"),
  status: z.enum(["brouillon", "publiée"], { errorMap: () => ({ message: "Statut invalide" }) }),
});

function checkNewsTitle(news: z.infer<typeof newsContent>, ctx: z.RefinementCtx) {
  const message =
    news.status === "publiée"
      ? news.title.length < 3 && "Le titre doit faire au moins 3 caractères"
      : !news.title && !news.body && "Saisis un titre ou un texte.";
  if (message) ctx.addIssue({ code: "custom", path: ["title"], message });
}

/** Règles du rédacteur de la vue d'ensemble, où l'auteur est le compte connecté. */
export const newsContentSchema = newsContent.superRefine(checkNewsTitle);

export const newsSchema = newsContent
  .extend({ author: z.string().trim().min(2, "Auteur requis").max(80, "80 caractères maximum") })
  .superRefine(checkNewsTitle);

export const REJECTION_CATEGORY_VALUES = ["à clarifier", "en désaccord avec les process", "doublon", "autre"] as const;

const rejectionTooLong = (n: number) =>
  `La raison du refus dépasse 500 caractères (${n.toLocaleString("fr-FR")} saisis).`;

export const rejectionSchema = z.object({
  rejection_category: z.enum(REJECTION_CATEGORY_VALUES, { errorMap: () => ({ message: "Choisis un motif de refus" }) }),
  rejection_note: z.string().trim().min(1, "La raison du refus est obligatoire").superRefine((v, ctx) => {
    if (v.length > 500) ctx.addIssue({ code: "custom", message: rejectionTooLong(v.length) });
  }),
});

export const submissionSchema = z.object({
  author_name: z.string().trim().min(2, "Nom requis").max(80, "80 caractères maximum"),
  team: z.string().trim().min(2, "Pôle requis").max(60, "60 caractères maximum"),
  content: z.string().trim().min(5, "5 caractères minimum").superRefine((v, ctx) => {
    if (v.length > 2000)
      ctx.addIssue({ code: "custom", message: `Ta proposition dépasse 2 000 caractères (${v.length.toLocaleString("fr-FR")} saisis). Raccourcis-la avant d'envoyer.` });
  }),
  status: z.enum(["en attente", "validée", "refusée", "clôturée"], {
    errorMap: () => ({ message: "Statut invalide" }),
  }),
  rejection_category: z.string().nullable().optional(),
  rejection_note: z.string().nullable().optional(),
}).superRefine((v, ctx) => {
  if (v.status !== "refusée") return;
  if (!v.rejection_category || !(REJECTION_CATEGORY_VALUES as readonly string[]).includes(v.rejection_category))
    ctx.addIssue({ code: "custom", path: ["rejection_category"], message: "Choisis un motif de refus" });
  if (!v.rejection_note || v.rejection_note.trim().length < 1)
    ctx.addIssue({ code: "custom", path: ["rejection_note"], message: "La raison du refus est obligatoire" });
  else if (v.rejection_note.trim().length > 500)
    ctx.addIssue({ code: "custom", path: ["rejection_note"], message: rejectionTooLong(v.rejection_note.trim().length) });
});

/** « Ce que ça change pour toi » d'un point bloquant (contrainte blockers_impact_length). */
export const BLOCKER_IMPACT_MAX = 300;

export const blockerSchema = z.object({
  title: z.string().trim().min(3, "Le titre doit faire au moins 3 caractères").max(160, "160 caractères maximum"),
  description: z.string().trim().max(2000, "2000 caractères maximum"),
  /** Vide : toutes les équipes. */
  teams: z.array(z.string()),
  impact: z.string().trim().max(BLOCKER_IMPACT_MAX, `${BLOCKER_IMPACT_MAX} caractères maximum`),
  severity: z.enum(["critical", "warning", "info"], {
    errorMap: () => ({ message: "Sévérité invalide" }),
  }),
  status: z.enum(["OUVERT", "EN COURS", "SURVEILLANCE", "RÉSOLU"], {
    errorMap: () => ({ message: "Statut invalide" }),
  }),
});

/** Seuil « à vérifier » d'un KPI (US21), même règle que la base. */
const STALE_AFTER_DAYS_ERROR = "Indique un nombre entier de jours, de 1 à 365.";

export const metricSchema = z.object({
  key: z
    .string()
    .trim()
    .min(2, "Clé requise")
    .max(40, "40 caractères maximum")
    .regex(/^[a-z0-9_]+$/, "Minuscules, chiffres et _ uniquement"),
  label: z.string().trim().min(2, "Libellé requis").max(60, "60 caractères maximum"),
  value: z
    .number({ invalid_type_error: "Valeur numérique requise" })
    .finite("Valeur numérique requise"),
  unit: z.string().trim().max(8, "8 caractères maximum").nullable(),
  definition: z.string().trim().max(200, "200 caractères maximum").nullable(),
  impact: z.string().trim().max(200, "200 caractères maximum").nullable(),
  stale_after_days: z
    .number({ invalid_type_error: STALE_AFTER_DAYS_ERROR })
    .int(STALE_AFTER_DAYS_ERROR)
    .min(1, STALE_AFTER_DAYS_ERROR)
    .max(365, STALE_AFTER_DAYS_ERROR),
});

export type FieldErrors = Record<string, string>;

export function validate<T>(
  schema: z.ZodType<T>,
  value: unknown,
): { ok: true; data: T } | { ok: false; errors: FieldErrors } {
  const result = schema.safeParse(value);
  if (result.success) return { ok: true, data: result.data };
  const errors: FieldErrors = {};
  for (const issue of result.error.issues) {
    const key = String(issue.path[0] ?? "_");
    if (!errors[key]) errors[key] = issue.message;
  }
  return { ok: false, errors };
}
