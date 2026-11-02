import type { ComponentProps } from "react";
import { cn } from "@/lib/utils";
import { DsIcon } from "./ds-icon";
import { DS_FOCUS } from "./focus";

const COUNT_MAX = 9;

type DsIconButtonProps = Omit<ComponentProps<"button">, "children" | "aria-label"> & {
  /** Nom d'un symbole Material Symbols. */
  icon: string;
  /** Lu à la place de l'icône : doit aussi dire ce que compte la pastille. */
  label: string;
  /** Pastille sur l'icône : rien à 0, « 9+ » au-delà de 9. */
  count?: number;
};

export function DsIconButton({
  icon,
  label,
  count = 0,
  type = "button",
  className,
  ...props
}: DsIconButtonProps) {
  return (
    <button
      type={type}
      aria-label={label}
      className={cn(
        "relative inline-flex size-11 shrink-0 items-center justify-center text-primary hover:bg-surface-container",
        DS_FOCUS,
        className,
      )}
      {...props}
    >
      <DsIcon name={icon} />
      {count > 0 && (
        <span
          aria-hidden="true"
          className="absolute right-0 top-0 inline-flex min-w-5 items-center justify-center bg-primary px-1 py-0.5 font-label-md text-label-md tracking-normal text-on-primary"
        >
          {count > COUNT_MAX ? `${COUNT_MAX}+` : count}
        </span>
      )}
    </button>
  );
}
