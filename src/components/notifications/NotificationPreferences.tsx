import { useState } from "react";
import { DsChoice, DsChoiceGroup, DsEmptyState, DsIcon } from "@/components/ds";
import { ReaderDialog } from "@/components/reader-dialog";
import {
  CHANNEL_LABELS,
  DEFAULT_CHANNELS,
  type NotificationChannel,
  type NotificationKindDef,
  type PreferenceKind,
  type PreferenceValues,
} from "./notification-kinds";

export type NotificationPreferencesProps = {
  /** Types ouverts au rôle, déjà filtrés (voir `notificationKindsFor`). */
  kinds: NotificationKindDef[];
  values: PreferenceValues;
  /** Enregistre un choix ; une erreur remet la case dans son état précédent. */
  onChange: (kind: PreferenceKind, channel: NotificationChannel, checked: boolean) => Promise<void>;
  onClose: () => void;
  onCloseAutoFocus?: (event: Event) => void;
};

const key = (kind: PreferenceKind, channel: NotificationChannel) => `${kind}:${channel}`;

/** Fenêtre « Préférences de notification » : une ligne par type, enregistrée à chaque clic. */
export function NotificationPreferences({
  kinds,
  values,
  onChange,
  onClose,
  onCloseAutoFocus,
}: NotificationPreferencesProps) {
  // Choix affichés avant que `values` ne les reflète, et cases en cours d'enregistrement.
  const [shown, setShown] = useState<Record<string, boolean>>({});
  const [saving, setSaving] = useState<Set<string>>(new Set());
  const [errors, setErrors] = useState<Partial<Record<PreferenceKind, string>>>({});
  const [saved, setSaved] = useState("");

  function isChecked(def: NotificationKindDef, channel: NotificationChannel) {
    if (def.locked?.includes(channel)) return true;
    return shown[key(def.kind, channel)] ?? (values[def.kind] ?? DEFAULT_CHANNELS)[channel];
  }

  async function toggle(def: NotificationKindDef, channel: NotificationChannel, checked: boolean) {
    const k = key(def.kind, channel);
    if (saving.has(k)) return;
    const previous = isChecked(def, channel);
    setShown((s) => ({ ...s, [k]: checked }));
    setSaving((s) => new Set(s).add(k));
    setErrors((e) => ({ ...e, [def.kind]: undefined }));
    setSaved("");
    try {
      await onChange(def.kind, channel, checked);
      setSaved(
        `${def.label}, ${CHANNEL_LABELS[channel].toLowerCase()} : ${checked ? "activé" : "désactivé"}.`,
      );
    } catch {
      setShown((s) => ({ ...s, [k]: previous }));
      setErrors((e) => ({
        ...e,
        [def.kind]:
          "Ton choix n'a pas pu être enregistré : la case est revenue à son état précédent. Réessaie.",
      }));
    } finally {
      setSaving((s) => {
        const next = new Set(s);
        next.delete(k);
        return next;
      });
    }
  }

  return (
    <ReaderDialog
      title="Préférences de notification"
      subtitle="Chaque choix est enregistré dès que tu cliques."
      onClose={onClose}
      onCloseAutoFocus={onCloseAutoFocus}
    >
      {kinds.length === 0 ? (
        <DsEmptyState>
          Aucune notification ne te concerne pour l'instant : rien à régler ici.
        </DsEmptyState>
      ) : (
        <>
          <p className="font-body-sm text-body-sm text-on-surface-variant">
            L'app n'envoie pas encore de mail : ton choix « Par mail » est gardé pour plus tard.
          </p>
          {kinds.map((def) => (
            <DsChoiceGroup key={def.kind} legend={def.label} error={errors[def.kind]}>
              <div className="grid gap-xs sm:grid-cols-2">
                {def.channels.map((channel) => {
                  const locked = def.locked?.includes(channel);
                  return (
                    <DsChoice
                      key={channel}
                      type="checkbox"
                      label={CHANNEL_LABELS[channel]}
                      hint={locked ? "Toujours activé" : undefined}
                      disabled={locked}
                      checked={isChecked(def, channel)}
                      aria-busy={saving.has(key(def.kind, channel)) || undefined}
                      onChange={(e) => toggle(def, channel, e.target.checked)}
                    />
                  );
                })}
              </div>
            </DsChoiceGroup>
          ))}
        </>
      )}
      <p
        role="status"
        className="flex items-center gap-xs font-body-sm text-body-sm text-on-surface-variant"
      >
        {saved && (
          <>
            <DsIcon name="check" className="text-success" />
            Enregistré : {saved}
          </>
        )}
      </p>
    </ReaderDialog>
  );
}
