/**
 * Tranches d'une liste (US24) : `useShowMore` tient le nombre affiché, qui ne baisse jamais tout
 * seul (une mise à jour ne replie pas la liste). « Voir plus » ajoute une tranche et met le focus
 * sur le premier élément ajouté ; « Voir moins » retire la dernière tranche et met le focus sur le
 * dernier élément qui reste. Chaque clic est annoncé. L'affichage est `DsShowMore`.
 */
import { useEffect, useRef, useState } from "react";
import { cn } from "@/lib/utils";
import { DS_FOCUS } from "./focus";

/** Ce qui est annoncé après un clic : « 10 demandes ajoutées. », « 1 demande masquée. » */
export type DsShowMoreNoun = { one: string; many: string };

export const SHOW_MORE_NEWS: DsShowMoreNoun = { one: "actu", many: "actus" };
export const SHOW_MORE_REQUESTS: DsShowMoreNoun = { one: "demande", many: "demandes" };

/** Accord au féminin (« actu », « demande ») : « 1 actu ajoutée », « 10 actus masquées ». */
function countText(n: number, noun: DsShowMoreNoun, verb: "ajoutée" | "masquée") {
  return n > 1 ? `${n} ${noun.many} ${verb}s.` : `${n} ${noun.one} ${verb}.`;
}

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
  /** Nombre ajouté (ou retiré) à chaque clic (10 par défaut). */
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

  /** Vide puis remplit la zone : un texte identique au précédent est quand même relu. */
  function say(text: string) {
    setAnnounce("");
    window.setTimeout(() => setAnnounce(text), 50);
  }

  function more() {
    const added = Math.min(step, total - shown);
    if (added <= 0) return;
    setLimit(shown + step);
    setFocusIndex(shown);
    say(countText(added, noun, "ajoutée"));
  }

  /** Revient à la tranche précédente (25 → 24 → 14 → 4), jamais sous la première. */
  function less() {
    if (shown <= first) return;
    const target = first + Math.floor((shown - first - 1) / step) * step;
    setLimit(target);
    setFocusIndex(target - 1);
    say(countText(shown - target, noun, "masquée"));
  }

  return {
    shown,
    total,
    announce,
    more,
    less,
    /** Il y a plus que la première tranche à l'écran : « Voir moins » s'affiche. */
    canLess: shown > first,
    /** Revient à la première tranche (ex. changement de filtre). */
    reset: () => {
      setLimit(first);
      setAnnounce("");
    },
    /** À poser sur l'enveloppe de chaque élément affiché : reçoit le focus après un clic. */
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
