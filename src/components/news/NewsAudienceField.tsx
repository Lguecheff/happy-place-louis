import type { ReactNode, RefObject } from "react";
import { DS_FOCUS } from "@/components/ds/focus";
import type { NewsAudienceValue } from "@/lib/news-audience";
import { cn } from "@/lib/utils";

const LABEL = "font-label-md text-label-md normal-case tracking-normal text-on-surface-variant";

function Option({
  selected,
  disabled,
  children,
}: {
  selected: boolean;
  disabled?: boolean;
  children: ReactNode;
}) {
  return (
    <label
      className={cn(
        "flex min-h-11 items-start gap-sm border p-sm",
        selected ? "border-primary bg-surface-container" : "border-outline-variant",
        disabled ? "cursor-not-allowed bg-surface-container" : "cursor-pointer",
      )}
    >
      {children}
    </label>
  );
}

function OptionText({ label, hint }: { label: string; hint?: string }) {
  return (
    <span className="min-w-0">
      <span className="block font-body-md text-body-md text-on-surface wrap-anywhere">{label}</span>
      {hint && (
        <span className="block font-body-sm text-body-sm text-on-surface-variant wrap-anywhere">
          {hint}
        </span>
      )}
    </span>
  );
}

/** Champ « Public » d'une actu. `teams` : les équipes que l'auteur peut cibler. */
export function NewsAudienceField({
  id,
  teams,
  value,
  onChange,
  error,
  disabled,
  firstInputRef,
}: {
  id: string;
  teams: string[];
  value: NewsAudienceValue;
  onChange: (value: NewsAudienceValue) => void;
  error?: string;
  disabled?: boolean;
  /** Pour ramener le focus sur le champ quand le public manque à la publication. */
  firstInputRef?: RefObject<HTMLInputElement | null>;
}) {
  const noTeam = teams.length === 0;
  const pickTeams = teams.length > 1;
  const onTeam = value.audience === "équipe";

  function toggleTeam(team: string, checked: boolean) {
    const picked = checked ? [...value.teams, team] : value.teams.filter((t) => t !== team);
    onChange({ ...value, teams: teams.filter((t) => picked.includes(t)) });
  }

  return (
    <fieldset id={id} className="min-w-0 space-y-xs">
      <legend className={cn(LABEL, "mb-xs")}>Public</legend>
      <Option selected={onTeam} disabled={noTeam}>
        <input
          ref={noTeam ? undefined : firstInputRef}
          type="radio"
          name={`${id}-choix`}
          className={cn("mt-1 accent-primary", DS_FOCUS)}
          checked={onTeam}
          disabled={noTeam || disabled}
          onChange={() => onChange({ audience: "équipe", teams: pickTeams ? [] : teams })}
        />
        <OptionText
          label="Mon équipe"
          hint={
            noTeam
              ? "Aucune équipe ne t'est rattachée : tu peux publier pour toute l'entreprise."
              : pickTeams
                ? undefined
                : teams[0]
          }
        />
      </Option>
      {onTeam && pickTeams && (
        <fieldset className="min-w-0 space-y-xs pl-lg">
          <legend className={cn(LABEL, "mb-xs")}>Équipes concernées</legend>
          {teams.map((team) => (
            <Option key={team} selected={value.teams.includes(team)}>
              <input
                type="checkbox"
                className={cn("mt-1 accent-primary", DS_FOCUS)}
                checked={value.teams.includes(team)}
                disabled={disabled}
                onChange={(e) => toggleTeam(team, e.target.checked)}
              />
              <OptionText label={team} />
            </Option>
          ))}
        </fieldset>
      )}
      <Option selected={value.audience === "entreprise"}>
        <input
          ref={noTeam ? firstInputRef : undefined}
          type="radio"
          name={`${id}-choix`}
          className={cn("mt-1 accent-primary", DS_FOCUS)}
          checked={value.audience === "entreprise"}
          disabled={disabled}
          onChange={() => onChange({ audience: "entreprise", teams: [] })}
        />
        <OptionText label="Toute l'entreprise" />
      </Option>
      {error && (
        <p role="alert" className="font-body-sm text-body-sm text-error">
          {error}
        </p>
      )}
    </fieldset>
  );
}
