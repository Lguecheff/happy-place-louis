import type { InputHTMLAttributes, ReactNode, Ref } from "react";
import { cn } from "@/lib/utils";
import { DS_FOCUS } from "./focus";

const LEGEND =
  "mb-xs font-label-md text-label-md normal-case tracking-normal text-on-surface-variant";

type DsChoiceGroupProps = {
  id?: string;
  legend: string;
  error?: string;
  children: ReactNode;
  className?: string;
};

/** Groupe de boutons radio ou de cases à cocher : un fieldset et sa legend. */
export function DsChoiceGroup({ id, legend, error, children, className }: DsChoiceGroupProps) {
  return (
    <fieldset id={id} className={cn("min-w-0 space-y-xs", className)}>
      <legend className={LEGEND}>{legend}</legend>
      {children}
      {error && (
        <p role="alert" className="font-body-sm text-body-sm text-error">
          {error}
        </p>
      )}
    </fieldset>
  );
}

type DsChoiceProps = Omit<InputHTMLAttributes<HTMLInputElement>, "type"> & {
  type?: "radio" | "checkbox";
  label: string;
  /** Précision sous le libellé. */
  hint?: string;
  inputRef?: Ref<HTMLInputElement>;
};

/** Bouton radio ou case à cocher sur une ligne cliquable de 44 px minimum. */
export function DsChoice({
  type = "radio",
  label,
  hint,
  inputRef,
  className,
  ...input
}: DsChoiceProps) {
  return (
    <label
      className={cn(
        "flex min-h-11 items-start gap-sm border p-sm",
        input.checked ? "border-primary bg-surface-container" : "border-outline-variant",
        input.disabled ? "cursor-not-allowed bg-surface-container" : "cursor-pointer",
        className,
      )}
    >
      <input
        ref={inputRef}
        type={type}
        className={cn("mt-1 accent-primary", DS_FOCUS)}
        {...input}
      />
      <span className="min-w-0">
        <span className="block font-body-md text-body-md text-on-surface wrap-anywhere">
          {label}
        </span>
        {hint && (
          <span className="block font-body-sm text-body-sm text-on-surface-variant wrap-anywhere">
            {hint}
          </span>
        )}
      </span>
    </label>
  );
}
