import { cn } from "@/lib/utils";

type DsCountProps = {
  value: number;
  /** Ce que compte le chiffre, en toutes lettres : lu à la place du chiffre seul. */
  label: string;
  className?: string;
};

export function DsCount({ value, label, className }: DsCountProps) {
  return (
    <span
      className={cn(
        "inline-flex min-w-6 items-center justify-center bg-secondary-fixed px-xs py-0.5 font-label-md text-label-md tracking-normal text-primary",
        className,
      )}
    >
      <span aria-hidden="true">{value}</span>
      <span className="sr-only">{label}</span>
    </span>
  );
}
