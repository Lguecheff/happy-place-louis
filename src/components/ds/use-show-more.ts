/**
 * Tranches d'une liste (US24) : `useShowMore` tient le nombre affiché, qui ne baisse jamais tout
 * seul (une mise à jour ne replie pas la liste), met le focus sur le premier élément ajouté et
 * prépare l'annonce. L'affichage est `DsShowMore`.
 */
import { useEffect, useRef, useState } from "react";
import { cn } from "@/lib/utils";
import { DS_FOCUS } from "./focus";

/** Ce qui est annoncé après un clic : « 1 demande ajoutée. », « 10 demandes ajoutées. » */
export type DsShowMoreNoun = { one: string; many: string };

export const SHOW_MORE_NEWS: DsShowMoreNoun = { one: "actu ajoutée", many: "actus ajoutées" };
export const SHOW_MORE_REQUESTS: DsShowMoreNoun = {
  one: "demande ajoutée",
  many: "demandes ajoutées",
};

export function useShowMore({
  total,
  first,
  step = 10,
  noun,
  limit: controlledLimit,
  onLimitChange,
}: {
  total: number;
  /** Taille de la première tranche. */
  first: number;
  /** Nombre ajouté à chaque clic (10 par défaut). */
  step?: number;
  noun: DsShowMoreNoun;
  /** Nombre demandé, si le parent le garde (ex. un onglet qui se démonte). */
  limit?: number;
  onLimitChange?: (limit: number) => void;
}) {
  const [ownLimit, setOwnLimit] = useState(first);
  const limit = controlledLimit ?? ownLimit;
  const setLimit = onLimitChange ?? setOwnLimit;
  const [announce, setAnnounce] = useState("");
  const [focusIndex, setFocusIndex] = useState<number | null>(null);
  const items = useRef(new Map<number, HTMLElement>());
  const shown = Math.min(limit, total);

  useEffect(() => {
    if (focusIndex === null) return;
    items.current.get(focusIndex)?.focus();
    setFocusIndex(null);
  }, [focusIndex]);

  function more() {
    const added = Math.min(step, total - shown);
    if (added <= 0) return;
    setLimit(shown + step);
    setFocusIndex(shown);
    setAnnounce(`${added} ${added > 1 ? noun.many : noun.one}.`);
  }

  return {
    shown,
    total,
    announce,
    more,
    /** Revient à la première tranche (ex. changement de filtre). */
    reset: () => {
      setLimit(first);
      setAnnounce("");
    },
    /** À poser sur l'enveloppe de chaque élément affiché : reçoit le focus quand il vient d'être ajouté. */
    itemProps: (index: number) => ({
      tabIndex: -1,
      className: cn("min-w-0", DS_FOCUS),
      ref: (el: HTMLDivElement | null) => {
        if (el) items.current.set(index, el);
        else items.current.delete(index);
      },
    }),
  };
}
