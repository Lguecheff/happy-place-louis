import {
  AlertDialog,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { DsButton } from "@/components/ds";

/** Confirmation d'une action sans annulation possible. */
export function ConfirmDialog({
  open,
  title,
  description,
  confirmLabel,
  danger,
  onConfirm,
  onCancel,
}: {
  open: boolean;
  title: string;
  description: string;
  confirmLabel: string;
  danger?: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}) {
  return (
    <AlertDialog open={open} onOpenChange={(o) => !o && onCancel()}>
      <AlertDialogContent className="max-w-[calc(100vw-2rem)] border-outline bg-surface-container-lowest p-md shadow-none sm:max-w-lg">
        <AlertDialogHeader className="text-left">
          <AlertDialogTitle className="font-headline-sm text-headline-sm font-normal text-primary wrap-anywhere">
            {title}
          </AlertDialogTitle>
          <AlertDialogDescription className="font-body-md text-body-md text-on-surface-variant">
            {description}
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter className="gap-xs sm:space-x-0">
          <DsButton onClick={onCancel}>Annuler</DsButton>
          <DsButton
            variant="confirm"
            onClick={onConfirm}
            className={danger ? "border-error text-error" : undefined}
          >
            {confirmLabel}
          </DsButton>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
