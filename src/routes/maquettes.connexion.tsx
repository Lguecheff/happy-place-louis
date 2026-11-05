import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useRef, useState } from "react";
import { BrandHeader } from "@/components/brand-header";
import {
  LOGIN_ERROR,
  LOGIN_NO_ACCESS,
  LOGIN_SIGNED_OUT,
  LoginCard,
  type LoginNotice,
} from "@/components/auth/LoginCard";
import { DS_INPUT, DsButton, DsField, DsIconButton } from "@/components/ds";

// Hors de _authenticated : la page de connexion s'affiche sans session.
export const Route = createFileRoute("/maquettes/connexion")({
  ssr: false,
  head: () => ({ meta: [{ title: "Happy Place · Maquette de la connexion" }] }),
  component: ConnexionMockup,
});

// ---------------------------------------------------------------------------
// Données factices (fictif). Aucun appel à Supabase.
// ---------------------------------------------------------------------------

const DELAY_MS = 1200;
const DEMO_EMAIL = "kesha.fictif@exemple.fr";

type State = {
  value: string;
  label: string;
  note: string;
  email: string;
  password: string;
  pending?: boolean;
  error?: string;
  notice?: LoginNotice;
};

const STATES: State[] = [
  {
    value: "vide",
    label: "Vide",
    note: "Arrivée sur /auth sans session. Pas de lien d'inscription ni de « mot de passe oublié ». Saisis n'importe quoi puis « Se connecter » : la connexion simulée réussit.",
    email: "",
    password: "",
  },
  {
    value: "en-cours",
    label: "Connexion en cours",
    note: "Le bouton est désactivé et affiche « Connexion… » le temps de signInWithPassword.",
    email: DEMO_EMAIL,
    password: "••••••••••",
    pending: true,
  },
  {
    value: "incorrect",
    label: "Identifiants incorrects",
    note: "Un seul message, quel que soit le champ faux. L'adresse est gardée, le mot de passe est vidé et reçoit le focus (soumets le formulaire vide pour le voir). Les deux champs sont marqués invalides et décrits par le message.",
    email: DEMO_EMAIL,
    password: "",
    error: LOGIN_ERROR,
  },
  {
    value: "sans-acces",
    label: "Compte sans accès",
    note: "Le mot de passe est bon, mais l'adresse n'est pas dans allowed_users avec un rôle : la session est fermée et on revient ici avec ce message.",
    email: "",
    password: "",
    notice: { tone: "alert", text: LOGIN_NO_ACCESS },
  },
  {
    value: "deconnecte",
    label: "Déconnecté (retour après déconnexion)",
    note: "Après « Se déconnecter » (menu du compte ou en-tête de « Gérer les données »). Message neutre, sans couleur d'alerte. Proposition : à confirmer, ou à retirer pour une page vide.",
    email: "",
    password: "",
    notice: { tone: "info", text: LOGIN_SIGNED_OUT },
  },
];

const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

// ---------------------------------------------------------------------------
// Présentation
// ---------------------------------------------------------------------------

function ConnexionMockup() {
  const [stateValue, setStateValue] = useState(STATES[0].value);
  const state = STATES.find((s) => s.value === stateValue) ?? STATES[0];

  return (
    <div className="min-h-dvh w-full bg-background text-on-surface font-body-md flex flex-col">
      <BrandHeader>
        <span className="font-label-md text-label-md uppercase text-on-surface-variant">
          Happy Place
        </span>
      </BrandHeader>
      <div className="mx-auto w-full max-w-interface px-sm pt-sm md:px-md md:pt-md">
        <div className="flex flex-wrap items-end gap-sm border border-dashed border-outline-variant p-sm">
          <DsField id="maquette-etat" label="Maquette (fictif)" className="w-full md:w-72">
            <select
              id="maquette-etat"
              className={DS_INPUT}
              value={state.value}
              onChange={(e) => setStateValue(e.target.value)}
            >
              {STATES.map((s) => (
                <option key={s.value} value={s.value}>
                  {s.label}
                </option>
              ))}
            </select>
          </DsField>
          <p className="min-w-0 flex-1 basis-64 font-body-sm text-body-sm text-on-surface">
            Maquette (fictif), /auth : {state.note}
          </p>
        </div>
      </div>
      {/* La clé repart d'un formulaire neuf à chaque changement d'état. */}
      <LoginDemo key={state.value} state={state} />
      <ManageHeaderPreview />
    </div>
  );
}

function LoginDemo({ state }: { state: State }) {
  const [email, setEmail] = useState(state.email);
  const [password, setPassword] = useState(state.password);
  const [pending, setPending] = useState(!!state.pending);
  const [error, setError] = useState<string | null>(state.error ?? null);
  const [done, setDone] = useState(false);
  const alive = useRef(true);

  useEffect(() => {
    alive.current = true;
    return () => {
      alive.current = false;
    };
  }, []);

  async function submit() {
    setError(null);
    setDone(false);
    setPending(true);
    await wait(DELAY_MS);
    if (!alive.current) return;
    setPending(false);
    if (!email.trim() || !password) {
      setPassword("");
      setError(LOGIN_ERROR);
      document.getElementById("connexion-mot-de-passe")?.focus();
      return;
    }
    setDone(true);
  }

  return (
    <>
      <div className="mx-auto w-full max-w-interface px-sm md:px-md">
        <p role="status" className="mt-xs font-body-sm text-body-sm text-success">
          {done &&
            "Connexion réussie (fictif) : tu arriverais sur la vue d'ensemble avec ton rôle, ou sur le lien reçu par mail."}
        </p>
      </div>

      <main className="flex flex-1 items-start justify-center px-sm pb-lg md:px-md">
        <LoginCard
          email={email}
          password={password}
          onEmailChange={setEmail}
          onPasswordChange={setPassword}
          onSubmit={submit}
          pending={pending}
          error={error}
          notice={state.notice}
        />
      </main>
    </>
  );
}

/** Aperçu statique de l'en-tête de « Gérer les données », avec « Se déconnecter » et sans « Changer de rôle ». */
function ManageHeaderPreview() {
  return (
    <section
      aria-labelledby="apercu-entete"
      className="border-t border-dashed border-outline-variant bg-surface-container py-md"
    >
      <div className="mx-auto w-full max-w-interface space-y-xs px-sm md:px-md">
        <h2 id="apercu-entete" className="font-headline-sm text-headline-sm text-primary">
          Aperçu : en-tête de « Gérer les données » (fictif)
        </h2>
        <p className="font-body-sm text-body-sm text-on-surface">
          Le lien « Changer de rôle » disparaît. « Se déconnecter » se place après les
          notifications, avant la mention Happy Place, et ramène sur /auth. Aperçu statique : rien
          ne se passe au clic.
        </p>
      </div>
      <div className="mt-sm">
        <BrandHeader>
          <div className="flex items-center gap-md">
            <DsIconButton
              icon="notifications"
              label="Notifications, 2 non lues (fictif)"
              count={2}
            />
            <DsButton variant="link" icon="logout" className="whitespace-nowrap">
              Se déconnecter
            </DsButton>
            <span className="font-label-md text-label-md uppercase text-on-surface-variant">
              Happy Place
            </span>
          </div>
        </BrandHeader>
      </div>
    </section>
  );
}
