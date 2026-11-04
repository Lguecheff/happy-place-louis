import { useEffect, useId, useRef, useState } from "react";
import { cn } from "@/lib/utils";
import { DsChoice } from "./ds-choice";
import { DS_INPUT } from "./ds-field";
import { DsIcon } from "./ds-icon";

type DsMultiSelectProps = {
  label: string;
  options: string[];
  /** Valeurs cochées ; vide = « allLabel ». */
  value: string[];
  onChange: (value: string[]) => void;
  /** Première case, cochée quand rien n'est choisi : la cocher vide la sélection. */
  allLabel: string;
  disabled?: boolean;
  className?: string;
};

/** Résumé du choix : « Toutes », « Product », « Product +2 » (même forme que les équipes d'un point bloquant). */
function multiSelectSummary(value: string[], allLabel: string) {
  if (!value.length) return allLabel;
  return value.length === 1 ? value[0] : `${value[0]} +${value.length - 1}`;
}

/**
 * Liste déroulante à choix multiple : un bouton au style d'un champ, qui ouvre des cases à cocher.
 * La liste reste dans la page (pas de portail) : elle peut vivre dans un panneau déjà ouvert,
 * comme celui de la recherche, sans lui faire perdre le focus.
 */
export function DsMultiSelect({
  label,
  options,
  value,
  onChange,
  allLabel,
  disabled,
  className,
}: DsMultiSelectProps) {
  const id = useId();
  const [open, setOpen] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);
  const buttonRef = useRef<HTMLButtonElement>(null);
  const isOpen = open && !disabled;

  useEffect(() => {
    if (!isOpen) return;
    const onPointerDown = (e: PointerEvent) => {
      if (!rootRef.current?.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener("pointerdown", onPointerDown);
    return () => document.removeEventListener("pointerdown", onPointerDown);
  }, [isOpen]);

  function toggle(option: string, checked: boolean) {
    onChange(
      checked
        ? options.filter((o) => o === option || value.includes(o))
        : value.filter((v) => v !== option),
    );
  }

  return (
    <div
      ref={rootRef}
      className={cn("relative min-w-0 space-y-xs", className)}
      onKeyDown={(e) => {
        if (e.key === "Escape" && isOpen) {
          // Échap ferme d'abord la liste, sans fermer ce qui l'entoure.
          e.preventDefault();
          e.stopPropagation();
          setOpen(false);
          buttonRef.current?.focus();
        }
      }}
      onBlur={(e) => {
        if (!e.currentTarget.contains(e.relatedTarget)) setOpen(false);
      }}
    >
      <span
        id={`${id}-label`}
        className="block font-label-md text-label-md normal-case tracking-normal text-on-surface-variant"
      >
        {label}
      </span>
      <button
        ref={buttonRef}
        type="button"
        disabled={disabled}
        aria-expanded={isOpen}
        aria-controls={`${id}-list`}
        aria-labelledby={`${id}-label ${id}-value`}
        onClick={() => setOpen((o) => !o)}
        className={cn(DS_INPUT, "flex items-center justify-between gap-xs text-left")}
      >
        <span aria-hidden="true" className="truncate">
          {multiSelectSummary(value, allLabel)}
        </span>
        <span id={`${id}-value`} className="sr-only">
          {value.length ? value.join(", ") : allLabel}
        </span>
        <DsIcon name={isOpen ? "expand_less" : "expand_more"} className="shrink-0" />
      </button>
      <div
        id={`${id}-list`}
        role="group"
        aria-labelledby={`${id}-label`}
        hidden={!isOpen}
        className="absolute left-0 top-full z-50 mt-xs max-h-[min(20rem,50vh)] w-full min-w-xs space-y-xs overflow-y-auto border border-outline bg-surface-container-lowest p-xs"
      >
        <DsChoice
          type="checkbox"
          label={allLabel}
          checked={!value.length}
          onChange={() => onChange([])}
        />
        {options.map((option) => (
          <DsChoice
            key={option}
            type="checkbox"
            label={option}
            checked={value.includes(option)}
            onChange={(e) => toggle(option, e.target.checked)}
          />
        ))}
      </div>
    </div>
  );
}
