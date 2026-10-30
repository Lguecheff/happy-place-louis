import { useState } from "react";
import { DS_INPUT, DsButton, DsField } from "@/components/ds";
import { CharCounter } from "@/components/expandable-card";
import { ErrorSummary, Modal } from "@/components/manage/crud-ui";
import type { AppRole } from "@/lib/auth";
import type { SubmissionInput } from "@/lib/dashboard";
import { submissionSchema, validate, type FieldErrors } from "@/lib/manage-schemas";

export function RequestFormModal({
  role,
  teams,
  defaultName,
  pending,
  onCancel,
  onSubmit,
}: {
  role: AppRole;
  teams: string[];
  defaultName: string;
  pending: boolean;
  onCancel: () => void;
  onSubmit: (input: SubmissionInput, attachment: File | null) => void;
}) {
  const [form, setForm] = useState<SubmissionInput>({
    author_name: defaultName,
    team: role === "manager" && teams.length === 1 ? teams[0] : "",
    content: "",
    status: "en attente",
  });
  const [attachment, setAttachment] = useState<File | null>(null);
  const [errors, setErrors] = useState<FieldErrors>({});

  function send(e: React.FormEvent) {
    e.preventDefault();
    // Collaborators: team is set server-side from their account
    // Admin: always the « Admin » team (set server-side); manager: one of their teams
    const team = role === "collaborateur" ? "auto" : role === "admin" ? "Admin" : form.team;
    const result = validate(submissionSchema, { ...form, team, status: "en attente" });
    if (!result.ok) {
      setErrors(result.errors);
      return;
    }
    setErrors({});
    onSubmit(result.data, attachment);
  }

  return (
    <Modal title="Faire une demande" onClose={onCancel}>
      <form onSubmit={send} className="space-y-sm" noValidate>
        <ErrorSummary errors={errors} />
        <DsField id="demande-nom" label="Nom" error={errors.author_name}>
          <input
            id="demande-nom"
            className={DS_INPUT}
            value={form.author_name}
            maxLength={80}
            placeholder="Ton nom"
            onChange={(e) => setForm({ ...form, author_name: e.target.value })}
          />
        </DsField>
        {role === "manager" && (
          <DsField id="demande-equipe" label="Équipe" error={errors.team}>
            <select
              id="demande-equipe"
              required
              className={DS_INPUT}
              value={form.team}
              onChange={(e) => setForm({ ...form, team: e.target.value })}
            >
              <option value="">Choisis une de tes équipes</option>
              {teams.map((t) => (
                <option key={t} value={t}>
                  {t}
                </option>
              ))}
            </select>
          </DsField>
        )}
        {role === "admin" && (
          <p className="font-body-sm text-body-sm text-on-surface-variant">Équipe : Admin</p>
        )}
        <DsField id="demande-contenu" label="Demande" error={errors.content}>
          <textarea
            id="demande-contenu"
            rows={5}
            className={DS_INPUT}
            value={form.content}
            placeholder="Décris ta demande…"
            onChange={(e) => setForm({ ...form, content: e.target.value })}
          />
          <CharCounter value={form.content} max={2000} min={5} />
        </DsField>
        <DsField
          id="demande-document"
          label="Document PDF (optionnel, 20 Mo max)"
          error={errors.attachment}
        >
          <input
            id="demande-document"
            type="file"
            accept="application/pdf,.pdf"
            className="block min-h-11 w-full font-body-sm text-body-sm"
            onChange={(e) => {
              const f = e.target.files?.[0] ?? null;
              if (f && f.type !== "application/pdf") {
                setErrors({ ...errors, attachment: "Seuls les fichiers PDF sont acceptés." });
                e.target.value = "";
                setAttachment(null);
                return;
              }
              if (f && f.size > 20 * 1024 * 1024) {
                setErrors({ ...errors, attachment: "Le fichier dépasse 20 Mo." });
                e.target.value = "";
                setAttachment(null);
                return;
              }
              const { attachment: _a, ...rest } = errors;
              setErrors(rest);
              setAttachment(f);
            }}
          />
        </DsField>
        <div className="flex flex-wrap justify-end gap-xs pt-sm">
          <DsButton onClick={onCancel}>Annuler</DsButton>
          <DsButton type="submit" variant="confirm" pending={pending}>
            Envoyer
          </DsButton>
        </div>
      </form>
    </Modal>
  );
}
