# Design system Happy Place

Source de vérité visuelle : `src/styles.css` (tokens oklch). Composants : `src/components/ds/`. Catalogue visuel : route `/design-system`.

## 1. Principes

1. **Un seul élément ressort par écran.** Un seul `DsButton` « primary » ; tout le reste est en retrait.
2. **Regroupement par zones.** Une idée = une `DsSection` ; les éléments liés sont dans la même carte.
3. **Cibles de 44 px.** Tout élément cliquable fait au moins 44 px de haut (`min-h-11`).
4. **Couleur forte réservée au critique.** `error` et `error-container` ne servent qu'à ce qui demande une action urgente.
5. **La couleur ne porte jamais seule le sens.** Toujours un texte (et au besoin une icône) avec elle.
6. **Coins carrés** (`--radius: 0`), bordures fines, pas d'ombre décorative.

## 2. Palette par rôle

| Rôle | Token Tailwind |
| --- | --- |
| Fond de page | `bg-background` |
| Carte, ligne, tuile | `bg-surface-container-lowest` + `border-outline-variant` |
| Zone en retrait (lignes de liste secondaires) | `bg-surface-container` |
| Survol | `bg-surface-container` ou `bg-surface-container-high` |
| Texte principal, titres | `text-primary` (titres), `text-on-surface` (texte) |
| Texte secondaire (méta, aide) | `text-on-surface-variant` (4,7:1 sur `surface-container`, 5,5:1 sur `surface-container-lowest`) |
| Bordure d'un contrôle (bouton, champ) | `border-outline` |
| Bordure de séparation | `border-outline-variant` |
| Action principale | `bg-primary text-on-primary` |
| Critique | `bg-error-container text-on-error-container`, `text-error`, `border-error` |
| À surveiller | `bg-tertiary-fixed text-on-tertiary-fixed` |
| Succès | `text-success` (avec un texte, jamais seul) |

Aucune couleur en dur (hex, rgb, oklch inline). Si un token manque, on l'ajoute dans `src/styles.css` (`:root`, puis `@theme inline`) et on le signale.

Attention : `text-on-surface-variant` passe sous 4,5:1 sur `surface-container-high` (4,4:1) et `surface-container-highest` : n'y mets pas de texte secondaire.

## 3. Typographie

| Usage | Classes | Taille |
| --- | --- | --- |
| Titre de page | `font-headline-lg text-headline-lg` | 44 px |
| Titre de section | `font-headline-sm text-headline-sm` | 22 px |
| Gros chiffre | `font-display text-3xl` | 30 px |
| Texte | `font-body-md text-body-md` / `font-body-sm text-body-sm` | 15 / 13 px |
| Étiquette, badge, fraîcheur | `font-label-md text-label-md` | 12 px |
| Libellé de bouton | `font-label-md text-sm` | 14 px |

Polices : Bodoni Moda (titres, chiffres), Inter Tight (texte), Space Grotesk (étiquettes, boutons).

**Aucune taille sous 12 px.** Interdit : `text-[10px]`, `text-[11px]`, `text-label-sm` (11 px). Utilise `text-label-md`.

## 4. Espacements

Tokens : `xs` 8 px, `sm` 12 px, `md` 20 px, `lg` 32 px (`p-md`, `gap-sm`, `space-y-xs`…). Cartes : `p-md`. Ligne de liste et tuile : `p-sm`. Entre cartes : `gap-md`. Largeur de page : `max-w-interface`.

Largeurs maximales : `max-w-xs` 20 rem, `max-w-sm` 24 rem, `max-w-md` 28 rem, `max-w-lg` 32 rem. Elles sont fixées dans `src/styles.css`, car Tailwind prendrait sinon les espacements du même nom (`max-w-lg` = 32 px).

## 5. Composants (`import { … } from "@/components/ds"`)

### DsButton
Props : `variant` (`primary` | `secondary` | `confirm` | `link`, défaut `secondary`), `icon`, `pending`, `disabled`, `href` (rend un `<a>`), + props natives. Hauteur min. 44 px, libellé 14 px.
`confirm` (contour épais) sert pour Valider, Publier et Enregistrer les modifications d'un contenu déjà publié. Un seul `primary` par écran.
```tsx
<DsButton variant="confirm" icon="check" onClick={valider}>Valider</DsButton>
```

### DsSection
Props : `id`, `title`, `action`, `children`, `className`. Carte avec h2 et bordure sous l'en-tête.
```tsx
<DsSection id="demandes" title="Demandes en attente" action={<DsBadge variant="watch">3 nouvelles</DsBadge>}>…</DsSection>
```

### DsBadge
Props : `variant` (`critical` | `watch` | `status` | `neutral`), `icon`, `children` (texte obligatoire).
```tsx
<DsBadge variant="critical" icon="error">Critique</DsBadge>
```

### DsCount
Props : `value`, `label` (ce que compte le chiffre, en toutes lettres : obligatoire et lu à la place du chiffre). Petit compteur sur fond `secondary-fixed`, à côté d'un titre. Pour un état avec du texte, utilise `DsBadge`.
```tsx
<DsCount value={7} label="7 éléments à traiter" />
```

### DsIconButton
Props : `icon`, `label` (obligatoire, lu à la place de l'icône), `count`, + props natives. Bouton icône de 44 px, sans contour. `count` affiche une pastille sur l'icône : rien à 0, « 9+ » au-delà de 9. La pastille n'est pas lue : `label` doit dire ce qu'elle compte. Pour une action avec du texte, utilise `DsButton`.
```tsx
<DsIconButton icon="notifications" label="Notifications, 3 non lues" count={3} />
```

### DsPopover
Props : `trigger`, `title`, `action`, `open`, `onOpenChange`, `children`, `className`. Panneau ancré à son déclencheur, avec un titre (h2) et au plus une action à droite. Entrée ouvre, Échap ferme et rend le focus au déclencheur. Pour un contenu à lire longuement ou une décision, utilise une fenêtre de lecture.
```tsx
<DsPopover trigger={<DsIconButton icon="tune" label="Ouvrir les réglages" />} title="Réglages">…</DsPopover>
```

### DsFreshness
Props : `at` (date ISO), `stale`. Affiche « Mis à jour il y a X » (via `timeAgo`). `stale` passe en couleur d'alerte avec icône d'avertissement.
```tsx
<DsFreshness at={metric.updated_at} stale={isOld} />
```

### DsSaveStatus
Props : `state` (`idle` | `saving` | `saved` | `error`), `at` (heure du dernier enregistrement), `onRetry`, `className`. État d'un enregistrement automatique : « Enregistrement… », « Enregistré à HH:MM », ou « Échec de l'enregistrement » en `text-error` avec le bouton « Réessayer » (`link`). La zone `aria-live` polie reste présente, même vide (`idle`), pour que chaque changement soit annoncé. Pas de toast pour un enregistrement automatique : l'indicateur suffit. Logique d'enregistrement : `useAutosaveDraft` (`src/components/news/use-autosave-draft.ts`).
```tsx
<DsSaveStatus state={status.state} at={status.at} onRetry={flush} />
```

### DsKpiTile
Props : `label`, `value`, `valueFont` (`display` | `headline`), `trend`, `trendDirection` (`up` | `down` | `flat`), `updatedAt`, `stale`, `helpHref` (lien) ou `onHelp` (bouton qui ouvre une fenêtre), `helpLabel`, `children` (ajout en bas de tuile).
```tsx
<DsKpiTile label="Taux de placement" value="78,4 %" trend="+2,1 points sur 30 jours" trendDirection="up" updatedAt={iso} helpHref="/aide#placement" />
```

### DsListItem
Props : `title`, `meta`, `icon` ou `leading` (ex. `DsAvatar`), et soit `actions` et `children` (ligne statique, `children` place le contenu et les actions sous le titre), soit `href`, soit `onClick` (ligne entièrement cliquable avec flèche, sans actions imbriquées).
```tsx
<DsListItem icon="article" title="Nouvelle offre" meta="Publiée il y a 3 heures · par Sam" href="/actualites/12" />
```

### DsStatTile
Props : `value`, `label`, `hint`, `href`, `linkLabel`, `tone` (`default` | `alert`). `alert` est réservé au critique.
```tsx
<DsStatTile tone="alert" value="2" label="Points bloquants critiques" href="/blocages" linkLabel="Voir les points bloquants" />
```

### DsEmptyState
Props : `children` (texte court, tutoiement), `action` (une seule).
```tsx
<DsEmptyState action={<DsButton icon="add">Créer ta première demande</DsButton>}>Tu n'as encore aucune demande.</DsEmptyState>
```

### toastUndo
`toastUndo(message, onUndo, { duration? })` : message sonner avec l'action « Annuler ». À préférer à une fenêtre de confirmation pour une action réversible.
```tsx
toastUndo("Demande refusée.", () => restaurer(id));
```

### DsAvatar
Props : `name`. Initiales sur fond `secondary-fixed`, décoratif : le nom est toujours écrit à côté.
```tsx
<DsAvatar name="Sam Martin" />
```

### DsField
Props : `id`, `label`, `error`, `children`. Relie le libellé au champ par `htmlFor`. `DS_INPUT` donne le style d'un champ (44 px minimum).
```tsx
<DsField id="titre" label="Titre" error={erreur}>
  <input id="titre" className={DS_INPUT} />
</DsField>
```

### DsChoiceGroup et DsChoice
`DsChoiceGroup` : `id`, `legend`, `error`, `children`. Un fieldset et sa legend, pour un groupe de boutons radio ou de cases à cocher : `DsField` reste réservé à un champ seul.
`DsChoice` : `type` (`radio` | `checkbox`, défaut `radio`), `label`, `hint`, `inputRef`, + props natives de l'input. Ligne cliquable de 44 px minimum, surlignée quand elle est cochée.
```tsx
<DsChoiceGroup legend="Public" error={erreur}>
  <DsChoice name="public" label="Mon équipe" hint="Product" checked={choix === "équipe"} onChange={…} />
  <DsChoice name="public" label="Toute l'entreprise" checked={choix === "entreprise"} onChange={…} />
</DsChoiceGroup>
```

### DsIcon
Props : `name`, `filled`, `label`, `className`. Décorative (`aria-hidden`) par défaut ; avec `label`, elle est annoncée.
```tsx
<DsIcon name="schedule" />
```

## 6. Accessibilité

- Vrais `<button>` et `<a>`, jamais un `<div onClick>`.
- Focus visible partout (`DS_FOCUS` dans `ds/focus.ts`).
- Un bouton icône seul a un `aria-label`.
- Chaque champ a un `<label htmlFor>` relié à son `id`.
- Contraste texte ≥ 4,5:1.

## 7. Règles de rédaction

- **Tutoiement** : « Crée ta demande », « Tu n'as aucune demande ».
- **Verbe à l'infinitif sur les boutons** : « Valider », « Publier », « Créer une demande ».
- **Casse normale** : pas de majuscules sur les boutons, badges et statuts (« Brouillon », pas « BROUILLON »).
- **Le mot « demande »** : jamais « idée » ni « soumission » dans l'interface.
- **Pas de jargon** : phrases courtes, mots du quotidien.
