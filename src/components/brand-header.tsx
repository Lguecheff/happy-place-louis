import { Link, useRouterState } from "@tanstack/react-router";
import { useEffect, useState, type ReactNode } from "react";
import sharkLogo from "@/assets/bigger-boat-shark.png";
import { supabase } from "@/integrations/supabase/client";
import { DsButton } from "@/components/ds";
import { ENTREE_LIBRE, signOut } from "@/lib/auth";

/** `children` remplace la zone de droite (navigation et compte de la vue d'ensemble). `search` s'ajoute avant elle, `notifications` au début de la zone par défaut. */
export function BrandHeader({
  children,
  search,
  notifications,
}: {
  children?: ReactNode;
  search?: ReactNode;
  notifications?: ReactNode;
}) {
  // Connecté : « Se déconnecter » (hors /auth). Entrée libre : « Changer de rôle » à la place, comme avant.
  const pathname = useRouterState({ select: (s) => s.location.pathname });
  const [signedIn, setSignedIn] = useState(false);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setSignedIn(!!data.session));
    const { data: sub } = supabase.auth.onAuthStateChange((_event, session) =>
      setSignedIn(!!session),
    );
    return () => sub.subscription.unsubscribe();
  }, []);

  return (
    <header className="border-b border-outline-variant bg-surface-container-lowest">
      <div className="mx-auto flex min-h-16 w-full max-w-interface flex-wrap items-center justify-between gap-x-md gap-y-xs px-sm py-xs md:px-md">
        <Link
          to="/"
          className="flex min-w-0 items-center gap-sm"
          aria-label="Bigger Boat — accueil"
        >
          <img
            src={sharkLogo}
            alt=""
            width={1024}
            height={1024}
            className="h-11 w-14 shrink-0 object-contain"
          />
          <span className="font-label-md text-lg font-bold uppercase text-primary">
            Bigger Boat
          </span>
        </Link>
        {search}
        {children ?? (
          <div className="flex items-center gap-md">
            {notifications}
            {signedIn &&
              (ENTREE_LIBRE
                ? pathname !== "/choisir-role" && (
                    <Link
                      to="/choisir-role"
                      className="inline-flex min-h-11 items-center font-label-md text-sm text-primary underline-offset-4 hover:underline"
                    >
                      Changer de rôle
                    </Link>
                  )
                : pathname !== "/auth" && (
                    <DsButton
                      variant="link"
                      icon="logout"
                      onClick={() => signOut()}
                      className="whitespace-nowrap"
                    >
                      Se déconnecter
                    </DsButton>
                  ))}
            <span className="font-label-md text-label-md uppercase text-on-surface-variant">
              Happy Place
            </span>
          </div>
        )}
      </div>
    </header>
  );
}
