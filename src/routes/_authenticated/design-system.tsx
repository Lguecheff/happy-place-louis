import { createFileRoute } from "@tanstack/react-router";
import { BrandHeader } from "@/components/brand-header";
import {
  DS_INPUT,
  DsBadge,
  DsButton,
  DsChoice,
  DsChoiceGroup,
  DsCount,
  DsEmptyState,
  DsField,
  DsFreshness,
  DsIcon,
  DsIconButton,
  DsKpiDefinition,
  DsKpiTile,
  DsListItem,
  DsPopover,
  DsSaveStatus,
  DsSection,
  DsStatTile,
  DsTooltip,
  toastUndo,
} from "@/components/ds";

export const Route = createFileRoute("/_authenticated/design-system")({
  head: () => ({
    meta: [{ title: "Happy Place — Catalogue du design system" }],
  }),
  component: DesignSystemPage,
});

// Données fictives : le catalogue ne lit rien en base.
const NOW = Date.now();
const ago = (minutes: number) => new Date(NOW - minutes * 60_000).toISOString();

function Demo({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="space-y-xs">
      <h3 className="font-label-md text-label-md normal-case tracking-normal text-on-surface-variant">
        {title}
      </h3>
      <div className="flex flex-wrap items-start gap-sm">{children}</div>
    </div>
  );
}

function DesignSystemPage() {
  return (
    <div className="flex min-h-screen flex-col bg-background font-body-md text-on-surface">
      <BrandHeader />
      <main className="mx-auto w-full max-w-interface flex-grow space-y-md p-sm md:p-md">
        <div className="space-y-xs">
          <h1 className="font-headline-lg text-headline-lg text-primary">Design system</h1>
          <p className="font-body-md text-body-md text-on-surface-variant">
            Catalogue de tous les composants de <code>src/components/ds/</code>, avec des données
            fictives. Les règles sont dans <code>DESIGN.md</code>. Ici, plusieurs boutons « primary
            » sont affichés pour montrer leurs états ; sur un vrai écran, il n'y en a qu'un.
          </p>
        </div>

        <DsSection id="boutons" title="DsButton">
          <Demo title="Variantes">
            <DsButton variant="primary" icon="add">
              Créer une demande
            </DsButton>
            <DsButton variant="secondary">Refuser</DsButton>
            <DsButton variant="confirm" icon="check">
              Valider
            </DsButton>
            <DsButton variant="link">Voir l'archive</DsButton>
          </Demo>
          <Demo title="Désactivé">
            <DsButton variant="primary" disabled>
              Créer une demande
            </DsButton>
            <DsButton variant="secondary" disabled>
              Refuser
            </DsButton>
            <DsButton variant="confirm" disabled>
              Publier
            </DsButton>
            <DsButton variant="link" disabled>
              Voir l'archive
            </DsButton>
          </Demo>
          <Demo title="En cours (pending)">
            <DsButton variant="primary" pending>
              Enregistrer
            </DsButton>
            <DsButton variant="confirm" pending>
              Publier
            </DsButton>
          </Demo>
          <Demo title="Lien (balise a)">
            <DsButton variant="secondary" href="#boutons" icon="arrow_forward">
              Revenir à cette section
            </DsButton>
          </Demo>
        </DsSection>

        <DsSection
          id="sections"
          title="DsSection"
          action={<DsButton variant="link">Voir l'archive</DsButton>}
        >
          <p className="font-body-md text-body-md text-on-surface-variant">
            Carte blanche avec bordure. Le titre est un h2, l'action se place à droite et une
            bordure sépare l'en-tête.
          </p>
        </DsSection>

        <DsSection id="badges" title="DsBadge">
          <Demo title="Variantes">
            <DsBadge variant="critical" icon="error">
              Critique
            </DsBadge>
            <DsBadge variant="watch">À surveiller</DsBadge>
            <DsBadge variant="status">Brouillon</DsBadge>
            <DsBadge variant="neutral">Équipe Data</DsBadge>
          </Demo>
        </DsSection>

        <DsSection id="compteurs" title="DsCount">
          <Demo title="À côté d'un titre (le libellé complet est lu par les lecteurs d'écran)">
            <p className="flex items-center gap-xs font-headline-sm text-headline-sm text-primary">
              À traiter
              <DsCount value={7} label="7 éléments à traiter" />
            </p>
          </Demo>
        </DsSection>

        <DsSection id="boutons-icone" title="DsIconButton">
          <Demo title="Sans pastille, avec pastille, au-delà de 9 (le libellé dit ce qui est compté)">
            <DsIconButton icon="notifications" label="Notifications, 0 non lue" />
            <DsIconButton icon="notifications" label="Notifications, 3 non lues" count={3} />
            <DsIconButton icon="notifications" label="Notifications, 12 non lues" count={12} />
          </Demo>
        </DsSection>

        <DsSection id="panneaux" title="DsPopover">
          <Demo title="Panneau ancré à son déclencheur, avec une action à droite du titre">
            <DsPopover
              trigger={<DsButton icon="expand_more">Ouvrir le panneau</DsButton>}
              title="Panneau"
              action={<DsButton variant="link">Tout marquer comme lu</DsButton>}
            >
              <DsEmptyState>Aucune notification</DsEmptyState>
            </DsPopover>
          </Demo>
        </DsSection>

        <DsSection id="fraicheur" title="DsFreshness">
          <Demo title="Normal et ancien (stale)">
            <DsFreshness at={ago(12)} />
            <DsFreshness at={ago(60 * 24 * 9)} stale />
          </Demo>
          <Demo title="Avec l'auteur (by), ou « Automatique » ; date complète au survol et au focus">
            <DsFreshness at={ago(60 * 24 * 2)} by="Olivia Laurent" />
            <DsFreshness at={ago(60 * 5)} by="Automatique" />
          </Demo>
        </DsSection>

        <DsSection id="enregistrement" title="DsSaveStatus">
          <Demo title="En cours, enregistré, échec avec « Réessayer » (zone aria-live polie)">
            <DsSaveStatus state="saving" />
            <DsSaveStatus state="saved" at={new Date(NOW)} />
            <DsSaveStatus
              state="error"
              onRetry={() => toastUndo("Nouvel essai (exemple)", () => {})}
            />
          </Demo>
        </DsSection>

        <DsSection id="kpi" title="DsKpiTile">
          <div className="grid grid-cols-1 gap-sm md:grid-cols-3">
            <DsKpiTile
              label="Taux de placement"
              value="78,4 %"
              trend="+2,1 points sur 30 jours"
              trendDirection="up"
              updatedAt={ago(35)}
              helpHref="#kpi"
              definition={{
                definition: "Part des candidats placés en mission sur 30 jours.",
                impact: "S'il baisse, tes demandes qui aident les candidats passent en premier.",
              }}
            />
            <DsKpiTile
              label="Missions actives"
              value="42"
              valueFont="headline"
              trend="Stable sur 30 jours"
              updatedAt={ago(60 * 5)}
              helpHref="#kpi"
            />
            <DsKpiTile
              label="NPS candidats"
              value="31"
              trend="−4 points sur 30 jours"
              trendDirection="down"
              updatedAt={ago(60 * 24 * 12)}
              stale
              helpHref="#kpi"
            />
          </div>
        </DsSection>

        <DsSection id="infobulles" title="DsTooltip et DsKpiDefinition">
          <Demo title="Infobulle au survol et au focus (Échap ferme), jamais au toucher">
            <DsTooltip
              content={<p className="font-body-sm text-body-sm">Mis à jour chaque nuit.</p>}
            >
              <DsButton variant="link">Survoler ou atteindre avec Tab</DsButton>
            </DsTooltip>
          </Demo>
          <Demo title="Textes d'un KPI, dont un vide">
            <DsKpiDefinition
              className="max-w-xs"
              definition="Nombre de missions en cours aujourd'hui."
              impact=""
            />
          </Demo>
        </DsSection>

        <DsSection id="lignes" title="DsListItem">
          <div className="space-y-xs">
            <DsListItem
              icon="draft"
              title="Refonte de l'accueil candidats"
              meta="Créée il y a 2 jours · par Camille"
              actions={
                <>
                  <DsButton variant="secondary">Modifier</DsButton>
                  <DsButton variant="confirm">Publier</DsButton>
                </>
              }
            />
            <DsListItem
              icon="article"
              title="Nouvelle offre cadre IT"
              meta="Publiée il y a 3 heures · par Sam"
              href="#lignes"
            />
            <DsListItem
              icon="history"
              title="Voir le fil de la demande"
              meta="Ligne cliquable en bouton"
              onClick={() => toastUndo("Fil ouvert (exemple)", () => {})}
            />
            <DsListItem
              icon="report"
              title="Accès au nouvel ATS en attente"
              meta="Ligne cliquable avec un contrôle dessous, hors du bouton"
              opensDialog
              onClick={() => toastUndo("Point ouvert (exemple)", () => {})}
            >
              <DsField id="demo-ligne-statut" label="Changer le statut">
                <select id="demo-ligne-statut" className={DS_INPUT} defaultValue="en-cours">
                  <option value="ouvert">Ouvert</option>
                  <option value="en-cours">En cours</option>
                </select>
              </DsField>
            </DsListItem>
          </div>
        </DsSection>

        <DsSection id="chiffres" title="DsStatTile">
          <div className="grid grid-cols-1 gap-sm md:grid-cols-2">
            <DsStatTile
              value="12"
              label="Demandes en attente"
              hint="3 de plus que la semaine dernière"
              href="#chiffres"
              linkLabel="Voir les demandes"
            />
            <DsStatTile
              tone="alert"
              value="2"
              label="Points bloquants critiques"
              hint="À traiter avant vendredi"
              href="#chiffres"
              linkLabel="Voir les points bloquants"
            />
          </div>
        </DsSection>

        <DsSection id="vide" title="DsEmptyState">
          <DsEmptyState
            action={
              <DsButton variant="secondary" icon="add">
                Créer ta première demande
              </DsButton>
            }
          >
            Tu n'as encore aucune demande. Dès que tu en crées une, elle apparaît ici.
          </DsEmptyState>
        </DsSection>

        <DsSection id="toast" title="toastUndo">
          <Demo title="Message avec action « Annuler »">
            <DsButton
              variant="secondary"
              icon="undo"
              onClick={() =>
                toastUndo("Demande refusée.", () => toastUndo("Refus annulé.", () => {}))
              }
            >
              Afficher le message
            </DsButton>
          </Demo>
        </DsSection>

        <DsSection id="choix" title="DsChoiceGroup et DsChoice">
          <div className="grid gap-md md:grid-cols-2">
            <DsChoiceGroup legend="Boutons radio">
              <DsChoice
                name="catalogue-radio"
                label="Coché"
                hint="Avec une précision"
                defaultChecked
              />
              <DsChoice name="catalogue-radio" label="Non coché" />
              <DsChoice
                name="catalogue-radio"
                label="Désactivé"
                hint="Explique pourquoi"
                disabled
              />
            </DsChoiceGroup>
            <DsChoiceGroup legend="Cases à cocher" error="Choisis au moins une équipe.">
              <DsChoice type="checkbox" label="Product" />
              <DsChoice type="checkbox" label="Marketing" />
            </DsChoiceGroup>
          </div>
        </DsSection>

        <DsSection id="icones" title="DsIcon">
          <Demo title="Décorative (aria-hidden) et porteuse de sens (label)">
            <DsIcon name="schedule" />
            <DsIcon name="error" filled label="Critique" className="text-error" />
          </Demo>
        </DsSection>
      </main>
    </div>
  );
}
