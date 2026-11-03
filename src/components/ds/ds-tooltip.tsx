import * as TooltipPrimitive from "@radix-ui/react-tooltip";
import type { ReactNode } from "react";
import { cn } from "@/lib/utils";

type DsTooltipProps = {
  /** Élément qui déclenche l'infobulle : il doit pouvoir recevoir le focus. */
  children: ReactNode;
  /** Texte court, lu par les lecteurs d'écran comme description du déclencheur. */
  content: ReactNode;
  className?: string;
};

/**
 * Infobulle au survol et au focus clavier (Échap ferme). Elle ne s'ouvre pas au toucher :
 * le même texte doit rester accessible par un bouton ou un lien à côté.
 */
export function DsTooltip({ children, content, className }: DsTooltipProps) {
  return (
    <TooltipPrimitive.Provider delayDuration={300}>
      <TooltipPrimitive.Root>
        <TooltipPrimitive.Trigger asChild>{children}</TooltipPrimitive.Trigger>
        <TooltipPrimitive.Portal>
          <TooltipPrimitive.Content
            side="bottom"
            align="start"
            sideOffset={8}
            collisionPadding={12}
            className={cn(
              "z-50 w-[calc(100vw-1.5rem)] max-w-xs border border-outline bg-surface-container-lowest p-sm text-on-surface",
              className,
            )}
          >
            {content}
          </TooltipPrimitive.Content>
        </TooltipPrimitive.Portal>
      </TooltipPrimitive.Root>
    </TooltipPrimitive.Provider>
  );
}
