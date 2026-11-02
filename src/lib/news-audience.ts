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

export function audienceLabel({ audience, teams }: NewsAudienceValue) {
  return audience === "entreprise" ? "Toute l'entreprise" : teams.join(", ");
}

export function audienceSentence(value: NewsAudienceValue) {
  return value.audience === "entreprise"
    ? "Cette actu sera visible par toute l'entreprise."
    : `Cette actu sera visible par : ${audienceLabel(value)}.`;
}
