import type { ReactNode } from "react";
import { cn } from "@/lib/utils";
import { DS_FOCUS } from "./focus";

/** Style commun des champs de saisie : 44 px minimum, bordure de contrôle. */
export const DS_INPUT = cn(
  "min-h-11 w-full border border-outline bg-surface-container-lowest px-sm py-xs font-body-md text-body-md text-on-surface",
  "placeholder:text-on-surface-variant disabled:cursor-not-allowed disabled:bg-surface-container",
  DS_FOCUS,
);

type DsFieldProps = {
  /** `id` du champ placé dans `children` : relie le libellé au champ. */
  id: string;
  label: string;
  error?: string;
  children: ReactNode;
  className?: string;
};

export function DsField({ id, label, error, children, className }: DsFieldProps) {
  return (
    <div className={cn("min-w-0 space-y-xs", className)}>
      <label
        htmlFor={id}
        className="block font-label-md text-label-md normal-case tracking-normal text-on-surface-variant"
      >
        {label}
      </label>
      {children}
      {error && (
        <p role="alert" className="font-body-sm text-body-sm text-error">
          {error}
        </p>
      )}
    </div>
  );
}
