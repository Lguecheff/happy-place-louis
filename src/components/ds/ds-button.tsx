/**
 * Règle : un seul DsButton « primary » par écran. C'est l'unique élément qui
 * ressort ; les autres actions sont « secondary », « confirm » ou « link ».
 * Libellés : verbe à l'infinitif, casse normale (« Valider », pas « VALIDER »).
 */
import type { AnchorHTMLAttributes, ButtonHTMLAttributes } from "react";
import { cn } from "@/lib/utils";
import { DS_FOCUS } from "./focus";
import { DsIcon } from "./ds-icon";

export type DsButtonVariant = "primary" | "secondary" | "confirm" | "link";

const VARIANTS: Record<DsButtonVariant, string> = {
  primary: "border border-primary bg-primary text-on-primary hover:opacity-90",
  secondary: "border border-outline bg-surface text-primary hover:bg-surface-container",
  confirm:
    "border-2 border-primary bg-surface-container-lowest text-primary hover:bg-surface-container",
  link: "border border-transparent bg-transparent text-primary underline underline-offset-4 hover:bg-surface-container",
};

type Common = {
  variant?: DsButtonVariant;
  /** Nom d'un symbole Material Symbols, affiché à gauche du libellé. */
  icon?: string;
  /** Action en cours : le bouton est désactivé et annonce qu'il est occupé. */
  pending?: boolean;
};

type DsButtonProps =
  | (Common & ButtonHTMLAttributes<HTMLButtonElement> & { href?: undefined })
  | (Common & AnchorHTMLAttributes<HTMLAnchorElement> & { href: string; disabled?: boolean });

export function DsButton(props: DsButtonProps) {
  const { variant = "secondary", icon, pending, className, children, ...rest } = props;
  const classes = cn(
    "inline-flex min-h-11 items-center justify-center gap-xs px-md py-xs font-label-md text-sm font-medium",
    "disabled:cursor-not-allowed disabled:opacity-50 aria-disabled:cursor-not-allowed aria-disabled:opacity-50",
    DS_FOCUS,
    VARIANTS[variant],
    className,
  );
  const content = (
    <>
      {pending ? (
        <DsIcon name="progress_activity" className="animate-spin" />
      ) : (
        icon && <DsIcon name={icon} />
      )}
      {children}
    </>
  );

  if ("href" in props && props.href !== undefined) {
    const { href, disabled, ...anchorRest } = rest as AnchorHTMLAttributes<HTMLAnchorElement> & {
      href: string;
      disabled?: boolean;
    };
    const off = disabled || pending;
    return (
      <a
        {...anchorRest}
        href={off ? undefined : href}
        aria-disabled={off || undefined}
        aria-busy={pending || undefined}
        className={classes}
      >
        {content}
      </a>
    );
  }

  const {
    type = "button",
    disabled,
    ...buttonRest
  } = rest as ButtonHTMLAttributes<HTMLButtonElement>;
  return (
    <button
      {...buttonRest}
      type={type}
      disabled={disabled || pending}
      aria-busy={pending || undefined}
      className={classes}
    >
      {content}
    </button>
  );
}
