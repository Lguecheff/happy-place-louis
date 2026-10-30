import { useEffect, useRef, useState } from "react";
import { DsButton } from "@/components/ds";
import { ManageIcon } from "@/components/manage/crud-ui";

// Changement de statut d'une demande (mêmes statuts partout : un statut peut toujours être corrigé).

/** Bouton secondaire compact des actions de demande (« Voir le suivi », « Statut »). */
export const ACTION_BUTTON =
  "inline-flex min-h-11 items-center justify-center gap-xs border border-outline bg-surface px-sm py-1 font-label-md text-sm font-medium text-primary hover:bg-surface-container focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary";

export type Status = "en attente" | "validée" | "refusée" | "clôturée";

export const STATUS_ACTIONS: { status: Status; label: string }[] = [
  { status: "validée", label: "Valider" },
  { status: "refusée", label: "Refuser" },
  { status: "clôturée", label: "Clôturer" },
  { status: "en attente", label: "Remettre en attente" },
];

/** Actions de statut en boutons (dans le fil). Le statut actuel n'est pas proposé. */
export function StatusButtons({
  current,
  onPick,
}: {
  current: string;
  onPick: (s: Status) => void;
}) {
  return (
    <div className="flex flex-wrap items-center gap-xs border border-outline-variant bg-surface-container p-sm">
      <p className="mr-auto font-label-md text-label-md normal-case tracking-normal text-on-surface-variant">
        Changer le statut
      </p>
      {STATUS_ACTIONS.filter((a) => a.status !== current).map((a) => (
        <DsButton
          key={a.status}
          variant={a.status === "validée" ? "confirm" : "secondary"}
          aria-haspopup={a.status === "refusée" ? "dialog" : undefined}
          onClick={() => onPick(a.status)}
        >
          {a.label}
        </DsButton>
      ))}
    </div>
  );
}

/** Menu rapide de la liste : bouton qui déplie les statuts disponibles. Échap ferme et rend le focus. */
export function StatusMenu({
  id,
  current,
  onPick,
}: {
  id: string;
  current: string;
  onPick: (s: Status) => void;
}) {
  const [isOpen, setIsOpen] = useState(false);
  const wrapRef = useRef<HTMLDivElement>(null);
  const buttonRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (!isOpen) return;
    wrapRef.current?.querySelector<HTMLButtonElement>("[role='menuitem']")?.focus();
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        setIsOpen(false);
        buttonRef.current?.focus();
      }
    };
    const onClick = (e: MouseEvent) => {
      if (!wrapRef.current?.contains(e.target as Node)) setIsOpen(false);
    };
    document.addEventListener("keydown", onKey);
    document.addEventListener("mousedown", onClick);
    return () => {
      document.removeEventListener("keydown", onKey);
      document.removeEventListener("mousedown", onClick);
    };
  }, [isOpen]);

  return (
    <div ref={wrapRef} className="relative inline-block text-left">
      <button
        ref={buttonRef}
        type="button"
        aria-haspopup="menu"
        aria-expanded={isOpen}
        aria-controls={`statut-menu-${id}`}
        onClick={() => setIsOpen((v) => !v)}
        className={ACTION_BUTTON}
      >
        <ManageIcon name="edit" /> Statut
      </button>
      {isOpen && (
        <ul
          id={`statut-menu-${id}`}
          role="menu"
          aria-label="Changer le statut"
          className="absolute right-0 z-10 mt-1 min-w-48 border border-outline bg-surface-container-lowest"
        >
          {STATUS_ACTIONS.filter((a) => a.status !== current).map((a) => (
            <li key={a.status} role="none">
              <button
                type="button"
                role="menuitem"
                onClick={() => {
                  setIsOpen(false);
                  onPick(a.status);
                }}
                className="block min-h-11 w-full px-sm py-xs text-left font-label-md text-sm text-primary hover:bg-surface-container focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-primary"
              >
                {a.label}
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
