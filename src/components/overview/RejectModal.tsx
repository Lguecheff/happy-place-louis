import { useState } from "react";
import { DS_INPUT, DsButton, DsField } from "@/components/ds";
import { CharCounter } from "@/components/expandable-card";
import { ErrorSummary, Modal } from "@/components/manage/crud-ui";
import { REJECTION_CATEGORIES, type RejectionCategory, type Submission } from "@/lib/dashboard";
import { rejectionSchema, validate, type FieldErrors } from "@/lib/manage-schemas";

export function RejectModal({
  submission,
  pending,
  onCancel,
  onSubmit,
}: {
  submission: Submission;
  pending: boolean;
  onCancel: () => void;
  onSubmit: (reason: { rejection_category: RejectionCategory; rejection_note: string }) => void;
}) {
  const [form, setForm] = useState({ rejection_category: "", rejection_note: "" });
  const [errors, setErrors] = useState<FieldErrors>({});

  return (
    <Modal title="Refuser la demande" onClose={onCancel}>
      <form
        noValidate
        className="space-y-sm"
        onSubmit={(e) => {
          e.preventDefault();
          const res = validate(rejectionSchema, form);
          if (!res.ok) return setErrors(res.errors);
          setErrors({});
          onSubmit(res.data);
        }}
      >
        <p className="max-h-48 overflow-y-auto border border-outline-variant bg-surface-container p-xs font-body-sm text-body-sm italic text-on-surface-variant whitespace-pre-line wrap-anywhere">
          “{submission.content}”
        </p>
        <ErrorSummary errors={errors} />
        <DsField id="refus-motif" label="Motif du refus" error={errors.rejection_category}>
          <select
            id="refus-motif"
            className={DS_INPUT}
            value={form.rejection_category}
            onChange={(e) => setForm({ ...form, rejection_category: e.target.value })}
          >
            <option value="">Choisir un motif</option>
            {REJECTION_CATEGORIES.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
        </DsField>
        <DsField
          id="refus-raison"
          label="Raison du refus (obligatoire)"
          error={errors.rejection_note}
        >
          <textarea
            id="refus-raison"
            rows={4}
            className={DS_INPUT}
            value={form.rejection_note}
            placeholder="Explique au collaborateur pourquoi sa demande est refusée…"
            onChange={(e) => setForm({ ...form, rejection_note: e.target.value })}
          />
          <CharCounter value={form.rejection_note} max={500} />
        </DsField>
        <div className="flex flex-wrap justify-end gap-xs pt-sm">
          <DsButton onClick={onCancel}>Annuler</DsButton>
          <DsButton type="submit" variant="confirm" pending={pending}>
            Refuser la demande
          </DsButton>
        </div>
      </form>
    </Modal>
  );
}
