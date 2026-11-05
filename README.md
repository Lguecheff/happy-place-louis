# Happy Place — version élèves

Happy Place est le dashboard interne de **Bigger Boat**, un cabinet de recrutement fictif. Il réunit les actualités, les idées et demandes des équipes, les points bloquants et les indicateurs.

Pour la démo, on **se connecte avec une adresse e-mail et un mot de passe**. Il n'y a pas d'inscription : les comptes sont créés à l'avance (étape 2), et chacun arrive sur la vue d'ensemble avec son rôle.

L'ancienne **entrée libre** (sans email ni mot de passe, avec l'écran **« Choisis ton rôle »** et le lien **« Changer de rôle »**) existe toujours, mais elle est coupée par défaut. Pour la rallumer, voir [VITE_ENTREE_LIBRE](#vite_entree_libre--rallumer-lentrée-libre).

Chaque groupe installe **sa propre base Supabase**, sans toucher à celle des autres groupes. Tout le groupe partage la même app et les mêmes données.

---

## Ce qu'il te faut

- Un compte [GitHub](https://github.com) et un compte [Supabase](https://supabase.com) (plans gratuits ; tu peux te connecter à Supabase avec ton compte GitHub).
- Rien à installer : l'app se lance dans ton navigateur avec **GitHub Codespaces**. Si tu préfères travailler sur ton ordinateur, il te faut [Node.js](https://nodejs.org) version 20 ou plus.

Compte environ 20 minutes. **Une seule personne par groupe** fait l'installation.

---

## 0. Créer le dépôt du groupe

1. En haut de cette page GitHub, clique sur le bouton vert **Use this template** → **Create a new repository**.
2. Donne-lui un nom (par exemple `happy-place-groupe-3`), puis **Create repository**.

Tu travailles désormais dans **ce nouveau dépôt** : c'est la copie de ton groupe.

## 1. Créer le projet Supabase

1. Sur [supabase.com/dashboard](https://supabase.com/dashboard), clique sur **New project**.
2. Donne-lui un nom (par exemple `happy-place-groupe-3`), clique sur **Generate a password** et choisis une région en Europe.
3. Clique sur **Create new project** et attends 1 à 2 minutes.

## 2. Connexion par mot de passe et comptes de démo

1. **Authentication** → **Sign In / Providers** → vérifie que **Email** est activé. Laisse **Allow anonymous sign-ins** coupé (il ne sert qu'à l'entrée libre).
2. Après l'étape 3 (la base), crée les 4 comptes de la démo : **Authentication** → **Users** → **Add user** → **Create new user**. Saisis l'adresse et le mot de passe, coche **Auto Confirm User**, puis **Create user**. Recommence pour chaque compte.

| Compte | Rôle | Équipe | Adresse de connexion |
|---|---|---|---|
| Kesha Démo | Manager | Product | `guecheff.louis+kesha@gmail.com` |
| Marc Démo | Manager | Product | `guecheff.louis+marc@gmail.com` |
| Gontran Démo | Collaborateur | Product | `guecheff.louis+gontran@gmail.com` |
| Olivia Démo | Admin | aucune | `guecheff.louis+olivia@gmail.com` |

Le mot de passe commun de la démo est donné à part : il n'est écrit nulle part dans le dépôt.

Le profil, le rôle, l'équipe et l'adresse de réception des mails de ces comptes sont déjà dans la base (migration `20261105200000_comptes_demo.sql`, comprise dans `setup.sql`). Une adresse qui se connecte sans être inscrite avec un rôle est déconnectée, avec le message « Ce compte n'a pas accès à Happy Place. ».

## 3. Installer la base de données

1. Dans ton dépôt GitHub, ouvre le dossier **supabase**, puis le fichier **setup.sql**. Clique sur l'icône **Copy raw file** (deux carrés superposés, au-dessus du code à droite).
2. Dans Supabase : **SQL Editor** → **+ New query**. Colle, puis clique sur **Run**.
3. Si Supabase te demande comment gérer la sécurité des tables (RLS), choisis **Run without RLS** : le script active lui-même les règles de sécurité sur toutes les tables. Si un avertissement parle de « destructive operations », clique sur **Run this query**.
4. Un tableau de 13 lignes apparaît : **toutes les lignes doivent indiquer `ok = true`**.
5. Fais de même avec **seed.sql** (les données de démo), dans une **nouvelle** requête. Résultat attendu : « Success. No rows returned ».

> Tu peux relancer `seed.sql` à tout moment pour remettre les contenus de démo dans leur état de départ. Les profils créés sont conservés.

## 4. Récupérer tes deux clés

Dans Supabase, clique sur **Connect** (en haut de la page) et note :
- l'**URL du projet** : `https://xxxx.supabase.co`
- la **Publishable key** : `sb_publishable_…`

*Sinon : **Project Settings** → **API Keys** pour la clé, **Data API** pour l'URL.*

> La clé « publishable » est faite pour être utilisée dans le navigateur. N'utilise **jamais** la clé `secret` ou `service_role`.

## 5. Lancer l'app dans un Codespace

1. Dans ton dépôt GitHub : bouton vert **Code** → onglet **Codespaces** → **Create codespace on main**. Un éditeur s'ouvre dans ton navigateur (environ une minute).
2. Dans le **Terminal** en bas de l'écran, tape `cp .env.example .env` puis Entrée. Le fichier `.env` apparaît à gauche : ouvre-le, remplace les deux valeurs par tes clés de l'étape 4, puis **Ctrl + S**.
3. Dans le terminal, tape `npm install` (attends la fin), puis `npm run dev`.
4. Clique sur **Open in Browser** dans la fenêtre qui apparaît (ou onglet **Ports** → ligne **3000** → icône du globe).

L'app s'ouvre sur la page de connexion.

Pour partager l'app avec ton groupe : onglet **Ports** → clic droit sur la ligne **3000** → **Port Visibility** → **Public**, puis copie l'adresse et envoie-la.

> Un Codespace s'arrête tout seul après 30 minutes d'inactivité. Pour le relancer : **Code** → **Codespaces** → clique sur son nom, puis relance `npm run dev`. Le compte gratuit GitHub inclut un quota mensuel d'heures de Codespaces.

**Sur ton ordinateur plutôt ?** Télécharge le dépôt, crée le fichier `.env` de la même façon, puis lance `npm install` et `npm run dev` dans un terminal, et ouvre [http://localhost:3000](http://localhost:3000).

---

## Les trois rôles

| Rôle | Ce qu'il peut faire |
|---|---|
| **Collaborateur** | Lit les actualités et les indicateurs, soumet des idées, questions ou problèmes pour son équipe. |
| **Manager** | Valide ou refuse les demandes des équipes qu'il manage, rédige des actualités (en brouillon), suit les points bloquants. |
| **Admin** | Gère tout : contenus, indicateurs, équipes et utilisateurs (espace « Gérer les données »). |

Ces droits sont appliqués **par la base elle-même** (règles RLS de Supabase), pas seulement par l'interface.

La base contient aussi dix membres fictifs de Bigger Boat (`@biggerboat.example`). Ils n'ont pas de compte : ils peuplent l'écran des utilisateurs et managent certaines équipes.

Les liens reçus par mail (`/?demande=…`, `/?actu=…`, `/?point=…`, `/?preferences`) passent par la connexion puis rouvrent la bonne page. **Se déconnecter** se trouve dans le menu du compte de la vue d'ensemble et dans l'en-tête de « Gérer les données ».

Les profils créés avec l'entrée libre restent dans la base, avec une adresse interne du type `eleve-xxxx@happyplace.test`.

### VITE_ENTREE_LIBRE : rallumer l'entrée libre

Ajoute `VITE_ENTREE_LIBRE=true` dans `.env`, active **Allow anonymous sign-ins** dans Supabase, puis relance `npm run dev`. L'ancien comportement revient à l'identique : session anonyme, écran **« Choisis ton rôle »**, lien **« Changer de rôle »**. Si la variable est absente, ou a une autre valeur que `true`, c'est la connexion par mot de passe : `/choisir-role` renvoie vers la vue d'ensemble (ou vers la connexion sans session). Ne l'ajoute pas aux variables de build Cloudflare : la version en ligne reste en mode connexion.

---

## Pour aller plus loin

- **Commandes utiles** : `npm run build` (version de production), `npm run start` (lance cette version), `npm run typecheck` (vérifie les types).
- **Structure** : les écrans sont dans `src/routes`, les composants dans `src/components`, et la base dans `supabase/migrations` (une migration par évolution, dans l'ordre).
- **Modifier la base** : écris une nouvelle migration SQL plutôt que de modifier les anciennes. Après toute modification d'ENUM, de trigger ou de statut, lance `select * from private.run_smoke_tests();` : toutes les lignes doivent revenir à `ok = true`.
- **Règles du projet** : le fichier `AGENTS.md` liste les conventions à respecter. Donne-le à ton assistant IA de code.
- **Tâches automatiques** : deux tâches tournent chaque nuit dans Supabase (clôture des demandes validées depuis un an, départs programmés des collaborateurs). Tu les retrouves dans le module **Cron** de Supabase.
- **Mise en ligne** : l'app se déploie sur Cloudflare Workers (preset Nitro `cloudflare_module`, réglé dans `vite.config.ts`). Commande de build : `npm run build` ; commande de déploiement : `npx wrangler deploy`. Ajoute `VITE_SUPABASE_URL` et `VITE_SUPABASE_PUBLISHABLE_KEY` dans les variables **du build** sur Cloudflare. Aperçu local du Worker : `npm run build` puis `npx wrangler dev --config .output/server/wrangler.json`.

## En cas de problème

| Symptôme | Cause probable |
|---|---|
| « Missing Supabase environment variable(s) » | Le fichier `.env` est absent ou mal nommé. Relance `npm run dev` après l'avoir corrigé. |
| « Adresse ou mot de passe incorrect. » avec le bon mot de passe | Le compte n'a pas été créé dans **Authentication** → **Users**, ou **Auto Confirm User** n'a pas été coché. |
| « Ce compte n'a pas accès à Happy Place. » | L'adresse n'est pas dans `allowed_users` avec un rôle : relance la migration des comptes de démo. |
| « Les connexions anonymes ne sont pas activées » | Entrée libre seulement : active **Allow anonymous sign-ins**, puis clique sur **Réessayer**. |
| « Blocked request. This host is not allowed » | Le fichier `vite.config.ts` a été modifié : il doit contenir `allowedHosts: [".app.github.dev"]`. |
| « Impossible de charger les équipes » | `setup.sql` n'a pas été exécuté en entier. Relance-le sur un projet neuf. |
| Le dashboard est vide | `seed.sql` n'a pas été exécuté. |
| Un test de `setup.sql` est à `false` | Le script a été lancé deux fois, ou en partie. Le plus simple est de repartir d'un projet Supabase neuf. |

---

### Différences avec l'app d'origine

- **Connexion par mot de passe** (`signInWithPassword`) à la place de la connexion Google, avec des comptes de démo créés à l'avance.
- **Entrée libre** gardée derrière `VITE_ENTREE_LIBRE` : session anonyme, écran `/choisir-role` et lien « Changer de rôle ».
- **Nouvelle fonction SQL** `choisir_mon_role` (migrations `20261016090000_connexion_libre.sql` et `20261016100000_entree_directe.sql`) : elle enregistre le rôle et donne au profil anonyme une adresse interne. Les règles de sécurité par rôle sont inchangées.
- **Configuration standard** à la place des outils propres à Lovable (`vite.config.ts`, client Supabase), compatible GitHub Codespaces.
- **Base installable de zéro** : migrations regroupées dans `supabase/migrations`, espaces de stockage ajoutés, et une ancienne migration inutilisée retirée.
