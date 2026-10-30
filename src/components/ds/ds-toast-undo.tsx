import { toast } from "sonner";

/**
 * Affiche un message avec une action « Annuler ».
 * À utiliser après une action réversible plutôt qu'une fenêtre de confirmation.
 */
export function toastUndo(
  message: string,
  onUndo: () => void,
  options: { duration?: number } = {},
) {
  return toast(message, {
    duration: options.duration ?? 8000,
    action: { label: "Annuler", onClick: onUndo },
    classNames: { actionButton: "!min-h-11 !px-sm" },
  });
}
