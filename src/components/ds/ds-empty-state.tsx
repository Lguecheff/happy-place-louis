import type { ReactNode } from "react";
import { cn } from "@/lib/utils";

type DsEmptyStateProps = {
  /** Texte court, au tutoiement (ex. « Tu n'as encore aucune demande. »). */
  children: ReactNode;
  /** Une seule action possible, en général un DsButton « secondary ». */
  action?: ReactNode;
  className?: string;
};

export function DsEmptyState({ children, action, className }: DsEmptyStateProps) {
  return (
    <div
      className={cn(
        "flex flex-col items-start gap-sm border border-dashed border-outline-variant p-md",
        className,
      )}
    >
      <p className="font-body-md text-body-md text-on-surface-variant">{children}</p>
      {action}
    </div>
  );
}
