import { clsx, type ClassValue } from "clsx";
import { extendTailwindMerge } from "tailwind-merge";

// Sans cela, tailwind-merge prend les tailles de texte du thème pour des couleurs et les retire,
// et ne sait pas qu'un `px-0` remplace un `px-md`.
const twMerge = extendTailwindMerge({
  extend: {
    theme: { spacing: ["xs", "sm", "md", "lg"] },
    classGroups: {
      "font-size": [
        { text: ["headline-lg", "headline-sm", "body-md", "body-sm", "label-md", "label-sm"] },
      ],
    },
  },
});

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
