import * as DialogPrimitive from "@radix-ui/react-dialog";
import type { ReactNode } from "react";
import { DsIcon } from "@/components/ds";
import { DS_FOCUS } from "@/components/ds/focus";
import { cn } from "@/lib/utils";

/** Fenêtre de lecture seule : titre, sous-titre, contenu (focus piégé, Échap, clic fond). */
export function ReaderDialog({
  title,
  subtitle,
  onClose,
  onCloseAutoFocus,
  children,
}: {
  title: string;
  subtitle: ReactNode;
  onClose: () => void;
  /** Rend le focus à l'élément d'origine quand la fenêtre n'a pas de déclencheur. */
  onCloseAutoFocus?: (event: Event) => void;
  children: ReactNode;
}) {
  return (
    <DialogPrimitive.Root open onOpenChange={(o) => !o && onClose()}>
      <DialogPrimitive.Portal>
        <DialogPrimitive.Overlay className="fixed inset-0 z-50 bg-black/50" />
        <DialogPrimitive.Content
          onCloseAutoFocus={onCloseAutoFocus}
          className="fixed z-50 inset-0 md:inset-auto md:left-1/2 md:top-1/2 md:-translate-x-1/2 md:-translate-y-1/2 w-full md:w-[min(48rem,calc(100vw-2rem))] h-dvh md:h-auto md:max-h-[85vh] flex flex-col bg-surface-container-lowest border border-outline focus:outline-none"
        >
          <div className="flex items-start justify-between gap-sm border-b border-outline-variant p-md">
            <div className="min-w-0">
              <DialogPrimitive.Title className="font-headline-sm text-headline-sm text-primary wrap-anywhere">
                {title}
              </DialogPrimitive.Title>
              <DialogPrimitive.Description className="font-label-md text-label-md normal-case tracking-normal text-on-surface-variant">
                {subtitle}
              </DialogPrimitive.Description>
            </div>
            <DialogPrimitive.Close
              aria-label="Fermer"
              className={cn(
                "inline-flex size-11 shrink-0 items-center justify-center text-on-surface-variant hover:text-primary",
                DS_FOCUS,
              )}
            >
              <DsIcon name="close" />
            </DialogPrimitive.Close>
          </div>
          <div className="flex-1 overflow-y-auto p-md space-y-md">{children}</div>
        </DialogPrimitive.Content>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  );
}
