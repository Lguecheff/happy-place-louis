import type { FormEvent } from "react";
import { DS_INPUT, DsButton, DsField, DsIcon } from "@/components/ds";

/** Message affiché en haut de la carte : refus d'accès (alerte) ou retour après déconnexion (information). */
export type LoginNotice = { tone: "alert" | "info"; text: string };

export const LOGIN_ERROR = "Adresse ou mot de passe incorrect.";
export const LOGIN_NO_ACCESS = "Ce compte n'a pas accès à Happy Place.";
export const LOGIN_SIGNED_OUT = "Tu es déconnecté.";

type LoginCardProps = {
  email: string;
  password: string;
  onEmailChange: (value: string) => void;
  onPasswordChange: (value: string) => void;
  onSubmit: () => void;
  /** Connexion en cours : bouton désactivé, libellé « Connexion… ». */
  pending?: boolean;
  /** Échec de la connexion : un seul message, sans dire lequel des deux champs est faux. */
  error?: string | null;
  notice?: LoginNotice | null;
};

/** Carte de connexion par adresse et mot de passe (pas d'inscription, pas de mot de passe oublié). */
export function LoginCard({
  email,
  password,
  onEmailChange,
  onPasswordChange,
  onSubmit,
  pending = false,
  error,
  notice,
}: LoginCardProps) {
  function submit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    if (!pending) onSubmit();
  }

  return (
    <section
      aria-labelledby="connexion-titre"
      className="w-full max-w-md border border-outline-variant bg-surface-container-lowest p-md md:p-lg"
    >
      <h1 id="connexion-titre" className="font-headline-lg text-headline-lg text-primary">
        Happy Place
      </h1>
      <p className="mt-xs font-body-md text-body-md text-on-surface-variant">
        Connecte-toi avec ton adresse e-mail et ton mot de passe.
      </p>

      {notice &&
        (notice.tone === "alert" ? (
          <p
            role="alert"
            className="mt-md flex items-start gap-xs border border-error bg-error-container p-sm font-body-sm text-body-sm text-on-error-container"
          >
            <DsIcon name="error" />
            {notice.text}
          </p>
        ) : (
          <p
            role="status"
            className="mt-md flex items-start gap-xs border border-outline-variant bg-surface-container p-sm font-body-sm text-body-sm text-on-surface"
          >
            <DsIcon name="logout" />
            {notice.text}
          </p>
        ))}

      <form onSubmit={submit} noValidate className="mt-md space-y-md">
        <DsField id="connexion-email" label="Adresse e-mail">
          <input
            id="connexion-email"
            type="email"
            name="email"
            autoComplete="username"
            inputMode="email"
            spellCheck={false}
            required
            value={email}
            onChange={(e) => onEmailChange(e.target.value)}
            aria-invalid={error ? true : undefined}
            aria-describedby={error ? "connexion-erreur" : undefined}
            className={DS_INPUT}
          />
        </DsField>
        <DsField id="connexion-mot-de-passe" label="Mot de passe">
          <input
            id="connexion-mot-de-passe"
            type="password"
            name="password"
            autoComplete="current-password"
            required
            value={password}
            onChange={(e) => onPasswordChange(e.target.value)}
            aria-invalid={error ? true : undefined}
            aria-describedby={error ? "connexion-erreur" : undefined}
            className={DS_INPUT}
          />
        </DsField>

        {error && (
          <p
            id="connexion-erreur"
            role="alert"
            className="flex items-start gap-xs font-body-sm text-body-sm text-error"
          >
            <DsIcon name="error" />
            {error}
          </p>
        )}

        <DsButton type="submit" variant="primary" pending={pending} className="w-full">
          {pending ? "Connexion…" : "Se connecter"}
        </DsButton>
      </form>
    </section>
  );
}
