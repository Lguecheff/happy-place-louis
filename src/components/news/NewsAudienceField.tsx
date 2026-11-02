import type { RefObject } from "react";
import { DsChoice, DsChoiceGroup } from "@/components/ds";
import type { NewsAudienceValue } from "@/lib/news-audience";

/** Champ « Public » d'une actu. `teams` : les équipes que l'auteur peut cibler. */
export function NewsAudienceField({
  id,
  teams,
  scope = "mine",
  teamsNotice,
  value,
  onChange,
  error,
  disabled,
  firstInputRef,
}: {
  id: string;
  teams: string[];
  /** « mine » : les équipes de l'auteur. « all » : l'admin choisit dans le référentiel. */
  scope?: "mine" | "all";
  /** Remplace le choix des équipes tant qu'elles ne sont pas disponibles (chargement, erreur). */
  teamsNotice?: string;
  value: NewsAudienceValue;
  onChange: (value: NewsAudienceValue) => void;
  error?: string;
  disabled?: boolean;
  /** Pour ramener le focus sur le champ quand le public manque à la publication. */
  firstInputRef?: RefObject<HTMLInputElement | null>;
}) {
  const mine = scope === "mine";
  const noTeam = teams.length === 0;
  const teamsDisabled = noTeam || !!teamsNotice;
  const pickTeams = !teamsDisabled && (!mine || teams.length > 1);
  const onTeam = value.audience === "équipe";
  const noTeamHint = mine
    ? "Aucune équipe ne t'est rattachée : tu peux publier pour toute l'entreprise."
    : "Aucune équipe dans le référentiel.";
  const teamHint = teamsNotice ?? (noTeam ? noTeamHint : pickTeams ? undefined : teams[0]);

  function toggleTeam(team: string, checked: boolean) {
    const picked = checked ? [...value.teams, team] : value.teams.filter((t) => t !== team);
    onChange({ ...value, teams: teams.filter((t) => picked.includes(t)) });
  }

  return (
    <DsChoiceGroup id={id} legend="Public" error={error}>
      <DsChoice
        inputRef={teamsDisabled ? undefined : firstInputRef}
        name={`${id}-choix`}
        label={mine ? "Mon équipe" : "Des équipes"}
        hint={teamHint}
        checked={onTeam}
        disabled={teamsDisabled || disabled}
        onChange={() => onChange({ audience: "équipe", teams: pickTeams ? [] : teams })}
      />
      {onTeam && pickTeams && (
        <DsChoiceGroup legend="Équipes concernées" className="pl-lg">
          {teams.map((team) => (
            <DsChoice
              key={team}
              type="checkbox"
              label={team}
              checked={value.teams.includes(team)}
              disabled={disabled}
              onChange={(e) => toggleTeam(team, e.target.checked)}
            />
          ))}
        </DsChoiceGroup>
      )}
      <DsChoice
        inputRef={teamsDisabled ? firstInputRef : undefined}
        name={`${id}-choix`}
        label="Toute l'entreprise"
        checked={value.audience === "entreprise"}
        disabled={disabled}
        onChange={() => onChange({ audience: "entreprise", teams: [] })}
      />
    </DsChoiceGroup>
  );
}
