import { createFileRoute, isRedirect, Outlet, redirect } from "@tanstack/react-router";
import { supabase } from "@/integrations/supabase/client";
import { safeRedirect } from "@/lib/app-url";
import { fetchOwnRole } from "@/lib/auth";

// Version élèves : un compte connecté sans rôle est envoyé vers /choisir-role
// (au lieu d'être déconnecté comme dans l'app d'origine, réservée à une liste blanche).
export const Route = createFileRoute("/_authenticated")({
  ssr: false,
  beforeLoad: async ({ location }) => {
    // Lien profond (mail) : on le garde pour y revenir après la connexion et le choix du rôle.
    const back = safeRedirect(location.href) ?? undefined;
    const search = { redirect: back === "/" ? undefined : back };
    try {
      const { data, error } = await supabase.auth.getUser();
      if (error || !data.user) throw redirect({ to: "/auth", search });
      const email = data.user.email ?? "";
      const role = email ? await fetchOwnRole(email) : null;
      if (!role) throw redirect({ to: "/choisir-role", search });
      return { user: data.user, email, role };
    } catch (e) {
      if (isRedirect(e)) throw e;
      // Session périmée ou compte changé dans un autre onglet : retour propre à la connexion.
      await supabase.auth.signOut({ scope: "local" }).catch(() => {});
      throw redirect({ to: "/auth", search });
    }
  },
  component: () => <Outlet />,
});
