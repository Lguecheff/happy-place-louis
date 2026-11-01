import type { ReactNode } from "react";
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
  /** Ligne entièrement cliquable (bouton) : flèche à droite, pas d'actions imbriquées. */
  | (Common & { onClick: () => void; href?: undefined; actions?: undefined; children?: undefined });

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
    return (
      <button
        type="button"
        onClick={props.onClick}
        className={cn(ROW, "hover:bg-surface-container", DS_FOCUS, className)}
      >
        {body}
        <DsIcon name="arrow_forward" className="shrink-0 text-primary" />
      </button>
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
