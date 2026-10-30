import { cn } from "@/lib/utils";

function initials(name: string) {
  const words = name.trim().split(/\s+/).filter(Boolean);
  return words
    .slice(0, 2)
    .map((w) => w.charAt(0).toUpperCase())
    .join("");
}

type DsAvatarProps = {
  /** Nom complet : seules les initiales sont affichées. */
  name: string;
  className?: string;
};

/** Décoratif : le nom est toujours écrit à côté. */
export function DsAvatar({ name, className }: DsAvatarProps) {
  return (
    <span
      aria-hidden="true"
      className={cn(
        "inline-flex size-10 shrink-0 items-center justify-center bg-secondary-fixed font-label-md text-label-md normal-case tracking-normal text-primary",
        className,
      )}
    >
      {initials(name)}
    </span>
  );
}
