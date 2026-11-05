import { createFileRoute, isRedirect, Outlet, redirect } from "@tanstack/react-router";
import { supabase } from "@/integrations/supabase/client";
import { safeRedirect } from "@/lib/app-url";
import { ENTREE_LIBRE, fetchOwnRole } from "@/lib/auth";

// Un compte connecté sans rôle est déconnecté et renvoyé sur /auth avec « Ce compte n'a pas accès ».
// Entrée libre (VITE_ENTREE_LIBRE=true) : il est envoyé vers /choisir-role, comme dans la version élèves.
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
      if (!role) {
        if (ENTREE_LIBRE) throw redirect({ to: "/choisir-role", search });
        await supabase.auth.signOut({ scope: "local" }).catch(() => {});
        throw redirect({ to: "/auth", search: { ...search, raison: "sans-acces" } });
      }
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
