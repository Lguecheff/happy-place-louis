/**
 * Adresse publique de l'app : seule constante côté app (côté base : private.app_base_url()).
 * Les mails ouvrent `/?demande=<id>`, `/?point=<id>`, `/?actu=<id>` ou `/?preferences`.
 */
export const APP_BASE_URL = "https://happy-place-louis.guecheff-louis.workers.dev";

/** Paramètres d'un lien profond vers la vue d'accueil. */
export type DeepLink = {
  demande?: string;
  point?: string;
  actu?: string;
  preferences?: boolean;
};

const ID = /^[0-9a-f-]{1,64}$/i;

/** Lit les paramètres d'adresse de la vue d'accueil ; un identifiant mal formé est ignoré. */
export function parseDeepLink(search: Record<string, unknown>): DeepLink {
  const id = (v: unknown) => (typeof v === "string" && ID.test(v) ? v : undefined);
  const link: DeepLink = {};
  if (id(search.demande)) link.demande = id(search.demande);
  else if (id(search.point)) link.point = id(search.point);
  else if (id(search.actu)) link.actu = id(search.actu);
  // « /?preferences » arrive vide ("") ou à true selon le chemin suivi.
  if ("preferences" in search && search.preferences !== false) link.preferences = true;
  return link;
}

/**
 * Chemin interne où revenir après la connexion et le choix du rôle, ou `null`.
 * Refuse tout ce qui sortirait de l'app (« //autre.site », « https:… », « /\\… »).
 */
export function safeRedirect(value: unknown): string | null {
  if (typeof value !== "string" || !value.startsWith("/")) return null;
  if (value.startsWith("//") || value.startsWith("/\\")) return null;
  try {
    const url = new URL(value, "https://app.invalid");
    if (url.origin !== "https://app.invalid") return null;
    if (url.pathname.startsWith("/auth") || url.pathname.startsWith("/choisir-role")) return null;
    return url.pathname + url.search;
  } catch {
    return null;
  }
}
