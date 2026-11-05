import { useState } from "react";
import { toast } from "sonner";
import { DS_INPUT, DsButton, DsField, dsFieldErrorId, dsFieldHintId } from "@/components/ds";

export type MailAddressSettings = {
  /** Adresse enregistrée ; vide, aucun mail n'est préparé pour la personne. */
  value: string;
  /** Enregistre l'adresse (vide : la retire). Une erreur porte le message à afficher sous le champ. */
  onSave: (address: string) => Promise<void>;
  /** Texte de départ du champ, s'il diffère de `value` (maquette). */
  initialDraft?: string;
};

const FIELD_ID = "adresse-mails";

/** Champ « Adresse pour recevoir les mails », sous les préférences de notification. */
export function MailAddressField({ value, onSave, initialDraft }: MailAddressSettings) {
  const [draft, setDraft] = useState(initialDraft ?? value);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string>();
  const saved = value.trim() !== "";
  const unchanged = draft.trim().toLowerCase() === value.trim().toLowerCase();

  async function save(event: React.FormEvent) {
    event.preventDefault();
    if (saving || unchanged) return;
    const address = draft.trim();
    setSaving(true);
    setError(undefined);
    try {
      await onSave(address);
      // La base enregistre l'adresse en minuscules : le champ montre ce qui est enregistré.
      setDraft(address.toLowerCase());
      toast.success(address ? "Adresse enregistrée" : "Adresse retirée", {
        description: address
          ? "Les alertes cochées « Par mail » arriveront à cette adresse."
          : "Tu ne reçois plus aucun mail.",
      });
    } catch (e) {
      setError((e as Error).message || "Ton adresse n'a pas pu être enregistrée. Réessaie.");
    } finally {
      setSaving(false);
    }
  }

  const describedBy = [error && dsFieldErrorId(FIELD_ID), dsFieldHintId(FIELD_ID)]
    .filter(Boolean)
    .join(" ");

  return (
    <form noValidate onSubmit={save} className="border-t border-outline-variant pt-md">
      <DsField
        id={FIELD_ID}
        label="Adresse pour recevoir les mails"
        error={error}
        hint={saved ? "Elle n'est visible que par toi." : "Sans adresse, tu ne reçois aucun mail."}
      >
        <div className="flex flex-wrap gap-sm">
          <input
            id={FIELD_ID}
            type="email"
            inputMode="email"
            autoComplete="email"
            maxLength={254}
            placeholder="prenom.nom@exemple.fr"
            value={draft}
            aria-invalid={!!error || undefined}
            aria-describedby={describedBy}
            onChange={(e) => {
              setDraft(e.target.value);
              setError(undefined);
            }}
            className={`${DS_INPUT} min-w-0 flex-1 basis-64`}
          />
          <DsButton type="submit" busy={saving} disabled={unchanged && !saving}>
            Enregistrer l'adresse
          </DsButton>
        </div>
      </DsField>
    </form>
  );
}
