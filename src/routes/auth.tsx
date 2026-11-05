import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useEffect, useRef, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { BrandHeader } from "@/components/brand-header";
import {
  LOGIN_ERROR,
  LOGIN_NO_ACCESS,
  LOGIN_SIGNED_OUT,
  LoginCard,
  type LoginNotice,
} from "@/components/auth/LoginCard";
import { DsButton } from "@/components/ds";
import { safeRedirect } from "@/lib/app-url";
import { ENTREE_LIBRE, fetchOwnRole, parseAuthReason, type AuthReason } from "@/lib/auth";

// Connexion par adresse et mot de passe (comptes créés à l'avance, pas d'inscription).
// Avec VITE_ENTREE_LIBRE=true, l'entrée libre de la version élèves revient : session anonyme
// ouverte automatiquement, puis choix du rôle sur /choisir-role.

export const Route = createFileRoute("/auth")({
  ssr: false,
  // Chemin interne où revenir (lien reçu par mail) ; toute autre valeur est ignorée.
  validateSearch: (
    search: Record<string, unknown>,
  ): { redirect?: string; raison?: AuthReason } => ({
    redirect: safeRedirect(search.redirect) ?? undefined,
    raison: parseAuthReason(search.raison),
  }),
  head: () => ({
    meta: [
      { title: "Happy Place" },
      { name: "description", content: "Happy Place, le dashboard interne de Bigger Boat." },
    ],
  }),
  component: () => (ENTREE_LIBRE ? <EntreeLibrePage /> : <ConnexionPage />),
});

/** Après la connexion : le lien reçu par mail, sinon la vue d'ensemble. */
function useGoInside() {
  const navigate = useNavigate();
  const { redirect } = Route.useSearch();
  return () => {
    // Le chemin vient de safeRedirect : interne à l'app.
    if (redirect) window.location.replace(redirect);
    else navigate({ to: "/" });
  };
}

function ConnexionPage() {
  const { raison } = Route.useSearch();
  const goInside = useGoInside();
  const [checking, setChecking] = useState(true);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<LoginNotice | null>(
    raison === "sans-acces"
      ? { tone: "alert", text: LOGIN_NO_ACCESS }
      : raison === "deconnecte"
        ? { tone: "info", text: LOGIN_SIGNED_OUT }
        : null,
  );
  const goRef = useRef(goInside);
  goRef.current = goInside;

  // Déjà connecté : on entre directement (la garde des pages connectées vérifie le rôle).
  useEffect(() => {
    let cancelled = false;
    supabase.auth.getSession().then(({ data }) => {
      if (cancelled) return;
      if (data.session) goRef.current();
      else setChecking(false);
    });
    return () => {
      cancelled = true;
    };
  }, []);

  function fail(message: string) {
    setPending(false);
    setPassword("");
    setError(message);
    // Après le rendu : le champ vidé reçoit le focus.
    setTimeout(() => document.getElementById("connexion-mot-de-passe")?.focus(), 0);
  }

  async function submit() {
    setError(null);
    setNotice(null);
    const address = email.trim().toLowerCase();
    if (!address || !password) return fail(LOGIN_ERROR);
    setPending(true);
    const { data, error: err } = await supabase.auth.signInWithPassword({
      email: address,
      password,
    });
    if (err || !data.user) return fail(LOGIN_ERROR);
    let role = null;
    try {
      role = await fetchOwnRole(data.user.email ?? address);
    } catch {
      role = null;
    }
    if (!role) {
      await supabase.auth.signOut({ scope: "local" }).catch(() => {});
      setPending(false);
      setPassword("");
      setNotice({ tone: "alert", text: LOGIN_NO_ACCESS });
      return;
    }
    goInside();
  }

  return (
    <div className="min-h-dvh w-full bg-background text-on-surface font-body-md flex flex-col">
      <BrandHeader />
      <main className="flex flex-1 items-start justify-center px-sm py-lg md:px-md">
        {checking ? (
          <p role="status" className="font-body-md text-body-md text-on-surface-variant">
            Ouverture de ton espace…
          </p>
        ) : (
          <LoginCard
            email={email}
            password={password}
            onEmailChange={setEmail}
            onPasswordChange={setPassword}
            onSubmit={submit}
            pending={pending}
            error={error}
            notice={notice}
          />
        )}
      </main>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Entrée libre (VITE_ENTREE_LIBRE=true) : comportement d'origine de la version élèves.
// ---------------------------------------------------------------------------

function EntreeLibrePage() {
  const navigate = useNavigate();
  const { redirect } = Route.useSearch();
  const [error, setError] = useState<string | null>(null);
  const [attempt, setAttempt] = useState(0);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setError(null);
      const { data } = await supabase.auth.getSession();
      if (data.session) {
        // Le chemin vient de safeRedirect : interne à l'app.
        if (redirect) window.location.replace(redirect);
        else navigate({ to: "/" });
        return;
      }
      const { error: err } = await supabase.auth.signInAnonymously();
      if (cancelled) return;
      if (err) {
        setError(
          /anonymous/i.test(err.message) && /disabled|not enabled/i.test(err.message)
            ? "Les connexions anonymes ne sont pas activées dans Supabase. Active « Allow anonymous sign-ins » (voir le README, étape 2), puis réessaie."
            : `Impossible d'ouvrir Happy Place : ${err.message}`,
        );
        return;
      }
      navigate({ to: "/choisir-role", search: { redirect } });
    })();
    return () => {
      cancelled = true;
    };
  }, [navigate, attempt, redirect]);

  return (
    <div className="min-h-dvh w-full bg-background flex flex-col">
      <BrandHeader />
      <main className="flex flex-1 items-center justify-center px-md py-lg">
        <section className="w-full max-w-md border border-outline-variant bg-surface-container-lowest p-lg">
          <h1 className="font-headline-lg text-headline-lg text-primary">Happy Place</h1>
          {error ? (
            <>
              <p
                className="mt-md border border-error bg-error-container p-sm font-body-sm text-on-error-container"
                role="alert"
              >
                {error}
              </p>
              <DsButton
                variant="primary"
                icon="refresh"
                onClick={() => setAttempt((n) => n + 1)}
                className="mt-md w-full"
              >
                Réessayer
              </DsButton>
            </>
          ) : (
            <p className="mt-sm font-body-md text-body-md text-on-surface-variant" role="status">
              Ouverture de ton espace…
            </p>
          )}
        </section>
      </main>
    </div>
  );
}
