import * as PopoverPrimitive from "@radix-ui/react-popover";
import { useId, type ReactNode } from "react";
import { cn } from "@/lib/utils";

type DsPopoverProps = {
  /** Élément qui ouvre le panneau : il reçoit le focus à la fermeture. */
  trigger: ReactNode;
  title: string;
  /** Une action à droite du titre, en général un DsButton « link ». */
  action?: ReactNode;
  open?: boolean;
  onOpenChange?: (open: boolean) => void;
  children: ReactNode;
  className?: string;
};

/** Panneau déroulant ancré à un élément (Entrée ouvre, Échap ferme et rend le focus). */
export function DsPopover({
  trigger,
  title,
  action,
  open,
  onOpenChange,
  children,
  className,
}: DsPopoverProps) {
  const titleId = useId();
  return (
    <PopoverPrimitive.Root open={open} onOpenChange={onOpenChange}>
      <PopoverPrimitive.Trigger asChild>{trigger}</PopoverPrimitive.Trigger>
      <PopoverPrimitive.Portal>
        <PopoverPrimitive.Content
          aria-labelledby={titleId}
          align="end"
          sideOffset={8}
          collisionPadding={12}
          className={cn(
            "z-40 flex max-h-[min(32rem,var(--radix-popover-content-available-height))] w-[calc(100vw-1.5rem)] max-w-md flex-col border border-outline bg-surface-container-lowest focus:outline-none",
            className,
          )}
        >
          <div className="flex flex-wrap items-center justify-between gap-xs border-b border-outline-variant p-sm">
            <h2 id={titleId} className="font-headline-sm text-headline-sm text-primary">
              {title}
            </h2>
            {action}
          </div>
          <div className="min-h-0 flex-1 overflow-y-auto p-sm">{children}</div>
        </PopoverPrimitive.Content>
      </PopoverPrimitive.Portal>
    </PopoverPrimitive.Root>
  );
}
