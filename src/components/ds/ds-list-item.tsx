import type { MouseEvent, ReactNode } from "react";
import { cn } from "@/lib/utils";
import { DsIcon } from "./ds-icon";
import { DS_FOCUS } from "./focus";

type Common = {
  title: ReactNode;
  /** Ligne de méta : auteur, date, équipe… en texte normal (pas de majuscules). */
  meta?: ReactNode;
  /** Symbole décoratif à gauche. */
  icon?: string;
  /** Élément à gauche à la place du symbole (ex. DsAvatar). */
  leading?: ReactNode;
  className?: string;
};

type DsListItemProps =
  /** Ligne statique avec actions à droite ; avec `children`, le contenu et les actions passent dessous. */
  | (Common & { actions?: ReactNode; children?: ReactNode; href?: undefined; onClick?: undefined })
  /** Ligne entièrement cliquable (lien) : flèche à droite, pas d'actions imbriquées. */
  | (Common & { href: string; onClick?: undefined; actions?: undefined; children?: undefined })
  /**
   * Ligne cliquable (bouton) : flèche à droite, pas d'actions imbriquées. Avec `children`,
   * seul le haut de la ligne est le bouton ; le contenu (ex. un sélecteur) passe dessous, hors du bouton.
   */
  | (Common & {
      onClick: (event: MouseEvent<HTMLButtonElement>) => void;
      /** Le bouton ouvre une fenêtre (annoncé aux lecteurs d'écran). */
      opensDialog?: boolean;
      children?: ReactNode;
      href?: undefined;
      actions?: undefined;
    });

const ROW =
  "flex min-h-11 w-full min-w-0 items-center gap-sm border border-outline-variant bg-surface-container-lowest p-sm text-left";

export function DsListItem(props: DsListItemProps) {
  const { title, meta, icon, leading, className } = props;
  const body = (
    <>
      {leading ?? (icon && <DsIcon name={icon} className="shrink-0 text-on-surface-variant" />)}
      <span className="min-w-0 flex-1 basis-48">
        <span className="block font-body-md text-body-md text-primary wrap-anywhere">{title}</span>
        {meta && (
          <span className="block font-body-sm text-body-sm text-on-surface-variant wrap-anywhere">
            {meta}
          </span>
        )}
      </span>
    </>
  );

  if (props.href !== undefined) {
    return (
      <a href={props.href} className={cn(ROW, "hover:bg-surface-container", DS_FOCUS, className)}>
        {body}
        <DsIcon name="arrow_forward" className="shrink-0 text-primary" />
      </a>
    );
  }
  if (props.onClick) {
    const button = (
      <button
        type="button"
        aria-haspopup={props.opensDialog ? "dialog" : undefined}
        onClick={props.onClick}
        className={cn(
          ROW,
          "hover:bg-surface-container",
          DS_FOCUS,
          props.children ? "border-0" : className,
        )}
      >
        {body}
        <DsIcon name="arrow_forward" className="shrink-0 text-primary" />
      </button>
    );
    if (!props.children) return button;
    return (
      <div
        className={cn(
          "flex min-w-0 flex-col border border-outline-variant bg-surface-container-lowest",
          className,
        )}
      >
        {button}
        <div className="space-y-xs px-sm pb-sm">{props.children}</div>
      </div>
    );
  }
  if (props.children) {
    return (
      <div className={cn(ROW, "flex-col items-stretch", className)}>
        <div className="flex min-w-0 items-center gap-sm">{body}</div>
        {props.children}
        {props.actions && <div className="flex flex-wrap items-center gap-xs">{props.actions}</div>}
      </div>
    );
  }
  return (
    <div className={cn(ROW, "flex-wrap", className)}>
      {body}
      {props.actions && <div className="flex flex-wrap items-center gap-xs">{props.actions}</div>}
    </div>
  );
}
