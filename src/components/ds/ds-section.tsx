import type { ReactNode } from "react";
import { cn } from "@/lib/utils";

type DsSectionProps = {
  /** Identifiant unique : sert d'ancre et relie le titre à la région. */
  id: string;
  title: string;
  /** Zone d'action à droite du titre (bouton, lien, badge). */
  action?: ReactNode;
  children: ReactNode;
  className?: string;
};

export function DsSection({ id, title, action, children, className }: DsSectionProps) {
  return (
    <section
      id={id}
      aria-labelledby={`${id}-titre`}
      className={cn(
        "flex min-w-0 flex-col gap-md border border-outline-variant bg-surface-container-lowest p-md",
        className,
      )}
    >
      <div className="flex flex-wrap items-center justify-between gap-sm border-b border-outline-variant pb-sm">
        <h2 id={`${id}-titre`} className="font-headline-sm text-headline-sm text-primary">
          {title}
        </h2>
        {action}
      </div>
      {children}
    </section>
  );
}
