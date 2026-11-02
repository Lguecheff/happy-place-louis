import { Link } from "@tanstack/react-router";
import type { ReactNode } from "react";
import { DS_INPUT, DsAvatar, DsIcon } from "@/components/ds";
import { DS_FOCUS } from "@/components/ds/focus";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { signOut, type AppRole } from "@/lib/auth";
import { cn } from "@/lib/utils";

const ROLE_LABELS: Record<AppRole, string> = {
  admin: "Admin",
  manager: "Manager",
  collaborateur: "Collaborateur",
};

const ANCHORS = [
  { href: "#actus", label: "Actualités" },
  { href: "#demandes", label: "Demandes" },
  { href: "#blocages", label: "Points bloquants" },
  { href: "#indicateurs", label: "Indicateurs" },
];

const NAV_LINK = cn(
  "inline-flex min-h-11 items-center px-xs font-label-md text-sm font-medium text-primary hover:bg-surface-container",
  "aria-[current=page]:underline aria-[current=page]:decoration-2 aria-[current=page]:underline-offset-8",
  DS_FOCUS,
);
const MENU_ITEM = "min-h-11 cursor-pointer font-body-md text-body-md";

/** Contenu de l'en-tête de la vue d'ensemble, placé dans BrandHeader. */
export function OverviewHeader({
  isAdmin,
  name,
  role,
  exporting,
  onExport,
  search,
}: {
  isAdmin: boolean;
  name: string;
  role: AppRole;
  exporting: boolean;
  onExport: () => void;
  /** Barre de recherche ; sans valeur, le champ désactivé reste en place. */
  search?: ReactNode;
}) {
  return (
    <>
      <nav aria-label="Navigation principale" className="basis-full xl:basis-auto">
        <ul className="flex flex-wrap items-center gap-x-xs">
          <li>
            <Link to="/" aria-current="page" className={NAV_LINK}>
              Vue d'ensemble
            </Link>
          </li>
          {ANCHORS.map((a) => (
            <li key={a.href}>
              <a href={a.href} className={NAV_LINK}>
                {a.label}
              </a>
            </li>
          ))}
          {isAdmin && (
            <li>
              <Link to="/manage/news" className={NAV_LINK}>
                Gérer les données
              </Link>
            </li>
          )}
        </ul>
      </nav>
      {search ?? (
        <div className="relative min-w-0 flex-1">
          <label htmlFor="recherche" className="sr-only">
            Rechercher dans Happy Place
          </label>
          <DsIcon
            name="search"
            className="pointer-events-none absolute left-sm top-1/2 -translate-y-1/2 text-on-surface-variant"
          />
          <input
            id="recherche"
            type="search"
            disabled
            placeholder="Rechercher une actu ou une demande"
            className={cn(DS_INPUT, "truncate pl-10")}
          />
        </div>
      )}
      <DropdownMenu>
        <DropdownMenuTrigger
          aria-label={`Menu du compte : ${name}, ${ROLE_LABELS[role]}`}
          className={cn(
            "flex min-h-11 min-w-0 shrink-0 items-center gap-xs px-xs text-left hover:bg-surface-container",
            DS_FOCUS,
          )}
        >
          <DsAvatar name={name} />
          <span className="hidden max-w-40 min-w-0 sm:block">
            <span className="block truncate font-body-sm text-body-sm text-primary">{name}</span>
            <span className="block font-label-md text-label-md normal-case tracking-normal text-on-surface-variant">
              {ROLE_LABELS[role]}
            </span>
          </span>
          <DsIcon name="expand_more" className="text-primary" />
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="w-64 max-w-[calc(100vw-2rem)] rounded-none">
          <DropdownMenuLabel className="font-normal">
            <span className="block font-body-sm text-body-sm text-primary wrap-anywhere">
              {name}
            </span>
            <span className="block font-label-md text-label-md normal-case tracking-normal text-on-surface-variant">
              {ROLE_LABELS[role]}
            </span>
          </DropdownMenuLabel>
          <DropdownMenuSeparator />
          <DropdownMenuItem asChild className={MENU_ITEM}>
            <Link to="/choisir-role">Changer de rôle</Link>
          </DropdownMenuItem>
          <DropdownMenuItem disabled={exporting} onSelect={onExport} className={MENU_ITEM}>
            {exporting ? "Export en cours…" : "Exporter mes demandes"}
          </DropdownMenuItem>
          <DropdownMenuItem onSelect={() => signOut()} className={MENU_ITEM}>
            Se déconnecter
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
    </>
  );
}
