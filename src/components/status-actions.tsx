import { useEffect, useRef, useState } from "react";
import { ManageIcon } from "@/components/manage/crud-ui";

// Changement de statut d'une demande (mêmes statuts partout : un statut peut toujours être corrigé).

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
    <div className="flex flex-wrap items-center gap-xs border border-outline-variant bg-surface-container-low p-sm">
      <p className="mr-auto font-label-sm text-label-sm uppercase text-on-surface-variant">
        Changer le statut
      </p>
      {STATUS_ACTIONS.filter((a) => a.status !== current).map((a) => (
        <button
          key={a.status}
          type="button"
          aria-haspopup={a.status === "refusée" ? "dialog" : undefined}
          onClick={() => onPick(a.status)}
          className={
            a.status === "validée"
              ? "bg-primary px-md py-xs font-label-md text-label-md uppercase text-on-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
              : "border border-outline bg-surface px-md py-xs font-label-md text-label-md uppercase text-primary hover:bg-surface-container focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
          }
        >
          {a.label}
        </button>
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
        className="inline-flex items-center justify-center gap-xs border border-outline bg-surface px-md py-xs font-label-md text-label-md uppercase text-primary hover:bg-surface-container focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
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
                className="block w-full px-sm py-xs text-left font-label-md text-label-md uppercase text-primary hover:bg-surface-container focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-primary"
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
