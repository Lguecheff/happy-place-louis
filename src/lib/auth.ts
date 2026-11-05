import { supabase } from "@/integrations/supabase/client";

export type AppRole = "admin" | "manager" | "collaborateur";

/**
 * Entrée libre (version élèves) : session anonyme et choix du rôle sur /choisir-role.
 * Seulement si VITE_ENTREE_LIBRE vaut exactement « true » ; sinon, connexion par mot de passe.
 */
export const ENTREE_LIBRE = import.meta.env.VITE_ENTREE_LIBRE === "true";

/** Motif affiché sur /auth après un renvoi : compte sans accès, ou déconnexion volontaire. */
export type AuthReason = "sans-acces" | "deconnecte";

export function parseAuthReason(value: unknown): AuthReason | undefined {
  return value === "sans-acces" || value === "deconnecte" ? value : undefined;
}

/** Returns the signed-in user's whitelist role, or null if not whitelisted. RLS only exposes the user's own row. */
export async function fetchOwnRole(email: string): Promise<AppRole | null> {
  const { data: allowedUser, error: userError } = await supabase
    .from("allowed_users")
    .select("id")
    .eq("email", email.toLowerCase())
    .maybeSingle();
  if (userError) throw userError;
  if (!allowedUser) return null;

  const { data: roleRow, error: roleError } = await supabase
    .from("allowed_user_roles")
    .select("role")
    .eq("allowed_user_id", allowedUser.id)
    .maybeSingle();
  if (roleError) throw roleError;
  return (roleRow?.role as AppRole | undefined) ?? null;
}

export async function signOut() {
  await supabase.auth.signOut();
  // Entrée libre : comportement d'origine (une nouvelle session anonyme s'ouvre sur /auth).
  window.location.replace(ENTREE_LIBRE ? "/auth" : "/auth?raison=deconnecte");
}
