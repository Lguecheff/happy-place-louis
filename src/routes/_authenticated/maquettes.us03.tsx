import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import { BrandHeader } from "@/components/brand-header";
import { DS_INPUT, DsEmptyState, DsField, DsListItem, DsSection, toastUndo } from "@/components/ds";
import { RejectModal } from "@/components/overview/RejectModal";
import { daysSince, formatDays } from "@/components/overview/overview-utils";
import { SubmissionReader } from "@/components/submission-reader";
import type { Submission } from "@/lib/dashboard";

export const Route = createFileRoute("/_authenticated/maquettes/us03")({
  head: () => ({
    meta: [{ title: "Happy Place · Maquette des demandes à traiter" }],
  }),
  component: Us03Mockup,
});

// ---------------------------------------------------------------------------
// Données factices (fictif)
// ---------------------------------------------------------------------------

type Scenario = "manager" | "admin" | "aucune" | "collaborateur";

const SCENARIOS: { value: Scenario; label: string; name: string; hint: string }[] = [
  {
    value: "manager",
    label: "Manager (2 équipes)",
    name: "Kesha",
    hint: "Les demandes de Direction Commerciale et Marketing. Celle de Sofia Benali compte depuis son repassage automatique en attente.",
  },
  {
    value: "admin",
    label: "Admin (toutes les équipes)",
    name: "Claire",
    hint: "Les demandes en attente de toutes les équipes.",
  },
  {
    value: "aucune",
    label: "Aucune demande",
    name: "Kesha",
    hint: "Le bloc reste en place, avec un compteur à zéro.",
  },
  {
    value: "collaborateur",
    label: "Collaborateur (bloc absent)",
    name: "Thomas",
    hint: "Le bloc n'apparaît pas : les autres modules remontent en haut.",
  },
];

// (fictif) Équipes dont Kesha est manager.
const MY_TEAMS = ["Direction Commerciale", "Marketing"];

const DAY_MS = 86_400_000;
const daysAgo = (days: number) => new Date(Date.now() - days * DAY_MS).toISOString();

/** `pending_since` : création, ou dernier repassage automatique en attente. */
type MockRequest = Submission & { pending_since: string };

function pendingRequest(
  id: string,
  author_name: string,
  team: string,
  content: string,
  days: number,
  createdDays = days,
): MockRequest {
  return {
    id,
    author_name,
    team,
    content,
    status: "en attente",
    created_at: daysAgo(createdDays),
    pending_since: daysAgo(days),
  };
}

// (fictif) Demandes en attente, volontairement dans le désordre : la liste les trie.
const MOCK_REQUESTS: MockRequest[] = [
  pendingRequest(
    "d1",
    "Julien Caron",
    "Marketing",
    "Ajouter une rubrique « qui fait quoi » pour savoir à qui s'adresser selon le sujet.",
    12,
  ),
  pendingRequest(
    "d2",
    "Nina Petit",
    "Product",
    "À qui dois-je m'adresser pour obtenir un accès au job board premium ?",
    9,
  ),
  pendingRequest(
    "d3",
    "Thomas Diallo",
    "Direction Commerciale",
    "Les indicateurs du dashboard ne correspondent pas aux chiffres de notre tableau d'équipe. Pourrait-on revoir ensemble le mode de calcul avant la prochaine réunion commerciale, pour que les deux sources donnent enfin le même résultat ?",
    23,
  ),
  pendingRequest(
    "d4",
    "Hugo Martin",
    "People",
    "Prime trimestrielle par équipe plutôt qu'individuelle.",
    3,
  ),
  // Validée il y a plus d'un an, repassée automatiquement en attente il y a 6 jours.
  pendingRequest(
    "d5",
    "Sofia Benali",
    "Direction Commerciale",
    "Mettre en place un compte rendu client systématique sous 24 heures après chaque entretien candidat.",
    6,
    412,
  ),
  pendingRequest(
    "d6",
    "Julien Caron",
    "Marketing",
    "Publier chaque mois une analyse courte des tendances de recrutement dans la tech.",
    1,
  ),
];

function requestsFor(scenario: Scenario) {
  if (scenario === "manager") return MOCK_REQUESTS.filter((r) => MY_TEAMS.includes(r.team));
  if (scenario === "admin") return MOCK_REQUESTS;
  return [];
}

// ---------------------------------------------------------------------------
// Présentation
// ---------------------------------------------------------------------------

function ModulePlaceholder({
  id,
  title,
  className,
}: {
  id: string;
  title: string;
  className: string;
}) {
  return (
    <DsSection id={id} title={title} className={`bg-surface-container ${className}`}>
      <p className="font-body-sm text-body-sm text-on-surface-variant">
        Module existant, non modifié (fictif).
      </p>
    </DsSection>
  );
}

function Us03Mockup() {
  const [scenario, setScenario] = useState<Scenario>("manager");
  const [treatedIds, setTreatedIds] = useState<string[]>([]);
  const [reading, setReading] = useState<MockRequest | null>(null);
  const [rejecting, setRejecting] = useState<MockRequest | null>(null);
  const listRef = useRef<HTMLDivElement>(null);

  const current = SCENARIOS.find((s) => s.value === scenario) ?? SCENARIOS[0];
  // La plus ancienne en premier : c'est celle à traiter d'abord.
  const queue = requestsFor(scenario)
    .filter((r) => !treatedIds.includes(r.id))
    .sort((a, b) => a.pending_since.localeCompare(b.pending_since));

  const changeScenario = (value: Scenario) => {
    setScenario(value);
    setTreatedIds([]);
    setReading(null);
    setRejecting(null);
  };

  // La ligne traitée disparaît : le focus passe à la ligne suivante, ou au bloc s'il est vide.
  const focusRow = (id?: string) => {
    window.setTimeout(() => {
      const row = id && listRef.current?.querySelector<HTMLElement>(`[data-id="${id}"] button`);
      (row || listRef.current)?.focus();
    }, 0);
  };

  const markTreated = (request: MockRequest) => {
    setTreatedIds((ids) => [...ids, request.id]);
    focusRow(queue.find((r) => r.id !== request.id)?.id);
  };

  const validateRequest = (request: MockRequest) => {
    setReading(null);
    markTreated(request);
    toastUndo("Demande validée", () =>
      setTreatedIds((ids) => ids.filter((id) => id !== request.id)),
    );
  };

  const cancelReject = () => {
    if (rejecting) focusRow(rejecting.id);
    setRejecting(null);
  };

  // Modal ne gère ni le focus d'ouverture ni Échap : la maquette s'en charge.
  useEffect(() => {
    if (!rejecting) return;
    const timer = window.setTimeout(() => document.getElementById("refus-motif")?.focus(), 0);
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") cancelReject();
    };
    document.addEventListener("keydown", onKey);
    return () => {
      window.clearTimeout(timer);
      document.removeEventListener("keydown", onKey);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [rejecting]);

  return (
    <div className="bg-background text-on-surface font-body-md min-h-screen flex flex-col">
      <BrandHeader>
        <span className="font-label-md text-label-md normal-case tracking-normal text-on-surface-variant">
          Happy Place
        </span>
      </BrandHeader>
      <main className="flex-grow w-full max-w-interface mx-auto p-sm md:p-md space-y-md">
        <div className="flex flex-wrap items-end gap-sm border border-dashed border-outline-variant p-sm">
          <DsField id="maquette-etat" label="Maquette (fictif)" className="w-full md:w-72">
            <select
              id="maquette-etat"
              className={DS_INPUT}
              value={scenario}
              onChange={(e) => changeScenario(e.target.value as Scenario)}
            >
              {SCENARIOS.map((s) => (
                <option key={s.value} value={s.value}>
                  {s.label}
                </option>
              ))}
            </select>
          </DsField>
          <p className="min-w-0 flex-1 basis-64 font-body-sm text-body-sm text-on-surface-variant">
            {current.hint}
          </p>
        </div>

        <div className="space-y-xs">
          <h1 className="font-headline-lg text-headline-lg text-primary">Bonjour {current.name}</h1>
          <p className="font-body-md text-body-md text-on-surface-variant">
            Voici ce qui demande ton attention aujourd'hui.
          </p>
        </div>

        <div className="bento-grid">
          {scenario !== "collaborateur" && (
            <DsSection
              id="demandes"
              title={`Demandes à traiter (${queue.length})`}
              className="col-span-12"
            >
              <div ref={listRef} tabIndex={-1} className="focus:outline-none">
                {queue.length === 0 ? (
                  <DsEmptyState>Aucune demande à traiter.</DsEmptyState>
                ) : (
                  <ul className="space-y-xs">
                    {queue.map((r) => {
                      const days = daysSince(r.pending_since);
                      return (
                        <li key={r.id} data-id={r.id}>
                          <DsListItem
                            leading={
                              <span className="w-12 shrink-0 font-label-md text-label-md text-primary">
                                <span aria-hidden="true">{days} j</span>
                                <span className="sr-only">
                                  En attente depuis {formatDays(days)}.
                                </span>
                              </span>
                            }
                            title={<span className="line-clamp-2">{r.content}</span>}
                            meta={`${r.team} · ${r.author_name}`}
                            onClick={() => setReading(r)}
                          />
                        </li>
                      );
                    })}
                  </ul>
                )}
              </div>
            </DsSection>
          )}
          <ModulePlaceholder
            id="actus"
            title="Actualités"
            className="col-span-12 min-h-48 md:col-span-8 md:row-span-2"
          />
          <ModulePlaceholder
            id="blocages"
            title="Points bloquants"
            className="col-span-12 md:col-span-4"
          />
          <ModulePlaceholder
            id="indicateurs"
            title="Indicateurs"
            className="col-span-12 md:col-span-4"
          />
        </div>
      </main>

      <SubmissionReader
        submission={reading}
        onClose={() => setReading(null)}
        onApprove={() => reading && validateRequest(reading)}
        onReject={() => {
          setRejecting(reading);
          setReading(null);
        }}
      />
      {rejecting && (
        <RejectModal
          submission={rejecting}
          pending={false}
          onCancel={cancelReject}
          onSubmit={() => {
            markTreated(rejecting);
            setRejecting(null);
            toast.success("Demande refusée");
          }}
        />
      )}
    </div>
  );
}
