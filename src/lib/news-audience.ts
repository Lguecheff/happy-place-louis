export type NewsAudience = "équipe" | "entreprise";

/** Public d'une actu : `audience` reste vide tant que l'auteur n'a pas choisi. */
export type NewsAudienceValue = { audience: NewsAudience | null; teams: string[] };

export const emptyAudience = (): NewsAudienceValue => ({ audience: null, teams: [] });

/** Contrôle à la publication : un brouillon peut rester sans public. */
export function audienceError({ audience, teams }: NewsAudienceValue) {
  if (!audience) return "Choisis qui verra cette actu.";
  if (audience === "équipe" && !teams.length) return "Choisis au moins une équipe.";
  return undefined;
}

/** Reprend le public d'un brouillon, sans les équipes que l'auteur ne peut plus cibler. */
export function editableAudience(value: NewsAudienceValue, teams: string[]): NewsAudienceValue {
  if (value.audience !== "équipe") return value;
  if (!teams.length) return emptyAudience();
  const kept = value.teams.filter((t) => teams.includes(t));
  return { audience: "équipe", teams: kept.length || teams.length > 1 ? kept : teams };
}

/** Reprend le public d'une actu publiée : rien n'est choisi à la place de l'auteur. */
export function publishedAudience(value: NewsAudienceValue, teams: string[]): NewsAudienceValue {
  if (value.audience !== "équipe") return value;
  const kept = value.teams.filter((t) => teams.includes(t));
  return kept.length ? { audience: "équipe", teams: kept } : emptyAudience();
}

export function audienceLabel({ audience, teams }: NewsAudienceValue) {
  return audience === "entreprise" ? "Toute l'entreprise" : teams.join(", ");
}

export function audienceSentence(value: NewsAudienceValue) {
  return value.audience === "entreprise"
    ? "Cette actu sera visible par toute l'entreprise."
    : `Cette actu sera visible par : ${audienceLabel(value)}.`;
}
