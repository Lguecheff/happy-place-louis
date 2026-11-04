/**
 * Modèles d'actu (US25) : une liste fixe, sans table. Ils préremplissent le titre
 * et le texte ; le public reste choisi par l'auteur (US8).
 * Textes proposés par Claude, à valider par Louis avant le branchement.
 */
export type NewsTemplate = { id: string; name: string; title: string; body: string };

export const NEWS_TEMPLATES: NewsTemplate[] = [
  {
    id: "arrivee",
    name: "Arrivée d'un collaborateur",
    title: "Bienvenue à [prénom] [nom] dans l'équipe [équipe]",
    body: [
      "[prénom] [nom] rejoint l'équipe [équipe] le [date d'arrivée] en tant que [poste].",
      "Avant de nous rejoindre, [prénom] [parcours en une phrase].",
      "Ses premières semaines : [premiers sujets].",
      "Passe lui dire bonjour [lieu ou canal] !",
    ].join("\n\n"),
  },
  {
    id: "mission",
    name: "Mission gagnée",
    title: "Mission gagnée : [client] nous confie [type de mission]",
    body: [
      "Bonne nouvelle : [client] nous confie [nombre] recrutements de [postes recherchés].",
      "La mission démarre le [date de démarrage]. Elle est pilotée par [prénom du responsable].",
      "Merci à [personnes ou équipe] pour [ce qui a fait la différence].",
      "Tu as des profils en tête ? Écris à [prénom du responsable].",
    ].join("\n\n"),
  },
  {
    id: "point-etape",
    name: "Point d'étape d'équipe",
    title: "Point d'étape de l'équipe [équipe] : [mois]",
    body: [
      "Ce qui avance : [réussite ou avancée principale].",
      "Ce qui bloque : [difficulté, ou rien pour l'instant].",
      "Prochaine étape : [objectif] d'ici le [date].",
      "Une question ? Écris à [prénom].",
    ].join("\n\n"),
  },
  {
    id: "rappel",
    name: "Rappel d'organisation",
    title: "Rappel : [sujet]",
    body: [
      "Petit rappel sur [sujet] : [la règle ou l'information en une phrase].",
      "À partir du [date], [ce qui change ou ce qu'il faut faire].",
      "Concrètement : [action attendue de chacun].",
      "Pour toute question, contacte [prénom ou équipe].",
    ].join("\n\n"),
  },
];

export const BRACKETS_LEFT = "Il reste des éléments entre crochets à compléter.";

const BRACKET = /\[[^\]\n]+\]/g;

/** Éléments entre crochets encore présents, sans doublon, dans l'ordre du texte. */
export function bracketsLeft(text: string): string[] {
  return [...new Set(text.match(BRACKET) ?? [])];
}
