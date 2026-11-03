import { useEffect, useRef, useState } from "react";

export type AutosaveState = "idle" | "saving" | "saved" | "error";
export type AutosaveStatus = { state: AutosaveState; at?: Date };

/** Enregistre `value` et renvoie l'id du brouillon : créé si `id` est absent, mis à jour sinon. */
export type AutosaveFn<T> = (value: T, id: string | undefined) => Promise<string>;

type Options<T> = {
  value: T;
  /** Rien à enregistrer : pas de création, et un brouillon existant garde sa dernière version. */
  isEmpty: (value: T) => boolean;
  save: AutosaveFn<T>;
  /** Faux pendant une publication, un enregistrement manuel ou sur une actu publiée. */
  enabled: boolean;
  /** Ce qui est déjà enregistré au montage : par défaut, la première valeur reçue. */
  baseline?: T;
  delay?: number;
};

/** Un brouillon ouvert dans le rédacteur. Un nouveau brouillon (reset) ne mélange jamais ses enregistrements avec l'ancien. */
type Session<T> = {
  id?: string;
  saved: string;
  latest: T;
  tail: Promise<boolean>;
  current: boolean;
};

const serialize = (value: unknown) => JSON.stringify(value);

function newSession<T>(value: T, id?: string): Session<T> {
  return { id, saved: serialize(value), latest: value, tail: Promise.resolve(true), current: true };
}

/**
 * Enregistrement automatique d'un brouillon, 2 s après la dernière saisie.
 * Un seul enregistrement à la fois : une saisie arrivée pendant un enregistrement
 * part à la fin de celui-ci, avec la dernière version. En quittant la page
 * (pagehide) ou en démontant le rédacteur, une dernière tentative est faite.
 */
export function useAutosaveDraft<T>({
  value,
  isEmpty,
  save,
  enabled,
  baseline = value,
  delay = 2000,
}: Options<T>) {
  const [status, setStatus] = useState<AutosaveStatus>({ state: "idle" });
  const session = useRef<Session<T>>(newSession(baseline));
  const latest = useRef(value);
  const timer = useRef<ReturnType<typeof setTimeout>>(undefined);
  const fns = useRef({ isEmpty, save, enabled });
  latest.current = value;
  fns.current = { isEmpty, save, enabled };
  const key = serialize(value);

  async function attempt(s: Session<T>) {
    const v = s.latest;
    const k = serialize(v);
    if (k === s.saved || fns.current.isEmpty(v)) return true;
    if (s.current) setStatus({ state: "saving" });
    try {
      s.id = await fns.current.save(v, s.id);
      s.saved = k;
      if (s.current) setStatus({ state: "saved", at: new Date() });
      return true;
    } catch {
      if (s.current) setStatus({ state: "error" });
      return false;
    }
  }

  /** Les tentatives s'enchaînent : chacune enregistre la dernière version, ou rien si elle l'est déjà. */
  function run(s: Session<T>, v: T) {
    clearTimeout(timer.current);
    s.latest = v;
    s.tail = s.tail.then(() => attempt(s));
    return s.tail;
  }

  useEffect(() => {
    const s = session.current;
    if (!enabled || key === s.saved || fns.current.isEmpty(latest.current)) return;
    timer.current = setTimeout(() => run(s, latest.current), delay);
    return () => clearTimeout(timer.current);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key, enabled, delay]);

  useEffect(() => {
    if (!enabled) return;
    const onHide = () => void run(session.current, latest.current);
    window.addEventListener("pagehide", onHide);
    return () => window.removeEventListener("pagehide", onHide);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [enabled]);

  useEffect(
    () => () => {
      if (fns.current.enabled) void run(session.current, latest.current);
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [],
  );

  return {
    status,
    /** Id du brouillon enregistré, s'il existe. */
    draftId: () => session.current.id,
    /** Enregistre tout de suite ce qui ne l'est pas encore (fermeture du rédacteur, Réessayer). */
    flush: () => run(session.current, latest.current),
    /** Attend la fin de l'enregistrement en cours, sans en lancer un nouveau ; renvoie l'id du brouillon. */
    idle: async () => {
      clearTimeout(timer.current);
      const s = session.current;
      await s.tail;
      return s.id;
    },
    /** Change de brouillon : `baseline` est ce qui est déjà enregistré sous `id` (rien pour un nouveau). */
    reset: (baseline: T, id?: string) => {
      clearTimeout(timer.current);
      session.current.current = false;
      session.current = newSession(baseline, id);
      setStatus({ state: "idle" });
    },
  };
}
