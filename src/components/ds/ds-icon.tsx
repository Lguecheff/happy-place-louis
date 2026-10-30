import { cn } from "@/lib/utils";

type DsIconProps = {
  /** Nom du symbole Material Symbols (ex. « schedule »). */
  name: string;
  className?: string;
  /** Rempli plutôt que contour (réservé aux alertes critiques). */
  filled?: boolean;
  /** Si fourni, l'icône porte du sens et est annoncée ; sinon elle est décorative (aria-hidden). */
  label?: string;
};

export function DsIcon({ name, className, filled, label }: DsIconProps) {
  return (
    <span
      aria-hidden={label ? undefined : true}
      role={label ? "img" : undefined}
      aria-label={label}
      className={cn(
        "material-symbols-outlined",
        filled && "[font-variation-settings:'FILL'_1]",
        className,
      )}
    >
      {name}
    </span>
  );
}
