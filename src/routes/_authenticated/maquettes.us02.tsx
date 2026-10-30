import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useRef, useState } from "react";
import { BrandHeader } from "@/components/brand-header";
import { CharCounter } from "@/components/expandable-card";
import { ManageIcon, Modal } from "@/components/manage/crud-ui";
import {
  StatusChip,
  SubmissionThreadView,
  sortSteps,
  type ThreadStep,
} from "@/components/submission-status-thread";
import { REJECTION_CATEGORIES, type Submission } from "@/lib/dashboard";
import { StatusButtons, StatusMenu, type Status } from "@/components/status-actions";
import { rejectionSchema, validate, type FieldErrors } from "@/lib/manage-schemas";

export const Route = createFileRoute("/_authenticated/maquettes/us02")({
  head: () => ({
    meta: [{ title: "Happy Place — Maquette : fil des demandes de mes équipes" }],
  }),
  component: Us02Mockup,
});

// ---------------------------------------------------------------------------
// Données factices (fictif)
// ---------------------------------------------------------------------------

type Scenario = "attente" | "validation" | "refus";

const SCENARIOS: { value: Scenario; label: string }[] = [
  { value: "attente", label: "Demande en attente" },
  { value: "validation", label: "Après validation" },
  { value: "refus", label: "Après refus" },
];

const ME = "Kesha"; // (fictif)

// (fictif) Équipes dont Kesha est manager (noms repris de supabase/seed.sql).
const MY_TEAMS = ["Direction Commerciale", "Marketing"];

type MockRequest = Pick<Submission, "id" | "content" | "team" | "author_name" | "created_at">;

// (fictif) Demandes de tous les services. Seules celles des équipes de Kesha sont affichées.
const MOCK_REQUESTS: MockRequest[] = [
  {
    id: "k1",
    author_name: "Thomas Diallo",
    team: "Direction Commerciale",
    content:
      "Les indicateurs du dashboard ne correspondent pas aux chiffres de notre tableau d'équipe.",
    created_at: "2026-10-21T09:12:00+02:00",
  },
  {
    id: "k2",
    author_name: "Julien Caron",
    team: "Marketing",
    content: "Ajouter une rubrique « qui fait quoi » pour savoir à qui s'adresser selon le sujet.",
    created_at: "2026-10-29T15:30:00+02:00",
  },
  {
    id: "k3",
    author_name: "Sofia Benali",
    team: "Direction Commerciale",
    content:
      "Mettre en place un compte rendu client systématique sous 24 heures après chaque entretien candidat.",
    created_at: "2026-10-13T11:05:00+02:00",
  },
  {
    id: "k4",
    author_name: "Julien Caron",
    team: "Marketing",
    content: "Publier chaque mois une analyse courte des tendances de recrutement dans la tech.",
    created_at: "2026-10-12T10:40:00+02:00",
  },
  // Équipes dont Kesha n'est pas manager : jamais affichées.
  {
    id: "x1",
    author_name: "Nina Petit",
    team: "Product",
    content: "À qui dois-je m'adresser pour obtenir un accès au job board premium ?",
    created_at: "2026-10-18T14:00:00+02:00",
  },
  {
    id: "x2",
    author_name: "Hugo Martin",
    team: "People",
    content: "Prime trimestrielle par équipe plutôt qu'individuelle.",
    created_at: "2026-10-15T16:20:00+02:00",
  },
];

function step(
  id: string,
  changed_at: string,
  old_status: string | null,
  new_status: string,
  name: string,
  rejection?: { category: string; note: string },
): ThreadStep {
  return {
    id,
    changed_at,
    old_status,
    new_status,
    changed_by_name: name,
    changed_by_email: null,
    is_automatic: false,
    rejection_category: rejection?.category ?? null,
    rejection_note: rejection?.note ?? null,
  };
}

// (fictif) Fils de départ. La demande k1 suit le scénario choisi ; les autres sont fixes.
function initialSteps(scenario: Scenario): Record<string, ThreadStep[]> {
  const k1 = [step("k1-0", "2026-10-21T09:12:00+02:00", null, "en attente", "Thomas Diallo")];
  if (scenario === "validation")
    k1.push(step("k1-1", "2026-10-22T10:02:00+02:00", "en attente", "validée", ME));
  if (scenario === "refus")
    k1.push(
      step("k1-1", "2026-10-22T10:02:00+02:00", "en attente", "refusée", ME, {
        category: REJECTION_CATEGORIES[0],
        note: "Précise de quels indicateurs il s'agit et joins un exemple de chiffre attendu.",
      }),
    );
  return {
    k1,
    k2: [step("k2-0", "2026-10-29T15:30:00+02:00", null, "en attente", "Julien Caron")],
    k3: [
      step("k3-0", "2026-10-13T11:05:00+02:00", null, "en attente", "Sofia Benali"),
      step("k3-1", "2026-10-14T09:45:00+02:00", "en attente", "validée", "Karim Haddad"),
    ],
    k4: [
      step("k4-0", "2026-10-12T10:40:00+02:00", null, "en attente", "Julien Caron"),
      step("k4-1", "2026-10-14T09:50:00+02:00", "en attente", "refusée", "Karim Haddad", {
        category: REJECTION_CATEGORIES[2],
        note: "Une analyse mensuelle équivalente est déjà publiée par la Direction Conseil.",
      }),
    ],
  };
}

const dateShort = new Intl.DateTimeFormat("fr-FR", { dateStyle: "medium" });

// ---------------------------------------------------------------------------
// Modale de refus
// ---------------------------------------------------------------------------

function RejectModal({
  content,
  onCancel,
  onConfirm,
}: {
  content: string;
  onCancel: () => void;
  onConfirm: (category: string, note: string) => void;
}) {
  const [category, setCategory] = useState("");
  const [note, setNote] = useState("");
  const [errors, setErrors] = useState<FieldErrors>({});
  const categoryRef = useRef<HTMLSelectElement>(null);

  // Focus dans la fenêtre à l'ouverture, Échap pour annuler.
  useEffect(() => {
    categoryRef.current?.focus();
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onCancel();
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <Modal title="Refuser la demande" onClose={onCancel}>
      <form
        noValidate
        className="space-y-sm"
        onSubmit={(e) => {
          e.preventDefault();
          const res = validate(rejectionSchema, {
            rejection_category: category,
            rejection_note: note,
          });
          if (!res.ok) return setErrors(res.errors);
          onConfirm(res.data.rejection_category, res.data.rejection_note);
        }}
      >
        <p className="max-h-48 overflow-y-auto border border-outline-variant bg-surface-container-low p-xs font-body-md text-body-md italic text-on-surface-variant whitespace-pre-line wrap-anywhere">
          “{content}”
        </p>
        <div className="space-y-xs">
          <label
            htmlFor="us02-categorie"
            className="block font-label-sm text-label-sm uppercase text-on-surface-variant"
          >
            Catégorie du refus
          </label>
          <select
            id="us02-categorie"
            ref={categoryRef}
            required
            aria-invalid={!!errors.rejection_category}
            aria-describedby={errors.rejection_category ? "us02-categorie-err" : undefined}
            value={category}
            onChange={(e) => setCategory(e.target.value)}
            className="w-full border border-outline-variant bg-card p-sm font-body-md text-body-md text-on-surface focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
          >
            <option value="">Choisir une catégorie</option>
            {REJECTION_CATEGORIES.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
          {errors.rejection_category && (
            <p
              id="us02-categorie-err"
              role="alert"
              className="font-body-md text-body-md text-error"
            >
              {errors.rejection_category}
            </p>
          )}
        </div>
        <div className="space-y-xs">
          <label
            htmlFor="us02-motif"
            className="block font-label-sm text-label-sm uppercase text-on-surface-variant"
          >
            Motif du refus (500 caractères maximum)
          </label>
          <textarea
            id="us02-motif"
            rows={4}
            required
            aria-invalid={!!errors.rejection_note}
            aria-describedby={errors.rejection_note ? "us02-motif-err" : undefined}
            value={note}
            placeholder="Explique à la personne pourquoi sa demande est refusée."
            onChange={(e) => setNote(e.target.value)}
            className="w-full border border-outline-variant bg-card p-sm font-body-md text-body-md text-on-surface focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
          />
          <CharCounter value={note} max={500} />
          {errors.rejection_note && (
            <p id="us02-motif-err" role="alert" className="font-body-md text-body-md text-error">
              {errors.rejection_note}
            </p>
          )}
        </div>
        <div className="flex justify-end gap-xs pt-sm">
          <button
            type="button"
            onClick={onCancel}
            className="border border-outline bg-surface px-md py-xs font-label-md text-label-md uppercase text-primary hover:bg-surface-container focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
          >
            Annuler
          </button>
          <button
            type="submit"
            className="bg-primary px-lg py-xs font-label-md text-label-md uppercase text-on-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
          >
            Refuser la demande
          </button>
        </div>
      </form>
    </Modal>
  );
}

// ---------------------------------------------------------------------------
// Présentation
// ---------------------------------------------------------------------------

function Us02Mockup() {
  const [scenario, setScenario] = useState<Scenario>("attente");
  const [stepsById, setStepsById] = useState(() => initialSteps("attente"));
  const [openId, setOpenId] = useState<string | null>(null);
  const [rejectingId, setRejectingId] = useState<string | null>(null);

  const changeScenario = (value: Scenario) => {
    setScenario(value);
    setStepsById(initialSteps(value));
    setOpenId(null);
    setRejectingId(null);
  };

  // Seules les demandes des équipes de Kesha sont listées.
  const requests = MOCK_REQUESTS.filter((r) => MY_TEAMS.includes(r.team)).map((r) => {
    const steps = sortSteps(stepsById[r.id] ?? []);
    return { ...r, steps, status: steps[0]?.new_status ?? "en attente" };
  });
  const open = requests.find((r) => r.id === openId) ?? null;
  const rejectTarget = requests.find((r) => r.id === rejectingId) ?? null;

  // Chaque changement ajoute une étape au fil, y compris les corrections : rien n'est écrasé.
  const addStep = (id: string, status: Status, rejection?: [string, string]) => {
    const prev = stepsById[id] ?? [];
    const old = sortSteps(prev)[0]?.new_status ?? "en attente";
    const next = step(
      `${id}-${prev.length}`,
      new Date().toISOString(),
      old,
      status,
      ME,
      rejection && { category: rejection[0], note: rejection[1] },
    );
    setStepsById({ ...stepsById, [id]: [...prev, next] });
  };

  const pick = (id: string, status: Status) => {
    if (status === "refusée") setRejectingId(id);
    else addStep(id, status);
  };

  return (
    <div className="bg-background text-on-surface font-body-md min-h-screen flex flex-col">
      <BrandHeader />
      <main className="flex-grow w-full max-w-interface mx-auto p-sm md:p-md space-y-md">
        <div className="flex flex-wrap items-center gap-xs border border-dashed border-outline-variant bg-surface px-sm py-xs">
          <label
            htmlFor="mockup-scenario"
            className="font-label-sm text-label-sm uppercase text-on-surface-variant"
          >
            Maquette (fictif)
          </label>
          <select
            id="mockup-scenario"
            value={scenario}
            onChange={(e) => changeScenario(e.target.value as Scenario)}
            className="border border-outline-variant bg-card px-xs py-1 font-label-md text-label-md text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
          >
            {SCENARIOS.map((s) => (
              <option key={s.value} value={s.value}>
                {s.label}
              </option>
            ))}
          </select>
          <span className="font-body-sm text-body-sm text-on-surface-variant">
            L'état s'applique à la première demande de la liste.
          </span>
        </div>

        <div className="space-y-sm mb-lg">
          <p className="font-label-sm text-label-sm text-on-surface-variant uppercase tracking-widest">
            Espace manager · {ME} · {MY_TEAMS.join(", ")}
          </p>
          <h1 className="font-headline-lg text-headline-lg text-primary">
            Demandes de mes équipes
          </h1>
        </div>

        <div className="bento-grid">
          <section
            aria-labelledby="demandes-equipes-titre"
            className="col-span-12 min-w-0 bg-surface-container-lowest border border-outline-variant p-md"
          >
            <h2
              id="demandes-equipes-titre"
              className="font-headline-sm text-headline-sm text-primary border-b border-outline-variant pb-sm mb-xs"
            >
              Demandes
            </h2>
            <p className="mb-md font-body-sm text-body-sm text-on-surface-variant">
              Seules les demandes de vos équipes sont affichées.
            </p>
            <div className="overflow-x-auto">
              <table className="w-full text-left">
                <caption className="sr-only">Demandes des équipes {MY_TEAMS.join(" et ")}</caption>
                <thead>
                  <tr className="border-b border-outline-variant font-label-sm text-label-sm uppercase text-on-surface-variant">
                    <th scope="col" className="py-xs pr-sm font-normal">
                      Équipe
                    </th>
                    <th scope="col" className="py-xs pr-sm font-normal">
                      Auteur
                    </th>
                    <th scope="col" className="py-xs pr-sm font-normal">
                      Extrait
                    </th>
                    <th scope="col" className="py-xs pr-sm font-normal">
                      Statut
                    </th>
                    <th scope="col" className="py-xs font-normal">
                      <span className="sr-only">Actions</span>
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {requests.map((r) => (
                    <tr
                      key={r.id}
                      className="border-b border-outline-variant align-top last:border-b-0"
                    >
                      <td className="py-sm pr-sm font-label-sm text-label-sm uppercase text-on-surface-variant">
                        {r.team}
                      </td>
                      <td className="py-sm pr-sm font-body-md text-body-md text-primary">
                        {r.author_name}
                        <span className="block font-body-sm text-body-sm text-on-surface-variant">
                          {dateShort.format(new Date(r.created_at))}
                        </span>
                      </td>
                      <td className="max-w-md py-sm pr-sm font-body-md text-body-md text-on-surface wrap-anywhere">
                        <span className="line-clamp-2">{r.content}</span>
                      </td>
                      <td className="py-sm pr-sm">
                        <StatusChip status={r.status} />
                      </td>
                      <td className="py-sm text-right">
                        <div className="flex flex-wrap justify-end gap-xs">
                          <button
                            type="button"
                            aria-haspopup="dialog"
                            onClick={() => setOpenId(r.id)}
                            className="inline-flex items-center justify-center gap-xs border border-outline bg-surface px-md py-xs font-label-md text-label-md uppercase text-primary hover:bg-surface-container focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
                          >
                            <ManageIcon name="history" /> Voir le fil
                          </button>
                          <StatusMenu
                            id={r.id}
                            current={r.status}
                            onPick={(st) => pick(r.id, st)}
                          />
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>
        </div>
      </main>

      {open && !rejectTarget && (
        <SubmissionThreadView
          content={open.content}
          team={`${open.team} · ${open.author_name}`}
          steps={open.steps}
          readOnly={false}
          actions={<StatusButtons current={open.status} onPick={(st) => pick(open.id, st)} />}
          onClose={() => setOpenId(null)}
        />
      )}
      {rejectTarget && (
        <RejectModal
          content={rejectTarget.content}
          onCancel={() => setRejectingId(null)}
          onConfirm={(category, note) => {
            addStep(rejectTarget.id, "refusée", [category, note]);
            setRejectingId(null);
          }}
        />
      )}
    </div>
  );
}
