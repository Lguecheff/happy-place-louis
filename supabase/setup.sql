-- ============================================================
-- Happy Place — installation complète de la base (version élèves)
-- ============================================================
-- À coller en entier dans Supabase > SQL Editor > New query, puis Run.
-- Contient les 48 migrations de l'app, dans l'ordre. Chacune est
-- validée séparément (BEGIN/COMMIT) : certaines ajoutent des valeurs
-- d'ENUM qui doivent être enregistrées avant d'être utilisées.
-- Ensuite, exécuter seed.sql pour charger les données de démo.

-- ---------- 20260929094155_c7483fb2-20dd-4f6c-a253-6036ecdd0ac2.sql ----------
BEGIN;
CREATE TYPE public.app_role AS ENUM ('admin', 'viewer');

CREATE TABLE public.allowed_users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL UNIQUE,
  role public.app_role NOT NULL DEFAULT 'viewer',
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT email_lower CHECK (email = lower(email))
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.allowed_users TO authenticated;
GRANT ALL ON public.allowed_users TO service_role;
ALTER TABLE public.allowed_users ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.current_app_role()
RETURNS public.app_role LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT role FROM public.allowed_users WHERE email = lower(auth.jwt() ->> 'email') LIMIT 1
$$;
CREATE OR REPLACE FUNCTION public.is_allowed()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.current_app_role() IS NOT NULL
$$;
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce(public.current_app_role() = 'admin', false)
$$;
REVOKE EXECUTE ON FUNCTION public.current_app_role(), public.is_allowed(), public.is_admin() FROM anon, public;
GRANT EXECUTE ON FUNCTION public.current_app_role(), public.is_allowed(), public.is_admin() TO authenticated;

CREATE POLICY "Admins manage whitelist" ON public.allowed_users FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY "Users see own entry" ON public.allowed_users FOR SELECT TO authenticated
  USING (email = lower(auth.jwt() ->> 'email'));

-- Prevent admin from removing/demoting the last admin
CREATE OR REPLACE FUNCTION public.protect_last_admin()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF OLD.role = 'admin' AND (TG_OP = 'DELETE' OR NEW.role <> 'admin') THEN
    IF (SELECT count(*) FROM public.allowed_users WHERE role = 'admin') <= 1 THEN
      RAISE EXCEPTION 'Impossible de retirer le dernier admin';
    END IF;
  END IF;
  RETURN COALESCE(NEW, OLD);
END $$;
CREATE TRIGGER protect_last_admin BEFORE UPDATE OR DELETE ON public.allowed_users
  FOR EACH ROW EXECUTE FUNCTION public.protect_last_admin();

INSERT INTO public.allowed_users (email, role) VALUES ('admin@biggerboat.example', 'admin');

CREATE TABLE public.news (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL, body text,
  author text NOT NULL DEFAULT 'Admin',
  status text NOT NULL DEFAULT 'published',
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.submissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  author_name text NOT NULL, team text NOT NULL, content text NOT NULL,
  status text NOT NULL DEFAULT 'pending',
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.blockers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL, description text,
  department text NOT NULL DEFAULT 'GENERAL',
  severity text NOT NULL DEFAULT 'warning',
  status text NOT NULL DEFAULT 'CRITICAL',
  updated_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.metrics (
  key text PRIMARY KEY, label text NOT NULL, value numeric NOT NULL,
  unit text, delta text,
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.news, public.submissions, public.blockers, public.metrics TO authenticated;
GRANT ALL ON public.news, public.submissions, public.blockers, public.metrics TO service_role;
ALTER TABLE public.news ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.blockers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.metrics ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allowed read" ON public.news FOR SELECT TO authenticated USING (public.is_allowed());
CREATE POLICY "Admin write" ON public.news FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY "Allowed read" ON public.submissions FOR SELECT TO authenticated USING (public.is_allowed());
CREATE POLICY "Admin write" ON public.submissions FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY "Allowed read" ON public.blockers FOR SELECT TO authenticated USING (public.is_allowed());
CREATE POLICY "Admin write" ON public.blockers FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY "Allowed read" ON public.metrics FOR SELECT TO authenticated USING (public.is_allowed());
CREATE POLICY "Admin write" ON public.metrics FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

INSERT INTO public.news (title, body, author, status, created_at) VALUES
('Résultats S1 2026', 'Croissance de 12% sur le premier semestre, portée par les nouveaux comptes.', 'Direction', 'published', now() - interval '1 day'),
('Ouverture du bureau de Lyon', 'Nos équipes s''installent dans les nouveaux locaux de la Part-Dieu en octobre.', 'RH', 'published', now() - interval '2 days'),
('Semaine de la qualité de vie au travail', 'Ateliers, conférences et activités du 14 au 18 octobre.', 'RH', 'published', now() - interval '3 days'),
('Mise à jour de la charte télétravail', 'Jusqu''à 3 jours de télétravail par semaine à partir de novembre.', 'RH', 'published', now() - interval '4 days'),
('Q3 Strategy Update', 'Priorités du trimestre : fidélisation client et efficacité opérationnelle.', 'Direction', 'published', now() - interval '6 days'),
('Nouveau portail des avantages salariés', 'Tous vos avantages regroupés dans un seul espace.', 'RH', 'published', now() - interval '8 days'),
('Bilan carbone 2025', 'Nos émissions baissent de 9% par rapport à l''an dernier.', 'RSE', 'published', now() - interval '10 days'),
('Arrivée de 14 nouveaux collaborateurs', 'Bienvenue aux nouvelles recrues de septembre.', 'RH', 'published', now() - interval '12 days'),
('Séminaire annuel', 'Rendez-vous les 5 et 6 décembre à Annecy.', 'Direction', 'published', now() - interval '14 days'),
('Programme de mentorat', 'Lancement d''un programme de mentorat interne (brouillon).', 'RH', 'draft', now() - interval '1 day'),
('Migration des outils IT', 'Calendrier de migration vers la nouvelle suite bureautique (brouillon).', 'IT', 'draft', now() - interval '2 days');

INSERT INTO public.submissions (author_name, team, content, status, created_at) VALUES
('Sarah Jenkins', 'Marketing', 'Refonte du kit de présentation commerciale.', 'pending', now() - interval '2 hours'),
('Thomas Martin', 'Support', 'Créer un canal dédié aux retours clients.', 'pending', now() - interval '5 hours'),
('Léa Bernard', 'IT', 'Demande de budget pour le renouvellement des postes.', 'pending', now() - interval '1 day'),
('Karim Haddad', 'Communication', 'Lancer une newsletter interne mensuelle.', 'pending', now() - interval '1 day'),
('Julie Moreau', 'Finance', 'Simplifier le processus de notes de frais.', 'approved', now() - interval '3 days'),
('Marc Dupont', 'Produit', 'Revue design hebdomadaire ouverte à tous.', 'approved', now() - interval '4 days'),
('Nina Petit', 'Ventes', 'Prime trimestrielle par équipe plutôt qu''individuelle.', 'rejected', now() - interval '6 days'),
('Paul Lefèvre', 'Logistique', 'Tableau d''affichage des délais de livraison.', 'pending', now() - interval '3 hours');

INSERT INTO public.blockers (title, description, department, severity, status) VALUES
('API Gateway Downtime', 'Coupures intermittentes du service de paiement.', 'IT', 'critical', 'IN PROGRESS'),
('Delayed Q4 Printing', 'Retard fournisseur sur les supports imprimés.', 'MARKETING', 'warning', 'IN PROGRESS'),
('Retard de livraison matériel', 'Les ordinateurs des nouvelles recrues arrivent avec 3 semaines de retard.', 'IT', 'critical', 'CRITICAL'),
('Absentéisme entrepôt', 'Hausse de l''absentéisme sur l''équipe de nuit.', 'LOGISTIQUE', 'warning', 'MONITORING'),
('Consommation du budget formation', 'Déjà 85% du budget annuel consommé.', 'RH', 'warning', 'MONITORING'),
('Accès VPN instable', 'Problème résolu après mise à jour du client.', 'IT', 'warning', 'SOLVED');

INSERT INTO public.metrics (key, label, value, unit, delta) VALUES
('training_kpi', 'Training KPI', 94.2, '%', '▲ 2.1%'),
('active_users', 'Active Users', 1280, NULL, 'vs 1,200 goal'),
('nps', 'NPS', 82, NULL, '▲ 4 pts'),
('engagement', 'Engagement', 72.5, '%', '▲ 1.8%'),
('turnover', 'Turnover', 8.4, '%', '▼ 0.6%'),
('absenteeism', 'Absentéisme', 3.9, '%', '▲ 0.3%'),
('open_positions', 'Postes ouverts', 17, NULL, '5 en finale'),
('training_hours', 'Heures de formation', 2340, 'h', '▲ 12%');
COMMIT;

-- ---------- 20260929094221_b002fc46-2fd7-4204-94bc-943049ab0f35.sql ----------
BEGIN;
CREATE SCHEMA IF NOT EXISTS private;
GRANT USAGE ON SCHEMA private TO authenticated;
ALTER FUNCTION public.current_app_role() SET SCHEMA private;
ALTER FUNCTION public.is_allowed() SET SCHEMA private;
ALTER FUNCTION public.is_admin() SET SCHEMA private;
ALTER FUNCTION private.current_app_role() SET search_path = public, private;
ALTER FUNCTION private.is_allowed() SET search_path = public, private;
ALTER FUNCTION private.is_admin() SET search_path = public, private;
CREATE OR REPLACE FUNCTION private.is_allowed()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, private AS $$
  SELECT private.current_app_role() IS NOT NULL
$$;
CREATE OR REPLACE FUNCTION private.is_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, private AS $$
  SELECT coalesce(private.current_app_role() = 'admin', false)
$$;
COMMIT;

-- ---------- 20261001152245_e9ea9c51-57c9-41a0-a2f1-76cbae4a40a5.sql ----------
BEGIN;
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'manager';
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'collaborateur';
COMMIT;

-- ---------- 20261001153145_e754c84f-1fde-4a44-9ae1-7fc3f7876ca6.sql ----------
BEGIN;
CREATE TABLE public.allowed_user_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  allowed_user_id uuid NOT NULL UNIQUE REFERENCES public.allowed_users(id) ON DELETE CASCADE,
  role public.app_role NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.allowed_user_roles TO authenticated;
GRANT ALL ON public.allowed_user_roles TO service_role;
ALTER TABLE public.allowed_user_roles ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.manager_teams (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  allowed_user_id uuid NOT NULL REFERENCES public.allowed_users(id) ON DELETE CASCADE,
  team text NOT NULL CHECK (char_length(trim(team)) BETWEEN 2 AND 60),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (allowed_user_id, team)
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.manager_teams TO authenticated;
GRANT ALL ON public.manager_teams TO service_role;
ALTER TABLE public.manager_teams ENABLE ROW LEVEL SECURITY;

INSERT INTO public.allowed_user_roles (allowed_user_id, role)
SELECT id, CASE WHEN role::text = 'admin' THEN 'admin'::public.app_role ELSE 'collaborateur'::public.app_role END
FROM public.allowed_users
ON CONFLICT (allowed_user_id) DO NOTHING;

CREATE OR REPLACE FUNCTION private.current_app_role()
RETURNS public.app_role
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
  SELECT aur.role
  FROM public.allowed_users au
  JOIN public.allowed_user_roles aur ON aur.allowed_user_id = au.id
  WHERE au.email = lower(auth.jwt() ->> 'email')
  LIMIT 1
$$;

CREATE OR REPLACE FUNCTION private.is_manager_or_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
  SELECT coalesce(private.current_app_role() IN ('admin'::public.app_role, 'manager'::public.app_role), false)
$$;

CREATE OR REPLACE FUNCTION private.can_review_team(_team text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
  SELECT coalesce(private.is_admin(), false)
    OR EXISTS (
      SELECT 1
      FROM public.allowed_users au
      JOIN public.allowed_user_roles aur ON aur.allowed_user_id = au.id
      JOIN public.manager_teams mt ON mt.allowed_user_id = au.id
      WHERE au.email = lower(auth.jwt() ->> 'email')
        AND aur.role = 'manager'::public.app_role
        AND lower(mt.team) = lower(_team)
    )
$$;

REVOKE ALL ON FUNCTION private.current_app_role() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.is_manager_or_admin() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.can_review_team(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.current_app_role() TO authenticated;
GRANT EXECUTE ON FUNCTION private.is_manager_or_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION private.can_review_team(text) TO authenticated;

CREATE POLICY "Admins manage roles"
ON public.allowed_user_roles FOR ALL TO authenticated
USING (private.is_admin()) WITH CHECK (private.is_admin());
CREATE POLICY "Users see own role"
ON public.allowed_user_roles FOR SELECT TO authenticated
USING (allowed_user_id IN (
  SELECT id FROM public.allowed_users WHERE email = lower(auth.jwt() ->> 'email')
));

CREATE POLICY "Admins manage manager teams"
ON public.manager_teams FOR ALL TO authenticated
USING (private.is_admin()) WITH CHECK (private.is_admin());
CREATE POLICY "Managers see own teams"
ON public.manager_teams FOR SELECT TO authenticated
USING (allowed_user_id IN (
  SELECT id FROM public.allowed_users WHERE email = lower(auth.jwt() ->> 'email')
));

DROP POLICY IF EXISTS "Allowed read" ON public.news;
CREATE POLICY "Allowed read published news"
ON public.news FOR SELECT TO authenticated
USING (private.is_allowed() AND (status = 'published' OR private.is_admin()));

DROP POLICY IF EXISTS "Allowed read" ON public.submissions;
DROP POLICY IF EXISTS "Admin write" ON public.submissions;
CREATE POLICY "Allowed read submissions"
ON public.submissions FOR SELECT TO authenticated
USING (
  private.is_admin()
  OR (private.current_app_role() = 'manager'::public.app_role AND private.can_review_team(team))
  OR (private.current_app_role() = 'collaborateur'::public.app_role AND status = 'approved')
);
CREATE POLICY "Allowed create pending submissions"
ON public.submissions FOR INSERT TO authenticated
WITH CHECK (private.is_allowed() AND status = 'pending');
CREATE POLICY "Managers review assigned submissions"
ON public.submissions FOR UPDATE TO authenticated
USING (private.current_app_role() = 'manager'::public.app_role AND private.can_review_team(team) AND status = 'pending')
WITH CHECK (private.current_app_role() = 'manager'::public.app_role AND private.can_review_team(team) AND status IN ('approved', 'rejected'));
CREATE POLICY "Admins manage submissions"
ON public.submissions FOR ALL TO authenticated
USING (private.is_admin()) WITH CHECK (private.is_admin());

CREATE OR REPLACE FUNCTION private.enforce_submission_review()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  IF private.current_app_role() = 'manager'::public.app_role THEN
    IF NEW.author_name IS DISTINCT FROM OLD.author_name
       OR NEW.team IS DISTINCT FROM OLD.team
       OR NEW.content IS DISTINCT FROM OLD.content
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
       OR NEW.status NOT IN ('approved', 'rejected')
       OR OLD.status <> 'pending'
       OR NOT private.can_review_team(OLD.team) THEN
      RAISE EXCEPTION 'Un manager peut uniquement valider ou refuser une soumission en attente de ses équipes';
    END IF;
  END IF;
  RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS enforce_submission_review ON public.submissions;
CREATE TRIGGER enforce_submission_review
BEFORE UPDATE ON public.submissions
FOR EACH ROW EXECUTE FUNCTION private.enforce_submission_review();

CREATE OR REPLACE FUNCTION private.protect_last_admin_role()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  IF OLD.role = 'admin'::public.app_role
     AND (TG_OP = 'DELETE' OR NEW.role <> 'admin'::public.app_role)
     AND (SELECT count(*) FROM public.allowed_user_roles WHERE role = 'admin'::public.app_role) <= 1 THEN
    RAISE EXCEPTION 'Impossible de retirer le dernier admin';
  END IF;
  RETURN COALESCE(NEW, OLD);
END
$$;

DROP TRIGGER IF EXISTS protect_last_admin_role ON public.allowed_user_roles;
CREATE TRIGGER protect_last_admin_role
BEFORE UPDATE OR DELETE ON public.allowed_user_roles
FOR EACH ROW EXECUTE FUNCTION private.protect_last_admin_role();
COMMIT;

-- ---------- 20261001153329_a9070f80-16a7-4191-8423-dceb407f7c59.sql ----------
BEGIN;
ALTER TABLE public.submissions ADD COLUMN submitted_by_email text;

CREATE OR REPLACE FUNCTION private.set_submission_owner()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  NEW.submitted_by_email := lower(auth.jwt() ->> 'email');
  RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS set_submission_owner ON public.submissions;
CREATE TRIGGER set_submission_owner
BEFORE INSERT ON public.submissions
FOR EACH ROW EXECUTE FUNCTION private.set_submission_owner();

DROP POLICY IF EXISTS "Allowed read submissions" ON public.submissions;
CREATE POLICY "Allowed read submissions"
ON public.submissions FOR SELECT TO authenticated
USING (
  private.is_admin()
  OR (private.current_app_role() = 'manager'::public.app_role AND private.can_review_team(team))
  OR submitted_by_email = lower(auth.jwt() ->> 'email')
  OR status = 'approved'
);
COMMIT;

-- ---------- 20261004125208_1b93c05f-dada-4c1c-983a-1db81433ab24.sql ----------
BEGIN;
DROP POLICY "Managers review assigned submissions" ON public.submissions;
DROP POLICY "Allowed read submissions" ON public.submissions;
DROP FUNCTION private.current_app_role();

ALTER TYPE public.app_role RENAME TO app_role_old;
CREATE TYPE public.app_role AS ENUM ('admin', 'manager', 'collaborateur');

ALTER TABLE public.allowed_users ALTER COLUMN role DROP DEFAULT;
ALTER TABLE public.allowed_users ALTER COLUMN role TYPE public.app_role USING role::text::public.app_role;
ALTER TABLE public.allowed_user_roles ALTER COLUMN role TYPE public.app_role USING role::text::public.app_role;
ALTER TABLE public.allowed_users ALTER COLUMN role SET DEFAULT 'collaborateur'::public.app_role;

DROP TYPE public.app_role_old;

CREATE FUNCTION private.current_app_role()
RETURNS public.app_role
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $$
  SELECT aur.role
  FROM public.allowed_users au
  JOIN public.allowed_user_roles aur ON aur.allowed_user_id = au.id
  WHERE au.email = lower(auth.jwt() ->> 'email')
  LIMIT 1
$$;

CREATE POLICY "Allowed read submissions" ON public.submissions
FOR SELECT TO authenticated
USING (private.is_admin() OR ((private.current_app_role() = 'manager'::public.app_role) AND private.can_review_team(team)) OR (submitted_by_email = lower((auth.jwt() ->> 'email'::text))) OR (status = 'approved'::text));

CREATE POLICY "Managers review assigned submissions" ON public.submissions
FOR UPDATE TO authenticated
USING ((private.current_app_role() = 'manager'::public.app_role) AND private.can_review_team(team) AND (status = 'pending'::text))
WITH CHECK ((private.current_app_role() = 'manager'::public.app_role) AND private.can_review_team(team) AND (status = ANY (ARRAY['approved'::text, 'rejected'::text])));
COMMIT;

-- ---------- 20261004125503_c247943c-a206-4f01-a514-2e82e32408e7.sql ----------
BEGIN;
CREATE TYPE public.blocker_status AS ENUM ('CRITICAL','IN PROGRESS','MONITORING','SOLVED');
CREATE TYPE public.blocker_severity AS ENUM ('critical','warning','info');
CREATE TYPE public.news_status AS ENUM ('draft','published');
CREATE TYPE public.submission_status AS ENUM ('pending','approved','rejected');

DROP POLICY "Allowed read published news" ON public.news;
DROP POLICY "Allowed create pending submissions" ON public.submissions;
DROP POLICY "Allowed read submissions" ON public.submissions;
DROP POLICY "Managers review assigned submissions" ON public.submissions;

ALTER TABLE public.blockers ALTER COLUMN status DROP DEFAULT, ALTER COLUMN status TYPE public.blocker_status USING status::public.blocker_status, ALTER COLUMN status SET DEFAULT 'CRITICAL';
ALTER TABLE public.blockers ALTER COLUMN severity DROP DEFAULT, ALTER COLUMN severity TYPE public.blocker_severity USING severity::public.blocker_severity, ALTER COLUMN severity SET DEFAULT 'warning';
ALTER TABLE public.news ALTER COLUMN status DROP DEFAULT, ALTER COLUMN status TYPE public.news_status USING status::public.news_status, ALTER COLUMN status SET DEFAULT 'published';
ALTER TABLE public.submissions ALTER COLUMN status DROP DEFAULT, ALTER COLUMN status TYPE public.submission_status USING status::public.submission_status, ALTER COLUMN status SET DEFAULT 'pending';

CREATE POLICY "Allowed read published news" ON public.news FOR SELECT TO authenticated
USING (private.is_allowed() AND (status = 'published' OR private.is_admin()));
CREATE POLICY "Allowed create pending submissions" ON public.submissions FOR INSERT TO authenticated
WITH CHECK (private.is_allowed() AND status = 'pending');
CREATE POLICY "Allowed read submissions" ON public.submissions FOR SELECT TO authenticated
USING (private.is_admin() OR (private.current_app_role() = 'manager'::public.app_role AND private.can_review_team(team)) OR submitted_by_email = lower(auth.jwt() ->> 'email') OR status = 'approved');
CREATE POLICY "Managers review assigned submissions" ON public.submissions FOR UPDATE TO authenticated
USING (private.current_app_role() = 'manager'::public.app_role AND private.can_review_team(team) AND status = 'pending')
WITH CHECK (private.current_app_role() = 'manager'::public.app_role AND private.can_review_team(team) AND status IN ('approved','rejected'));
COMMIT;

-- ---------- 20261004130041_92857a61-e2b3-4822-a5ca-4953e8707d86.sql ----------
BEGIN;
ALTER TABLE public.allowed_users ADD COLUMN team text;

CREATE OR REPLACE FUNCTION private.set_submission_owner()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  _email text := lower(auth.jwt() ->> 'email');
  _role public.app_role;
  _team text;
BEGIN
  NEW.submitted_by_email := _email;
  SELECT COALESCE(r.role, u.role), u.team INTO _role, _team
  FROM public.allowed_users u
  LEFT JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id
  WHERE u.email = _email;
  IF _role = 'collaborateur' THEN
    IF _team IS NULL OR btrim(_team) = '' THEN
      RAISE EXCEPTION 'Aucune équipe n''est associée à ton compte. Contacte un administrateur.';
    END IF;
    NEW.team := _team;
  END IF;
  RETURN NEW;
END
$$;
COMMIT;

-- ---------- 20261004130819_8177e3c3-73fc-4c2e-ba7f-0b26c4238353.sql ----------
BEGIN;
ALTER TABLE public.manager_teams ADD CONSTRAINT manager_teams_team_unique UNIQUE (team);
COMMIT;

-- ---------- 20261004130926_b749e8ed-a820-4ef6-ba88-124f578b7eb2.sql ----------
BEGIN;
CREATE TYPE public.rejection_category AS ENUM ('à clarifier', 'en désaccord avec les process', 'doublon', 'autre');
ALTER TABLE public.submissions
  ADD COLUMN rejection_category public.rejection_category,
  ADD COLUMN rejection_note text;
UPDATE public.submissions
  SET rejection_category = 'autre', rejection_note = 'Motif non renseigné (refus antérieur à la mise en place des motifs)'
  WHERE status = 'rejected';
ALTER TABLE public.submissions ADD CONSTRAINT submissions_rejection_reason_check CHECK (
  (status = 'rejected' AND rejection_category IS NOT NULL AND rejection_note IS NOT NULL AND length(btrim(rejection_note)) > 0)
  OR (status <> 'rejected' AND rejection_category IS NULL AND rejection_note IS NULL)
);
COMMIT;

-- ---------- 20261004131123_36086d66-c492-447f-ae17-0fa9d76307a0.sql ----------
BEGIN;
ALTER TABLE public.news ADD COLUMN author_email text;

CREATE OR REPLACE FUNCTION private.set_news_author_email()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, private AS $$
BEGIN
  IF NEW.author_email IS NULL THEN
    NEW.author_email := lower(auth.jwt() ->> 'email');
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER set_news_author_email
BEFORE INSERT ON public.news
FOR EACH ROW EXECUTE FUNCTION private.set_news_author_email();

CREATE OR REPLACE FUNCTION private.anonymize_removed_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, private AS $$
BEGIN
  UPDATE public.submissions
     SET author_name = 'Utilisateur supprimé',
         submitted_by_email = 'Utilisateur supprimé'
   WHERE lower(submitted_by_email) = lower(OLD.email);

  UPDATE public.news
     SET author = 'Utilisateur supprimé',
         author_email = 'Utilisateur supprimé'
   WHERE lower(author_email) = lower(OLD.email);

  RETURN OLD;
END $$;

CREATE TRIGGER anonymize_removed_user
AFTER DELETE ON public.allowed_users
FOR EACH ROW EXECUTE FUNCTION private.anonymize_removed_user();
COMMIT;

-- ---------- 20261004131651_56ca3c56-582c-4d37-b709-3b74c725970a.sql ----------
BEGIN;
ALTER TABLE public.submissions ADD COLUMN revalidate_at timestamptz;
ALTER TABLE public.news ADD COLUMN revalidate_at timestamptz;

CREATE OR REPLACE FUNCTION private.set_revalidate_at()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, private AS $$
DECLARE
  live text := CASE TG_TABLE_NAME WHEN 'submissions' THEN 'approved' ELSE 'published' END;
BEGIN
  IF NEW.status::text = live THEN
    IF TG_OP = 'INSERT' OR OLD.status::text <> live OR NEW.revalidate_at IS NULL THEN
      NEW.revalidate_at := now() + interval '1 year';
    END IF;
  ELSE
    NEW.revalidate_at := NULL;
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER set_revalidate_at BEFORE INSERT OR UPDATE OF status ON public.submissions
FOR EACH ROW EXECUTE FUNCTION private.set_revalidate_at();
CREATE TRIGGER set_revalidate_at BEFORE INSERT OR UPDATE OF status ON public.news
FOR EACH ROW EXECUTE FUNCTION private.set_revalidate_at();

UPDATE public.submissions SET revalidate_at = now() + interval '1 year' WHERE status = 'approved';
UPDATE public.news SET revalidate_at = now() + interval '1 year' WHERE status = 'published';

CREATE OR REPLACE FUNCTION private.expire_revalidations()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, private AS $$
BEGIN
  UPDATE public.submissions SET status = 'pending', revalidate_at = NULL
   WHERE status = 'approved' AND revalidate_at <= now();
  UPDATE public.news SET status = 'draft', revalidate_at = NULL
   WHERE status = 'published' AND revalidate_at <= now();
END $$;
REVOKE ALL ON FUNCTION private.expire_revalidations() FROM PUBLIC, anon, authenticated;

CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.schedule('expire-revalidations-daily', '0 3 * * *', $$SELECT private.expire_revalidations()$$);
COMMIT;

-- ---------- 20261004131801_3b2b328c-9616-4f46-9085-7c574e911d93.sql ----------
BEGIN;
ALTER TABLE public.submissions ADD COLUMN attachment_path text, ADD COLUMN attachment_name text;

CREATE OR REPLACE FUNCTION private.check_submission_attachment()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, private AS $$
BEGIN
  IF NEW.attachment_path IS NOT NULL
     AND (TG_OP = 'INSERT' OR NEW.attachment_path IS DISTINCT FROM OLD.attachment_path)
     AND NOT private.is_admin()
     AND split_part(NEW.attachment_path, '/', 1) <> coalesce(auth.uid()::text, '') THEN
    RAISE EXCEPTION 'Pièce jointe invalide';
  END IF;
  IF NEW.attachment_path IS NULL THEN NEW.attachment_name := NULL; END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER check_submission_attachment BEFORE INSERT OR UPDATE ON public.submissions
FOR EACH ROW EXECUTE FUNCTION private.check_submission_attachment();

CREATE POLICY "Allowed users upload own submission PDF" ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'submission-attachments'
  AND private.is_allowed()
  AND (storage.foldername(name))[1] = auth.uid()::text
  AND lower(storage.extension(name)) = 'pdf'
);

CREATE POLICY "Reviewers and owner read submission PDF" ON storage.objects
FOR SELECT TO authenticated
USING (
  bucket_id = 'submission-attachments'
  AND (
    private.is_admin()
    OR (storage.foldername(name))[1] = auth.uid()::text
    OR EXISTS (
      SELECT 1 FROM public.submissions s
      WHERE s.attachment_path = storage.objects.name
        AND private.current_app_role() = 'manager'::public.app_role
        AND private.can_review_team(s.team)
    )
  )
);

CREATE POLICY "Admins delete submission PDF" ON storage.objects
FOR DELETE TO authenticated
USING (bucket_id = 'submission-attachments' AND private.is_admin());
COMMIT;

-- ---------- 20261004132027_b1065e71-8c66-435d-849b-e4ce4f2472c3.sql ----------
BEGIN;
CREATE TABLE public.metrics_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  metric_key text NOT NULL,
  value numeric NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX metrics_history_key_time ON public.metrics_history (metric_key, recorded_at DESC);
GRANT SELECT ON public.metrics_history TO authenticated;
GRANT ALL ON public.metrics_history TO service_role;
ALTER TABLE public.metrics_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allowed read metrics history" ON public.metrics_history
FOR SELECT TO authenticated USING (private.is_allowed());

INSERT INTO public.metrics_history (metric_key, value, recorded_at)
SELECT key, value, updated_at FROM public.metrics;

CREATE OR REPLACE FUNCTION private.record_metric_history()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, private AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.key <> OLD.key THEN
    UPDATE public.metrics_history SET metric_key = NEW.key WHERE metric_key = OLD.key;
  END IF;
  IF TG_OP = 'INSERT' OR NEW.value IS DISTINCT FROM OLD.value THEN
    INSERT INTO public.metrics_history (metric_key, value) VALUES (NEW.key, NEW.value);
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER record_metric_history AFTER INSERT OR UPDATE ON public.metrics
FOR EACH ROW EXECUTE FUNCTION private.record_metric_history();

CREATE OR REPLACE FUNCTION private.delete_metric_history()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, private AS $$
BEGIN
  DELETE FROM public.metrics_history WHERE metric_key = OLD.key;
  RETURN OLD;
END $$;
CREATE TRIGGER delete_metric_history AFTER DELETE ON public.metrics
FOR EACH ROW EXECUTE FUNCTION private.delete_metric_history();

ALTER TABLE public.metrics DROP COLUMN delta;

CREATE VIEW public.metrics_with_trend WITH (security_invoker = true) AS
SELECT m.key, m.label, m.value, m.unit, m.updated_at,
  p.value AS previous_value,
  CASE WHEN p.value IS NULL OR p.value = m.value THEN 'stable'
       WHEN m.value > p.value THEN 'hausse' ELSE 'baisse' END AS trend
FROM public.metrics m
LEFT JOIN LATERAL (
  SELECT h.value FROM public.metrics_history h
  WHERE h.metric_key = m.key
  ORDER BY h.recorded_at DESC OFFSET 1 LIMIT 1
) p ON true;
GRANT SELECT ON public.metrics_with_trend TO authenticated;
COMMIT;

-- ---------- 20261006093542_cbce0e4b-6f68-4bf1-ab0e-c3033d4ad1dd.sql ----------
BEGIN;
ALTER TYPE public.blocker_status RENAME VALUE 'CRITICAL' TO 'CRITIQUE';
ALTER TYPE public.blocker_status RENAME VALUE 'IN PROGRESS' TO 'EN COURS';
ALTER TYPE public.blocker_status RENAME VALUE 'MONITORING' TO 'SURVEILLANCE';
ALTER TYPE public.blocker_status RENAME VALUE 'SOLVED' TO 'RÉSOLU';

ALTER TYPE public.news_status RENAME VALUE 'draft' TO 'brouillon';
ALTER TYPE public.news_status RENAME VALUE 'published' TO 'publiée';

ALTER TYPE public.submission_status RENAME VALUE 'pending' TO 'en attente';
ALTER TYPE public.submission_status RENAME VALUE 'approved' TO 'validée';
ALTER TYPE public.submission_status RENAME VALUE 'rejected' TO 'refusée';

CREATE OR REPLACE FUNCTION private.set_revalidate_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, private
AS $$
DECLARE
  live text := CASE TG_TABLE_NAME WHEN 'submissions' THEN 'validée' ELSE 'publiée' END;
BEGIN
  IF NEW.status::text = live THEN
    IF TG_OP = 'INSERT' OR OLD.status::text <> live OR NEW.revalidate_at IS NULL THEN
      NEW.revalidate_at := now() + interval '1 year';
    END IF;
  ELSE
    NEW.revalidate_at := NULL;
  END IF;
  RETURN NEW;
END
$$;

CREATE OR REPLACE FUNCTION private.expire_revalidations()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  UPDATE public.submissions
  SET status = 'en attente', revalidate_at = NULL
  WHERE status = 'validée' AND revalidate_at <= now();

  UPDATE public.news
  SET status = 'brouillon', revalidate_at = NULL
  WHERE status = 'publiée' AND revalidate_at <= now();
END
$$;

REVOKE ALL ON FUNCTION private.expire_revalidations() FROM PUBLIC, anon, authenticated;
COMMIT;

-- ---------- 20261006114836_db9781bc-b259-43e4-8c72-64ccb293ca87.sql ----------
BEGIN;
CREATE OR REPLACE FUNCTION private.enforce_submission_review()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $function$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF NEW.status NOT IN ('validée'::public.submission_status, 'refusée'::public.submission_status) THEN
      RAISE EXCEPTION 'Une soumission ne peut passer qu''à validée ou refusée';
    END IF;
    IF OLD.status <> 'en attente'::public.submission_status THEN
      RAISE EXCEPTION 'Seule une soumission en attente peut être validée ou refusée';
    END IF;
  END IF;
  RETURN NEW;
END
$function$;
COMMIT;

-- ---------- 20261006114933_6bf78b7c-2c1c-4e6c-89f4-ff5bfd6783a3.sql ----------
BEGIN;
CREATE OR REPLACE FUNCTION private.enforce_submission_review()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  IF private.current_app_role() = 'manager'::public.app_role THEN
    IF NEW.author_name IS DISTINCT FROM OLD.author_name
       OR NEW.team IS DISTINCT FROM OLD.team
       OR NEW.content IS DISTINCT FROM OLD.content
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
       OR NEW.status NOT IN ('validée'::public.submission_status, 'refusée'::public.submission_status)
       OR OLD.status <> 'en attente'::public.submission_status
       OR NOT private.can_review_team(OLD.team) THEN
      RAISE EXCEPTION 'Un manager peut uniquement valider ou refuser une soumission en attente de ses équipes';
    END IF;
  END IF;
  RETURN NEW;
END
$function$;
COMMIT;

-- ---------- 20261006120720_5fc3190f-e292-4e6c-a75b-02d12f1835b9.sql ----------
BEGIN;
-- 1. Faille : un compte non inscrit sur la liste blanche pouvait lire les soumissions validées
DROP POLICY IF EXISTS "Allowed read submissions" ON public.submissions;
CREATE POLICY "Allowed read submissions" ON public.submissions
  FOR SELECT TO authenticated
  USING (
    private.is_allowed() AND (
      private.is_admin()
      OR ((private.current_app_role() = 'manager'::public.app_role) AND private.can_review_team(team))
      OR (submitted_by_email = lower((auth.jwt() ->> 'email'::text)))
      OR (status = 'validée'::public.submission_status)
    )
  );

-- 2. Longueur du contenu d'une soumission contrôlée en base (5 à 2000 caractères)
ALTER TABLE public.submissions
  ADD CONSTRAINT submissions_content_length_check
  CHECK (char_length(btrim(content)) BETWEEN 5 AND 2000);

-- 3. Un seul manager par équipe, sans tenir compte des majuscules ni des espaces
ALTER TABLE public.manager_teams DROP CONSTRAINT IF EXISTS manager_teams_team_unique;
CREATE UNIQUE INDEX manager_teams_team_unique_ci ON public.manager_teams (lower(btrim(team)));
COMMIT;

-- ---------- 20261006160032_924327a2-5ab9-4dcd-918a-209d615d6254.sql ----------
BEGIN;
ALTER TABLE public.news ALTER COLUMN status SET DEFAULT 'brouillon'::public.news_status;

CREATE OR REPLACE FUNCTION private.set_news_author_email()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  IF NOT private.is_admin() OR NEW.author_email IS NULL THEN
    NEW.author_email := lower(auth.jwt() ->> 'email');
  END IF;
  RETURN NEW;
END $function$;

DROP POLICY IF EXISTS "Allowed read published news" ON public.news;
CREATE POLICY "Allowed read published news" ON public.news
  FOR SELECT TO authenticated
  USING (
    private.is_allowed() AND (
      status = 'publiée'::public.news_status
      OR private.is_admin()
      OR (private.current_app_role() = 'manager'::public.app_role AND author_email = lower(auth.jwt() ->> 'email'))
    )
  );

CREATE POLICY "Manager insert own draft news" ON public.news
  FOR INSERT TO authenticated
  WITH CHECK (
    private.current_app_role() = 'manager'::public.app_role
    AND status = 'brouillon'::public.news_status
    AND author_email = lower(auth.jwt() ->> 'email')
  );

CREATE POLICY "Manager update own draft news" ON public.news
  FOR UPDATE TO authenticated
  USING (
    private.current_app_role() = 'manager'::public.app_role
    AND status = 'brouillon'::public.news_status
    AND author_email = lower(auth.jwt() ->> 'email')
  )
  WITH CHECK (
    private.current_app_role() = 'manager'::public.app_role
    AND status IN ('brouillon'::public.news_status, 'publiée'::public.news_status)
    AND author_email = lower(auth.jwt() ->> 'email')
  );

CREATE POLICY "Manager delete own draft news" ON public.news
  FOR DELETE TO authenticated
  USING (
    private.current_app_role() = 'manager'::public.app_role
    AND status = 'brouillon'::public.news_status
    AND author_email = lower(auth.jwt() ->> 'email')
  );
COMMIT;

-- ---------- 20261006161350_6ec2cf28-1264-4871-b32d-1841c544fe69.sql ----------
BEGIN;
-- Le trigger de protection du dernier admin sur allowed_users lisait l'ancienne colonne.
-- La protection reste assurée par private.protect_last_admin_role() sur allowed_user_roles,
-- qui se déclenche aussi lors d'une suppression en cascade depuis allowed_users.
DROP TRIGGER IF EXISTS protect_last_admin ON public.allowed_users;
DROP FUNCTION IF EXISTS public.protect_last_admin();

CREATE OR REPLACE FUNCTION private.set_submission_owner()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _email text := lower(auth.jwt() ->> 'email');
  _role public.app_role;
  _team text;
BEGIN
  NEW.submitted_by_email := _email;
  SELECT r.role, u.team INTO _role, _team
  FROM public.allowed_users u
  LEFT JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id
  WHERE u.email = _email;
  IF _role = 'collaborateur' THEN
    IF _team IS NULL OR btrim(_team) = '' THEN
      RAISE EXCEPTION 'Aucune équipe n''est associée à ton compte. Contacte un administrateur.';
    END IF;
    NEW.team := _team;
  END IF;
  RETURN NEW;
END
$function$;

ALTER TABLE public.allowed_users DROP COLUMN role;
COMMIT;

-- ---------- 20261006162220_30e65ee6-8958-489c-b816-58418f6c104d.sql ----------
BEGIN;
CREATE OR REPLACE VIEW public.metrics_with_trend
WITH (security_invoker = true) AS
SELECT m.key,
    m.label,
    m.value,
    m.unit,
    m.updated_at,
    p.value AS previous_value,
    CASE
        WHEN p.value IS NULL OR p.value = m.value THEN 'stable'::text
        WHEN m.value > p.value THEN 'hausse'::text
        ELSE 'baisse'::text
    END AS trend,
    CASE WHEN p.value IS NULL THEN NULL ELSE m.value - p.value END AS delta
FROM public.metrics m
LEFT JOIN LATERAL (
    SELECT h.value
    FROM public.metrics_history h
    WHERE h.metric_key = m.key
    ORDER BY h.recorded_at DESC
    OFFSET 1
    LIMIT 1
) p ON true;
COMMIT;

-- ---------- 20261006163825_cafe9ae6-9472-4c91-b125-cde664a6bbf5.sql ----------
BEGIN;
CREATE TABLE public.submission_status_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  submission_id uuid NOT NULL REFERENCES public.submissions(id) ON DELETE CASCADE,
  old_status public.submission_status,
  new_status public.submission_status NOT NULL,
  changed_by_email text,
  changed_by_name text,
  is_automatic boolean NOT NULL DEFAULT false,
  rejection_category public.rejection_category,
  rejection_note text,
  changed_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX submission_status_history_submission_idx
  ON public.submission_status_history (submission_id, changed_at);

GRANT SELECT ON public.submission_status_history TO authenticated;
GRANT ALL ON public.submission_status_history TO service_role;

ALTER TABLE public.submission_status_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Read history of readable submissions" ON public.submission_status_history
  FOR SELECT TO authenticated
  USING (private.is_allowed() AND EXISTS (
    SELECT 1 FROM public.submissions s WHERE s.id = submission_id
  ));

CREATE OR REPLACE FUNCTION private.record_submission_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _email text := lower(nullif(auth.jwt() ->> 'email', ''));
  _name text := coalesce(auth.jwt() -> 'user_metadata' ->> 'full_name', auth.jwt() -> 'user_metadata' ->> 'name', _email);
BEGIN
  IF TG_OP = 'INSERT' OR NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO public.submission_status_history
      (submission_id, old_status, new_status, changed_by_email, changed_by_name, is_automatic, rejection_category, rejection_note)
    VALUES
      (NEW.id,
       CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE OLD.status END,
       NEW.status,
       _email,
       CASE WHEN _email IS NULL THEN NULL ELSE _name END,
       _email IS NULL,
       CASE WHEN NEW.status = 'refusée'::public.submission_status THEN NEW.rejection_category END,
       CASE WHEN NEW.status = 'refusée'::public.submission_status THEN NEW.rejection_note END);
  END IF;
  RETURN NEW;
END
$function$;

CREATE TRIGGER record_submission_status
  AFTER INSERT OR UPDATE ON public.submissions
  FOR EACH ROW EXECUTE FUNCTION private.record_submission_status();

CREATE OR REPLACE FUNCTION private.anonymize_removed_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  UPDATE public.submissions
     SET author_name = 'Utilisateur supprimé',
         submitted_by_email = 'Utilisateur supprimé'
   WHERE lower(submitted_by_email) = lower(OLD.email);

  UPDATE public.news
     SET author = 'Utilisateur supprimé',
         author_email = 'Utilisateur supprimé'
   WHERE lower(author_email) = lower(OLD.email);

  UPDATE public.submission_status_history
     SET changed_by_name = 'Utilisateur supprimé',
         changed_by_email = 'Utilisateur supprimé'
   WHERE lower(changed_by_email) = lower(OLD.email);

  RETURN OLD;
END $function$;

INSERT INTO public.submission_status_history (submission_id, old_status, new_status, is_automatic, changed_at)
SELECT id, NULL, status, true, created_at FROM public.submissions;
COMMIT;

-- ---------- 20261006170014_9615024a-f1ef-46ac-9c89-202c1352facc.sql ----------
BEGIN;
CREATE TABLE public.attachment_deletion_queue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  path text NOT NULL UNIQUE,
  queued_at timestamptz NOT NULL DEFAULT now(),
  last_error text
);
GRANT SELECT, UPDATE, DELETE ON public.attachment_deletion_queue TO authenticated;
GRANT ALL ON public.attachment_deletion_queue TO service_role;
ALTER TABLE public.attachment_deletion_queue ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins manage attachment deletion queue" ON public.attachment_deletion_queue
  FOR ALL TO authenticated USING (private.is_admin()) WITH CHECK (private.is_admin());

CREATE OR REPLACE FUNCTION private.anonymize_removed_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  -- Pièces jointes : fichiers mis en file de suppression, liens retirés (avant l'anonymisation de l'email)
  INSERT INTO public.attachment_deletion_queue (path)
  SELECT attachment_path FROM public.submissions
   WHERE lower(submitted_by_email) = lower(OLD.email) AND attachment_path IS NOT NULL
  ON CONFLICT (path) DO NOTHING;

  UPDATE public.submissions
     SET attachment_path = NULL,
         attachment_name = NULL
   WHERE lower(submitted_by_email) = lower(OLD.email) AND attachment_path IS NOT NULL;

  UPDATE public.submissions
     SET author_name = 'Utilisateur supprimé',
         submitted_by_email = 'Utilisateur supprimé'
   WHERE lower(submitted_by_email) = lower(OLD.email);

  UPDATE public.news
     SET author = 'Utilisateur supprimé',
         author_email = 'Utilisateur supprimé'
   WHERE lower(author_email) = lower(OLD.email);

  UPDATE public.submission_status_history
     SET changed_by_name = 'Utilisateur supprimé',
         changed_by_email = 'Utilisateur supprimé'
   WHERE lower(changed_by_email) = lower(OLD.email);

  RETURN OLD;
END $function$;
COMMIT;

-- ---------- 20261006172727_a1bd7df4-2b61-41cb-86ea-0acf1b4674bb.sql ----------
BEGIN;
-- Date de départ prévue
ALTER TABLE public.allowed_users ADD COLUMN departure_date date;

CREATE OR REPLACE FUNCTION private.check_departure_date()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public', 'private' AS $function$
BEGIN
  IF NEW.departure_date IS NOT NULL
     AND (TG_OP = 'INSERT' OR NEW.departure_date IS DISTINCT FROM OLD.departure_date)
     AND NEW.departure_date < current_date + 7 THEN
    RAISE EXCEPTION 'La date de départ doit être au moins 7 jours après aujourd''hui';
  END IF;
  RETURN NEW;
END $function$;
CREATE TRIGGER check_departure_date BEFORE INSERT OR UPDATE OF departure_date ON public.allowed_users
  FOR EACH ROW EXECUTE FUNCTION private.check_departure_date();

-- Suppression différée des fichiers
ALTER TABLE public.attachment_deletion_queue ADD COLUMN delete_after timestamptz NOT NULL DEFAULT now();

-- Alertes de départ (servent aussi de journal des alertes envoyées)
CREATE TABLE public.departure_notices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  departing_user_id uuid,
  departing_label text NOT NULL,
  recipient_email text NOT NULL,
  departure_date date NOT NULL,
  kind text NOT NULL CHECK (kind IN ('préavis', 'sans préavis')),
  documents jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  reminder_at timestamptz,
  downloaded_at timestamptz,
  closed_at timestamptz
);
CREATE INDEX departure_notices_open_idx ON public.departure_notices (recipient_email) WHERE closed_at IS NULL;
GRANT SELECT ON public.departure_notices TO authenticated;
GRANT ALL ON public.departure_notices TO service_role;
ALTER TABLE public.departure_notices ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Recipients and admins read departure notices" ON public.departure_notices
  FOR SELECT TO authenticated
  USING (private.is_allowed() AND (recipient_email = lower(auth.jwt() ->> 'email') OR private.is_admin()));

-- Destinataires : les managers de l'équipe de la personne qui part, et les admins (sauf elle-même)
CREATE OR REPLACE FUNCTION private.departure_recipients(_email text, _team text)
RETURNS SETOF text LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'private' AS $function$
  SELECT DISTINCT u.email
  FROM public.allowed_users u
  JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id
  LEFT JOIN public.manager_teams mt ON mt.allowed_user_id = u.id
  WHERE lower(u.email) <> lower(_email)
    AND (r.role = 'admin'::public.app_role
         OR (r.role = 'manager'::public.app_role AND _team IS NOT NULL
             AND lower(btrim(mt.team)) = lower(btrim(_team))))
$function$;

CREATE OR REPLACE FUNCTION private.departure_documents(_email text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'private' AS $function$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'submission_id', s.id, 'path', s.attachment_path, 'name', s.attachment_name,
           'created_at', s.created_at, 'excerpt', left(s.content, 60)) ORDER BY s.created_at), '[]'::jsonb)
  FROM public.submissions s
  WHERE lower(s.submitted_by_email) = lower(_email) AND s.attachment_path IS NOT NULL
$function$;

CREATE OR REPLACE FUNCTION private.notify_departure(_user_id uuid, _email text, _team text, _date date, _kind text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'private' AS $function$
DECLARE _docs jsonb := private.departure_documents(_email);
BEGIN
  UPDATE public.departure_notices SET closed_at = now()
   WHERE departing_user_id = _user_id AND closed_at IS NULL;
  IF jsonb_array_length(_docs) = 0 THEN RETURN; END IF;
  INSERT INTO public.departure_notices (departing_user_id, departing_label, recipient_email, departure_date, kind, documents)
  SELECT _user_id, _email, rcpt, _date, _kind, _docs FROM private.departure_recipients(_email, _team) AS rcpt;
END $function$;

CREATE OR REPLACE FUNCTION private.on_departure_date_change()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'private' AS $function$
BEGIN
  IF NEW.departure_date IS DISTINCT FROM OLD.departure_date THEN
    IF NEW.departure_date IS NULL THEN
      UPDATE public.departure_notices SET closed_at = now()
       WHERE departing_user_id = NEW.id AND closed_at IS NULL;
    ELSE
      PERFORM private.notify_departure(NEW.id, NEW.email, NEW.team, NEW.departure_date, 'préavis');
    END IF;
  END IF;
  RETURN NEW;
END $function$;
CREATE TRIGGER on_departure_date_change AFTER UPDATE OF departure_date ON public.allowed_users
  FOR EACH ROW EXECUTE FUNCTION private.on_departure_date_change();

CREATE OR REPLACE FUNCTION private.anonymize_removed_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'private' AS $function$
DECLARE _planned boolean := OLD.departure_date IS NOT NULL AND OLD.departure_date <= current_date;
BEGIN
  INSERT INTO public.attachment_deletion_queue (path, delete_after)
  SELECT attachment_path, CASE WHEN _planned THEN now() ELSE now() + interval '7 days' END
    FROM public.submissions
   WHERE lower(submitted_by_email) = lower(OLD.email) AND attachment_path IS NOT NULL
  ON CONFLICT (path) DO NOTHING;

  IF _planned THEN
    UPDATE public.departure_notices SET closed_at = now(), departing_label = 'Utilisateur supprimé'
     WHERE departing_user_id = OLD.id AND closed_at IS NULL;
  ELSE
    PERFORM private.notify_departure(OLD.id, OLD.email, OLD.team, current_date, 'sans préavis');
  END IF;

  UPDATE public.submissions
     SET author_name = 'Utilisateur supprimé', submitted_by_email = 'Utilisateur supprimé'
   WHERE lower(submitted_by_email) = lower(OLD.email);
  UPDATE public.news
     SET author = 'Utilisateur supprimé', author_email = 'Utilisateur supprimé'
   WHERE lower(author_email) = lower(OLD.email);
  UPDATE public.submission_status_history
     SET changed_by_name = 'Utilisateur supprimé', changed_by_email = 'Utilisateur supprimé'
   WHERE lower(changed_by_email) = lower(OLD.email);
  RETURN OLD;
END $function$;

CREATE OR REPLACE FUNCTION public.mark_departure_notice_downloaded(_id uuid)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path TO 'public', 'private' AS $function$
  UPDATE public.departure_notices SET downloaded_at = now()
   WHERE id = _id AND downloaded_at IS NULL
     AND (recipient_email = lower(auth.jwt() ->> 'email') OR private.is_admin());
$function$;
REVOKE ALL ON FUNCTION public.mark_departure_notice_downloaded(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.mark_departure_notice_downloaded(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION private.run_departures()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'private' AS $function$
DECLARE u record;
BEGIN
  UPDATE public.departure_notices SET reminder_at = now()
   WHERE closed_at IS NULL AND downloaded_at IS NULL AND reminder_at IS NULL
     AND kind = 'préavis' AND departure_date - 2 <= current_date;

  FOR u IN SELECT id FROM public.allowed_users
            WHERE departure_date IS NOT NULL AND departure_date <= current_date LOOP
    BEGIN
      DELETE FROM public.allowed_users WHERE id = u.id;
    EXCEPTION WHEN others THEN
      RAISE WARNING 'Départ non appliqué pour % : %', u.id, SQLERRM;
    END;
  END LOOP;

  UPDATE public.departure_notices SET closed_at = now(), departing_label = 'Utilisateur supprimé'
   WHERE closed_at IS NULL AND kind = 'sans préavis' AND created_at <= now() - interval '7 days';
END $function$;
SELECT cron.schedule('run-departures-daily', '15 3 * * *', 'SELECT private.run_departures()');
COMMIT;

-- ---------- 20261006174221_e48290ac-5fab-491f-8872-f3f2ba2ff848.sql ----------
BEGIN;
ALTER TYPE public.blocker_status RENAME VALUE 'CRITIQUE' TO 'OUVERT';
ALTER TABLE public.blockers ALTER COLUMN status SET DEFAULT 'OUVERT'::public.blocker_status;

CREATE OR REPLACE FUNCTION private.set_submission_owner()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _email text := lower(auth.jwt() ->> 'email');
  _role public.app_role;
  _team text;
  _uid uuid;
  _chosen text;
BEGIN
  NEW.submitted_by_email := _email;
  SELECT r.role, u.team, u.id INTO _role, _team, _uid
  FROM public.allowed_users u
  LEFT JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id
  WHERE u.email = _email;
  IF _role = 'collaborateur' THEN
    IF _team IS NULL OR btrim(_team) = '' THEN
      RAISE EXCEPTION 'Aucune équipe n''est associée à ton compte. Contacte un administrateur.';
    END IF;
    NEW.team := _team;
  ELSIF _role = 'manager' THEN
    SELECT mt.team INTO _chosen FROM public.manager_teams mt
     WHERE mt.allowed_user_id = _uid AND lower(btrim(mt.team)) = lower(btrim(coalesce(NEW.team, '')))
     LIMIT 1;
    IF _chosen IS NULL THEN
      RAISE EXCEPTION 'Choisis une de tes équipes pour cette demande.';
    END IF;
    NEW.team := _chosen;
  ELSIF _role = 'admin' THEN
    NEW.team := 'Admin';
  END IF;
  RETURN NEW;
END
$function$;

ALTER TABLE public.manager_teams
  ADD CONSTRAINT manager_teams_not_admin_team CHECK (lower(btrim(team)) <> 'admin');

-- Version élèves : cette tâche planifiée n'existe pas sur une base neuve
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'purge-attachments-daily') THEN
    PERFORM cron.unschedule('purge-attachments-daily');
  END IF;
END $$;
COMMIT;

-- ---------- 20261006181329_24292ff8-bc0d-41e2-853d-f06cac21faf8.sql ----------
BEGIN;
CREATE OR REPLACE FUNCTION private.check_blocker_transition()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  IF TG_OP = 'INSERT' AND NEW.status = 'RÉSOLU'::public.blocker_status THEN
    RAISE EXCEPTION 'Un point bloquant ne peut pas être créé directement au statut RÉSOLU.';
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.status = 'OUVERT'::public.blocker_status
     AND NEW.status = 'RÉSOLU'::public.blocker_status THEN
    RAISE EXCEPTION 'Un point bloquant OUVERT doit d''abord passer EN COURS avant d''être RÉSOLU.';
  END IF;
  RETURN NEW;
END
$function$;

CREATE TRIGGER check_blocker_transition
  BEFORE INSERT OR UPDATE OF status ON public.blockers
  FOR EACH ROW EXECUTE FUNCTION private.check_blocker_transition();
COMMIT;

-- ---------- 20261006182306_7842ec11-02a6-45b1-adee-bdba515f0ea9.sql ----------
BEGIN;
CREATE OR REPLACE FUNCTION private.queue_deleted_submission_attachment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  IF OLD.attachment_path IS NOT NULL THEN
    INSERT INTO public.attachment_deletion_queue (path, delete_after)
    VALUES (OLD.attachment_path, now())
    ON CONFLICT (path) DO UPDATE SET delete_after = least(public.attachment_deletion_queue.delete_after, now());
  END IF;
  RETURN OLD;
END
$function$;

CREATE TRIGGER queue_deleted_submission_attachment
  AFTER DELETE ON public.submissions
  FOR EACH ROW EXECUTE FUNCTION private.queue_deleted_submission_attachment();
COMMIT;

-- ---------- 20261006184200_e816c7cd-5737-47c1-97ef-4218181f7d72.sql ----------
BEGIN;
ALTER TABLE public.allowed_users
  ADD COLUMN IF NOT EXISTS first_name text,
  ADD COLUMN IF NOT EXISTS last_name text;

ALTER TABLE public.allowed_users
  ADD CONSTRAINT allowed_users_first_name_len CHECK (first_name IS NULL OR char_length(btrim(first_name)) BETWEEN 1 AND 100),
  ADD CONSTRAINT allowed_users_last_name_len CHECK (last_name IS NULL OR char_length(btrim(last_name)) BETWEEN 1 AND 100);

CREATE OR REPLACE FUNCTION public.bulk_import_allowed_users(_rows jsonb, _dry_run boolean DEFAULT true)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  _r jsonb;
  _i int := 0;
  _line int;
  _email text; _first text; _last text; _role_txt text; _team text;
  _role public.app_role;
  _reason text;
  _id uuid;
  _out jsonb := '[]'::jsonb;
  _dup_emails text[];
  _dup_teams text[];
  _ok int := 0; _ko int := 0;
BEGIN
  IF NOT private.is_admin() THEN
    RAISE EXCEPTION 'Seul un admin peut importer des utilisateurs.' USING ERRCODE = '42501';
  END IF;
  IF _rows IS NULL OR jsonb_typeof(_rows) <> 'array' THEN
    RAISE EXCEPTION 'Format invalide : une liste de lignes est attendue.';
  END IF;
  IF jsonb_array_length(_rows) = 0 THEN
    RAISE EXCEPTION 'Le fichier ne contient aucune ligne.';
  END IF;
  IF jsonb_array_length(_rows) > 500 THEN
    RAISE EXCEPTION 'Maximum 500 lignes par import (% reçues).', jsonb_array_length(_rows);
  END IF;

  SELECT coalesce(array_agg(e), '{}') INTO _dup_emails FROM (
    SELECT lower(btrim(x->>'email')) e FROM jsonb_array_elements(_rows) x
    WHERE coalesce(btrim(x->>'email'), '') <> ''
    GROUP BY 1 HAVING count(*) > 1) d;

  SELECT coalesce(array_agg(t), '{}') INTO _dup_teams FROM (
    SELECT lower(btrim(x->>'team')) t FROM jsonb_array_elements(_rows) x
    WHERE lower(btrim(x->>'role')) = 'manager' AND coalesce(btrim(x->>'team'), '') <> ''
    GROUP BY 1 HAVING count(*) > 1) d;

  FOR _r IN SELECT value FROM jsonb_array_elements(_rows) LOOP
    _i := _i + 1;
    _line := coalesce((_r->>'line')::int, _i + 1);
    _email := lower(btrim(coalesce(_r->>'email', '')));
    _first := nullif(btrim(coalesce(_r->>'first_name', '')), '');
    _last := nullif(btrim(coalesce(_r->>'last_name', '')), '');
    _role_txt := lower(btrim(coalesce(_r->>'role', '')));
    _team := nullif(btrim(coalesce(_r->>'team', '')), '');
    _reason := NULL;

    IF _last IS NULL THEN _reason := 'Nom manquant';
    ELSIF _first IS NULL THEN _reason := 'Prénom manquant';
    ELSIF char_length(_last) > 100 OR char_length(_first) > 100 THEN _reason := 'Nom ou prénom trop long (100 caractères maximum)';
    ELSIF _email = '' THEN _reason := 'Adresse mail manquante';
    ELSIF char_length(_email) > 255 OR _email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN _reason := 'Adresse mail invalide';
    ELSIF _email = ANY(_dup_emails) THEN _reason := 'Adresse mail en double dans le fichier : une adresse ne peut avoir qu''un seul rôle';
    ELSIF EXISTS (SELECT 1 FROM public.allowed_users WHERE email = _email) THEN _reason := 'Adresse mail déjà autorisée';
    ELSIF _role_txt NOT IN ('admin', 'manager', 'collaborateur') THEN _reason := 'Rôle invalide (collaborateur, manager ou admin)';
    ELSIF _team IS NOT NULL AND (char_length(_team) < 2 OR char_length(_team) > 60) THEN _reason := 'Nom d''équipe invalide (2 à 60 caractères)';
    ELSIF _role_txt = 'collaborateur' AND _team IS NULL THEN _reason := 'Équipe obligatoire pour un collaborateur';
    ELSIF _role_txt IN ('collaborateur', 'manager') AND lower(_team) = 'admin' THEN _reason := 'L''équipe Admin est réservée aux admins';
    ELSIF _role_txt = 'admin' AND _team IS NOT NULL AND lower(_team) <> 'admin' THEN _reason := 'Un admin appartient à l''équipe Admin : laisser vide ou choisir Admin';
    ELSIF _role_txt = 'manager' AND _team IS NOT NULL AND lower(_team) = ANY(_dup_teams) THEN _reason := 'Équipe attribuée à plusieurs managers dans le fichier';
    ELSIF _role_txt = 'manager' AND _team IS NOT NULL AND EXISTS (SELECT 1 FROM public.manager_teams WHERE lower(btrim(team)) = lower(_team)) THEN _reason := 'Cette équipe a déjà un manager';
    END IF;

    IF _reason IS NULL THEN
      _role := _role_txt::public.app_role;
      BEGIN
        INSERT INTO public.allowed_users (email, team, first_name, last_name)
        VALUES (_email, CASE WHEN _role = 'collaborateur' THEN _team END, _first, _last)
        RETURNING id INTO _id;
        INSERT INTO public.allowed_user_roles (allowed_user_id, role) VALUES (_id, _role);
        IF _role = 'manager' AND _team IS NOT NULL THEN
          INSERT INTO public.manager_teams (allowed_user_id, team) VALUES (_id, _team);
        END IF;
        IF _dry_run THEN
          RAISE EXCEPTION 'HP_DRY_RUN_OK';
        END IF;
      EXCEPTION
        WHEN unique_violation THEN _reason := 'Adresse mail ou équipe déjà utilisée';
        WHEN check_violation THEN _reason := 'Valeur refusée par la base (' || SQLERRM || ')';
        WHEN OTHERS THEN
          IF SQLERRM <> 'HP_DRY_RUN_OK' THEN _reason := SQLERRM; END IF;
      END;
    END IF;

    IF _reason IS NULL THEN _ok := _ok + 1; ELSE _ko := _ko + 1; END IF;
    _out := _out || jsonb_build_object(
      'line', _line, 'email', _email, 'last_name', _last, 'first_name', _first,
      'role', _role_txt, 'team', _team,
      'status', CASE WHEN _reason IS NOT NULL THEN 'refusée' WHEN _dry_run THEN 'valide' ELSE 'importée' END,
      'reason', _reason);
  END LOOP;

  RETURN jsonb_build_object('dry_run', _dry_run, 'accepted', _ok, 'rejected', _ko, 'rows', _out);
END;
$$;

REVOKE ALL ON FUNCTION public.bulk_import_allowed_users(jsonb, boolean) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.bulk_import_allowed_users(jsonb, boolean) TO authenticated;
COMMIT;

-- ---------- 20261007063846_fe451ba6-7500-4135-9841-4958631aa2e0.sql ----------
BEGIN;
DROP INDEX IF EXISTS public.manager_teams_team_unique_ci;
CREATE UNIQUE INDEX manager_teams_user_team_unique_ci ON public.manager_teams (allowed_user_id, lower(btrim(team)));

CREATE OR REPLACE FUNCTION public.bulk_import_allowed_users(_rows jsonb, _dry_run boolean DEFAULT true)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  _r jsonb;
  _i int := 0;
  _line int;
  _email text; _first text; _last text; _role_txt text; _team text;
  _role public.app_role;
  _reason text;
  _id uuid;
  _out jsonb := '[]'::jsonb;
  _dup_emails text[];
  _ok int := 0; _ko int := 0;
BEGIN
  IF NOT private.is_admin() THEN
    RAISE EXCEPTION 'Seul un admin peut importer des utilisateurs.' USING ERRCODE = '42501';
  END IF;
  IF _rows IS NULL OR jsonb_typeof(_rows) <> 'array' THEN
    RAISE EXCEPTION 'Format invalide : une liste de lignes est attendue.';
  END IF;
  IF jsonb_array_length(_rows) = 0 THEN
    RAISE EXCEPTION 'Le fichier ne contient aucune ligne.';
  END IF;
  IF jsonb_array_length(_rows) > 500 THEN
    RAISE EXCEPTION 'Maximum 500 lignes par import (% reçues).', jsonb_array_length(_rows);
  END IF;

  SELECT coalesce(array_agg(e), '{}') INTO _dup_emails FROM (
    SELECT lower(btrim(x->>'email')) e FROM jsonb_array_elements(_rows) x
    WHERE coalesce(btrim(x->>'email'), '') <> ''
    GROUP BY 1 HAVING count(*) > 1) d;

  FOR _r IN SELECT value FROM jsonb_array_elements(_rows) LOOP
    _i := _i + 1;
    _line := coalesce((_r->>'line')::int, _i + 1);
    _email := lower(btrim(coalesce(_r->>'email', '')));
    _first := nullif(btrim(coalesce(_r->>'first_name', '')), '');
    _last := nullif(btrim(coalesce(_r->>'last_name', '')), '');
    _role_txt := lower(btrim(coalesce(_r->>'role', '')));
    _team := nullif(btrim(coalesce(_r->>'team', '')), '');
    _reason := NULL;

    IF _last IS NULL THEN _reason := 'Nom manquant';
    ELSIF _first IS NULL THEN _reason := 'Prénom manquant';
    ELSIF char_length(_last) > 100 OR char_length(_first) > 100 THEN _reason := 'Nom ou prénom trop long (100 caractères maximum)';
    ELSIF _email = '' THEN _reason := 'Adresse mail manquante';
    ELSIF char_length(_email) > 255 OR _email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN _reason := 'Adresse mail invalide';
    ELSIF _email = ANY(_dup_emails) THEN _reason := 'Adresse mail en double dans le fichier : une adresse ne peut avoir qu''un seul rôle';
    ELSIF EXISTS (SELECT 1 FROM public.allowed_users WHERE email = _email) THEN _reason := 'Adresse mail déjà autorisée';
    ELSIF _role_txt NOT IN ('admin', 'manager', 'collaborateur') THEN _reason := 'Rôle invalide (collaborateur, manager ou admin)';
    ELSIF _team IS NOT NULL AND (char_length(_team) < 2 OR char_length(_team) > 60) THEN _reason := 'Nom d''équipe invalide (2 à 60 caractères)';
    ELSIF _role_txt = 'collaborateur' AND _team IS NULL THEN _reason := 'Équipe obligatoire pour un collaborateur';
    ELSIF _role_txt IN ('collaborateur', 'manager') AND lower(_team) = 'admin' THEN _reason := 'L''équipe Admin est réservée aux admins';
    ELSIF _role_txt = 'admin' AND _team IS NOT NULL AND lower(_team) <> 'admin' THEN _reason := 'Un admin appartient à l''équipe Admin : laisser vide ou choisir Admin';
    END IF;

    IF _reason IS NULL THEN
      _role := _role_txt::public.app_role;
      BEGIN
        INSERT INTO public.allowed_users (email, team, first_name, last_name)
        VALUES (_email, CASE WHEN _role = 'collaborateur' THEN _team END, _first, _last)
        RETURNING id INTO _id;
        INSERT INTO public.allowed_user_roles (allowed_user_id, role) VALUES (_id, _role);
        IF _role = 'manager' AND _team IS NOT NULL THEN
          INSERT INTO public.manager_teams (allowed_user_id, team) VALUES (_id, _team);
        END IF;
        IF _dry_run THEN
          RAISE EXCEPTION 'HP_DRY_RUN_OK';
        END IF;
      EXCEPTION
        WHEN unique_violation THEN _reason := 'Adresse mail déjà utilisée';
        WHEN check_violation THEN _reason := 'Valeur refusée par la base (' || SQLERRM || ')';
        WHEN OTHERS THEN
          IF SQLERRM <> 'HP_DRY_RUN_OK' THEN _reason := SQLERRM; END IF;
      END;
    END IF;

    IF _reason IS NULL THEN _ok := _ok + 1; ELSE _ko := _ko + 1; END IF;
    _out := _out || jsonb_build_object(
      'line', _line, 'email', _email, 'last_name', _last, 'first_name', _first,
      'role', _role_txt, 'team', _team,
      'status', CASE WHEN _reason IS NOT NULL THEN 'refusée' WHEN _dry_run THEN 'valide' ELSE 'importée' END,
      'reason', _reason);
  END LOOP;

  RETURN jsonb_build_object('dry_run', _dry_run, 'accepted', _ok, 'rejected', _ko, 'rows', _out);
END;
$$;

REVOKE ALL ON FUNCTION public.bulk_import_allowed_users(jsonb, boolean) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.bulk_import_allowed_users(jsonb, boolean) TO authenticated;
COMMIT;

-- ---------- 20261007065411_0bda54f2-a18c-4e8f-9dba-495682a41f94.sql ----------
BEGIN;
-- Garde-fou contre les régressions silencieuses après une modification d'ENUM (7 oct. 2026)

-- 1) Audit statique : valeurs d'ENUM écrites en dur dans les fonctions
CREATE OR REPLACE FUNCTION private.audit_enum_literals()
RETURNS TABLE(fonction text, valeur text, probleme text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  _f record;
  _m text[];
  _labels text[];
  _ok boolean;
BEGIN
  SELECT array_agg(e.enumlabel) INTO _labels
  FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
  JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'public';

  FOR _f IN
    SELECT n.nspname || '.' || p.proname AS fn, p.prosrc
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_language l ON l.oid = p.prolang
    WHERE n.nspname IN ('public', 'private') AND p.prokind = 'f'
      AND l.lanname IN ('plpgsql', 'sql')
      AND p.proname NOT IN ('audit_enum_literals', 'run_smoke_tests')
  LOOP
    -- a) valeur castée explicitement vers un ENUM : 'x'::public.mon_enum
    FOR _m IN SELECT regexp_matches(_f.prosrc, '''((?:[^'']|'''')*)''::(?:public\.)?(\w+)', 'g') LOOP
      IF EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
                 WHERE n.nspname = 'public' AND t.typname = _m[2] AND t.typtype = 'e') THEN
        SELECT EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
                       JOIN pg_namespace n ON n.oid = t.typnamespace
                       WHERE n.nspname = 'public' AND t.typname = _m[2]
                         AND e.enumlabel = replace(_m[1], '''''', '''')) INTO _ok;
        IF NOT _ok THEN
          fonction := _f.fn; valeur := replace(_m[1], '''''', '''');
          probleme := 'Valeur absente de l''ENUM ' || _m[2];
          RETURN NEXT;
        END IF;
      END IF;
    END LOOP;
    -- b) comparaison non typée sur une colonne d'ENUM : status = 'x', role IN ('x', 'y')…
    FOR _m IN SELECT regexp_matches(_f.prosrc,
        '\m_?(?:status|old_status|new_status|role|severity|rejection_category)\s*(?:=|<>|!=)\s*''((?:[^'']|'''')*)''(?!::)', 'g') LOOP
      IF NOT (replace(_m[1], '''''', '''') = ANY(_labels)) THEN
        fonction := _f.fn; valeur := replace(_m[1], '''''', '''');
        probleme := 'Comparaison à une valeur qui n''existe dans aucun ENUM';
        RETURN NEXT;
      END IF;
    END LOOP;
    FOR _m IN SELECT regexp_matches(_f.prosrc,
        '\m_?(?:status|old_status|new_status|role|severity|rejection_category)\s+(?:NOT\s+)?IN\s*\(([^)]*)\)', 'gi') LOOP
      FOR valeur IN SELECT replace(x[1], '''''', '''')
                    FROM regexp_matches(_m[1], '''((?:[^'']|'''')*)''', 'g') x LOOP
        IF NOT (valeur = ANY(_labels)) THEN
          fonction := _f.fn;
          probleme := 'Liste IN contenant une valeur qui n''existe dans aucun ENUM';
          RETURN NEXT;
        END IF;
      END LOOP;
    END LOOP;
  END LOOP;
END;
$$;

-- 2) Test de fumée : rejoue les parcours qui dépendent des statuts, puis annule tout
CREATE OR REPLACE FUNCTION private.run_smoke_tests()
RETURNS TABLE(test text, ok boolean, detail text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  _res jsonb := '[]'::jsonb;
  _collab uuid; _mgr uuid; _adm uuid;
  _s1 uuid; _s2 uuid; _b uuid; _n uuid;
  _st text; _cnt int; _err text;
  _team text := 'ZZ Test fumée';
BEGIN
  BEGIN
    INSERT INTO allowed_users(email, team) VALUES ('smoke.collab@test.invalid', _team) RETURNING id INTO _collab;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_collab, 'collaborateur');
    INSERT INTO allowed_users(email) VALUES ('smoke.manager@test.invalid') RETURNING id INTO _mgr;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_mgr, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_mgr, _team);
    INSERT INTO allowed_users(email) VALUES ('smoke.admin@test.invalid') RETURNING id INTO _adm;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_adm, 'admin');

    -- Collaborateur : soumission
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 1') RETURNING id, status::text INTO _s1, _st;
    _res := _res || jsonb_build_object('t', 'Soumission créée « en attente », dans l''équipe du collaborateur',
      'ok', _st = 'en attente' AND (SELECT team FROM submissions WHERE id = _s1) = _team, 'd', _st);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 2') RETURNING id INTO _s2;

    -- Manager : validation et refus
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    BEGIN
      UPDATE submissions SET status = 'validée' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager valide une demande en attente', 'ok', true, 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager valide une demande en attente', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'refusée', rejection_category = 'doublon', rejection_note = 'Test' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager refuse une demande avec un motif', 'ok', true, 'd', 'refusée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager refuse une demande avec un motif', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'refusée' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager ne peut pas revenir sur une demande validée', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager ne peut pas revenir sur une demande validée', 'ok', true, 'd', 'refusé par la base');
    END;
    SELECT count(*) INTO _cnt FROM submission_status_history WHERE submission_id IN (_s1, _s2);
    _res := _res || jsonb_build_object('t', 'Historique : 4 lignes (2 créations, 1 validation, 1 refus)', 'ok', _cnt = 4, 'd', _cnt || ' ligne(s)');

    -- Revalidation annuelle
    PERFORM set_config('request.jwt.claims', '', true);
    UPDATE submissions SET revalidate_at = now() - interval '1 day' WHERE id = _s1;
    PERFORM private.expire_revalidations();
    SELECT status::text INTO _st FROM submissions WHERE id = _s1;
    _res := _res || jsonb_build_object('t', 'Revalidation annuelle : une demande validée échue repasse « en attente »', 'ok', _st = 'en attente', 'd', _st);

    -- Points bloquants
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.admin@test.invalid"}', true);
    INSERT INTO blockers(title, department) VALUES ('Blocage de test', 'Test') RETURNING id, status::text INTO _b, _st;
    _res := _res || jsonb_build_object('t', 'Point bloquant créé au statut OUVERT', 'ok', _st = 'OUVERT', 'd', _st);
    BEGIN
      UPDATE blockers SET status = 'RÉSOLU' WHERE id = _b;
      _res := _res || jsonb_build_object('t', 'OUVERT → RÉSOLU refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'OUVERT → RÉSOLU refusé', 'ok', true, 'd', 'refusé par la base');
    END;
    BEGIN
      UPDATE blockers SET status = 'EN COURS' WHERE id = _b;
      UPDATE blockers SET status = 'SURVEILLANCE' WHERE id = _b;
      UPDATE blockers SET status = 'RÉSOLU' WHERE id = _b;
      _res := _res || jsonb_build_object('t', 'OUVERT → EN COURS → SURVEILLANCE → RÉSOLU accepté', 'ok', true, 'd', 'RÉSOLU');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'OUVERT → EN COURS → SURVEILLANCE → RÉSOLU accepté', 'ok', false, 'd', SQLERRM);
    END;

    -- Actualités
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    INSERT INTO news(title, body, author, status) VALUES ('Actu de test', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _n;
    UPDATE news SET status = 'publiée' WHERE id = _n;
    _res := _res || jsonb_build_object('t', 'Actualité : brouillon puis publiée, échéance de revalidation posée', 'ok',
      (SELECT revalidate_at IS NOT NULL FROM news WHERE id = _n), 'd', (SELECT status::text FROM news WHERE id = _n));

    RAISE EXCEPTION 'HP_SMOKE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'HP_SMOKE_ROLLBACK' THEN
      _res := _res || jsonb_build_object('t', 'Exécution du test de fumée', 'ok', false, 'd', 'Erreur inattendue : ' || SQLERRM);
    END IF;
  END;

  SELECT count(*) INTO _cnt FROM private.audit_enum_literals();
  _res := _res || jsonb_build_object('t', 'Aucune valeur d''ENUM obsolète dans les fonctions', 'ok', _cnt = 0, 'd', _cnt || ' anomalie(s)');

  RETURN QUERY SELECT x->>'t', (x->>'ok')::boolean, x->>'d' FROM jsonb_array_elements(_res) x;
END;
$$;

REVOKE ALL ON FUNCTION private.audit_enum_literals() FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION private.run_smoke_tests() FROM public, anon, authenticated;
COMMIT;

-- ---------- 20261007082655_aefb36b5-4606-4e03-8a0d-0dc4788c9906.sql ----------
BEGIN;
ALTER TABLE public.submissions
  ADD CONSTRAINT submissions_rejection_note_max_500
  CHECK (rejection_note IS NULL OR char_length(btrim(rejection_note)) <= 500);
COMMIT;

-- ---------- 20261008000000_drizzle_0000_us26_teams.sql ----------
BEGIN;
-- Référentiel des équipes (US26)
CREATE TABLE IF NOT EXISTS public.teams (
  name text PRIMARY KEY,
  is_reserved boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT teams_name_length CHECK (char_length(btrim(name)) BETWEEN 2 AND 60 AND name = btrim(name))
);
CREATE UNIQUE INDEX IF NOT EXISTS teams_name_unique_ci ON public.teams (lower(name));

CREATE OR REPLACE FUNCTION private.protect_reserved_team()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public', 'private' AS $$
BEGIN
  IF OLD.is_reserved THEN
    RAISE EXCEPTION 'L''équipe % est réservée : elle ne peut être ni renommée ni supprimée.', OLD.name;
  END IF;
  IF TG_OP = 'UPDATE' THEN
    NEW.is_reserved := OLD.is_reserved;
    RETURN NEW;
  END IF;
  RETURN OLD;
END $$;
DROP TRIGGER IF EXISTS protect_reserved_team ON public.teams;
CREATE TRIGGER protect_reserved_team BEFORE UPDATE OR DELETE ON public.teams
  FOR EACH ROW EXECUTE FUNCTION private.protect_reserved_team();

ALTER TABLE public.teams ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allowed read teams" ON public.teams;
CREATE POLICY "Allowed read teams" ON public.teams FOR SELECT TO authenticated USING (private.is_allowed());
DROP POLICY IF EXISTS "Admins insert teams" ON public.teams;
CREATE POLICY "Admins insert teams" ON public.teams FOR INSERT TO authenticated WITH CHECK (private.is_admin() AND NOT is_reserved);
DROP POLICY IF EXISTS "Admins update teams" ON public.teams;
CREATE POLICY "Admins update teams" ON public.teams FOR UPDATE TO authenticated USING (private.is_admin()) WITH CHECK (private.is_admin());
DROP POLICY IF EXISTS "Admins delete teams" ON public.teams;
CREATE POLICY "Admins delete teams" ON public.teams FOR DELETE TO authenticated USING (private.is_admin());
GRANT SELECT, INSERT, UPDATE, DELETE ON public.teams TO authenticated;

INSERT INTO public.teams (name, is_reserved) VALUES ('Admin', true) ON CONFLICT DO NOTHING;
INSERT INTO public.teams (name) VALUES
  ('Accounting'), ('Finance'), ('Legal'), ('Marketing'), ('People'), ('Product'),
  ('Direction Commerciale'), ('Opérations'), ('Relation clients'),
  ('Direction Conseil'), ('Pôle Data et IA'), ('Direction recrutement')
ON CONFLICT DO NOTHING;

UPDATE public.allowed_users SET team = 'Direction Commerciale' WHERE lower(btrim(team)) = 'sales';
DELETE FROM public.manager_teams a USING public.manager_teams b
  WHERE lower(btrim(a.team)) = 'sales' AND lower(btrim(b.team)) = 'direction commerciale' AND a.allowed_user_id = b.allowed_user_id;
UPDATE public.manager_teams SET team = 'Direction Commerciale' WHERE lower(btrim(team)) = 'sales';
UPDATE public.submissions SET team = 'Direction Commerciale' WHERE lower(btrim(team)) = 'sales';

UPDATE public.allowed_users u SET team = t.name FROM public.teams t WHERE lower(btrim(u.team)) = lower(t.name) AND u.team <> t.name;
UPDATE public.manager_teams m SET team = t.name FROM public.teams t WHERE lower(btrim(m.team)) = lower(t.name) AND m.team <> t.name;
UPDATE public.submissions s SET team = t.name FROM public.teams t WHERE lower(btrim(s.team)) = lower(t.name) AND s.team <> t.name;

INSERT INTO public.teams (name)
SELECT DISTINCT btrim(x.team) FROM (
  SELECT team FROM public.allowed_users UNION SELECT team FROM public.manager_teams UNION SELECT team FROM public.submissions
) x WHERE x.team IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.teams t WHERE lower(t.name) = lower(btrim(x.team)))
ON CONFLICT DO NOTHING;

ALTER TABLE public.allowed_users DROP CONSTRAINT IF EXISTS allowed_users_team_fkey;
ALTER TABLE public.allowed_users ADD CONSTRAINT allowed_users_team_fkey
  FOREIGN KEY (team) REFERENCES public.teams(name) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE public.manager_teams DROP CONSTRAINT IF EXISTS manager_teams_team_fkey;
ALTER TABLE public.manager_teams ADD CONSTRAINT manager_teams_team_fkey
  FOREIGN KEY (team) REFERENCES public.teams(name) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE public.submissions DROP CONSTRAINT IF EXISTS submissions_team_fkey;
ALTER TABLE public.submissions ADD CONSTRAINT submissions_team_fkey
  FOREIGN KEY (team) REFERENCES public.teams(name) ON UPDATE CASCADE ON DELETE RESTRICT;

CREATE OR REPLACE FUNCTION public.bulk_import_allowed_users(_rows jsonb, _dry_run boolean DEFAULT true)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _r jsonb; _i int := 0; _line int;
  _email text; _first text; _last text; _role_txt text; _team text;
  _role public.app_role; _reason text; _id uuid;
  _out jsonb := '[]'::jsonb; _dup_emails text[]; _ok int := 0; _ko int := 0;
BEGIN
  IF NOT private.is_admin() THEN
    RAISE EXCEPTION 'Seul un admin peut importer des utilisateurs.' USING ERRCODE = '42501';
  END IF;
  IF _rows IS NULL OR jsonb_typeof(_rows) <> 'array' THEN
    RAISE EXCEPTION 'Format invalide : une liste de lignes est attendue.';
  END IF;
  IF jsonb_array_length(_rows) = 0 THEN RAISE EXCEPTION 'Le fichier ne contient aucune ligne.'; END IF;
  IF jsonb_array_length(_rows) > 500 THEN
    RAISE EXCEPTION 'Maximum 500 lignes par import (% reçues).', jsonb_array_length(_rows);
  END IF;
  SELECT coalesce(array_agg(e), '{}') INTO _dup_emails FROM (
    SELECT lower(btrim(x->>'email')) e FROM jsonb_array_elements(_rows) x
    WHERE coalesce(btrim(x->>'email'), '') <> '' GROUP BY 1 HAVING count(*) > 1) d;
  FOR _r IN SELECT value FROM jsonb_array_elements(_rows) LOOP
    _i := _i + 1;
    _line := coalesce((_r->>'line')::int, _i + 1);
    _email := lower(btrim(coalesce(_r->>'email', '')));
    _first := nullif(btrim(coalesce(_r->>'first_name', '')), '');
    _last := nullif(btrim(coalesce(_r->>'last_name', '')), '');
    _role_txt := lower(btrim(coalesce(_r->>'role', '')));
    _team := nullif(btrim(coalesce(_r->>'team', '')), '');
    IF _team IS NOT NULL THEN
      _team := coalesce((SELECT t.name FROM public.teams t WHERE lower(t.name) = lower(_team)), _team);
    END IF;
    _reason := NULL;
    IF _last IS NULL THEN _reason := 'Nom manquant';
    ELSIF _first IS NULL THEN _reason := 'Prénom manquant';
    ELSIF char_length(_last) > 100 OR char_length(_first) > 100 THEN _reason := 'Nom ou prénom trop long (100 caractères maximum)';
    ELSIF _email = '' THEN _reason := 'Adresse mail manquante';
    ELSIF char_length(_email) > 255 OR _email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN _reason := 'Adresse mail invalide';
    ELSIF _email = ANY(_dup_emails) THEN _reason := 'Adresse mail en double dans le fichier : une adresse ne peut avoir qu''un seul rôle';
    ELSIF EXISTS (SELECT 1 FROM public.allowed_users WHERE email = _email) THEN _reason := 'Adresse mail déjà autorisée';
    ELSIF _role_txt NOT IN ('admin', 'manager', 'collaborateur') THEN _reason := 'Rôle invalide (collaborateur, manager ou admin)';
    ELSIF _team IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.teams t WHERE t.name = _team) THEN _reason := 'Équipe inconnue : choisis une équipe de la liste';
    ELSIF _role_txt = 'collaborateur' AND _team IS NULL THEN _reason := 'Équipe obligatoire pour un collaborateur';
    ELSIF _role_txt IN ('collaborateur', 'manager') AND lower(_team) = 'admin' THEN _reason := 'L''équipe Admin est réservée aux admins';
    ELSIF _role_txt = 'admin' AND _team IS NOT NULL AND lower(_team) <> 'admin' THEN _reason := 'Un admin appartient à l''équipe Admin : laisser vide ou choisir Admin';
    END IF;
    IF _reason IS NULL THEN
      _role := _role_txt::public.app_role;
      BEGIN
        INSERT INTO public.allowed_users (email, team, first_name, last_name)
        VALUES (_email, CASE WHEN _role = 'collaborateur' THEN _team END, _first, _last)
        RETURNING id INTO _id;
        INSERT INTO public.allowed_user_roles (allowed_user_id, role) VALUES (_id, _role);
        IF _role = 'manager' AND _team IS NOT NULL THEN
          INSERT INTO public.manager_teams (allowed_user_id, team) VALUES (_id, _team);
        END IF;
        IF _dry_run THEN RAISE EXCEPTION 'HP_DRY_RUN_OK'; END IF;
      EXCEPTION
        WHEN unique_violation THEN _reason := 'Adresse mail déjà utilisée';
        WHEN check_violation THEN _reason := 'Valeur refusée par la base (' || SQLERRM || ')';
        WHEN foreign_key_violation THEN _reason := 'Équipe inconnue : choisis une équipe de la liste';
        WHEN OTHERS THEN IF SQLERRM <> 'HP_DRY_RUN_OK' THEN _reason := SQLERRM; END IF;
      END;
    END IF;
    IF _reason IS NULL THEN _ok := _ok + 1; ELSE _ko := _ko + 1; END IF;
    _out := _out || jsonb_build_object(
      'line', _line, 'email', _email, 'last_name', _last, 'first_name', _first,
      'role', _role_txt, 'team', _team,
      'status', CASE WHEN _reason IS NOT NULL THEN 'refusée' WHEN _dry_run THEN 'valide' ELSE 'importée' END,
      'reason', _reason);
  END LOOP;
  RETURN jsonb_build_object('dry_run', _dry_run, 'accepted', _ok, 'rejected', _ko, 'rows', _out);
END;
$function$;
REVOKE ALL ON FUNCTION public.bulk_import_allowed_users(jsonb, boolean) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.bulk_import_allowed_users(jsonb, boolean) TO authenticated;
COMMIT;

-- ---------- 20261008000001_drizzle_0001_us26_fix_smoke_tests.sql ----------
BEGIN;
CREATE OR REPLACE FUNCTION private.run_smoke_tests()
 RETURNS TABLE(test text, ok boolean, detail text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _res jsonb := '[]'::jsonb;
  _collab uuid; _mgr uuid; _adm uuid;
  _s1 uuid; _s2 uuid; _b uuid; _n uuid;
  _st text; _cnt int; _err text;
  _team text := 'ZZ Test fumée';
BEGIN
  BEGIN
    INSERT INTO teams(name) VALUES (_team) ON CONFLICT DO NOTHING;
    INSERT INTO allowed_users(email, team) VALUES ('smoke.collab@test.invalid', _team) RETURNING id INTO _collab;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_collab, 'collaborateur');
    INSERT INTO allowed_users(email) VALUES ('smoke.manager@test.invalid') RETURNING id INTO _mgr;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_mgr, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_mgr, _team);
    INSERT INTO allowed_users(email) VALUES ('smoke.admin@test.invalid') RETURNING id INTO _adm;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_adm, 'admin');

    -- Collaborateur : soumission
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 1') RETURNING id, status::text INTO _s1, _st;
    _res := _res || jsonb_build_object('t', 'Soumission créée « en attente », dans l''équipe du collaborateur',
      'ok', _st = 'en attente' AND (SELECT team FROM submissions WHERE id = _s1) = _team, 'd', _st);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 2') RETURNING id INTO _s2;

    -- Manager : validation et refus
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    BEGIN
      UPDATE submissions SET status = 'validée' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager valide une demande en attente', 'ok', true, 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager valide une demande en attente', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'refusée', rejection_category = 'doublon', rejection_note = 'Test' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager refuse une demande avec un motif', 'ok', true, 'd', 'refusée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager refuse une demande avec un motif', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'refusée' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager ne peut pas revenir sur une demande validée', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager ne peut pas revenir sur une demande validée', 'ok', true, 'd', 'refusé par la base');
    END;
    SELECT count(*) INTO _cnt FROM submission_status_history WHERE submission_id IN (_s1, _s2);
    _res := _res || jsonb_build_object('t', 'Historique : 4 lignes (2 créations, 1 validation, 1 refus)', 'ok', _cnt = 4, 'd', _cnt || ' ligne(s)');

    -- Revalidation annuelle
    PERFORM set_config('request.jwt.claims', '', true);
    UPDATE submissions SET revalidate_at = now() - interval '1 day' WHERE id = _s1;
    PERFORM private.expire_revalidations();
    SELECT status::text INTO _st FROM submissions WHERE id = _s1;
    _res := _res || jsonb_build_object('t', 'Revalidation annuelle : une demande validée échue repasse « en attente »', 'ok', _st = 'en attente', 'd', _st);

    -- Points bloquants
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.admin@test.invalid"}', true);
    INSERT INTO blockers(title, department) VALUES ('Blocage de test', 'Test') RETURNING id, status::text INTO _b, _st;
    _res := _res || jsonb_build_object('t', 'Point bloquant créé au statut OUVERT', 'ok', _st = 'OUVERT', 'd', _st);
    BEGIN
      UPDATE blockers SET status = 'RÉSOLU' WHERE id = _b;
      _res := _res || jsonb_build_object('t', 'OUVERT → RÉSOLU refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'OUVERT → RÉSOLU refusé', 'ok', true, 'd', 'refusé par la base');
    END;
    BEGIN
      UPDATE blockers SET status = 'EN COURS' WHERE id = _b;
      UPDATE blockers SET status = 'SURVEILLANCE' WHERE id = _b;
      UPDATE blockers SET status = 'RÉSOLU' WHERE id = _b;
      _res := _res || jsonb_build_object('t', 'OUVERT → EN COURS → SURVEILLANCE → RÉSOLU accepté', 'ok', true, 'd', 'RÉSOLU');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'OUVERT → EN COURS → SURVEILLANCE → RÉSOLU accepté', 'ok', false, 'd', SQLERRM);
    END;

    -- Actualités
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    INSERT INTO news(title, body, author, status) VALUES ('Actu de test', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _n;
    UPDATE news SET status = 'publiée' WHERE id = _n;
    _res := _res || jsonb_build_object('t', 'Actualité : brouillon puis publiée, échéance de revalidation posée', 'ok',
      (SELECT revalidate_at IS NOT NULL FROM news WHERE id = _n), 'd', (SELECT status::text FROM news WHERE id = _n));

    -- Référentiel des équipes
    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      UPDATE teams SET name = 'ZZ Test fumée 2' WHERE name = _team;
      _res := _res || jsonb_build_object('t', 'Référentiel : renommer une équipe met à jour utilisateurs, managers et demandes', 'ok',
        (SELECT team FROM allowed_users WHERE id = _collab) = 'ZZ Test fumée 2'
        AND (SELECT team FROM manager_teams WHERE allowed_user_id = _mgr) = 'ZZ Test fumée 2'
        AND (SELECT team FROM submissions WHERE id = _s1) = 'ZZ Test fumée 2', 'd', 'ZZ Test fumée 2');
      _team := 'ZZ Test fumée 2';
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Référentiel : renommer une équipe met à jour utilisateurs, managers et demandes', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      DELETE FROM teams WHERE name = _team;
      _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN foreign_key_violation THEN
        _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', false, 'd', SQLERRM);
    END;

    RAISE EXCEPTION 'HP_SMOKE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'HP_SMOKE_ROLLBACK' THEN
      _res := _res || jsonb_build_object('t', 'Exécution du test de fumée', 'ok', false, 'd', 'Erreur inattendue : ' || SQLERRM);
    END IF;
  END;

  SELECT count(*) INTO _cnt FROM private.audit_enum_literals();
  _res := _res || jsonb_build_object('t', 'Aucune valeur d''ENUM obsolète dans les fonctions', 'ok', _cnt = 0, 'd', _cnt || ' anomalie(s)');

  RETURN QUERY SELECT x->>'t', (x->>'ok')::boolean, x->>'d' FROM jsonb_array_elements(_res) x;
END;
$function$;
COMMIT;

-- ---------- 20261008000002_drizzle_0002_news_media_links.sql ----------
BEGIN;
ALTER TABLE public.news ADD COLUMN IF NOT EXISTS image_path text;
ALTER TABLE public.news ADD COLUMN IF NOT EXISTS links jsonb NOT NULL DEFAULT '[]'::jsonb;

CREATE OR REPLACE FUNCTION private.check_news_links()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, private AS $$
DECLARE _l jsonb; _url text; _label text;
BEGIN
  IF NEW.links IS NULL OR jsonb_typeof(NEW.links) <> 'array' THEN
    RAISE EXCEPTION 'Les liens doivent être une liste.' USING ERRCODE = '23514';
  END IF;
  IF jsonb_array_length(NEW.links) > 3 THEN
    RAISE EXCEPTION '3 liens maximum par actualité.' USING ERRCODE = '23514';
  END IF;
  FOR _l IN SELECT value FROM jsonb_array_elements(NEW.links) LOOP
    IF jsonb_typeof(_l) <> 'object' OR jsonb_typeof(_l->'url') IS DISTINCT FROM 'string' THEN
      RAISE EXCEPTION 'Chaque lien doit avoir une adresse.' USING ERRCODE = '23514';
    END IF;
    _url := _l->>'url';
    IF _url !~* '^https?://[^\s]+$' THEN
      RAISE EXCEPTION 'Adresse de lien invalide : seules les adresses http:// ou https:// sont acceptées.' USING ERRCODE = '23514';
    END IF;
    IF char_length(_url) > 2000 THEN
      RAISE EXCEPTION 'Adresse de lien trop longue (2 000 caractères maximum).' USING ERRCODE = '23514';
    END IF;
    IF _l ? 'label' AND jsonb_typeof(_l->'label') NOT IN ('string', 'null') THEN
      RAISE EXCEPTION 'Libellé de lien invalide.' USING ERRCODE = '23514';
    END IF;
    _label := _l->>'label';
    IF _label IS NOT NULL AND char_length(_label) > 80 THEN
      RAISE EXCEPTION 'Libellé de lien trop long (80 caractères maximum).' USING ERRCODE = '23514';
    END IF;
  END LOOP;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS check_news_links ON public.news;
CREATE TRIGGER check_news_links BEFORE INSERT OR UPDATE OF links ON public.news
FOR EACH ROW EXECUTE FUNCTION private.check_news_links();

CREATE OR REPLACE FUNCTION private.can_edit_news_media(_news_id text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, private AS $$
  SELECT private.is_admin() OR EXISTS (
    SELECT 1 FROM public.news n
    WHERE n.id::text = _news_id
      AND private.current_app_role() = 'manager'
      AND n.status = 'brouillon'
      AND n.author_email = lower(auth.jwt() ->> 'email'))
$$;
REVOKE EXECUTE ON FUNCTION private.can_edit_news_media(text) FROM public, anon;
GRANT EXECUTE ON FUNCTION private.can_edit_news_media(text) TO authenticated;

CREATE POLICY "News media read" ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'news-media' AND private.is_allowed()
  AND EXISTS (SELECT 1 FROM public.news n WHERE n.id::text = (storage.foldername(name))[1]));

CREATE POLICY "News media insert" ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'news-media' AND private.is_allowed()
  AND lower(storage.extension(name)) IN ('jpg', 'jpeg', 'png', 'webp')
  AND private.can_edit_news_media((storage.foldername(name))[1]));

CREATE POLICY "News media update" ON storage.objects FOR UPDATE TO authenticated
USING (bucket_id = 'news-media' AND private.can_edit_news_media((storage.foldername(name))[1]))
WITH CHECK (bucket_id = 'news-media' AND lower(storage.extension(name)) IN ('jpg', 'jpeg', 'png', 'webp')
  AND private.can_edit_news_media((storage.foldername(name))[1]));

CREATE POLICY "News media delete" ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'news-media' AND private.can_edit_news_media((storage.foldername(name))[1]));
COMMIT;

-- ---------- 20261008000003_drizzle_0003_notify_departure_even_without_documents.sql ----------
BEGIN;
CREATE OR REPLACE FUNCTION private.notify_departure(_user_id uuid, _email text, _team text, _date date, _kind text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'private' AS $function$
DECLARE _docs jsonb := private.departure_documents(_email);
BEGIN
  UPDATE public.departure_notices SET closed_at = now()
   WHERE departing_user_id = _user_id AND closed_at IS NULL;
  INSERT INTO public.departure_notices (departing_user_id, departing_label, recipient_email, departure_date, kind, documents)
  SELECT _user_id, _email, rcpt, _date, _kind, _docs FROM private.departure_recipients(_email, _team) AS rcpt;
END $function$;
COMMIT;

-- ---------- 20261008000004_drizzle_0004_verify_smoke_tests_after_notify_change.sql ----------
BEGIN;
DO $$
DECLARE _bad int;
BEGIN
  SELECT count(*) INTO _bad FROM private.run_smoke_tests() WHERE NOT ok;
  IF _bad > 0 THEN
    RAISE EXCEPTION 'Smoke tests failed: % test(s) not ok', _bad;
  END IF;
END $$;
COMMENT ON FUNCTION private.notify_departure(uuid, text, text, date, text) IS 'Crée les alertes de départ même sans document joint (le bandeau informe alors simplement du départ).';
COMMIT;

-- ---------- 20261016085900_buckets_stockage.sql ----------
BEGIN;
-- Version élèves : espaces de stockage utilisés par l'app (créés hors migrations dans l'app d'origine)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types) VALUES
  ('submission-attachments', 'submission-attachments', false, 20971520, ARRAY['application/pdf']),
  ('news-media', 'news-media', false, 5242880, ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO NOTHING;
COMMIT;

-- ---------- 20261016090000_connexion_libre.sql ----------
BEGIN;
-- ============================================================
-- Version élèves : connexion libre et choix du rôle
-- ============================================================
-- Dans l'app d'origine, seul un admin inscrit un email sur la liste blanche
-- et lui attribue un rôle. Ici, toute personne connectée choisit elle-même
-- son rôle (et peut en changer). Les règles de sécurité (RLS) ne changent pas :
-- elles lisent toujours allowed_users / allowed_user_roles / manager_teams.

-- 1. La liste des équipes doit être lisible avant d'avoir un rôle
--    (sinon l'écran de choix ne peut pas proposer les équipes).
DROP POLICY IF EXISTS "Authenticated read teams" ON public.teams;
CREATE POLICY "Authenticated read teams" ON public.teams
  FOR SELECT TO authenticated USING (true);

-- 2. Choisir (ou changer) son rôle
CREATE OR REPLACE FUNCTION public.choisir_mon_role(
  _role public.app_role,
  _first_name text,
  _last_name text,
  _team text DEFAULT NULL
)
RETURNS public.app_role
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  _email text := lower(nullif(auth.jwt() ->> 'email', ''));
  _first text := nullif(btrim(coalesce(_first_name, '')), '');
  _last text := nullif(btrim(coalesce(_last_name, '')), '');
  _t text := nullif(btrim(coalesce(_team, '')), '');
  _id uuid;
BEGIN
  IF _email IS NULL THEN
    RAISE EXCEPTION 'Connecte-toi avant de choisir un rôle.' USING ERRCODE = '42501';
  END IF;
  IF _role IS NULL THEN
    RAISE EXCEPTION 'Choisis un rôle.';
  END IF;
  IF _first IS NULL OR _last IS NULL THEN
    RAISE EXCEPTION 'Renseigne ton prénom et ton nom.';
  END IF;

  IF _role = 'admin' THEN
    _t := NULL;
  ELSE
    IF _t IS NULL THEN
      RAISE EXCEPTION 'Choisis une équipe.';
    END IF;
    SELECT t.name INTO _t FROM public.teams t
     WHERE lower(t.name) = lower(_t) AND NOT t.is_reserved;
    IF _t IS NULL THEN
      RAISE EXCEPTION 'Équipe inconnue : choisis une équipe de la liste.';
    END IF;
  END IF;

  INSERT INTO public.allowed_users (email, first_name, last_name, team)
  VALUES (_email, _first, _last, CASE WHEN _role = 'collaborateur' THEN _t END)
  ON CONFLICT (email) DO UPDATE
    SET first_name = excluded.first_name,
        last_name = excluded.last_name,
        team = excluded.team
  RETURNING id INTO _id;

  BEGIN
    INSERT INTO public.allowed_user_roles (allowed_user_id, role)
    VALUES (_id, _role)
    ON CONFLICT (allowed_user_id) DO UPDATE
      SET role = excluded.role, updated_at = now();
  EXCEPTION WHEN raise_exception THEN
    -- Déclenché par private.protect_last_admin_role()
    RAISE EXCEPTION 'Tu es le dernier admin : un autre membre doit devenir admin avant que tu changes de rôle.';
  END;

  DELETE FROM public.manager_teams WHERE allowed_user_id = _id;
  IF _role = 'manager' THEN
    INSERT INTO public.manager_teams (allowed_user_id, team) VALUES (_id, _t);
  END IF;

  RETURN _role;
END;
$$;

REVOKE ALL ON FUNCTION public.choisir_mon_role(public.app_role, text, text, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.choisir_mon_role(public.app_role, text, text, text) TO authenticated;

COMMENT ON FUNCTION public.choisir_mon_role(public.app_role, text, text, text) IS
  'Version élèves : la personne connectée choisit son rôle (admin, manager ou collaborateur) et son équipe.';
COMMIT;

-- ---------- 20261016100000_entree_directe.sql ----------
BEGIN;
-- ============================================================
-- Version élèves : entrée directe, sans email ni mot de passe
-- ============================================================
-- L'app ouvre une session anonyme Supabase (signInAnonymously). Au premier
-- choix de rôle, la base donne à ce compte une adresse interne
-- (eleve-xxxx@happyplace.test) : toutes les règles de sécurité de l'app
-- reposent sur l'email du compte connecté, elles fonctionnent donc sans changement.

CREATE OR REPLACE FUNCTION public.choisir_mon_role(
  _role public.app_role,
  _first_name text,
  _last_name text,
  _team text DEFAULT NULL
)
RETURNS public.app_role
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  _uid uuid := auth.uid();
  _email text := lower(nullif(auth.jwt() ->> 'email', ''));
  _first text := nullif(btrim(coalesce(_first_name, '')), '');
  _last text := nullif(btrim(coalesce(_last_name, '')), '');
  _t text := nullif(btrim(coalesce(_team, '')), '');
  _id uuid;
BEGIN
  IF _uid IS NULL AND _email IS NULL THEN
    RAISE EXCEPTION 'Session introuvable : recharge la page.' USING ERRCODE = '42501';
  END IF;

  -- Compte anonyme : on lui attribue une adresse interne, une fois pour toutes
  IF _email IS NULL THEN
    SELECT lower(u.email) INTO _email FROM auth.users u WHERE u.id = _uid;
    IF _email IS NULL OR _email = '' THEN
      _email := 'eleve-' || left(replace(_uid::text, '-', ''), 12) || '@happyplace.test';
      UPDATE auth.users SET email = _email WHERE id = _uid;
    END IF;
  END IF;

  IF _role IS NULL THEN
    RAISE EXCEPTION 'Choisis un rôle.';
  END IF;
  IF _first IS NULL OR _last IS NULL THEN
    RAISE EXCEPTION 'Renseigne ton prénom et ton nom.';
  END IF;

  IF _role = 'admin' THEN
    _t := NULL;
  ELSE
    IF _t IS NULL THEN
      RAISE EXCEPTION 'Choisis une équipe.';
    END IF;
    SELECT t.name INTO _t FROM public.teams t
     WHERE lower(t.name) = lower(_t) AND NOT t.is_reserved;
    IF _t IS NULL THEN
      RAISE EXCEPTION 'Équipe inconnue : choisis une équipe de la liste.';
    END IF;
  END IF;

  INSERT INTO public.allowed_users (email, first_name, last_name, team)
  VALUES (_email, _first, _last, CASE WHEN _role = 'collaborateur' THEN _t END)
  ON CONFLICT (email) DO UPDATE
    SET first_name = excluded.first_name,
        last_name = excluded.last_name,
        team = excluded.team
  RETURNING id INTO _id;

  BEGIN
    INSERT INTO public.allowed_user_roles (allowed_user_id, role)
    VALUES (_id, _role)
    ON CONFLICT (allowed_user_id) DO UPDATE
      SET role = excluded.role, updated_at = now();
  EXCEPTION WHEN raise_exception THEN
    RAISE EXCEPTION 'Tu es le dernier admin : un autre membre doit devenir admin avant que tu changes de rôle.';
  END;

  DELETE FROM public.manager_teams WHERE allowed_user_id = _id;
  IF _role = 'manager' THEN
    INSERT INTO public.manager_teams (allowed_user_id, team) VALUES (_id, _t);
  END IF;

  RETURN _role;
END;
$$;

REVOKE ALL ON FUNCTION public.choisir_mon_role(public.app_role, text, text, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.choisir_mon_role(public.app_role, text, text, text) TO authenticated;
COMMIT;

-- ---------- 20261030090000_statut_cloturee.sql ----------
BEGIN;
-- Nouveau statut de demande « clôturée » (30 oct. 2026).
-- Séparé de la migration suivante : une valeur d'ENUM ajoutée ne peut pas être
-- utilisée dans la même transaction.
ALTER TYPE public.submission_status ADD VALUE IF NOT EXISTS 'clôturée';
COMMIT;

-- ---------- 20261030090100_managers_changent_statut.sql ----------
BEGIN;
-- Les managers changent librement le statut d'une demande de leurs équipes (30 oct. 2026)
-- et nouveau statut « clôturée », atteint automatiquement un an après la validation.

-- 1) Garde-fou : un manager ne modifie que le statut (et le motif de refus), jamais le contenu.
--    Le motif de refus est effacé dès que le statut n'est plus « refusée ».
CREATE OR REPLACE FUNCTION private.enforce_submission_review()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  IF private.current_app_role() = 'manager'::public.app_role THEN
    IF NEW.author_name IS DISTINCT FROM OLD.author_name
       OR NEW.team IS DISTINCT FROM OLD.team
       OR NEW.content IS DISTINCT FROM OLD.content
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
       OR NOT private.can_review_team(OLD.team) THEN
      RAISE EXCEPTION 'Un manager peut uniquement changer le statut des demandes de ses équipes';
    END IF;
  END IF;
  IF NEW.status <> 'refusée'::public.submission_status THEN
    NEW.rejection_category := NULL;
    NEW.rejection_note := NULL;
  END IF;
  RETURN NEW;
END
$function$;

-- 2) RLS : le manager lit et change le statut quel que soit le statut actuel.
DROP POLICY IF EXISTS "Managers review assigned submissions" ON public.submissions;
CREATE POLICY "Managers review assigned submissions" ON public.submissions FOR UPDATE TO authenticated
USING (private.current_app_role() = 'manager'::public.app_role AND private.can_review_team(team))
WITH CHECK (
  private.current_app_role() = 'manager'::public.app_role
  AND private.can_review_team(team)
  AND status IN ('en attente'::public.submission_status, 'validée'::public.submission_status,
                 'refusée'::public.submission_status, 'clôturée'::public.submission_status)
);

-- 3) Un an après la validation sans modification, la demande est clôturée (et non plus remise en attente).
CREATE OR REPLACE FUNCTION private.expire_revalidations()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  UPDATE public.submissions
  SET status = 'clôturée'::public.submission_status, revalidate_at = NULL
  WHERE status = 'validée'::public.submission_status AND revalidate_at <= now();

  UPDATE public.news
  SET status = 'brouillon', revalidate_at = NULL
  WHERE status = 'publiée' AND revalidate_at <= now();
END
$$;
REVOKE ALL ON FUNCTION private.expire_revalidations() FROM PUBLIC, anon, authenticated;

-- 4) Test de fumée mis à jour pour ces règles
CREATE OR REPLACE FUNCTION private.run_smoke_tests()
 RETURNS TABLE(test text, ok boolean, detail text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _res jsonb := '[]'::jsonb;
  _collab uuid; _mgr uuid; _adm uuid;
  _s1 uuid; _s2 uuid; _b uuid; _n uuid;
  _st text; _cnt int; _err text;
  _team text := 'ZZ Test fumée';
BEGIN
  BEGIN
    INSERT INTO teams(name) VALUES (_team) ON CONFLICT DO NOTHING;
    INSERT INTO allowed_users(email, team) VALUES ('smoke.collab@test.invalid', _team) RETURNING id INTO _collab;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_collab, 'collaborateur');
    INSERT INTO allowed_users(email) VALUES ('smoke.manager@test.invalid') RETURNING id INTO _mgr;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_mgr, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_mgr, _team);
    INSERT INTO allowed_users(email) VALUES ('smoke.admin@test.invalid') RETURNING id INTO _adm;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_adm, 'admin');

    -- Collaborateur : soumission
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 1') RETURNING id, status::text INTO _s1, _st;
    _res := _res || jsonb_build_object('t', 'Soumission créée « en attente », dans l''équipe du collaborateur',
      'ok', _st = 'en attente' AND (SELECT team FROM submissions WHERE id = _s1) = _team, 'd', _st);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 2') RETURNING id INTO _s2;

    -- Manager : validation et refus
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    BEGIN
      UPDATE submissions SET status = 'validée' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager valide une demande en attente', 'ok', true, 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager valide une demande en attente', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'refusée', rejection_category = 'doublon', rejection_note = 'Test' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager refuse une demande avec un motif', 'ok', true, 'd', 'refusée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager refuse une demande avec un motif', 'ok', false, 'd', SQLERRM);
    END;
    -- Le manager change le statut librement, autant de fois que nécessaire (erreurs humaines)
    BEGIN
      UPDATE submissions SET status = 'clôturée' WHERE id = _s1;
      UPDATE submissions SET status = 'validée' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager corrige une clôture par erreur (clôturée puis validée)', 'ok',
        (SELECT status::text FROM submissions WHERE id = _s1) = 'validée', 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager corrige une clôture par erreur (clôturée puis validée)', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'validée' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager passe un refus en validée, le motif est effacé', 'ok',
        (SELECT rejection_category IS NULL AND rejection_note IS NULL FROM submissions WHERE id = _s2), 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager passe un refus en validée, le motif est effacé', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'en attente' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager remet une demande « en attente »', 'ok', true, 'd', 'en attente');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager remet une demande « en attente »', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET content = 'Contenu modifié par le manager' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager ne peut pas modifier le contenu d''une demande', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager ne peut pas modifier le contenu d''une demande', 'ok', true, 'd', 'refusé par la base');
    END;
    SELECT count(*) INTO _cnt FROM submission_status_history WHERE submission_id IN (_s1, _s2);
    _res := _res || jsonb_build_object('t', 'Historique : 8 lignes (2 créations, 6 changements de statut)', 'ok', _cnt = 8, 'd', _cnt || ' ligne(s)');

    -- Clôture automatique après un an sans modification
    PERFORM set_config('request.jwt.claims', '', true);
    UPDATE submissions SET revalidate_at = now() - interval '1 day' WHERE id = _s1;
    PERFORM private.expire_revalidations();
    SELECT status::text INTO _st FROM submissions WHERE id = _s1;
    _res := _res || jsonb_build_object('t', 'Clôture automatique : une demande validée échue passe « clôturée »', 'ok', _st = 'clôturée', 'd', _st);
    _res := _res || jsonb_build_object('t', 'Clôture automatique : l''historique la marque « Automatique »', 'ok',
      EXISTS (SELECT 1 FROM submission_status_history WHERE submission_id = _s1 AND new_status = 'clôturée' AND is_automatic), 'd', _st);

    -- Points bloquants
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.admin@test.invalid"}', true);
    INSERT INTO blockers(title, department) VALUES ('Blocage de test', 'Test') RETURNING id, status::text INTO _b, _st;
    _res := _res || jsonb_build_object('t', 'Point bloquant créé au statut OUVERT', 'ok', _st = 'OUVERT', 'd', _st);
    BEGIN
      UPDATE blockers SET status = 'RÉSOLU' WHERE id = _b;
      _res := _res || jsonb_build_object('t', 'OUVERT → RÉSOLU refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'OUVERT → RÉSOLU refusé', 'ok', true, 'd', 'refusé par la base');
    END;
    BEGIN
      UPDATE blockers SET status = 'EN COURS' WHERE id = _b;
      UPDATE blockers SET status = 'SURVEILLANCE' WHERE id = _b;
      UPDATE blockers SET status = 'RÉSOLU' WHERE id = _b;
      _res := _res || jsonb_build_object('t', 'OUVERT → EN COURS → SURVEILLANCE → RÉSOLU accepté', 'ok', true, 'd', 'RÉSOLU');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'OUVERT → EN COURS → SURVEILLANCE → RÉSOLU accepté', 'ok', false, 'd', SQLERRM);
    END;

    -- Actualités
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    INSERT INTO news(title, body, author, status) VALUES ('Actu de test', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _n;
    UPDATE news SET status = 'publiée' WHERE id = _n;
    _res := _res || jsonb_build_object('t', 'Actualité : brouillon puis publiée, échéance de revalidation posée', 'ok',
      (SELECT revalidate_at IS NOT NULL FROM news WHERE id = _n), 'd', (SELECT status::text FROM news WHERE id = _n));

    -- Référentiel des équipes
    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      UPDATE teams SET name = 'ZZ Test fumée 2' WHERE name = _team;
      _res := _res || jsonb_build_object('t', 'Référentiel : renommer une équipe met à jour utilisateurs, managers et demandes', 'ok',
        (SELECT team FROM allowed_users WHERE id = _collab) = 'ZZ Test fumée 2'
        AND (SELECT team FROM manager_teams WHERE allowed_user_id = _mgr) = 'ZZ Test fumée 2'
        AND (SELECT team FROM submissions WHERE id = _s1) = 'ZZ Test fumée 2', 'd', 'ZZ Test fumée 2');
      _team := 'ZZ Test fumée 2';
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Référentiel : renommer une équipe met à jour utilisateurs, managers et demandes', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      DELETE FROM teams WHERE name = _team;
      _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN foreign_key_violation THEN
        _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', false, 'd', SQLERRM);
    END;

    RAISE EXCEPTION 'HP_SMOKE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'HP_SMOKE_ROLLBACK' THEN
      _res := _res || jsonb_build_object('t', 'Exécution du test de fumée', 'ok', false, 'd', 'Erreur inattendue : ' || SQLERRM);
    END IF;
  END;

  SELECT count(*) INTO _cnt FROM private.audit_enum_literals();
  _res := _res || jsonb_build_object('t', 'Aucune valeur d''ENUM obsolète dans les fonctions', 'ok', _cnt = 0, 'd', _cnt || ' anomalie(s)');

  RETURN QUERY SELECT x->>'t', (x->>'ok')::boolean, x->>'d' FROM jsonb_array_elements(_res) x;
END;
$function$;

DO $$
DECLARE _bad int;
BEGIN
  SELECT count(*) INTO _bad FROM private.run_smoke_tests() WHERE NOT ok;
  IF _bad > 0 THEN
    RAISE EXCEPTION 'Smoke tests failed: % test(s) not ok', _bad;
  END IF;
END $$;
COMMIT;

-- ---------- 20261030100000_dates_actus.sql ----------
BEGIN;
-- Date de modification et date de publication des actualités (30 oct. 2026).
-- La base les renseigne seule : l'application ne peut pas les écrire, et corriger
-- une actu déjà publiée ne change pas sa date de publication.

ALTER TABLE public.news
  ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN published_at timestamptz;

-- Actus existantes : la date de création est la seule date connue.
UPDATE public.news SET updated_at = created_at;
UPDATE public.news SET published_at = created_at WHERE status = 'publiée'::public.news_status;

CREATE OR REPLACE FUNCTION private.set_news_dates()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.updated_at := NEW.created_at;
    NEW.published_at := CASE WHEN NEW.status = 'publiée'::public.news_status THEN NEW.created_at END;
    RETURN NEW;
  END IF;

  NEW.updated_at := now();
  IF NEW.status <> 'publiée'::public.news_status THEN
    NEW.published_at := NULL;
  ELSIF OLD.status = 'publiée'::public.news_status THEN
    NEW.published_at := OLD.published_at;
  ELSE
    NEW.published_at := now();
  END IF;
  RETURN NEW;
END
$function$;

CREATE TRIGGER set_news_dates
BEFORE INSERT OR UPDATE ON public.news
FOR EACH ROW EXECUTE FUNCTION private.set_news_dates();

-- ---------- 20261031090000_equipe_points_bloquants.sql ----------
-- Équipe concernée par un point bloquant (31 oct. 2026).
-- Le pôle reste un texte libre : seule l'équipe permet de savoir quel manager est concerné.
-- Sans équipe, le point concerne toutes les équipes.

ALTER TABLE public.blockers
  ADD COLUMN team text REFERENCES public.teams(name) ON UPDATE CASCADE ON DELETE SET NULL;

-- Points existants : on ne rattache que les pôles qui correspondent à une équipe.
UPDATE public.blockers b
SET team = m.team
FROM (VALUES
  ('PRODUCT TEAM', 'Product'),
  ('RELATIONS CLIENTS', 'Relation clients'),
  ('DATA & IA', 'Pôle Data et IA'),
  ('DIRECTION RECRUTEMENT', 'Direction recrutement'),
  ('OPÉRATIONS', 'Opérations')
) AS m(department, team)
JOIN public.teams t ON t.name = m.team
WHERE b.department = m.department;
COMMIT;

-- ---------- 20261101090000_actus_sans_revalidation.sql ----------
BEGIN;
-- Les actus sortent de la revalidation annuelle (1er nov. 2026) : une actu publiée reste publiée.
-- La tâche quotidienne ne concerne plus que les demandes, clôturées un an après leur validation.

DROP TRIGGER IF EXISTS set_revalidate_at ON public.news;
ALTER TABLE public.news DROP COLUMN revalidate_at;

CREATE OR REPLACE FUNCTION private.set_revalidate_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, private
AS $$
BEGIN
  IF NEW.status = 'validée'::public.submission_status THEN
    IF TG_OP = 'INSERT' OR OLD.status <> NEW.status OR NEW.revalidate_at IS NULL THEN
      NEW.revalidate_at := now() + interval '1 year';
    END IF;
  ELSE
    NEW.revalidate_at := NULL;
  END IF;
  RETURN NEW;
END
$$;

CREATE OR REPLACE FUNCTION private.expire_revalidations()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  UPDATE public.submissions
  SET status = 'clôturée'::public.submission_status, revalidate_at = NULL
  WHERE status = 'validée'::public.submission_status AND revalidate_at <= now();
END
$$;
REVOKE ALL ON FUNCTION private.expire_revalidations() FROM PUBLIC, anon, authenticated;

-- Test de fumée mis à jour pour cette règle
CREATE OR REPLACE FUNCTION private.run_smoke_tests()
 RETURNS TABLE(test text, ok boolean, detail text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _res jsonb := '[]'::jsonb;
  _collab uuid; _mgr uuid; _adm uuid;
  _s1 uuid; _s2 uuid; _b uuid; _n uuid;
  _st text; _cnt int; _err text;
  _team text := 'ZZ Test fumée';
BEGIN
  BEGIN
    INSERT INTO teams(name) VALUES (_team) ON CONFLICT DO NOTHING;
    INSERT INTO allowed_users(email, team) VALUES ('smoke.collab@test.invalid', _team) RETURNING id INTO _collab;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_collab, 'collaborateur');
    INSERT INTO allowed_users(email) VALUES ('smoke.manager@test.invalid') RETURNING id INTO _mgr;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_mgr, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_mgr, _team);
    INSERT INTO allowed_users(email) VALUES ('smoke.admin@test.invalid') RETURNING id INTO _adm;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_adm, 'admin');

    -- Collaborateur : soumission
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 1') RETURNING id, status::text INTO _s1, _st;
    _res := _res || jsonb_build_object('t', 'Soumission créée « en attente », dans l''équipe du collaborateur',
      'ok', _st = 'en attente' AND (SELECT team FROM submissions WHERE id = _s1) = _team, 'd', _st);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 2') RETURNING id INTO _s2;

    -- Manager : validation et refus
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    BEGIN
      UPDATE submissions SET status = 'validée' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager valide une demande en attente', 'ok', true, 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager valide une demande en attente', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'refusée', rejection_category = 'doublon', rejection_note = 'Test' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager refuse une demande avec un motif', 'ok', true, 'd', 'refusée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager refuse une demande avec un motif', 'ok', false, 'd', SQLERRM);
    END;
    -- Le manager change le statut librement, autant de fois que nécessaire (erreurs humaines)
    BEGIN
      UPDATE submissions SET status = 'clôturée' WHERE id = _s1;
      UPDATE submissions SET status = 'validée' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager corrige une clôture par erreur (clôturée puis validée)', 'ok',
        (SELECT status::text FROM submissions WHERE id = _s1) = 'validée', 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager corrige une clôture par erreur (clôturée puis validée)', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'validée' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager passe un refus en validée, le motif est effacé', 'ok',
        (SELECT rejection_category IS NULL AND rejection_note IS NULL FROM submissions WHERE id = _s2), 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager passe un refus en validée, le motif est effacé', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'en attente' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager remet une demande « en attente »', 'ok', true, 'd', 'en attente');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager remet une demande « en attente »', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET content = 'Contenu modifié par le manager' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager ne peut pas modifier le contenu d''une demande', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager ne peut pas modifier le contenu d''une demande', 'ok', true, 'd', 'refusé par la base');
    END;
    SELECT count(*) INTO _cnt FROM submission_status_history WHERE submission_id IN (_s1, _s2);
    _res := _res || jsonb_build_object('t', 'Historique : 8 lignes (2 créations, 6 changements de statut)', 'ok', _cnt = 8, 'd', _cnt || ' ligne(s)');

    -- Clôture automatique après un an sans modification
    PERFORM set_config('request.jwt.claims', '', true);
    UPDATE submissions SET revalidate_at = now() - interval '1 day' WHERE id = _s1;
    PERFORM private.expire_revalidations();
    SELECT status::text INTO _st FROM submissions WHERE id = _s1;
    _res := _res || jsonb_build_object('t', 'Clôture automatique : une demande validée échue passe « clôturée »', 'ok', _st = 'clôturée', 'd', _st);
    _res := _res || jsonb_build_object('t', 'Clôture automatique : l''historique la marque « Automatique »', 'ok',
      EXISTS (SELECT 1 FROM submission_status_history WHERE submission_id = _s1 AND new_status = 'clôturée' AND is_automatic), 'd', _st);

    -- Points bloquants
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.admin@test.invalid"}', true);
    INSERT INTO blockers(title, department) VALUES ('Blocage de test', 'Test') RETURNING id, status::text INTO _b, _st;
    _res := _res || jsonb_build_object('t', 'Point bloquant créé au statut OUVERT', 'ok', _st = 'OUVERT', 'd', _st);
    BEGIN
      UPDATE blockers SET status = 'RÉSOLU' WHERE id = _b;
      _res := _res || jsonb_build_object('t', 'OUVERT → RÉSOLU refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'OUVERT → RÉSOLU refusé', 'ok', true, 'd', 'refusé par la base');
    END;
    BEGIN
      UPDATE blockers SET status = 'EN COURS' WHERE id = _b;
      UPDATE blockers SET status = 'SURVEILLANCE' WHERE id = _b;
      UPDATE blockers SET status = 'RÉSOLU' WHERE id = _b;
      _res := _res || jsonb_build_object('t', 'OUVERT → EN COURS → SURVEILLANCE → RÉSOLU accepté', 'ok', true, 'd', 'RÉSOLU');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'OUVERT → EN COURS → SURVEILLANCE → RÉSOLU accepté', 'ok', false, 'd', SQLERRM);
    END;

    -- Actualités
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    INSERT INTO news(title, body, author, status) VALUES ('Actu de test', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _n;
    UPDATE news SET status = 'publiée' WHERE id = _n;
    PERFORM private.expire_revalidations();
    SELECT status::text INTO _st FROM news WHERE id = _n;
    _res := _res || jsonb_build_object('t', 'Actualité : brouillon puis publiée, elle reste publiée après la tâche quotidienne', 'ok', _st = 'publiée', 'd', _st);

    -- Référentiel des équipes
    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      UPDATE teams SET name = 'ZZ Test fumée 2' WHERE name = _team;
      _res := _res || jsonb_build_object('t', 'Référentiel : renommer une équipe met à jour utilisateurs, managers et demandes', 'ok',
        (SELECT team FROM allowed_users WHERE id = _collab) = 'ZZ Test fumée 2'
        AND (SELECT team FROM manager_teams WHERE allowed_user_id = _mgr) = 'ZZ Test fumée 2'
        AND (SELECT team FROM submissions WHERE id = _s1) = 'ZZ Test fumée 2', 'd', 'ZZ Test fumée 2');
      _team := 'ZZ Test fumée 2';
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Référentiel : renommer une équipe met à jour utilisateurs, managers et demandes', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      DELETE FROM teams WHERE name = _team;
      _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN foreign_key_violation THEN
        _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', false, 'd', SQLERRM);
    END;

    RAISE EXCEPTION 'HP_SMOKE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'HP_SMOKE_ROLLBACK' THEN
      _res := _res || jsonb_build_object('t', 'Exécution du test de fumée', 'ok', false, 'd', 'Erreur inattendue : ' || SQLERRM);
    END IF;
  END;

  SELECT count(*) INTO _cnt FROM private.audit_enum_literals();
  _res := _res || jsonb_build_object('t', 'Aucune valeur d''ENUM obsolète dans les fonctions', 'ok', _cnt = 0, 'd', _cnt || ' anomalie(s)');

  RETURN QUERY SELECT x->>'t', (x->>'ok')::boolean, x->>'d' FROM jsonb_array_elements(_res) x;
END;
$function$;

DO $$
DECLARE _bad int;
BEGIN
  SELECT count(*) INTO _bad FROM private.run_smoke_tests() WHERE NOT ok;
  IF _bad > 0 THEN
    RAISE EXCEPTION 'Smoke tests failed: % test(s) not ok', _bad;
  END IF;
END $$;
COMMIT;

-- ---------- 20261101120000_actu_publiee_sans_retour.sql ----------
BEGIN;
-- Une actu publiée ne repasse plus en brouillon (1er nov. 2026) : son texte reste modifiable,
-- et sa date de publication, donc le compteur du mois, ne bouge plus.

CREATE OR REPLACE FUNCTION private.set_news_dates()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.updated_at := NEW.created_at;
    NEW.published_at := CASE WHEN NEW.status = 'publiée'::public.news_status THEN NEW.created_at END;
    RETURN NEW;
  END IF;

  NEW.updated_at := now();
  IF OLD.status = 'publiée'::public.news_status THEN
    IF NEW.status <> 'publiée'::public.news_status THEN
      RAISE EXCEPTION 'Une actu publiée ne peut pas repasser en brouillon.';
    END IF;
    NEW.published_at := OLD.published_at;
  ELSIF NEW.status = 'publiée'::public.news_status THEN
    NEW.published_at := now();
  ELSE
    NEW.published_at := NULL;
  END IF;
  RETURN NEW;
END
$function$;

-- Test de fumée mis à jour pour cette règle
CREATE OR REPLACE FUNCTION private.run_smoke_tests()
 RETURNS TABLE(test text, ok boolean, detail text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _res jsonb := '[]'::jsonb;
  _collab uuid; _mgr uuid; _adm uuid;
  _s1 uuid; _s2 uuid; _b uuid; _n uuid;
  _st text; _cnt int; _err text;
  _team text := 'ZZ Test fumée';
BEGIN
  BEGIN
    INSERT INTO teams(name) VALUES (_team) ON CONFLICT DO NOTHING;
    INSERT INTO allowed_users(email, team) VALUES ('smoke.collab@test.invalid', _team) RETURNING id INTO _collab;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_collab, 'collaborateur');
    INSERT INTO allowed_users(email) VALUES ('smoke.manager@test.invalid') RETURNING id INTO _mgr;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_mgr, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_mgr, _team);
    INSERT INTO allowed_users(email) VALUES ('smoke.admin@test.invalid') RETURNING id INTO _adm;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_adm, 'admin');

    -- Collaborateur : soumission
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 1') RETURNING id, status::text INTO _s1, _st;
    _res := _res || jsonb_build_object('t', 'Soumission créée « en attente », dans l''équipe du collaborateur',
      'ok', _st = 'en attente' AND (SELECT team FROM submissions WHERE id = _s1) = _team, 'd', _st);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 2') RETURNING id INTO _s2;

    -- Manager : validation et refus
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    BEGIN
      UPDATE submissions SET status = 'validée' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager valide une demande en attente', 'ok', true, 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager valide une demande en attente', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'refusée', rejection_category = 'doublon', rejection_note = 'Test' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager refuse une demande avec un motif', 'ok', true, 'd', 'refusée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager refuse une demande avec un motif', 'ok', false, 'd', SQLERRM);
    END;
    -- Le manager change le statut librement, autant de fois que nécessaire (erreurs humaines)
    BEGIN
      UPDATE submissions SET status = 'clôturée' WHERE id = _s1;
      UPDATE submissions SET status = 'validée' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager corrige une clôture par erreur (clôturée puis validée)', 'ok',
        (SELECT status::text FROM submissions WHERE id = _s1) = 'validée', 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager corrige une clôture par erreur (clôturée puis validée)', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'validée' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager passe un refus en validée, le motif est effacé', 'ok',
        (SELECT rejection_category IS NULL AND rejection_note IS NULL FROM submissions WHERE id = _s2), 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager passe un refus en validée, le motif est effacé', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'en attente' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager remet une demande « en attente »', 'ok', true, 'd', 'en attente');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager remet une demande « en attente »', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET content = 'Contenu modifié par le manager' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager ne peut pas modifier le contenu d''une demande', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager ne peut pas modifier le contenu d''une demande', 'ok', true, 'd', 'refusé par la base');
    END;
    SELECT count(*) INTO _cnt FROM submission_status_history WHERE submission_id IN (_s1, _s2);
    _res := _res || jsonb_build_object('t', 'Historique : 8 lignes (2 créations, 6 changements de statut)', 'ok', _cnt = 8, 'd', _cnt || ' ligne(s)');

    -- Clôture automatique après un an sans modification
    PERFORM set_config('request.jwt.claims', '', true);
    UPDATE submissions SET revalidate_at = now() - interval '1 day' WHERE id = _s1;
    PERFORM private.expire_revalidations();
    SELECT status::text INTO _st FROM submissions WHERE id = _s1;
    _res := _res || jsonb_build_object('t', 'Clôture automatique : une demande validée échue passe « clôturée »', 'ok', _st = 'clôturée', 'd', _st);
    _res := _res || jsonb_build_object('t', 'Clôture automatique : l''historique la marque « Automatique »', 'ok',
      EXISTS (SELECT 1 FROM submission_status_history WHERE submission_id = _s1 AND new_status = 'clôturée' AND is_automatic), 'd', _st);

    -- Points bloquants
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.admin@test.invalid"}', true);
    INSERT INTO blockers(title, department) VALUES ('Blocage de test', 'Test') RETURNING id, status::text INTO _b, _st;
    _res := _res || jsonb_build_object('t', 'Point bloquant créé au statut OUVERT', 'ok', _st = 'OUVERT', 'd', _st);
    BEGIN
      UPDATE blockers SET status = 'RÉSOLU' WHERE id = _b;
      _res := _res || jsonb_build_object('t', 'OUVERT → RÉSOLU refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'OUVERT → RÉSOLU refusé', 'ok', true, 'd', 'refusé par la base');
    END;
    BEGIN
      UPDATE blockers SET status = 'EN COURS' WHERE id = _b;
      UPDATE blockers SET status = 'SURVEILLANCE' WHERE id = _b;
      UPDATE blockers SET status = 'RÉSOLU' WHERE id = _b;
      _res := _res || jsonb_build_object('t', 'OUVERT → EN COURS → SURVEILLANCE → RÉSOLU accepté', 'ok', true, 'd', 'RÉSOLU');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'OUVERT → EN COURS → SURVEILLANCE → RÉSOLU accepté', 'ok', false, 'd', SQLERRM);
    END;

    -- Actualités
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    INSERT INTO news(title, body, author, status) VALUES ('Actu de test', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _n;
    UPDATE news SET status = 'publiée' WHERE id = _n;
    PERFORM private.expire_revalidations();
    SELECT status::text INTO _st FROM news WHERE id = _n;
    _res := _res || jsonb_build_object('t', 'Actualité : brouillon puis publiée, elle reste publiée après la tâche quotidienne', 'ok', _st = 'publiée', 'd', _st);
    BEGIN
      UPDATE news SET status = 'brouillon' WHERE id = _n;
      _res := _res || jsonb_build_object('t', 'Une actu publiée ne repasse pas en brouillon', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Une actu publiée ne repasse pas en brouillon', 'ok', true, 'd', 'refusé par la base');
    END;
    UPDATE news SET title = 'Actu de test corrigée' WHERE id = _n;
    SELECT status::text INTO _st FROM news WHERE id = _n;
    _res := _res || jsonb_build_object('t', 'Une actu publiée reste modifiable et reste publiée', 'ok', _st = 'publiée', 'd', _st);

    -- Référentiel des équipes
    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      UPDATE teams SET name = 'ZZ Test fumée 2' WHERE name = _team;
      _res := _res || jsonb_build_object('t', 'Référentiel : renommer une équipe met à jour utilisateurs, managers et demandes', 'ok',
        (SELECT team FROM allowed_users WHERE id = _collab) = 'ZZ Test fumée 2'
        AND (SELECT team FROM manager_teams WHERE allowed_user_id = _mgr) = 'ZZ Test fumée 2'
        AND (SELECT team FROM submissions WHERE id = _s1) = 'ZZ Test fumée 2', 'd', 'ZZ Test fumée 2');
      _team := 'ZZ Test fumée 2';
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Référentiel : renommer une équipe met à jour utilisateurs, managers et demandes', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      DELETE FROM teams WHERE name = _team;
      _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN foreign_key_violation THEN
        _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', false, 'd', SQLERRM);
    END;

    RAISE EXCEPTION 'HP_SMOKE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'HP_SMOKE_ROLLBACK' THEN
      _res := _res || jsonb_build_object('t', 'Exécution du test de fumée', 'ok', false, 'd', 'Erreur inattendue : ' || SQLERRM);
    END IF;
  END;

  SELECT count(*) INTO _cnt FROM private.audit_enum_literals();
  _res := _res || jsonb_build_object('t', 'Aucune valeur d''ENUM obsolète dans les fonctions', 'ok', _cnt = 0, 'd', _cnt || ' anomalie(s)');

  RETURN QUERY SELECT x->>'t', (x->>'ok')::boolean, x->>'d' FROM jsonb_array_elements(_res) x;
END;
$function$;

DO $$
DECLARE _bad int;
BEGIN
  SELECT count(*) INTO _bad FROM private.run_smoke_tests() WHERE NOT ok;
  IF _bad > 0 THEN
    RAISE EXCEPTION 'Smoke tests failed: % test(s) not ok', _bad;
  END IF;
END $$;
COMMIT;

-- ---------- 20261102090000_public_des_actus.sql ----------
BEGIN;
-- Public d'une actu (US8) : mon équipe ou toute l'entreprise.
-- La lecture des actus ne change pas ici : le filtrage par public relève de l'US9.

CREATE TYPE public.news_audience AS ENUM ('équipe', 'entreprise');

-- Le défaut remplit les actus existantes sans déclencher set_news_dates (updated_at reste intact).
ALTER TABLE public.news ADD COLUMN audience public.news_audience DEFAULT 'entreprise';
ALTER TABLE public.news ALTER COLUMN audience DROP DEFAULT;

CREATE TABLE public.news_teams (
  news_id uuid NOT NULL REFERENCES public.news(id) ON DELETE CASCADE,
  team text NOT NULL REFERENCES public.teams(name) ON UPDATE CASCADE ON DELETE RESTRICT,
  PRIMARY KEY (news_id, team)
);
CREATE INDEX news_teams_team_idx ON public.news_teams (team);

ALTER TABLE public.news_teams ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allowed read news teams" ON public.news_teams
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.news n WHERE n.id = news_id));

CREATE POLICY "Admin write" ON public.news_teams
  FOR ALL TO authenticated
  USING (private.is_admin())
  WITH CHECK (private.is_admin());

CREATE POLICY "Manager insert own news teams" ON public.news_teams
  FOR INSERT TO authenticated
  WITH CHECK (
    private.current_app_role() = 'manager'::public.app_role
    AND private.can_review_team(team)
    AND EXISTS (
      SELECT 1 FROM public.news n
      WHERE n.id = news_id AND n.author_email = lower(auth.jwt() ->> 'email')
    )
  );

-- Retirer une équipe ne fait que réduire le public : l'auteur peut le faire même s'il a quitté l'équipe.
CREATE POLICY "Manager delete own news teams" ON public.news_teams
  FOR DELETE TO authenticated
  USING (
    private.current_app_role() = 'manager'::public.app_role
    AND EXISTS (
      SELECT 1 FROM public.news n
      WHERE n.id = news_id AND n.author_email = lower(auth.jwt() ->> 'email')
    )
  );

GRANT SELECT, INSERT, DELETE ON public.news_teams TO authenticated;

-- Message clair quand un manager cible une équipe qui n'est pas la sienne.
CREATE OR REPLACE FUNCTION private.check_news_team_target()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  IF private.current_app_role() = 'manager'::public.app_role
     AND NOT private.can_review_team(NEW.team) THEN
    RAISE EXCEPTION 'Tu ne peux cibler que tes équipes.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN NEW;
END
$function$;

CREATE TRIGGER check_news_team_target BEFORE INSERT ON public.news_teams
  FOR EACH ROW EXECUTE FUNCTION private.check_news_team_target();

-- Une actu publiée a toujours un public. Contrôle différé à la fin de la transaction :
-- save_news_audience peut retirer puis remettre les équipes sans état invalide visible.
CREATE OR REPLACE FUNCTION private.check_news_audience()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _id uuid;
  _status public.news_status;
  _audience public.news_audience;
BEGIN
  IF TG_TABLE_NAME = 'news' THEN
    _id := NEW.id;
  ELSE
    _id := OLD.news_id;
  END IF;

  SELECT status, audience INTO _status, _audience FROM public.news WHERE id = _id;
  IF NOT FOUND OR _status <> 'publiée'::public.news_status THEN
    RETURN NULL;
  END IF;
  IF _audience IS NULL THEN
    RAISE EXCEPTION 'Choisis qui verra cette actu.' USING ERRCODE = 'check_violation';
  END IF;
  IF _audience = 'équipe'::public.news_audience
     AND NOT EXISTS (SELECT 1 FROM public.news_teams WHERE news_id = _id) THEN
    RAISE EXCEPTION 'Choisis au moins une équipe.' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NULL;
END
$function$;

CREATE CONSTRAINT TRIGGER check_news_audience AFTER INSERT OR UPDATE ON public.news
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION private.check_news_audience();

CREATE CONSTRAINT TRIGGER check_news_audience AFTER DELETE ON public.news_teams
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION private.check_news_audience();

-- Remplace le public d'une actu en une seule transaction. Droits de l'appelant : les règles RLS s'appliquent.
CREATE OR REPLACE FUNCTION public.save_news_audience(
  _news_id uuid,
  _audience public.news_audience,
  _teams text[] DEFAULT '{}'
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  UPDATE public.news SET audience = _audience WHERE id = _news_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tu n''as pas le droit de modifier cette actu.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  DELETE FROM public.news_teams WHERE news_id = _news_id;
  IF _audience = 'équipe'::public.news_audience THEN
    INSERT INTO public.news_teams (news_id, team)
    SELECT DISTINCT _news_id, t FROM unnest(_teams) AS t;
  END IF;
END
$function$;

REVOKE ALL ON FUNCTION public.save_news_audience(uuid, public.news_audience, text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_news_audience(uuid, public.news_audience, text[]) TO authenticated;

-- Test de fumée mis à jour pour ces règles
CREATE OR REPLACE FUNCTION private.run_smoke_tests()
 RETURNS TABLE(test text, ok boolean, detail text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _res jsonb := '[]'::jsonb;
  _collab uuid; _mgr uuid; _adm uuid;
  _s1 uuid; _s2 uuid; _b uuid; _n uuid;
  _st text; _cnt int; _err text;
  _team text := 'ZZ Test fumée';
BEGIN
  BEGIN
    INSERT INTO teams(name) VALUES (_team), ('ZZ Test fumée autre') ON CONFLICT DO NOTHING;
    INSERT INTO allowed_users(email, team) VALUES ('smoke.collab@test.invalid', _team) RETURNING id INTO _collab;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_collab, 'collaborateur');
    INSERT INTO allowed_users(email) VALUES ('smoke.manager@test.invalid') RETURNING id INTO _mgr;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_mgr, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_mgr, _team);
    INSERT INTO allowed_users(email) VALUES ('smoke.admin@test.invalid') RETURNING id INTO _adm;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_adm, 'admin');

    -- Collaborateur : soumission
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 1') RETURNING id, status::text INTO _s1, _st;
    _res := _res || jsonb_build_object('t', 'Soumission créée « en attente », dans l''équipe du collaborateur',
      'ok', _st = 'en attente' AND (SELECT team FROM submissions WHERE id = _s1) = _team, 'd', _st);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 2') RETURNING id INTO _s2;

    -- Manager : validation et refus
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    BEGIN
      UPDATE submissions SET status = 'validée' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager valide une demande en attente', 'ok', true, 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager valide une demande en attente', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'refusée', rejection_category = 'doublon', rejection_note = 'Test' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager refuse une demande avec un motif', 'ok', true, 'd', 'refusée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager refuse une demande avec un motif', 'ok', false, 'd', SQLERRM);
    END;
    -- Le manager change le statut librement, autant de fois que nécessaire (erreurs humaines)
    BEGIN
      UPDATE submissions SET status = 'clôturée' WHERE id = _s1;
      UPDATE submissions SET status = 'validée' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager corrige une clôture par erreur (clôturée puis validée)', 'ok',
        (SELECT status::text FROM submissions WHERE id = _s1) = 'validée', 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager corrige une clôture par erreur (clôturée puis validée)', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'validée' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager passe un refus en validée, le motif est effacé', 'ok',
        (SELECT rejection_category IS NULL AND rejection_note IS NULL FROM submissions WHERE id = _s2), 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager passe un refus en validée, le motif est effacé', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'en attente' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager remet une demande « en attente »', 'ok', true, 'd', 'en attente');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager remet une demande « en attente »', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET content = 'Contenu modifié par le manager' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager ne peut pas modifier le contenu d''une demande', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager ne peut pas modifier le contenu d''une demande', 'ok', true, 'd', 'refusé par la base');
    END;
    SELECT count(*) INTO _cnt FROM submission_status_history WHERE submission_id IN (_s1, _s2);
    _res := _res || jsonb_build_object('t', 'Historique : 8 lignes (2 créations, 6 changements de statut)', 'ok', _cnt = 8, 'd', _cnt || ' ligne(s)');

    -- Clôture automatique après un an sans modification
    PERFORM set_config('request.jwt.claims', '', true);
    UPDATE submissions SET revalidate_at = now() - interval '1 day' WHERE id = _s1;
    PERFORM private.expire_revalidations();
    SELECT status::text INTO _st FROM submissions WHERE id = _s1;
    _res := _res || jsonb_build_object('t', 'Clôture automatique : une demande validée échue passe « clôturée »', 'ok', _st = 'clôturée', 'd', _st);
    _res := _res || jsonb_build_object('t', 'Clôture automatique : l''historique la marque « Automatique »', 'ok',
      EXISTS (SELECT 1 FROM submission_status_history WHERE submission_id = _s1 AND new_status = 'clôturée' AND is_automatic), 'd', _st);

    -- Points bloquants
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.admin@test.invalid"}', true);
    INSERT INTO blockers(title, department) VALUES ('Blocage de test', 'Test') RETURNING id, status::text INTO _b, _st;
    _res := _res || jsonb_build_object('t', 'Point bloquant créé au statut OUVERT', 'ok', _st = 'OUVERT', 'd', _st);
    BEGIN
      UPDATE blockers SET status = 'RÉSOLU' WHERE id = _b;
      _res := _res || jsonb_build_object('t', 'OUVERT → RÉSOLU refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'OUVERT → RÉSOLU refusé', 'ok', true, 'd', 'refusé par la base');
    END;
    BEGIN
      UPDATE blockers SET status = 'EN COURS' WHERE id = _b;
      UPDATE blockers SET status = 'SURVEILLANCE' WHERE id = _b;
      UPDATE blockers SET status = 'RÉSOLU' WHERE id = _b;
      _res := _res || jsonb_build_object('t', 'OUVERT → EN COURS → SURVEILLANCE → RÉSOLU accepté', 'ok', true, 'd', 'RÉSOLU');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'OUVERT → EN COURS → SURVEILLANCE → RÉSOLU accepté', 'ok', false, 'd', SQLERRM);
    END;

    -- Actualités
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    -- Différée, la contrainte ne se déclencherait qu'au COMMIT, jamais atteint dans ce test.
    SET CONSTRAINTS check_news_audience IMMEDIATE;
    INSERT INTO news(title, body, author, status) VALUES ('Actu de test', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _n;
    BEGIN
      UPDATE news SET status = 'publiée' WHERE id = _n;
      _res := _res || jsonb_build_object('t', 'Publier une actu sans public est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN check_violation THEN
        _res := _res || jsonb_build_object('t', 'Publier une actu sans public est refusé', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Publier une actu sans public est refusé', 'ok', false, 'd', SQLERRM);
    END;
    UPDATE news SET audience = 'équipe' WHERE id = _n;
    BEGIN
      UPDATE news SET status = 'publiée' WHERE id = _n;
      _res := _res || jsonb_build_object('t', 'Publier une actu « équipe » sans équipe est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN check_violation THEN
        _res := _res || jsonb_build_object('t', 'Publier une actu « équipe » sans équipe est refusé', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Publier une actu « équipe » sans équipe est refusé', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      PERFORM public.save_news_audience(_n, 'équipe', ARRAY['ZZ Test fumée autre']);
      _res := _res || jsonb_build_object('t', 'Un manager ne cible pas une équipe qui n''est pas la sienne', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN insufficient_privilege THEN
        _res := _res || jsonb_build_object('t', 'Un manager ne cible pas une équipe qui n''est pas la sienne', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Un manager ne cible pas une équipe qui n''est pas la sienne', 'ok', false, 'd', SQLERRM);
    END;
    PERFORM public.save_news_audience(_n, 'équipe', ARRAY[_team]);
    UPDATE news SET status = 'publiée' WHERE id = _n;
    PERFORM private.expire_revalidations();
    SELECT status::text INTO _st FROM news WHERE id = _n;
    _res := _res || jsonb_build_object('t', 'Actualité : brouillon puis publiée, elle reste publiée après la tâche quotidienne', 'ok', _st = 'publiée', 'd', _st);
    BEGIN
      UPDATE news SET status = 'brouillon' WHERE id = _n;
      _res := _res || jsonb_build_object('t', 'Une actu publiée ne repasse pas en brouillon', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Une actu publiée ne repasse pas en brouillon', 'ok', true, 'd', 'refusé par la base');
    END;
    UPDATE news SET title = 'Actu de test corrigée' WHERE id = _n;
    SELECT status::text INTO _st FROM news WHERE id = _n;
    _res := _res || jsonb_build_object('t', 'Une actu publiée reste modifiable et reste publiée', 'ok', _st = 'publiée', 'd', _st);

    -- Référentiel des équipes
    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      UPDATE teams SET name = 'ZZ Test fumée 2' WHERE name = _team;
      _res := _res || jsonb_build_object('t', 'Référentiel : renommer une équipe met à jour utilisateurs, managers et demandes', 'ok',
        (SELECT team FROM allowed_users WHERE id = _collab) = 'ZZ Test fumée 2'
        AND (SELECT team FROM manager_teams WHERE allowed_user_id = _mgr) = 'ZZ Test fumée 2'
        AND (SELECT team FROM submissions WHERE id = _s1) = 'ZZ Test fumée 2', 'd', 'ZZ Test fumée 2');
      _res := _res || jsonb_build_object('t', 'Référentiel : renommer une équipe met à jour le public des actus', 'ok',
        (SELECT team FROM news_teams WHERE news_id = _n) = 'ZZ Test fumée 2', 'd', 'ZZ Test fumée 2');
      _team := 'ZZ Test fumée 2';
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Référentiel : renommer une équipe met à jour utilisateurs, managers et demandes', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      DELETE FROM teams WHERE name = _team;
      _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN foreign_key_violation THEN
        _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', false, 'd', SQLERRM);
    END;

    RAISE EXCEPTION 'HP_SMOKE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'HP_SMOKE_ROLLBACK' THEN
      _res := _res || jsonb_build_object('t', 'Exécution du test de fumée', 'ok', false, 'd', 'Erreur inattendue : ' || SQLERRM);
    END IF;
  END;

  SELECT count(*) INTO _cnt FROM private.audit_enum_literals();
  _res := _res || jsonb_build_object('t', 'Aucune valeur d''ENUM obsolète dans les fonctions', 'ok', _cnt = 0, 'd', _cnt || ' anomalie(s)');

  RETURN QUERY SELECT x->>'t', (x->>'ok')::boolean, x->>'d' FROM jsonb_array_elements(_res) x;
END;
$function$;

DO $$
DECLARE _bad int;
BEGIN
  SELECT count(*) INTO _bad FROM private.run_smoke_tests() WHERE NOT ok;
  IF _bad > 0 THEN
    RAISE EXCEPTION 'Smoke tests failed: % test(s) not ok', _bad;
  END IF;
END $$;
COMMIT;

-- ---------- 20261102100000_actus_filtrees_par_public.sql ----------
BEGIN;
-- Actus filtrées par public (US9) : chacun ne lit que les actus de son public.

-- Équipes de l'utilisateur courant, selon son rôle : allowed_users.team pour un collaborateur,
-- manager_teams pour un manager.
CREATE OR REPLACE FUNCTION private.current_user_teams()
RETURNS SETOF text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
  SELECT au.team
  FROM public.allowed_users au
  JOIN public.allowed_user_roles aur ON aur.allowed_user_id = au.id
  WHERE au.email = lower(auth.jwt() ->> 'email')
    AND aur.role = 'collaborateur'::public.app_role
    AND au.team IS NOT NULL
  UNION
  SELECT mt.team
  FROM public.allowed_users au
  JOIN public.allowed_user_roles aur ON aur.allowed_user_id = au.id
  JOIN public.manager_teams mt ON mt.allowed_user_id = au.id
  WHERE au.email = lower(auth.jwt() ->> 'email')
    AND aur.role = 'manager'::public.app_role
$function$;

-- La règle de news_teams lit news : passer par SECURITY DEFINER évite la récursion entre les deux règles.
CREATE OR REPLACE FUNCTION private.news_targets_my_team(_news_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.news_teams nt
    WHERE nt.news_id = _news_id
      AND nt.team IN (SELECT private.current_user_teams())
  )
$function$;

REVOKE ALL ON FUNCTION private.current_user_teams() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.news_targets_my_team(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.current_user_teams() TO authenticated;
GRANT EXECUTE ON FUNCTION private.news_targets_my_team(uuid) TO authenticated;

-- L'auteur voit ses actus quel que soit son rôle. news_teams et « News media read » lisent news
-- sous RLS : elles suivent cette règle sans changement.
DROP POLICY IF EXISTS "Allowed read published news" ON public.news;
CREATE POLICY "Allowed read published news" ON public.news
  FOR SELECT TO authenticated
  USING (
    private.is_allowed() AND (
      private.is_admin()
      OR author_email = lower(auth.jwt() ->> 'email')
      OR (
        status = 'publiée'::public.news_status
        AND (audience = 'entreprise'::public.news_audience OR private.news_targets_my_team(id))
      )
    )
  );

-- Lit les actus sous le rôle authenticated, donc sous RLS, avec le compte demandé.
-- Le propriétaire des tables contourne la RLS : un simple SELECT ne prouverait rien.
CREATE OR REPLACE FUNCTION private.smoke_read_as(
  _email text,
  _ids uuid[],
  OUT _news uuid[],
  OUT _teams uuid[],
  OUT _images uuid[]
)
LANGUAGE plpgsql
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('email', _email)::text, true);
  SET LOCAL ROLE authenticated;
  _news := ARRAY(SELECT n.id FROM public.news n WHERE n.id = ANY(_ids) ORDER BY 1);
  _teams := ARRAY(SELECT DISTINCT t.news_id FROM public.news_teams t WHERE t.news_id = ANY(_ids) ORDER BY 1);
  _images := ARRAY(
    SELECT DISTINCT ((storage.foldername(o.name))[1])::uuid
    FROM storage.objects o
    WHERE o.bucket_id = 'news-media'
      AND (storage.foldername(o.name))[1] = ANY(_ids::text[])
    ORDER BY 1
  );
  RESET ROLE;
END
$function$;

REVOKE ALL ON FUNCTION private.smoke_read_as(text, uuid[]) FROM PUBLIC, anon, authenticated;

-- Test de fumée mis à jour pour ces règles. SECURITY INVOKER : SET ROLE est interdit dans une fonction
-- SECURITY DEFINER, et smoke_read_as en a besoin. La fonction reste réservée à l'administration de la base.
CREATE OR REPLACE FUNCTION private.run_smoke_tests()
 RETURNS TABLE(test text, ok boolean, detail text)
 LANGUAGE plpgsql
 SECURITY INVOKER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _res jsonb := '[]'::jsonb;
  _collab uuid; _mgr uuid; _adm uuid;
  _s1 uuid; _s2 uuid; _b uuid; _n uuid;
  _st text; _cnt int; _err text;
  _team text := 'ZZ Test fumée';
  _mgr2 uuid; _nb uuid; _ne uuid; _nm uuid; _nd uuid;
  _ids uuid[]; _with_teams uuid[]; _with_images uuid[] := '{}';
  _reader record; _read record; _want uuid[];
BEGIN
  BEGIN
    INSERT INTO teams(name) VALUES (_team), ('ZZ Test fumée autre') ON CONFLICT DO NOTHING;
    INSERT INTO allowed_users(email, team) VALUES ('smoke.collab@test.invalid', _team) RETURNING id INTO _collab;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_collab, 'collaborateur');
    INSERT INTO allowed_users(email) VALUES ('smoke.manager@test.invalid') RETURNING id INTO _mgr;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_mgr, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_mgr, _team);
    INSERT INTO allowed_users(email) VALUES ('smoke.admin@test.invalid') RETURNING id INTO _adm;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_adm, 'admin');

    -- Collaborateur : soumission
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 1') RETURNING id, status::text INTO _s1, _st;
    _res := _res || jsonb_build_object('t', 'Soumission créée « en attente », dans l''équipe du collaborateur',
      'ok', _st = 'en attente' AND (SELECT team FROM submissions WHERE id = _s1) = _team, 'd', _st);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 2') RETURNING id INTO _s2;

    -- Manager : validation et refus
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    BEGIN
      UPDATE submissions SET status = 'validée' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager valide une demande en attente', 'ok', true, 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager valide une demande en attente', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'refusée', rejection_category = 'doublon', rejection_note = 'Test' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager refuse une demande avec un motif', 'ok', true, 'd', 'refusée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager refuse une demande avec un motif', 'ok', false, 'd', SQLERRM);
    END;
    -- Le manager change le statut librement, autant de fois que nécessaire (erreurs humaines)
    BEGIN
      UPDATE submissions SET status = 'clôturée' WHERE id = _s1;
      UPDATE submissions SET status = 'validée' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager corrige une clôture par erreur (clôturée puis validée)', 'ok',
        (SELECT status::text FROM submissions WHERE id = _s1) = 'validée', 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager corrige une clôture par erreur (clôturée puis validée)', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'validée' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager passe un refus en validée, le motif est effacé', 'ok',
        (SELECT rejection_category IS NULL AND rejection_note IS NULL FROM submissions WHERE id = _s2), 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager passe un refus en validée, le motif est effacé', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'en attente' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager remet une demande « en attente »', 'ok', true, 'd', 'en attente');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager remet une demande « en attente »', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET content = 'Contenu modifié par le manager' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager ne peut pas modifier le contenu d''une demande', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager ne peut pas modifier le contenu d''une demande', 'ok', true, 'd', 'refusé par la base');
    END;
    SELECT count(*) INTO _cnt FROM submission_status_history WHERE submission_id IN (_s1, _s2);
    _res := _res || jsonb_build_object('t', 'Historique : 8 lignes (2 créations, 6 changements de statut)', 'ok', _cnt = 8, 'd', _cnt || ' ligne(s)');

    -- Clôture automatique après un an sans modification
    PERFORM set_config('request.jwt.claims', '', true);
    UPDATE submissions SET revalidate_at = now() - interval '1 day' WHERE id = _s1;
    PERFORM private.expire_revalidations();
    SELECT status::text INTO _st FROM submissions WHERE id = _s1;
    _res := _res || jsonb_build_object('t', 'Clôture automatique : une demande validée échue passe « clôturée »', 'ok', _st = 'clôturée', 'd', _st);
    _res := _res || jsonb_build_object('t', 'Clôture automatique : l''historique la marque « Automatique »', 'ok',
      EXISTS (SELECT 1 FROM submission_status_history WHERE submission_id = _s1 AND new_status = 'clôturée' AND is_automatic), 'd', _st);

    -- Points bloquants
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.admin@test.invalid"}', true);
    INSERT INTO blockers(title, department) VALUES ('Blocage de test', 'Test') RETURNING id, status::text INTO _b, _st;
    _res := _res || jsonb_build_object('t', 'Point bloquant créé au statut OUVERT', 'ok', _st = 'OUVERT', 'd', _st);
    BEGIN
      UPDATE blockers SET status = 'RÉSOLU' WHERE id = _b;
      _res := _res || jsonb_build_object('t', 'OUVERT → RÉSOLU refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'OUVERT → RÉSOLU refusé', 'ok', true, 'd', 'refusé par la base');
    END;
    BEGIN
      UPDATE blockers SET status = 'EN COURS' WHERE id = _b;
      UPDATE blockers SET status = 'SURVEILLANCE' WHERE id = _b;
      UPDATE blockers SET status = 'RÉSOLU' WHERE id = _b;
      _res := _res || jsonb_build_object('t', 'OUVERT → EN COURS → SURVEILLANCE → RÉSOLU accepté', 'ok', true, 'd', 'RÉSOLU');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'OUVERT → EN COURS → SURVEILLANCE → RÉSOLU accepté', 'ok', false, 'd', SQLERRM);
    END;

    -- Actualités
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    -- Différée, la contrainte ne se déclencherait qu'au COMMIT, jamais atteint dans ce test.
    SET CONSTRAINTS check_news_audience IMMEDIATE;
    INSERT INTO news(title, body, author, status) VALUES ('Actu de test', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _n;
    BEGIN
      UPDATE news SET status = 'publiée' WHERE id = _n;
      _res := _res || jsonb_build_object('t', 'Publier une actu sans public est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN check_violation THEN
        _res := _res || jsonb_build_object('t', 'Publier une actu sans public est refusé', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Publier une actu sans public est refusé', 'ok', false, 'd', SQLERRM);
    END;
    UPDATE news SET audience = 'équipe' WHERE id = _n;
    BEGIN
      UPDATE news SET status = 'publiée' WHERE id = _n;
      _res := _res || jsonb_build_object('t', 'Publier une actu « équipe » sans équipe est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN check_violation THEN
        _res := _res || jsonb_build_object('t', 'Publier une actu « équipe » sans équipe est refusé', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Publier une actu « équipe » sans équipe est refusé', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      PERFORM public.save_news_audience(_n, 'équipe', ARRAY['ZZ Test fumée autre']);
      _res := _res || jsonb_build_object('t', 'Un manager ne cible pas une équipe qui n''est pas la sienne', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN insufficient_privilege THEN
        _res := _res || jsonb_build_object('t', 'Un manager ne cible pas une équipe qui n''est pas la sienne', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Un manager ne cible pas une équipe qui n''est pas la sienne', 'ok', false, 'd', SQLERRM);
    END;
    PERFORM public.save_news_audience(_n, 'équipe', ARRAY[_team]);
    UPDATE news SET status = 'publiée' WHERE id = _n;
    PERFORM private.expire_revalidations();
    SELECT status::text INTO _st FROM news WHERE id = _n;
    _res := _res || jsonb_build_object('t', 'Actualité : brouillon puis publiée, elle reste publiée après la tâche quotidienne', 'ok', _st = 'publiée', 'd', _st);
    BEGIN
      UPDATE news SET status = 'brouillon' WHERE id = _n;
      _res := _res || jsonb_build_object('t', 'Une actu publiée ne repasse pas en brouillon', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Une actu publiée ne repasse pas en brouillon', 'ok', true, 'd', 'refusé par la base');
    END;
    UPDATE news SET title = 'Actu de test corrigée' WHERE id = _n;
    SELECT status::text INTO _st FROM news WHERE id = _n;
    _res := _res || jsonb_build_object('t', 'Une actu publiée reste modifiable et reste publiée', 'ok', _st = 'publiée', 'd', _st);

    -- Public des actus : lecture réelle sous RLS (voir private.smoke_read_as)
    PERFORM set_config('request.jwt.claims', '', true);
    INSERT INTO allowed_users(email) VALUES ('smoke.manager2@test.invalid') RETURNING id INTO _mgr2;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_mgr2, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_mgr2, 'ZZ Test fumée autre');

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager2@test.invalid"}', true);
    INSERT INTO news(title, body, author, status) VALUES ('Actu équipe B', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _nb;
    PERFORM public.save_news_audience(_nb, 'équipe', ARRAY['ZZ Test fumée autre']);
    UPDATE news SET status = 'publiée' WHERE id = _nb;

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.admin@test.invalid"}', true);
    INSERT INTO news(title, body, author, status) VALUES ('Actu entreprise', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _ne;
    PERFORM public.save_news_audience(_ne, 'entreprise');
    UPDATE news SET status = 'publiée' WHERE id = _ne;
    INSERT INTO news(title, body, author, status) VALUES ('Actu deux équipes', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _nm;
    PERFORM public.save_news_audience(_nm, 'équipe', ARRAY[_team, 'ZZ Test fumée autre']);
    UPDATE news SET status = 'publiée' WHERE id = _nm;

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    INSERT INTO news(title, body, author, status) VALUES ('Brouillon du manager A', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _nd;

    _ids := ARRAY[_n, _nb, _ne, _nm, _nd];
    _with_teams := ARRAY[_n, _nb, _nm];
    -- L'écriture directe dans storage.objects dépend des droits du projet : sans elle, le détail le dit.
    BEGIN
      INSERT INTO storage.objects(bucket_id, name) VALUES ('news-media', _n || '/smoke.png'), ('news-media', _nb || '/smoke.png');
      _with_images := ARRAY[_n, _nb];
    EXCEPTION WHEN insufficient_privilege THEN
      NULL;
    END;

    FOR _reader IN
      SELECT * FROM (VALUES
        ('collaborateur équipe A', 'smoke.collab@test.invalid', ARRAY[_n, _ne, _nm]),
        ('manager équipe A', 'smoke.manager@test.invalid', ARRAY[_n, _ne, _nm, _nd]),
        ('manager équipe B', 'smoke.manager2@test.invalid', ARRAY[_nb, _ne, _nm]),
        ('admin', 'smoke.admin@test.invalid', _ids)
      ) AS v(label, email, ids)
    LOOP
      _want := ARRAY(SELECT unnest(_reader.ids) ORDER BY 1);
      SELECT * INTO _read FROM private.smoke_read_as(_reader.email, _ids);
      _res := _res || jsonb_build_object('t', 'Public des actus : lecture du ' || _reader.label, 'ok',
        _read._news = _want, 'd', cardinality(_read._news) || ' actu(s) lue(s)');
      _res := _res || jsonb_build_object('t', 'Public des actus : équipes ciblées lues par le ' || _reader.label, 'ok',
        _read._teams = ARRAY(SELECT unnest(_want) INTERSECT SELECT unnest(_with_teams) ORDER BY 1),
        'd', cardinality(_read._teams) || ' actu(s)');
      _res := _res || jsonb_build_object('t', 'Public des actus : images lues par le ' || _reader.label, 'ok',
        _read._images = ARRAY(SELECT unnest(_want) INTERSECT SELECT unnest(_with_images) ORDER BY 1),
        'd', CASE WHEN cardinality(_with_images) = 0 THEN 'NON TESTÉ : image de test impossible à créer'
             ELSE cardinality(_read._images) || ' image(s)' END);
    END LOOP;

    -- L'auteur garde ses actus même s'il n'est plus manager de l'équipe ciblée
    PERFORM set_config('request.jwt.claims', '', true);
    UPDATE allowed_user_roles SET role = 'collaborateur' WHERE allowed_user_id = _mgr2;
    DELETE FROM manager_teams WHERE allowed_user_id = _mgr2;
    SELECT * INTO _read FROM private.smoke_read_as('smoke.manager2@test.invalid', _ids);
    _res := _res || jsonb_build_object('t', 'Public des actus : l''auteur lit la sienne même sans rôle manager ni équipe', 'ok',
      _read._news = ARRAY(SELECT unnest(ARRAY[_nb, _ne]) ORDER BY 1), 'd', cardinality(_read._news) || ' actu(s) lue(s)');

    -- Référentiel des équipes
    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      UPDATE teams SET name = 'ZZ Test fumée 2' WHERE name = _team;
      _res := _res || jsonb_build_object('t', 'Référentiel : renommer une équipe met à jour utilisateurs, managers et demandes', 'ok',
        (SELECT team FROM allowed_users WHERE id = _collab) = 'ZZ Test fumée 2'
        AND (SELECT team FROM manager_teams WHERE allowed_user_id = _mgr) = 'ZZ Test fumée 2'
        AND (SELECT team FROM submissions WHERE id = _s1) = 'ZZ Test fumée 2', 'd', 'ZZ Test fumée 2');
      _res := _res || jsonb_build_object('t', 'Référentiel : renommer une équipe met à jour le public des actus', 'ok',
        (SELECT team FROM news_teams WHERE news_id = _n) = 'ZZ Test fumée 2', 'd', 'ZZ Test fumée 2');
      _team := 'ZZ Test fumée 2';
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Référentiel : renommer une équipe met à jour utilisateurs, managers et demandes', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      DELETE FROM teams WHERE name = _team;
      _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN foreign_key_violation THEN
        _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', false, 'd', SQLERRM);
    END;

    RAISE EXCEPTION 'HP_SMOKE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'HP_SMOKE_ROLLBACK' THEN
      _res := _res || jsonb_build_object('t', 'Exécution du test de fumée', 'ok', false, 'd', 'Erreur inattendue : ' || SQLERRM);
    END IF;
  END;

  SELECT count(*) INTO _cnt FROM private.audit_enum_literals();
  _res := _res || jsonb_build_object('t', 'Aucune valeur d''ENUM obsolète dans les fonctions', 'ok', _cnt = 0, 'd', _cnt || ' anomalie(s)');

  RETURN QUERY SELECT x->>'t', (x->>'ok')::boolean, x->>'d' FROM jsonb_array_elements(_res) x;
END;
$function$;

DO $$
DECLARE _bad int;
BEGIN
  SELECT count(*) INTO _bad FROM private.run_smoke_tests() WHERE NOT ok;
  IF _bad > 0 THEN
    RAISE EXCEPTION 'Smoke tests failed: % test(s) not ok', _bad;
  END IF;
END $$;
COMMIT;

-- ---------- 20261102110000_modification_actu_publiee.sql ----------
BEGIN;
-- Modification d'une actu publiée (US10) : par son auteur manager ou un admin, sans la republier.

DROP POLICY IF EXISTS "Manager update own published news" ON public.news;
CREATE POLICY "Manager update own published news" ON public.news
  FOR UPDATE TO authenticated
  USING (
    private.current_app_role() = 'manager'::public.app_role
    AND status = 'publiée'::public.news_status
    AND author_email = lower(auth.jwt() ->> 'email')
  )
  WITH CHECK (
    private.current_app_role() = 'manager'::public.app_role
    AND status = 'publiée'::public.news_status
    AND author_email = lower(auth.jwt() ->> 'email')
  );

CREATE OR REPLACE FUNCTION private.can_edit_news_media(_news_id text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, private AS $$
  SELECT private.is_admin() OR EXISTS (
    SELECT 1 FROM public.news n
    WHERE n.id::text = _news_id
      AND private.current_app_role() = 'manager'
      AND n.status IN ('brouillon', 'publiée')
      AND n.author_email = lower(auth.jwt() ->> 'email'))
$$;

-- Une actu publiée garde un titre et son auteur d'origine. La seule écriture sur news faite par un
-- trigger est l'anonymisation d'un compte supprimé (private.anonymize_removed_user) : elle passe.
CREATE OR REPLACE FUNCTION private.check_published_news()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  IF pg_trigger_depth() > 1 OR NEW.status <> 'publiée'::public.news_status THEN
    RETURN NEW;
  END IF;
  IF btrim(NEW.title) = '' THEN
    RAISE EXCEPTION 'Ajoute un titre.' USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.status = 'publiée'::public.news_status
     AND (NEW.author, NEW.author_email) IS DISTINCT FROM (OLD.author, OLD.author_email) THEN
    RAISE EXCEPTION 'L''auteur d''une actu publiée ne change pas.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN NEW;
END
$function$;

DROP TRIGGER IF EXISTS check_published_news ON public.news;
CREATE TRIGGER check_published_news BEFORE INSERT OR UPDATE ON public.news
  FOR EACH ROW EXECUTE FUNCTION private.check_published_news();

-- L'anonymisation d'un compte supprimé n'est pas une modification : « Modifiée le » ne doit pas apparaître.
CREATE OR REPLACE FUNCTION private.set_news_dates()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.updated_at := NEW.created_at;
    NEW.published_at := CASE WHEN NEW.status = 'publiée'::public.news_status THEN NEW.created_at END;
    RETURN NEW;
  END IF;

  NEW.updated_at := CASE WHEN pg_trigger_depth() > 1 THEN OLD.updated_at ELSE now() END;
  IF OLD.status = 'publiée'::public.news_status THEN
    IF NEW.status <> 'publiée'::public.news_status THEN
      RAISE EXCEPTION 'Une actu publiée ne peut pas repasser en brouillon.';
    END IF;
    NEW.published_at := OLD.published_at;
  ELSIF NEW.status = 'publiée'::public.news_status THEN
    NEW.published_at := now();
  ELSE
    NEW.published_at := NULL;
  END IF;
  RETURN NEW;
END
$function$;

-- Texte, liens, image et public en une seule transaction : si un champ est refusé, rien ne change.
-- L'application envoie le fichier avant l'appel, puis retire l'ancien. Droits de l'appelant : les règles RLS s'appliquent.
CREATE OR REPLACE FUNCTION public.save_published_news(
  _news_id uuid,
  _title text,
  _body text,
  _links jsonb,
  _image_path text,
  _audience public.news_audience,
  _teams text[] DEFAULT '{}'
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  IF split_part(_image_path, '/', 1) <> _news_id::text THEN
    RAISE EXCEPTION 'Image invalide.' USING ERRCODE = 'check_violation';
  END IF;

  UPDATE public.news
     SET title = _title, body = _body, links = _links, image_path = _image_path
   WHERE id = _news_id AND status = 'publiée'::public.news_status;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tu n''as pas le droit de modifier cette actu.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  PERFORM public.save_news_audience(_news_id, _audience, _teams);
END
$function$;

REVOKE ALL ON FUNCTION public.save_published_news(uuid, text, text, jsonb, text, public.news_audience, text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_published_news(uuid, text, text, jsonb, text, public.news_audience, text[]) TO authenticated;

-- Modifie le titre d'une actu sous le rôle authenticated, donc sous RLS, avec le compte demandé.
-- Le propriétaire des tables contourne la RLS : un simple UPDATE ne prouverait rien.
CREATE OR REPLACE FUNCTION private.smoke_update_as(
  _email text,
  _id uuid,
  _title text,
  OUT _rows int,
  OUT _error text
)
LANGUAGE plpgsql
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('email', _email)::text, true);
  SET LOCAL ROLE authenticated;
  BEGIN
    UPDATE public.news SET title = _title WHERE id = _id;
    GET DIAGNOSTICS _rows = ROW_COUNT;
  EXCEPTION WHEN OTHERS THEN
    _rows := 0;
    _error := SQLERRM;
  END;
  RESET ROLE;
END
$function$;

REVOKE ALL ON FUNCTION private.smoke_update_as(text, uuid, text) FROM PUBLIC, anon, authenticated;

-- Test de fumée mis à jour pour ces règles
CREATE OR REPLACE FUNCTION private.run_smoke_tests()
 RETURNS TABLE(test text, ok boolean, detail text)
 LANGUAGE plpgsql
 SECURITY INVOKER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _res jsonb := '[]'::jsonb;
  _collab uuid; _mgr uuid; _adm uuid;
  _s1 uuid; _s2 uuid; _b uuid; _n uuid;
  _st text; _cnt int; _err text;
  _team text := 'ZZ Test fumée';
  _mgr2 uuid; _nb uuid; _ne uuid; _nm uuid; _nd uuid;
  _ids uuid[]; _with_teams uuid[]; _with_images uuid[] := '{}';
  _reader record; _read record; _want uuid[];
  _mgr3 uuid; _np uuid; _nq uuid; _pub timestamptz; _try record;
BEGIN
  BEGIN
    INSERT INTO teams(name) VALUES (_team), ('ZZ Test fumée autre') ON CONFLICT DO NOTHING;
    INSERT INTO allowed_users(email, team) VALUES ('smoke.collab@test.invalid', _team) RETURNING id INTO _collab;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_collab, 'collaborateur');
    INSERT INTO allowed_users(email) VALUES ('smoke.manager@test.invalid') RETURNING id INTO _mgr;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_mgr, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_mgr, _team);
    INSERT INTO allowed_users(email) VALUES ('smoke.admin@test.invalid') RETURNING id INTO _adm;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_adm, 'admin');

    -- Collaborateur : soumission
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 1') RETURNING id, status::text INTO _s1, _st;
    _res := _res || jsonb_build_object('t', 'Soumission créée « en attente », dans l''équipe du collaborateur',
      'ok', _st = 'en attente' AND (SELECT team FROM submissions WHERE id = _s1) = _team, 'd', _st);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 2') RETURNING id INTO _s2;

    -- Manager : validation et refus
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    BEGIN
      UPDATE submissions SET status = 'validée' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager valide une demande en attente', 'ok', true, 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager valide une demande en attente', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'refusée', rejection_category = 'doublon', rejection_note = 'Test' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager refuse une demande avec un motif', 'ok', true, 'd', 'refusée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager refuse une demande avec un motif', 'ok', false, 'd', SQLERRM);
    END;
    -- Le manager change le statut librement, autant de fois que nécessaire (erreurs humaines)
    BEGIN
      UPDATE submissions SET status = 'clôturée' WHERE id = _s1;
      UPDATE submissions SET status = 'validée' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager corrige une clôture par erreur (clôturée puis validée)', 'ok',
        (SELECT status::text FROM submissions WHERE id = _s1) = 'validée', 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager corrige une clôture par erreur (clôturée puis validée)', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'validée' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager passe un refus en validée, le motif est effacé', 'ok',
        (SELECT rejection_category IS NULL AND rejection_note IS NULL FROM submissions WHERE id = _s2), 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager passe un refus en validée, le motif est effacé', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'en attente' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager remet une demande « en attente »', 'ok', true, 'd', 'en attente');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager remet une demande « en attente »', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET content = 'Contenu modifié par le manager' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager ne peut pas modifier le contenu d''une demande', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager ne peut pas modifier le contenu d''une demande', 'ok', true, 'd', 'refusé par la base');
    END;
    SELECT count(*) INTO _cnt FROM submission_status_history WHERE submission_id IN (_s1, _s2);
    _res := _res || jsonb_build_object('t', 'Historique : 8 lignes (2 créations, 6 changements de statut)', 'ok', _cnt = 8, 'd', _cnt || ' ligne(s)');

    -- Clôture automatique après un an sans modification
    PERFORM set_config('request.jwt.claims', '', true);
    UPDATE submissions SET revalidate_at = now() - interval '1 day' WHERE id = _s1;
    PERFORM private.expire_revalidations();
    SELECT status::text INTO _st FROM submissions WHERE id = _s1;
    _res := _res || jsonb_build_object('t', 'Clôture automatique : une demande validée échue passe « clôturée »', 'ok', _st = 'clôturée', 'd', _st);
    _res := _res || jsonb_build_object('t', 'Clôture automatique : l''historique la marque « Automatique »', 'ok',
      EXISTS (SELECT 1 FROM submission_status_history WHERE submission_id = _s1 AND new_status = 'clôturée' AND is_automatic), 'd', _st);

    -- Points bloquants
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.admin@test.invalid"}', true);
    INSERT INTO blockers(title, department) VALUES ('Blocage de test', 'Test') RETURNING id, status::text INTO _b, _st;
    _res := _res || jsonb_build_object('t', 'Point bloquant créé au statut OUVERT', 'ok', _st = 'OUVERT', 'd', _st);
    BEGIN
      UPDATE blockers SET status = 'RÉSOLU' WHERE id = _b;
      _res := _res || jsonb_build_object('t', 'OUVERT → RÉSOLU refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'OUVERT → RÉSOLU refusé', 'ok', true, 'd', 'refusé par la base');
    END;
    BEGIN
      UPDATE blockers SET status = 'EN COURS' WHERE id = _b;
      UPDATE blockers SET status = 'SURVEILLANCE' WHERE id = _b;
      UPDATE blockers SET status = 'RÉSOLU' WHERE id = _b;
      _res := _res || jsonb_build_object('t', 'OUVERT → EN COURS → SURVEILLANCE → RÉSOLU accepté', 'ok', true, 'd', 'RÉSOLU');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'OUVERT → EN COURS → SURVEILLANCE → RÉSOLU accepté', 'ok', false, 'd', SQLERRM);
    END;

    -- Actualités
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    -- Différée, la contrainte ne se déclencherait qu'au COMMIT, jamais atteint dans ce test.
    SET CONSTRAINTS check_news_audience IMMEDIATE;
    INSERT INTO news(title, body, author, status) VALUES ('Actu de test', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _n;
    BEGIN
      UPDATE news SET status = 'publiée' WHERE id = _n;
      _res := _res || jsonb_build_object('t', 'Publier une actu sans public est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN check_violation THEN
        _res := _res || jsonb_build_object('t', 'Publier une actu sans public est refusé', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Publier une actu sans public est refusé', 'ok', false, 'd', SQLERRM);
    END;
    UPDATE news SET audience = 'équipe' WHERE id = _n;
    BEGIN
      UPDATE news SET status = 'publiée' WHERE id = _n;
      _res := _res || jsonb_build_object('t', 'Publier une actu « équipe » sans équipe est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN check_violation THEN
        _res := _res || jsonb_build_object('t', 'Publier une actu « équipe » sans équipe est refusé', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Publier une actu « équipe » sans équipe est refusé', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      PERFORM public.save_news_audience(_n, 'équipe', ARRAY['ZZ Test fumée autre']);
      _res := _res || jsonb_build_object('t', 'Un manager ne cible pas une équipe qui n''est pas la sienne', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN insufficient_privilege THEN
        _res := _res || jsonb_build_object('t', 'Un manager ne cible pas une équipe qui n''est pas la sienne', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Un manager ne cible pas une équipe qui n''est pas la sienne', 'ok', false, 'd', SQLERRM);
    END;
    PERFORM public.save_news_audience(_n, 'équipe', ARRAY[_team]);
    UPDATE news SET status = 'publiée' WHERE id = _n;
    PERFORM private.expire_revalidations();
    SELECT status::text INTO _st FROM news WHERE id = _n;
    _res := _res || jsonb_build_object('t', 'Actualité : brouillon puis publiée, elle reste publiée après la tâche quotidienne', 'ok', _st = 'publiée', 'd', _st);
    BEGIN
      UPDATE news SET status = 'brouillon' WHERE id = _n;
      _res := _res || jsonb_build_object('t', 'Une actu publiée ne repasse pas en brouillon', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Une actu publiée ne repasse pas en brouillon', 'ok', true, 'd', 'refusé par la base');
    END;
    UPDATE news SET title = 'Actu de test corrigée' WHERE id = _n;
    SELECT status::text INTO _st FROM news WHERE id = _n;
    _res := _res || jsonb_build_object('t', 'Une actu publiée reste modifiable et reste publiée', 'ok', _st = 'publiée', 'd', _st);

    -- Public des actus : lecture réelle sous RLS (voir private.smoke_read_as)
    PERFORM set_config('request.jwt.claims', '', true);
    INSERT INTO allowed_users(email) VALUES ('smoke.manager2@test.invalid') RETURNING id INTO _mgr2;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_mgr2, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_mgr2, 'ZZ Test fumée autre');

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager2@test.invalid"}', true);
    INSERT INTO news(title, body, author, status) VALUES ('Actu équipe B', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _nb;
    PERFORM public.save_news_audience(_nb, 'équipe', ARRAY['ZZ Test fumée autre']);
    UPDATE news SET status = 'publiée' WHERE id = _nb;

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.admin@test.invalid"}', true);
    INSERT INTO news(title, body, author, status) VALUES ('Actu entreprise', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _ne;
    PERFORM public.save_news_audience(_ne, 'entreprise');
    UPDATE news SET status = 'publiée' WHERE id = _ne;
    INSERT INTO news(title, body, author, status) VALUES ('Actu deux équipes', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _nm;
    PERFORM public.save_news_audience(_nm, 'équipe', ARRAY[_team, 'ZZ Test fumée autre']);
    UPDATE news SET status = 'publiée' WHERE id = _nm;

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    INSERT INTO news(title, body, author, status) VALUES ('Brouillon du manager A', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _nd;

    _ids := ARRAY[_n, _nb, _ne, _nm, _nd];
    _with_teams := ARRAY[_n, _nb, _nm];
    -- L'écriture directe dans storage.objects dépend des droits du projet : sans elle, le détail le dit.
    BEGIN
      INSERT INTO storage.objects(bucket_id, name) VALUES ('news-media', _n || '/smoke.png'), ('news-media', _nb || '/smoke.png');
      _with_images := ARRAY[_n, _nb];
    EXCEPTION WHEN insufficient_privilege THEN
      NULL;
    END;

    FOR _reader IN
      SELECT * FROM (VALUES
        ('collaborateur équipe A', 'smoke.collab@test.invalid', ARRAY[_n, _ne, _nm]),
        ('manager équipe A', 'smoke.manager@test.invalid', ARRAY[_n, _ne, _nm, _nd]),
        ('manager équipe B', 'smoke.manager2@test.invalid', ARRAY[_nb, _ne, _nm]),
        ('admin', 'smoke.admin@test.invalid', _ids)
      ) AS v(label, email, ids)
    LOOP
      _want := ARRAY(SELECT unnest(_reader.ids) ORDER BY 1);
      SELECT * INTO _read FROM private.smoke_read_as(_reader.email, _ids);
      _res := _res || jsonb_build_object('t', 'Public des actus : lecture du ' || _reader.label, 'ok',
        _read._news = _want, 'd', cardinality(_read._news) || ' actu(s) lue(s)');
      _res := _res || jsonb_build_object('t', 'Public des actus : équipes ciblées lues par le ' || _reader.label, 'ok',
        _read._teams = ARRAY(SELECT unnest(_want) INTERSECT SELECT unnest(_with_teams) ORDER BY 1),
        'd', cardinality(_read._teams) || ' actu(s)');
      _res := _res || jsonb_build_object('t', 'Public des actus : images lues par le ' || _reader.label, 'ok',
        _read._images = ARRAY(SELECT unnest(_want) INTERSECT SELECT unnest(_with_images) ORDER BY 1),
        'd', CASE WHEN cardinality(_with_images) = 0 THEN 'NON TESTÉ : image de test impossible à créer'
             ELSE cardinality(_read._images) || ' image(s)' END);
    END LOOP;

    -- L'auteur garde ses actus même s'il n'est plus manager de l'équipe ciblée
    PERFORM set_config('request.jwt.claims', '', true);
    UPDATE allowed_user_roles SET role = 'collaborateur' WHERE allowed_user_id = _mgr2;
    DELETE FROM manager_teams WHERE allowed_user_id = _mgr2;
    SELECT * INTO _read FROM private.smoke_read_as('smoke.manager2@test.invalid', _ids);
    _res := _res || jsonb_build_object('t', 'Public des actus : l''auteur lit la sienne même sans rôle manager ni équipe', 'ok',
      _read._news = ARRAY(SELECT unnest(ARRAY[_nb, _ne]) ORDER BY 1), 'd', cardinality(_read._news) || ' actu(s) lue(s)');

    -- Modification d'une actu publiée : écriture réelle sous RLS (voir private.smoke_update_as).
    -- Actus créées dans le passé : dans une transaction, now() ne bouge pas et les dates se confondraient.
    -- Différée comme dans l'application : save_news_audience change le public avant d'écrire les équipes.
    SET CONSTRAINTS check_news_audience DEFERRED;
    PERFORM set_config('request.jwt.claims', '', true);
    INSERT INTO allowed_users(email) VALUES ('smoke.manager3@test.invalid') RETURNING id INTO _mgr3;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_mgr3, 'manager');

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    INSERT INTO news(title, body, author, status, audience, created_at)
    VALUES ('Actu publiée', 'Corps', 'Smoke', 'publiée', 'entreprise', now() - interval '2 days')
    RETURNING id, published_at INTO _np, _pub;

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager3@test.invalid"}', true);
    INSERT INTO news(title, body, author, status, audience, created_at)
    VALUES ('Actu d''un auteur parti', 'Corps', 'Smoke', 'publiée', 'entreprise', now() - interval '2 days')
    RETURNING id INTO _nq;

    SELECT * INTO _try FROM private.smoke_update_as('smoke.manager3@test.invalid', _np, 'Modifiée à tort');
    _res := _res || jsonb_build_object('t', 'Un autre manager ne modifie pas une actu publiée', 'ok',
      _try._rows = 0 AND (SELECT title FROM news WHERE id = _np) = 'Actu publiée', 'd', _try._rows || ' ligne(s)');
    SELECT * INTO _try FROM private.smoke_update_as('smoke.collab@test.invalid', _np, 'Modifiée à tort');
    _res := _res || jsonb_build_object('t', 'Un collaborateur ne modifie pas une actu publiée', 'ok',
      _try._rows = 0 AND (SELECT title FROM news WHERE id = _np) = 'Actu publiée', 'd', _try._rows || ' ligne(s)');

    SELECT * INTO _try FROM private.smoke_update_as('smoke.manager@test.invalid', _np, 'Actu publiée corrigée');
    _res := _res || jsonb_build_object('t', 'Le manager auteur modifie son actu : même date de publication, statut publiée', 'ok',
      _try._rows = 1 AND EXISTS (
        SELECT 1 FROM news WHERE id = _np AND title = 'Actu publiée corrigée' AND status = 'publiée'
          AND published_at = _pub AND updated_at > published_at),
      'd', COALESCE(_try._error, _try._rows || ' ligne(s)'));
    SELECT * INTO _try FROM private.smoke_update_as('smoke.manager@test.invalid', _np, '   ');
    _res := _res || jsonb_build_object('t', 'Une actu publiée ne perd pas son titre', 'ok',
      _try._error IS NOT NULL AND (SELECT title FROM news WHERE id = _np) = 'Actu publiée corrigée', 'd', COALESCE(_try._error, 'accepté à tort'));
    SELECT * INTO _try FROM private.smoke_update_as('smoke.admin@test.invalid', _np, 'Actu corrigée par l''admin');
    _res := _res || jsonb_build_object('t', 'L''admin modifie l''actu d''un manager : auteur et date de publication inchangés', 'ok',
      _try._rows = 1 AND EXISTS (
        SELECT 1 FROM news WHERE id = _np AND title = 'Actu corrigée par l''admin'
          AND author_email = 'smoke.manager@test.invalid' AND published_at = _pub),
      'd', COALESCE(_try._error, _try._rows || ' ligne(s)'));

    BEGIN
      UPDATE news SET author = 'Autre auteur' WHERE id = _np;
      _res := _res || jsonb_build_object('t', 'L''auteur d''une actu publiée ne change pas', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN insufficient_privilege THEN
        _res := _res || jsonb_build_object('t', 'L''auteur d''une actu publiée ne change pas', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'L''auteur d''une actu publiée ne change pas', 'ok', false, 'd', SQLERRM);
    END;

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    BEGIN
      PERFORM public.save_published_news(_np, 'Titre à ne pas garder', 'Corps', '[]', NULL, 'équipe', ARRAY['ZZ Test fumée autre']);
      _res := _res || jsonb_build_object('t', 'Enregistrement refusé : rien ne change, ni le titre ni le public', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN insufficient_privilege THEN
        _res := _res || jsonb_build_object('t', 'Enregistrement refusé : rien ne change, ni le titre ni le public', 'ok',
          EXISTS (SELECT 1 FROM news WHERE id = _np AND title = 'Actu corrigée par l''admin' AND audience = 'entreprise'), 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Enregistrement refusé : rien ne change, ni le titre ni le public', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      PERFORM public.save_published_news(_np, 'Titre et public', 'Corps', '[]', 'autre-actu/image.png', 'entreprise');
      _res := _res || jsonb_build_object('t', 'Une actu ne reprend pas l''image d''une autre', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN check_violation THEN
      _res := _res || jsonb_build_object('t', 'Une actu ne reprend pas l''image d''une autre', 'ok', true, 'd', 'refusé par la base');
    END;
    PERFORM public.save_published_news(_np, 'Titre et public', 'Corps', '[]', NULL, 'équipe', ARRAY[_team]);
    _res := _res || jsonb_build_object('t', 'Enregistrement accepté : le titre et le public changent ensemble', 'ok',
      EXISTS (SELECT 1 FROM news n JOIN news_teams t ON t.news_id = n.id
              WHERE n.id = _np AND n.title = 'Titre et public' AND n.audience = 'équipe' AND t.team = _team), 'd', 'équipe');

    -- Auteur parti : il perd d'abord son rôle, puis son compte. L'anonymisation ne compte pas comme une modification.
    PERFORM set_config('request.jwt.claims', '', true);
    UPDATE allowed_user_roles SET role = 'collaborateur' WHERE allowed_user_id = _mgr3;
    SELECT * INTO _try FROM private.smoke_update_as('smoke.manager3@test.invalid', _nq, 'Modifiée à tort');
    _res := _res || jsonb_build_object('t', 'L''auteur qui n''est plus manager ne modifie plus son actu', 'ok', _try._rows = 0, 'd', _try._rows || ' ligne(s)');
    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      DELETE FROM allowed_users WHERE id = _mgr3;
      _res := _res || jsonb_build_object('t', 'Compte supprimé : auteur anonymisé, sans mention « Modifiée le »', 'ok',
        EXISTS (SELECT 1 FROM news WHERE id = _nq AND author = 'Utilisateur supprimé' AND updated_at = published_at), 'd', 'Utilisateur supprimé');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Compte supprimé : auteur anonymisé, sans mention « Modifiée le »', 'ok', false, 'd', SQLERRM);
    END;
    SELECT * INTO _try FROM private.smoke_update_as('smoke.admin@test.invalid', _nq, 'Actu reprise par l''admin');
    _res := _res || jsonb_build_object('t', 'Auteur supprimé : l''admin modifie encore l''actu', 'ok', _try._rows = 1, 'd', COALESCE(_try._error, _try._rows || ' ligne(s)'));

    -- Référentiel des équipes
    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      UPDATE teams SET name = 'ZZ Test fumée 2' WHERE name = _team;
      _res := _res || jsonb_build_object('t', 'Référentiel : renommer une équipe met à jour utilisateurs, managers et demandes', 'ok',
        (SELECT team FROM allowed_users WHERE id = _collab) = 'ZZ Test fumée 2'
        AND (SELECT team FROM manager_teams WHERE allowed_user_id = _mgr) = 'ZZ Test fumée 2'
        AND (SELECT team FROM submissions WHERE id = _s1) = 'ZZ Test fumée 2', 'd', 'ZZ Test fumée 2');
      _res := _res || jsonb_build_object('t', 'Référentiel : renommer une équipe met à jour le public des actus', 'ok',
        (SELECT team FROM news_teams WHERE news_id = _n) = 'ZZ Test fumée 2', 'd', 'ZZ Test fumée 2');
      _team := 'ZZ Test fumée 2';
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Référentiel : renommer une équipe met à jour utilisateurs, managers et demandes', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      DELETE FROM teams WHERE name = _team;
      _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN foreign_key_violation THEN
        _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', false, 'd', SQLERRM);
    END;

    RAISE EXCEPTION 'HP_SMOKE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'HP_SMOKE_ROLLBACK' THEN
      _res := _res || jsonb_build_object('t', 'Exécution du test de fumée', 'ok', false, 'd', 'Erreur inattendue : ' || SQLERRM);
    END IF;
  END;

  SELECT count(*) INTO _cnt FROM private.audit_enum_literals();
  _res := _res || jsonb_build_object('t', 'Aucune valeur d''ENUM obsolète dans les fonctions', 'ok', _cnt = 0, 'd', _cnt || ' anomalie(s)');

  RETURN QUERY SELECT x->>'t', (x->>'ok')::boolean, x->>'d' FROM jsonb_array_elements(_res) x;
END;
$function$;

DO $$
DECLARE _bad text;
BEGIN
  SELECT string_agg(test || ' : ' || COALESCE(detail, ''), ' | ') INTO _bad FROM private.run_smoke_tests() WHERE NOT ok;
  IF _bad IS NOT NULL THEN
    RAISE EXCEPTION 'Smoke tests failed: %', _bad;
  END IF;
END $$;
COMMIT;

-- ---------- 20261102120000_centre_de_notifications.sql ----------
BEGIN;
-- Centre de notifications (US12). La base crée les notifications, jamais l'interface.
-- Les US13 à US16 ajouteront leurs valeurs à l'enum et leurs cas à private.notify_submission_event.

CREATE TYPE public.notification_kind AS ENUM ('nouvelle_demande');

CREATE TABLE public.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_email text NOT NULL,
  kind public.notification_kind NOT NULL,
  submission_id uuid REFERENCES public.submissions(id) ON DELETE SET NULL,
  blocker_id uuid REFERENCES public.blockers(id) ON DELETE SET NULL,
  -- Texte figé à la création : il reste affichable quand la demande n'est plus lisible.
  message text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  read_at timestamptz
);
CREATE INDEX notifications_recipient_created_idx ON public.notifications (recipient_email, created_at);

-- Aucune insertion ni suppression par authenticated ; seule la colonne read_at est modifiable.
-- REVOKE d'abord : Supabase donne par défaut tous les droits sur une nouvelle table.
REVOKE ALL ON public.notifications FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.notifications TO authenticated;
GRANT UPDATE (read_at) ON public.notifications TO authenticated;
GRANT ALL ON public.notifications TO service_role;

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Recipients read own notifications" ON public.notifications
  FOR SELECT TO authenticated
  USING (private.is_allowed() AND recipient_email = lower(auth.jwt() ->> 'email'));

CREATE POLICY "Recipients mark own notifications as read" ON public.notifications
  FOR UPDATE TO authenticated
  USING (private.is_allowed() AND recipient_email = lower(auth.jwt() ->> 'email'))
  WITH CHECK (private.is_allowed() AND recipient_email = lower(auth.jwt() ->> 'email'));

ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;

-- Une demande créée notifie les managers de son équipe, sauf son auteur. old_status vide = création.
CREATE OR REPLACE FUNCTION private.notify_submission_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  IF NEW.old_status IS NULL THEN
    INSERT INTO public.notifications (recipient_email, kind, submission_id, message)
    SELECT lower(u.email),
           'nouvelle_demande'::public.notification_kind,
           s.id,
           format('Nouvelle demande de %s (%s)', s.author_name, s.team)
      FROM public.submissions s
      JOIN public.manager_teams mt ON mt.team = s.team
      JOIN public.allowed_users u ON u.id = mt.allowed_user_id
      JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id
     WHERE s.id = NEW.submission_id
       AND r.role = 'manager'::public.app_role
       AND lower(u.email) IS DISTINCT FROM lower(s.submitted_by_email);
  END IF;
  RETURN NEW;
END
$function$;

CREATE TRIGGER notify_submission_event
  AFTER INSERT ON public.submission_status_history
  FOR EACH ROW EXECUTE FUNCTION private.notify_submission_event();

-- Purge quotidienne des notifications de plus de 30 jours.
CREATE OR REPLACE FUNCTION private.purge_notifications()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
  DELETE FROM public.notifications WHERE created_at < now() - interval '30 days';
$function$;

REVOKE ALL ON FUNCTION private.purge_notifications() FROM PUBLIC, anon, authenticated;

SELECT cron.schedule('purge-notifications-daily', '30 3 * * *', 'SELECT private.purge_notifications()');

-- Compte supprimé : ses notifications disparaissent et son nom sort des messages des autres.
CREATE OR REPLACE FUNCTION private.anonymize_removed_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'private' AS $function$
DECLARE _planned boolean := OLD.departure_date IS NOT NULL AND OLD.departure_date <= current_date;
BEGIN
  INSERT INTO public.attachment_deletion_queue (path, delete_after)
  SELECT attachment_path, CASE WHEN _planned THEN now() ELSE now() + interval '7 days' END
    FROM public.submissions
   WHERE lower(submitted_by_email) = lower(OLD.email) AND attachment_path IS NOT NULL
  ON CONFLICT (path) DO NOTHING;

  IF _planned THEN
    UPDATE public.departure_notices SET closed_at = now(), departing_label = 'Utilisateur supprimé'
     WHERE departing_user_id = OLD.id AND closed_at IS NULL;
  ELSE
    PERFORM private.notify_departure(OLD.id, OLD.email, OLD.team, current_date, 'sans préavis');
  END IF;

  DELETE FROM public.notifications WHERE recipient_email = lower(OLD.email);
  UPDATE public.notifications n
     SET message = format('Nouvelle demande de %s (%s)', 'Utilisateur supprimé', s.team)
    FROM public.submissions s
   WHERE n.submission_id = s.id
     AND n.kind = 'nouvelle_demande'::public.notification_kind
     AND lower(s.submitted_by_email) = lower(OLD.email);

  UPDATE public.submissions
     SET author_name = 'Utilisateur supprimé', submitted_by_email = 'Utilisateur supprimé'
   WHERE lower(submitted_by_email) = lower(OLD.email);
  UPDATE public.news
     SET author = 'Utilisateur supprimé', author_email = 'Utilisateur supprimé'
   WHERE lower(author_email) = lower(OLD.email);
  UPDATE public.submission_status_history
     SET changed_by_name = 'Utilisateur supprimé', changed_by_email = 'Utilisateur supprimé'
   WHERE lower(changed_by_email) = lower(OLD.email);
  RETURN OLD;
END $function$;

-- Lit, puis tente d'écrire une notification sous le rôle authenticated, donc sous RLS.
-- Le propriétaire des tables contourne la RLS : un simple SELECT ne prouverait rien.
CREATE OR REPLACE FUNCTION private.smoke_notification_as(
  _email text,
  _id uuid,
  OUT _visible int,
  OUT _marked int,
  OUT _denied int
)
LANGUAGE plpgsql
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  _denied := 0;
  PERFORM set_config('request.jwt.claims', json_build_object('email', _email)::text, true);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO _visible FROM public.notifications WHERE id = _id;
  UPDATE public.notifications SET read_at = now() WHERE id = _id;
  GET DIAGNOSTICS _marked = ROW_COUNT;
  BEGIN
    UPDATE public.notifications SET message = 'Modifiée à tort' WHERE id = _id;
  EXCEPTION WHEN insufficient_privilege THEN
    _denied := _denied + 1;
  END;
  BEGIN
    INSERT INTO public.notifications (recipient_email, kind, message)
    VALUES (_email, 'nouvelle_demande', 'Créée à tort');
  EXCEPTION WHEN insufficient_privilege THEN
    _denied := _denied + 1;
  END;
  BEGIN
    DELETE FROM public.notifications WHERE id = _id;
  EXCEPTION WHEN insufficient_privilege THEN
    _denied := _denied + 1;
  END;
  RESET ROLE;
END
$function$;

REVOKE ALL ON FUNCTION private.smoke_notification_as(text, uuid) FROM PUBLIC, anon, authenticated;

-- Test de fumée mis à jour pour ces règles
CREATE OR REPLACE FUNCTION private.run_smoke_tests()
 RETURNS TABLE(test text, ok boolean, detail text)
 LANGUAGE plpgsql
 SECURITY INVOKER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _res jsonb := '[]'::jsonb;
  _collab uuid; _mgr uuid; _adm uuid;
  _s1 uuid; _s2 uuid; _b uuid; _n uuid;
  _st text; _cnt int; _err text;
  _team text := 'ZZ Test fumée';
  _mgr2 uuid; _nb uuid; _ne uuid; _nm uuid; _nd uuid;
  _ids uuid[]; _with_teams uuid[]; _with_images uuid[] := '{}';
  _reader record; _read record; _want uuid[];
  _mgr3 uuid; _np uuid; _nq uuid; _pub timestamptz; _try record;
  _collab2 uuid; _s3 uuid; _s4 uuid; _notif uuid; _notif_try record; _emails text[];
BEGIN
  BEGIN
    INSERT INTO teams(name) VALUES (_team), ('ZZ Test fumée autre') ON CONFLICT DO NOTHING;
    INSERT INTO allowed_users(email, team) VALUES ('smoke.collab@test.invalid', _team) RETURNING id INTO _collab;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_collab, 'collaborateur');
    INSERT INTO allowed_users(email) VALUES ('smoke.manager@test.invalid') RETURNING id INTO _mgr;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_mgr, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_mgr, _team);
    INSERT INTO allowed_users(email) VALUES ('smoke.admin@test.invalid') RETURNING id INTO _adm;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_adm, 'admin');

    -- Collaborateur : soumission
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 1') RETURNING id, status::text INTO _s1, _st;
    _res := _res || jsonb_build_object('t', 'Soumission créée « en attente », dans l''équipe du collaborateur',
      'ok', _st = 'en attente' AND (SELECT team FROM submissions WHERE id = _s1) = _team, 'd', _st);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 2') RETURNING id INTO _s2;

    -- Manager : validation et refus
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    BEGIN
      UPDATE submissions SET status = 'validée' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager valide une demande en attente', 'ok', true, 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager valide une demande en attente', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'refusée', rejection_category = 'doublon', rejection_note = 'Test' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager refuse une demande avec un motif', 'ok', true, 'd', 'refusée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager refuse une demande avec un motif', 'ok', false, 'd', SQLERRM);
    END;
    -- Le manager change le statut librement, autant de fois que nécessaire (erreurs humaines)
    BEGIN
      UPDATE submissions SET status = 'clôturée' WHERE id = _s1;
      UPDATE submissions SET status = 'validée' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager corrige une clôture par erreur (clôturée puis validée)', 'ok',
        (SELECT status::text FROM submissions WHERE id = _s1) = 'validée', 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager corrige une clôture par erreur (clôturée puis validée)', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'validée' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager passe un refus en validée, le motif est effacé', 'ok',
        (SELECT rejection_category IS NULL AND rejection_note IS NULL FROM submissions WHERE id = _s2), 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager passe un refus en validée, le motif est effacé', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'en attente' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager remet une demande « en attente »', 'ok', true, 'd', 'en attente');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager remet une demande « en attente »', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET content = 'Contenu modifié par le manager' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager ne peut pas modifier le contenu d''une demande', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager ne peut pas modifier le contenu d''une demande', 'ok', true, 'd', 'refusé par la base');
    END;
    SELECT count(*) INTO _cnt FROM submission_status_history WHERE submission_id IN (_s1, _s2);
    _res := _res || jsonb_build_object('t', 'Historique : 8 lignes (2 créations, 6 changements de statut)', 'ok', _cnt = 8, 'd', _cnt || ' ligne(s)');

    -- Clôture automatique après un an sans modification
    PERFORM set_config('request.jwt.claims', '', true);
    UPDATE submissions SET revalidate_at = now() - interval '1 day' WHERE id = _s1;
    PERFORM private.expire_revalidations();
    SELECT status::text INTO _st FROM submissions WHERE id = _s1;
    _res := _res || jsonb_build_object('t', 'Clôture automatique : une demande validée échue passe « clôturée »', 'ok', _st = 'clôturée', 'd', _st);
    _res := _res || jsonb_build_object('t', 'Clôture automatique : l''historique la marque « Automatique »', 'ok',
      EXISTS (SELECT 1 FROM submission_status_history WHERE submission_id = _s1 AND new_status = 'clôturée' AND is_automatic), 'd', _st);

    -- Points bloquants
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.admin@test.invalid"}', true);
    INSERT INTO blockers(title, department) VALUES ('Blocage de test', 'Test') RETURNING id, status::text INTO _b, _st;
    _res := _res || jsonb_build_object('t', 'Point bloquant créé au statut OUVERT', 'ok', _st = 'OUVERT', 'd', _st);
    BEGIN
      UPDATE blockers SET status = 'RÉSOLU' WHERE id = _b;
      _res := _res || jsonb_build_object('t', 'OUVERT → RÉSOLU refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'OUVERT → RÉSOLU refusé', 'ok', true, 'd', 'refusé par la base');
    END;
    BEGIN
      UPDATE blockers SET status = 'EN COURS' WHERE id = _b;
      UPDATE blockers SET status = 'SURVEILLANCE' WHERE id = _b;
      UPDATE blockers SET status = 'RÉSOLU' WHERE id = _b;
      _res := _res || jsonb_build_object('t', 'OUVERT → EN COURS → SURVEILLANCE → RÉSOLU accepté', 'ok', true, 'd', 'RÉSOLU');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'OUVERT → EN COURS → SURVEILLANCE → RÉSOLU accepté', 'ok', false, 'd', SQLERRM);
    END;

    -- Actualités
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    -- Différée, la contrainte ne se déclencherait qu'au COMMIT, jamais atteint dans ce test.
    SET CONSTRAINTS check_news_audience IMMEDIATE;
    INSERT INTO news(title, body, author, status) VALUES ('Actu de test', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _n;
    BEGIN
      UPDATE news SET status = 'publiée' WHERE id = _n;
      _res := _res || jsonb_build_object('t', 'Publier une actu sans public est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN check_violation THEN
        _res := _res || jsonb_build_object('t', 'Publier une actu sans public est refusé', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Publier une actu sans public est refusé', 'ok', false, 'd', SQLERRM);
    END;
    UPDATE news SET audience = 'équipe' WHERE id = _n;
    BEGIN
      UPDATE news SET status = 'publiée' WHERE id = _n;
      _res := _res || jsonb_build_object('t', 'Publier une actu « équipe » sans équipe est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN check_violation THEN
        _res := _res || jsonb_build_object('t', 'Publier une actu « équipe » sans équipe est refusé', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Publier une actu « équipe » sans équipe est refusé', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      PERFORM public.save_news_audience(_n, 'équipe', ARRAY['ZZ Test fumée autre']);
      _res := _res || jsonb_build_object('t', 'Un manager ne cible pas une équipe qui n''est pas la sienne', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN insufficient_privilege THEN
        _res := _res || jsonb_build_object('t', 'Un manager ne cible pas une équipe qui n''est pas la sienne', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Un manager ne cible pas une équipe qui n''est pas la sienne', 'ok', false, 'd', SQLERRM);
    END;
    PERFORM public.save_news_audience(_n, 'équipe', ARRAY[_team]);
    UPDATE news SET status = 'publiée' WHERE id = _n;
    PERFORM private.expire_revalidations();
    SELECT status::text INTO _st FROM news WHERE id = _n;
    _res := _res || jsonb_build_object('t', 'Actualité : brouillon puis publiée, elle reste publiée après la tâche quotidienne', 'ok', _st = 'publiée', 'd', _st);
    BEGIN
      UPDATE news SET status = 'brouillon' WHERE id = _n;
      _res := _res || jsonb_build_object('t', 'Une actu publiée ne repasse pas en brouillon', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Une actu publiée ne repasse pas en brouillon', 'ok', true, 'd', 'refusé par la base');
    END;
    UPDATE news SET title = 'Actu de test corrigée' WHERE id = _n;
    SELECT status::text INTO _st FROM news WHERE id = _n;
    _res := _res || jsonb_build_object('t', 'Une actu publiée reste modifiable et reste publiée', 'ok', _st = 'publiée', 'd', _st);

    -- Public des actus : lecture réelle sous RLS (voir private.smoke_read_as)
    PERFORM set_config('request.jwt.claims', '', true);
    INSERT INTO allowed_users(email) VALUES ('smoke.manager2@test.invalid') RETURNING id INTO _mgr2;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_mgr2, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_mgr2, 'ZZ Test fumée autre');

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager2@test.invalid"}', true);
    INSERT INTO news(title, body, author, status) VALUES ('Actu équipe B', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _nb;
    PERFORM public.save_news_audience(_nb, 'équipe', ARRAY['ZZ Test fumée autre']);
    UPDATE news SET status = 'publiée' WHERE id = _nb;

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.admin@test.invalid"}', true);
    INSERT INTO news(title, body, author, status) VALUES ('Actu entreprise', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _ne;
    PERFORM public.save_news_audience(_ne, 'entreprise');
    UPDATE news SET status = 'publiée' WHERE id = _ne;
    INSERT INTO news(title, body, author, status) VALUES ('Actu deux équipes', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _nm;
    PERFORM public.save_news_audience(_nm, 'équipe', ARRAY[_team, 'ZZ Test fumée autre']);
    UPDATE news SET status = 'publiée' WHERE id = _nm;

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    INSERT INTO news(title, body, author, status) VALUES ('Brouillon du manager A', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _nd;

    _ids := ARRAY[_n, _nb, _ne, _nm, _nd];
    _with_teams := ARRAY[_n, _nb, _nm];
    -- L'écriture directe dans storage.objects dépend des droits du projet : sans elle, le détail le dit.
    BEGIN
      INSERT INTO storage.objects(bucket_id, name) VALUES ('news-media', _n || '/smoke.png'), ('news-media', _nb || '/smoke.png');
      _with_images := ARRAY[_n, _nb];
    EXCEPTION WHEN insufficient_privilege THEN
      NULL;
    END;

    FOR _reader IN
      SELECT * FROM (VALUES
        ('collaborateur équipe A', 'smoke.collab@test.invalid', ARRAY[_n, _ne, _nm]),
        ('manager équipe A', 'smoke.manager@test.invalid', ARRAY[_n, _ne, _nm, _nd]),
        ('manager équipe B', 'smoke.manager2@test.invalid', ARRAY[_nb, _ne, _nm]),
        ('admin', 'smoke.admin@test.invalid', _ids)
      ) AS v(label, email, ids)
    LOOP
      _want := ARRAY(SELECT unnest(_reader.ids) ORDER BY 1);
      SELECT * INTO _read FROM private.smoke_read_as(_reader.email, _ids);
      _res := _res || jsonb_build_object('t', 'Public des actus : lecture du ' || _reader.label, 'ok',
        _read._news = _want, 'd', cardinality(_read._news) || ' actu(s) lue(s)');
      _res := _res || jsonb_build_object('t', 'Public des actus : équipes ciblées lues par le ' || _reader.label, 'ok',
        _read._teams = ARRAY(SELECT unnest(_want) INTERSECT SELECT unnest(_with_teams) ORDER BY 1),
        'd', cardinality(_read._teams) || ' actu(s)');
      _res := _res || jsonb_build_object('t', 'Public des actus : images lues par le ' || _reader.label, 'ok',
        _read._images = ARRAY(SELECT unnest(_want) INTERSECT SELECT unnest(_with_images) ORDER BY 1),
        'd', CASE WHEN cardinality(_with_images) = 0 THEN 'NON TESTÉ : image de test impossible à créer'
             ELSE cardinality(_read._images) || ' image(s)' END);
    END LOOP;

    -- L'auteur garde ses actus même s'il n'est plus manager de l'équipe ciblée
    PERFORM set_config('request.jwt.claims', '', true);
    UPDATE allowed_user_roles SET role = 'collaborateur' WHERE allowed_user_id = _mgr2;
    DELETE FROM manager_teams WHERE allowed_user_id = _mgr2;
    SELECT * INTO _read FROM private.smoke_read_as('smoke.manager2@test.invalid', _ids);
    _res := _res || jsonb_build_object('t', 'Public des actus : l''auteur lit la sienne même sans rôle manager ni équipe', 'ok',
      _read._news = ARRAY(SELECT unnest(ARRAY[_nb, _ne]) ORDER BY 1), 'd', cardinality(_read._news) || ' actu(s) lue(s)');

    -- Modification d'une actu publiée : écriture réelle sous RLS (voir private.smoke_update_as).
    -- Actus créées dans le passé : dans une transaction, now() ne bouge pas et les dates se confondraient.
    -- Différée comme dans l'application : save_news_audience change le public avant d'écrire les équipes.
    SET CONSTRAINTS check_news_audience DEFERRED;
    PERFORM set_config('request.jwt.claims', '', true);
    INSERT INTO allowed_users(email) VALUES ('smoke.manager3@test.invalid') RETURNING id INTO _mgr3;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_mgr3, 'manager');

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    INSERT INTO news(title, body, author, status, audience, created_at)
    VALUES ('Actu publiée', 'Corps', 'Smoke', 'publiée', 'entreprise', now() - interval '2 days')
    RETURNING id, published_at INTO _np, _pub;

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager3@test.invalid"}', true);
    INSERT INTO news(title, body, author, status, audience, created_at)
    VALUES ('Actu d''un auteur parti', 'Corps', 'Smoke', 'publiée', 'entreprise', now() - interval '2 days')
    RETURNING id INTO _nq;

    SELECT * INTO _try FROM private.smoke_update_as('smoke.manager3@test.invalid', _np, 'Modifiée à tort');
    _res := _res || jsonb_build_object('t', 'Un autre manager ne modifie pas une actu publiée', 'ok',
      _try._rows = 0 AND (SELECT title FROM news WHERE id = _np) = 'Actu publiée', 'd', _try._rows || ' ligne(s)');
    SELECT * INTO _try FROM private.smoke_update_as('smoke.collab@test.invalid', _np, 'Modifiée à tort');
    _res := _res || jsonb_build_object('t', 'Un collaborateur ne modifie pas une actu publiée', 'ok',
      _try._rows = 0 AND (SELECT title FROM news WHERE id = _np) = 'Actu publiée', 'd', _try._rows || ' ligne(s)');

    SELECT * INTO _try FROM private.smoke_update_as('smoke.manager@test.invalid', _np, 'Actu publiée corrigée');
    _res := _res || jsonb_build_object('t', 'Le manager auteur modifie son actu : même date de publication, statut publiée', 'ok',
      _try._rows = 1 AND EXISTS (
        SELECT 1 FROM news WHERE id = _np AND title = 'Actu publiée corrigée' AND status = 'publiée'
          AND published_at = _pub AND updated_at > published_at),
      'd', COALESCE(_try._error, _try._rows || ' ligne(s)'));
    SELECT * INTO _try FROM private.smoke_update_as('smoke.manager@test.invalid', _np, '   ');
    _res := _res || jsonb_build_object('t', 'Une actu publiée ne perd pas son titre', 'ok',
      _try._error IS NOT NULL AND (SELECT title FROM news WHERE id = _np) = 'Actu publiée corrigée', 'd', COALESCE(_try._error, 'accepté à tort'));
    SELECT * INTO _try FROM private.smoke_update_as('smoke.admin@test.invalid', _np, 'Actu corrigée par l''admin');
    _res := _res || jsonb_build_object('t', 'L''admin modifie l''actu d''un manager : auteur et date de publication inchangés', 'ok',
      _try._rows = 1 AND EXISTS (
        SELECT 1 FROM news WHERE id = _np AND title = 'Actu corrigée par l''admin'
          AND author_email = 'smoke.manager@test.invalid' AND published_at = _pub),
      'd', COALESCE(_try._error, _try._rows || ' ligne(s)'));

    BEGIN
      UPDATE news SET author = 'Autre auteur' WHERE id = _np;
      _res := _res || jsonb_build_object('t', 'L''auteur d''une actu publiée ne change pas', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN insufficient_privilege THEN
        _res := _res || jsonb_build_object('t', 'L''auteur d''une actu publiée ne change pas', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'L''auteur d''une actu publiée ne change pas', 'ok', false, 'd', SQLERRM);
    END;

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    BEGIN
      PERFORM public.save_published_news(_np, 'Titre à ne pas garder', 'Corps', '[]', NULL, 'équipe', ARRAY['ZZ Test fumée autre']);
      _res := _res || jsonb_build_object('t', 'Enregistrement refusé : rien ne change, ni le titre ni le public', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN insufficient_privilege THEN
        _res := _res || jsonb_build_object('t', 'Enregistrement refusé : rien ne change, ni le titre ni le public', 'ok',
          EXISTS (SELECT 1 FROM news WHERE id = _np AND title = 'Actu corrigée par l''admin' AND audience = 'entreprise'), 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Enregistrement refusé : rien ne change, ni le titre ni le public', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      PERFORM public.save_published_news(_np, 'Titre et public', 'Corps', '[]', 'autre-actu/image.png', 'entreprise');
      _res := _res || jsonb_build_object('t', 'Une actu ne reprend pas l''image d''une autre', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN check_violation THEN
      _res := _res || jsonb_build_object('t', 'Une actu ne reprend pas l''image d''une autre', 'ok', true, 'd', 'refusé par la base');
    END;
    PERFORM public.save_published_news(_np, 'Titre et public', 'Corps', '[]', NULL, 'équipe', ARRAY[_team]);
    _res := _res || jsonb_build_object('t', 'Enregistrement accepté : le titre et le public changent ensemble', 'ok',
      EXISTS (SELECT 1 FROM news n JOIN news_teams t ON t.news_id = n.id
              WHERE n.id = _np AND n.title = 'Titre et public' AND n.audience = 'équipe' AND t.team = _team), 'd', 'équipe');

    -- Auteur parti : il perd d'abord son rôle, puis son compte. L'anonymisation ne compte pas comme une modification.
    PERFORM set_config('request.jwt.claims', '', true);
    UPDATE allowed_user_roles SET role = 'collaborateur' WHERE allowed_user_id = _mgr3;
    SELECT * INTO _try FROM private.smoke_update_as('smoke.manager3@test.invalid', _nq, 'Modifiée à tort');
    _res := _res || jsonb_build_object('t', 'L''auteur qui n''est plus manager ne modifie plus son actu', 'ok', _try._rows = 0, 'd', _try._rows || ' ligne(s)');
    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      DELETE FROM allowed_users WHERE id = _mgr3;
      _res := _res || jsonb_build_object('t', 'Compte supprimé : auteur anonymisé, sans mention « Modifiée le »', 'ok',
        EXISTS (SELECT 1 FROM news WHERE id = _nq AND author = 'Utilisateur supprimé' AND updated_at = published_at), 'd', 'Utilisateur supprimé');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Compte supprimé : auteur anonymisé, sans mention « Modifiée le »', 'ok', false, 'd', SQLERRM);
    END;
    SELECT * INTO _try FROM private.smoke_update_as('smoke.admin@test.invalid', _nq, 'Actu reprise par l''admin');
    _res := _res || jsonb_build_object('t', 'Auteur supprimé : l''admin modifie encore l''actu', 'ok', _try._rows = 1, 'd', COALESCE(_try._error, _try._rows || ' ligne(s)'));

    -- Centre de notifications : destinataires, puis droits réels sous RLS (voir private.smoke_notification_as).
    -- L'admin a une ligne dans manager_teams pour prouver que le rôle est bien contrôlé.
    PERFORM set_config('request.jwt.claims', '', true);
    -- Le second manager a perdu son rôle et son équipe dans le test « l'auteur lit la sienne ».
    UPDATE allowed_user_roles SET role = 'manager' WHERE allowed_user_id = _mgr2;
    INSERT INTO allowed_users(email, team) VALUES ('smoke.collab2@test.invalid', _team) RETURNING id INTO _collab2;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_collab2, 'collaborateur');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_mgr2, _team), (_adm, _team);

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab2@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 3') RETURNING id INTO _s3;
    SELECT COALESCE(array_agg(recipient_email), '{}') INTO _emails FROM notifications WHERE submission_id = _s3;
    _res := _res || jsonb_build_object('t', 'Une demande créée notifie les managers de son équipe', 'ok',
      _emails @> ARRAY['smoke.manager@test.invalid', 'smoke.manager2@test.invalid'], 'd', array_to_string(_emails, ', '));
    _res := _res || jsonb_build_object('t', 'Une demande créée ne notifie ni son auteur ni un admin', 'ok',
      NOT _emails && ARRAY['smoke.collab2@test.invalid', 'smoke.admin@test.invalid'], 'd', array_to_string(_emails, ', '));
    _res := _res || jsonb_build_object('t', 'Le texte de la notification nomme l''auteur et l''équipe', 'ok',
      EXISTS (SELECT 1 FROM notifications n JOIN submissions s ON s.id = n.submission_id
              WHERE s.id = _s3 AND n.kind = 'nouvelle_demande'
                AND n.message = format('Nouvelle demande de %s (%s)', s.author_name, s.team)), 'd', _team);

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', _team, 'Demande de test 4') RETURNING id INTO _s4;
    SELECT COALESCE(array_agg(recipient_email), '{}') INTO _emails FROM notifications WHERE submission_id = _s4;
    _res := _res || jsonb_build_object('t', 'Un manager n''est pas notifié de sa propre demande', 'ok',
      _emails = ARRAY['smoke.manager2@test.invalid'], 'd', array_to_string(_emails, ', '));

    SELECT id INTO _notif FROM notifications WHERE submission_id = _s3 AND recipient_email = 'smoke.manager@test.invalid';
    SELECT * INTO _notif_try FROM private.smoke_notification_as('smoke.manager2@test.invalid', _notif);
    _res := _res || jsonb_build_object('t', 'Un utilisateur ne lit ni ne marque les notifications d''un autre', 'ok',
      _notif_try._visible = 0 AND _notif_try._marked = 0
      AND (SELECT read_at FROM notifications WHERE id = _notif) IS NULL,
      'd', _notif_try._visible || ' lue(s), ' || _notif_try._marked || ' marquée(s)');
    SELECT * INTO _notif_try FROM private.smoke_notification_as('smoke.manager@test.invalid', _notif);
    _res := _res || jsonb_build_object('t', 'Le destinataire lit sa notification et la marque comme lue', 'ok',
      _notif_try._visible = 1 AND _notif_try._marked = 1
      AND (SELECT read_at FROM notifications WHERE id = _notif) IS NOT NULL,
      'd', _notif_try._visible || ' lue(s), ' || _notif_try._marked || ' marquée(s)');
    _res := _res || jsonb_build_object('t', 'Seul read_at est modifiable : ni autre colonne, ni création, ni suppression', 'ok',
      _notif_try._denied = 3 AND EXISTS (SELECT 1 FROM notifications WHERE id = _notif AND message <> 'Modifiée à tort'),
      'd', _notif_try._denied || ' écriture(s) refusée(s) sur 3');

    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      DELETE FROM allowed_users WHERE id IN (_collab2, _mgr2);
      _res := _res || jsonb_build_object('t', 'Compte supprimé : son nom sort des messages, ses notifications disparaissent', 'ok',
        EXISTS (SELECT 1 FROM notifications WHERE id = _notif
                AND message = format('Nouvelle demande de Utilisateur supprimé (%s)', _team))
        AND NOT EXISTS (SELECT 1 FROM notifications WHERE recipient_email = 'smoke.manager2@test.invalid'),
        'd', 'Utilisateur supprimé');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Compte supprimé : son nom sort des messages, ses notifications disparaissent', 'ok', false, 'd', SQLERRM);
    END;
    DELETE FROM manager_teams WHERE allowed_user_id = _adm;

    INSERT INTO notifications(recipient_email, kind, message, created_at) VALUES
      ('smoke.manager@test.invalid', 'nouvelle_demande', 'Ancienne', now() - interval '31 days'),
      ('smoke.manager@test.invalid', 'nouvelle_demande', 'Récente', now() - interval '29 days');
    PERFORM private.purge_notifications();
    _res := _res || jsonb_build_object('t', 'La purge efface les notifications de plus de 30 jours, pas les autres', 'ok',
      NOT EXISTS (SELECT 1 FROM notifications WHERE message = 'Ancienne')
      AND EXISTS (SELECT 1 FROM notifications WHERE message = 'Récente'), 'd', '30 jours');

    -- Référentiel des équipes
    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      UPDATE teams SET name = 'ZZ Test fumée 2' WHERE name = _team;
      _res := _res || jsonb_build_object('t', 'Référentiel : renommer une équipe met à jour utilisateurs, managers et demandes', 'ok',
        (SELECT team FROM allowed_users WHERE id = _collab) = 'ZZ Test fumée 2'
        AND (SELECT team FROM manager_teams WHERE allowed_user_id = _mgr) = 'ZZ Test fumée 2'
        AND (SELECT team FROM submissions WHERE id = _s1) = 'ZZ Test fumée 2', 'd', 'ZZ Test fumée 2');
      _res := _res || jsonb_build_object('t', 'Référentiel : renommer une équipe met à jour le public des actus', 'ok',
        (SELECT team FROM news_teams WHERE news_id = _n) = 'ZZ Test fumée 2', 'd', 'ZZ Test fumée 2');
      _team := 'ZZ Test fumée 2';
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Référentiel : renommer une équipe met à jour utilisateurs, managers et demandes', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      DELETE FROM teams WHERE name = _team;
      _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN foreign_key_violation THEN
        _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', false, 'd', SQLERRM);
    END;

    RAISE EXCEPTION 'HP_SMOKE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'HP_SMOKE_ROLLBACK' THEN
      _res := _res || jsonb_build_object('t', 'Exécution du test de fumée', 'ok', false, 'd', 'Erreur inattendue : ' || SQLERRM);
    END IF;
  END;

  SELECT count(*) INTO _cnt FROM private.audit_enum_literals();
  _res := _res || jsonb_build_object('t', 'Aucune valeur d''ENUM obsolète dans les fonctions', 'ok', _cnt = 0, 'd', _cnt || ' anomalie(s)');

  RETURN QUERY SELECT x->>'t', (x->>'ok')::boolean, x->>'d' FROM jsonb_array_elements(_res) x;
END;
$function$;

DO $$
DECLARE _bad text;
BEGIN
  SELECT string_agg(test || ' : ' || COALESCE(detail, ''), ' | ') INTO _bad FROM private.run_smoke_tests() WHERE NOT ok;
  IF _bad IS NOT NULL THEN
    RAISE EXCEPTION 'Smoke tests failed: %', _bad;
  END IF;
END $$;
COMMIT;

-- ---------- 20261103090000_types_de_notification.sql ----------
BEGIN;
-- Préférences de notification (US13) : nouveaux types de notification.
-- Séparé de la migration suivante : une valeur d'ENUM ajoutée ne peut pas être
-- utilisée dans la même transaction.
-- 'resume_hebdo' ne crée aucune notification dans l'app : il sert seulement à enregistrer le choix « Par mail ».
ALTER TYPE public.notification_kind ADD VALUE IF NOT EXISTS 'changement_statut';
ALTER TYPE public.notification_kind ADD VALUE IF NOT EXISTS 'resume_hebdo';
COMMIT;

-- ---------- 20261103090100_preferences_de_notification.sql ----------
BEGIN;
-- Préférences de notification (US13). Une absence de ligne vaut les valeurs par défaut :
-- dans l'app et par mail actifs. Aucune ligne n'est créée d'avance.
-- Le choix « Par mail » est seulement enregistré : l'app n'envoie aucun mail.

CREATE TABLE public.notification_preferences (
  recipient_email text NOT NULL CHECK (recipient_email = lower(recipient_email)),
  kind public.notification_kind NOT NULL,
  in_app boolean NOT NULL DEFAULT true,
  by_email boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (recipient_email, kind)
);

-- REVOKE d'abord : Supabase donne par défaut tous les droits sur une nouvelle table.
-- Pas de suppression : décocher puis recocher suffit.
REVOKE ALL ON public.notification_preferences FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.notification_preferences TO authenticated;
GRANT ALL ON public.notification_preferences TO service_role;

ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users read own notification preferences" ON public.notification_preferences
  FOR SELECT TO authenticated
  USING (private.is_allowed() AND recipient_email = lower(auth.jwt() ->> 'email'));

CREATE POLICY "Users create own notification preferences" ON public.notification_preferences
  FOR INSERT TO authenticated
  WITH CHECK (private.is_allowed() AND recipient_email = lower(auth.jwt() ->> 'email'));

CREATE POLICY "Users update own notification preferences" ON public.notification_preferences
  FOR UPDATE TO authenticated
  USING (private.is_allowed() AND recipient_email = lower(auth.jwt() ->> 'email'))
  WITH CHECK (private.is_allowed() AND recipient_email = lower(auth.jwt() ->> 'email'));

CREATE OR REPLACE FUNCTION private.touch_notification_preference()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END
$function$;

CREATE TRIGGER touch_notification_preference
  BEFORE INSERT OR UPDATE ON public.notification_preferences
  FOR EACH ROW EXECUTE FUNCTION private.touch_notification_preference();

-- Réutilisées par les US14 à US16 avant de créer une notification.
CREATE OR REPLACE FUNCTION private.wants_in_app(_email text, _kind public.notification_kind)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
  SELECT COALESCE(
    (SELECT in_app FROM public.notification_preferences
      WHERE recipient_email = lower(_email) AND kind = _kind),
    true);
$function$;

CREATE OR REPLACE FUNCTION private.wants_by_email(_email text, _kind public.notification_kind)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
  SELECT COALESCE(
    (SELECT by_email FROM public.notification_preferences
      WHERE recipient_email = lower(_email) AND kind = _kind),
    true);
$function$;

REVOKE ALL ON FUNCTION private.wants_in_app(text, public.notification_kind) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.wants_by_email(text, public.notification_kind) FROM PUBLIC, anon, authenticated;

-- Une demande créée notifie les managers de son équipe, sauf son auteur.
-- Un statut changé notifie l'auteur (collaborateur ou manager), sauf s'il l'a changé lui-même.
-- Chaque destinataire peut avoir décoché « Dans l'app » pour ce type. old_status vide = création.
CREATE OR REPLACE FUNCTION private.notify_submission_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  IF NEW.old_status IS NULL THEN
    INSERT INTO public.notifications (recipient_email, kind, submission_id, message)
    SELECT lower(u.email),
           'nouvelle_demande'::public.notification_kind,
           s.id,
           format('Nouvelle demande de %s (%s)', s.author_name, s.team)
      FROM public.submissions s
      JOIN public.manager_teams mt ON mt.team = s.team
      JOIN public.allowed_users u ON u.id = mt.allowed_user_id
      JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id
     WHERE s.id = NEW.submission_id
       AND r.role = 'manager'::public.app_role
       AND lower(u.email) IS DISTINCT FROM lower(s.submitted_by_email)
       AND private.wants_in_app(u.email, 'nouvelle_demande'::public.notification_kind);
  ELSIF NEW.new_status IS DISTINCT FROM NEW.old_status THEN
    INSERT INTO public.notifications (recipient_email, kind, submission_id, message)
    SELECT lower(u.email),
           'changement_statut'::public.notification_kind,
           s.id,
           format('Ta demande « %s » est maintenant %s',
                  CASE WHEN length(c.text) > 60 THEN left(c.text, 59) || '…' ELSE c.text END,
                  NEW.new_status)
      FROM public.submissions s
      CROSS JOIN LATERAL (SELECT btrim(regexp_replace(s.content, '\s+', ' ', 'g')) AS text) c
      JOIN public.allowed_users u ON lower(u.email) = lower(s.submitted_by_email)
      JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id
     WHERE s.id = NEW.submission_id
       AND r.role IN ('collaborateur'::public.app_role, 'manager'::public.app_role)
       AND lower(u.email) IS DISTINCT FROM lower(NEW.changed_by_email)
       AND private.wants_in_app(u.email, 'changement_statut'::public.notification_kind);
  END IF;
  RETURN NEW;
END
$function$;

-- Lit, puis tente de modifier et de créer les préférences de _target sous le rôle authenticated, donc sous RLS.
CREATE OR REPLACE FUNCTION private.smoke_preference_as(
  _email text,
  _target text,
  OUT _visible int,
  OUT _updated int,
  OUT _insert_denied boolean
)
LANGUAGE plpgsql
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('email', _email)::text, true);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO _visible FROM public.notification_preferences WHERE recipient_email = _target;
  UPDATE public.notification_preferences SET by_email = NOT by_email WHERE recipient_email = _target;
  GET DIAGNOSTICS _updated = ROW_COUNT;
  BEGIN
    INSERT INTO public.notification_preferences (recipient_email, kind, by_email)
    VALUES (_target, 'resume_hebdo', false);
    _insert_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN
    _insert_denied := true;
  END;
  RESET ROLE;
END
$function$;

REVOKE ALL ON FUNCTION private.smoke_preference_as(text, text) FROM PUBLIC, anon, authenticated;

-- Compte supprimé : ses notifications et ses préférences disparaissent et son nom sort des messages des autres.
CREATE OR REPLACE FUNCTION private.anonymize_removed_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'private' AS $function$
DECLARE _planned boolean := OLD.departure_date IS NOT NULL AND OLD.departure_date <= current_date;
BEGIN
  INSERT INTO public.attachment_deletion_queue (path, delete_after)
  SELECT attachment_path, CASE WHEN _planned THEN now() ELSE now() + interval '7 days' END
    FROM public.submissions
   WHERE lower(submitted_by_email) = lower(OLD.email) AND attachment_path IS NOT NULL
  ON CONFLICT (path) DO NOTHING;

  IF _planned THEN
    UPDATE public.departure_notices SET closed_at = now(), departing_label = 'Utilisateur supprimé'
     WHERE departing_user_id = OLD.id AND closed_at IS NULL;
  ELSE
    PERFORM private.notify_departure(OLD.id, OLD.email, OLD.team, current_date, 'sans préavis');
  END IF;

  DELETE FROM public.notifications WHERE recipient_email = lower(OLD.email);
  DELETE FROM public.notification_preferences WHERE recipient_email = lower(OLD.email);
  UPDATE public.notifications n
     SET message = format('Nouvelle demande de %s (%s)', 'Utilisateur supprimé', s.team)
    FROM public.submissions s
   WHERE n.submission_id = s.id
     AND n.kind = 'nouvelle_demande'::public.notification_kind
     AND lower(s.submitted_by_email) = lower(OLD.email);

  UPDATE public.submissions
     SET author_name = 'Utilisateur supprimé', submitted_by_email = 'Utilisateur supprimé'
   WHERE lower(submitted_by_email) = lower(OLD.email);
  UPDATE public.news
     SET author = 'Utilisateur supprimé', author_email = 'Utilisateur supprimé'
   WHERE lower(author_email) = lower(OLD.email);
  UPDATE public.submission_status_history
     SET changed_by_name = 'Utilisateur supprimé', changed_by_email = 'Utilisateur supprimé'
   WHERE lower(changed_by_email) = lower(OLD.email);
  RETURN OLD;
END $function$;

-- Test de fumée mis à jour pour ces règles
CREATE OR REPLACE FUNCTION private.run_smoke_tests()
 RETURNS TABLE(test text, ok boolean, detail text)
 LANGUAGE plpgsql
 SECURITY INVOKER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _res jsonb := '[]'::jsonb;
  _collab uuid; _mgr uuid; _adm uuid;
  _s1 uuid; _s2 uuid; _b uuid; _n uuid;
  _st text; _cnt int; _err text;
  _team text := 'ZZ Test fumée';
  _mgr2 uuid; _nb uuid; _ne uuid; _nm uuid; _nd uuid;
  _ids uuid[]; _with_teams uuid[]; _with_images uuid[] := '{}';
  _reader record; _read record; _want uuid[];
  _mgr3 uuid; _np uuid; _nq uuid; _pub timestamptz; _try record;
  _collab2 uuid; _s3 uuid; _s4 uuid; _notif uuid; _notif_try record; _emails text[];
  _s5 uuid; _pref_try record;
BEGIN
  BEGIN
    INSERT INTO teams(name) VALUES (_team), ('ZZ Test fumée autre') ON CONFLICT DO NOTHING;
    INSERT INTO allowed_users(email, team) VALUES ('smoke.collab@test.invalid', _team) RETURNING id INTO _collab;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_collab, 'collaborateur');
    INSERT INTO allowed_users(email) VALUES ('smoke.manager@test.invalid') RETURNING id INTO _mgr;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_mgr, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_mgr, _team);
    INSERT INTO allowed_users(email) VALUES ('smoke.admin@test.invalid') RETURNING id INTO _adm;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_adm, 'admin');

    -- Collaborateur : soumission
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 1') RETURNING id, status::text INTO _s1, _st;
    _res := _res || jsonb_build_object('t', 'Soumission créée « en attente », dans l''équipe du collaborateur',
      'ok', _st = 'en attente' AND (SELECT team FROM submissions WHERE id = _s1) = _team, 'd', _st);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 2') RETURNING id INTO _s2;

    -- Manager : validation et refus
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    BEGIN
      UPDATE submissions SET status = 'validée' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager valide une demande en attente', 'ok', true, 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager valide une demande en attente', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'refusée', rejection_category = 'doublon', rejection_note = 'Test' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager refuse une demande avec un motif', 'ok', true, 'd', 'refusée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager refuse une demande avec un motif', 'ok', false, 'd', SQLERRM);
    END;
    -- Le manager change le statut librement, autant de fois que nécessaire (erreurs humaines)
    BEGIN
      UPDATE submissions SET status = 'clôturée' WHERE id = _s1;
      UPDATE submissions SET status = 'validée' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager corrige une clôture par erreur (clôturée puis validée)', 'ok',
        (SELECT status::text FROM submissions WHERE id = _s1) = 'validée', 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager corrige une clôture par erreur (clôturée puis validée)', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'validée' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager passe un refus en validée, le motif est effacé', 'ok',
        (SELECT rejection_category IS NULL AND rejection_note IS NULL FROM submissions WHERE id = _s2), 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager passe un refus en validée, le motif est effacé', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'en attente' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager remet une demande « en attente »', 'ok', true, 'd', 'en attente');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager remet une demande « en attente »', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET content = 'Contenu modifié par le manager' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager ne peut pas modifier le contenu d''une demande', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager ne peut pas modifier le contenu d''une demande', 'ok', true, 'd', 'refusé par la base');
    END;
    SELECT count(*) INTO _cnt FROM submission_status_history WHERE submission_id IN (_s1, _s2);
    _res := _res || jsonb_build_object('t', 'Historique : 8 lignes (2 créations, 6 changements de statut)', 'ok', _cnt = 8, 'd', _cnt || ' ligne(s)');

    -- Clôture automatique après un an sans modification
    PERFORM set_config('request.jwt.claims', '', true);
    UPDATE submissions SET revalidate_at = now() - interval '1 day' WHERE id = _s1;
    PERFORM private.expire_revalidations();
    SELECT status::text INTO _st FROM submissions WHERE id = _s1;
    _res := _res || jsonb_build_object('t', 'Clôture automatique : une demande validée échue passe « clôturée »', 'ok', _st = 'clôturée', 'd', _st);
    _res := _res || jsonb_build_object('t', 'Clôture automatique : l''historique la marque « Automatique »', 'ok',
      EXISTS (SELECT 1 FROM submission_status_history WHERE submission_id = _s1 AND new_status = 'clôturée' AND is_automatic), 'd', _st);

    -- Points bloquants
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.admin@test.invalid"}', true);
    INSERT INTO blockers(title, department) VALUES ('Blocage de test', 'Test') RETURNING id, status::text INTO _b, _st;
    _res := _res || jsonb_build_object('t', 'Point bloquant créé au statut OUVERT', 'ok', _st = 'OUVERT', 'd', _st);
    BEGIN
      UPDATE blockers SET status = 'RÉSOLU' WHERE id = _b;
      _res := _res || jsonb_build_object('t', 'OUVERT → RÉSOLU refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'OUVERT → RÉSOLU refusé', 'ok', true, 'd', 'refusé par la base');
    END;
    BEGIN
      UPDATE blockers SET status = 'EN COURS' WHERE id = _b;
      UPDATE blockers SET status = 'SURVEILLANCE' WHERE id = _b;
      UPDATE blockers SET status = 'RÉSOLU' WHERE id = _b;
      _res := _res || jsonb_build_object('t', 'OUVERT → EN COURS → SURVEILLANCE → RÉSOLU accepté', 'ok', true, 'd', 'RÉSOLU');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'OUVERT → EN COURS → SURVEILLANCE → RÉSOLU accepté', 'ok', false, 'd', SQLERRM);
    END;

    -- Actualités
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    -- Différée, la contrainte ne se déclencherait qu'au COMMIT, jamais atteint dans ce test.
    SET CONSTRAINTS check_news_audience IMMEDIATE;
    INSERT INTO news(title, body, author, status) VALUES ('Actu de test', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _n;
    BEGIN
      UPDATE news SET status = 'publiée' WHERE id = _n;
      _res := _res || jsonb_build_object('t', 'Publier une actu sans public est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN check_violation THEN
        _res := _res || jsonb_build_object('t', 'Publier une actu sans public est refusé', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Publier une actu sans public est refusé', 'ok', false, 'd', SQLERRM);
    END;
    UPDATE news SET audience = 'équipe' WHERE id = _n;
    BEGIN
      UPDATE news SET status = 'publiée' WHERE id = _n;
      _res := _res || jsonb_build_object('t', 'Publier une actu « équipe » sans équipe est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN check_violation THEN
        _res := _res || jsonb_build_object('t', 'Publier une actu « équipe » sans équipe est refusé', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Publier une actu « équipe » sans équipe est refusé', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      PERFORM public.save_news_audience(_n, 'équipe', ARRAY['ZZ Test fumée autre']);
      _res := _res || jsonb_build_object('t', 'Un manager ne cible pas une équipe qui n''est pas la sienne', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN insufficient_privilege THEN
        _res := _res || jsonb_build_object('t', 'Un manager ne cible pas une équipe qui n''est pas la sienne', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Un manager ne cible pas une équipe qui n''est pas la sienne', 'ok', false, 'd', SQLERRM);
    END;
    PERFORM public.save_news_audience(_n, 'équipe', ARRAY[_team]);
    UPDATE news SET status = 'publiée' WHERE id = _n;
    PERFORM private.expire_revalidations();
    SELECT status::text INTO _st FROM news WHERE id = _n;
    _res := _res || jsonb_build_object('t', 'Actualité : brouillon puis publiée, elle reste publiée après la tâche quotidienne', 'ok', _st = 'publiée', 'd', _st);
    BEGIN
      UPDATE news SET status = 'brouillon' WHERE id = _n;
      _res := _res || jsonb_build_object('t', 'Une actu publiée ne repasse pas en brouillon', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Une actu publiée ne repasse pas en brouillon', 'ok', true, 'd', 'refusé par la base');
    END;
    UPDATE news SET title = 'Actu de test corrigée' WHERE id = _n;
    SELECT status::text INTO _st FROM news WHERE id = _n;
    _res := _res || jsonb_build_object('t', 'Une actu publiée reste modifiable et reste publiée', 'ok', _st = 'publiée', 'd', _st);

    -- Public des actus : lecture réelle sous RLS (voir private.smoke_read_as)
    PERFORM set_config('request.jwt.claims', '', true);
    INSERT INTO allowed_users(email) VALUES ('smoke.manager2@test.invalid') RETURNING id INTO _mgr2;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_mgr2, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_mgr2, 'ZZ Test fumée autre');

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager2@test.invalid"}', true);
    INSERT INTO news(title, body, author, status) VALUES ('Actu équipe B', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _nb;
    PERFORM public.save_news_audience(_nb, 'équipe', ARRAY['ZZ Test fumée autre']);
    UPDATE news SET status = 'publiée' WHERE id = _nb;

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.admin@test.invalid"}', true);
    INSERT INTO news(title, body, author, status) VALUES ('Actu entreprise', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _ne;
    PERFORM public.save_news_audience(_ne, 'entreprise');
    UPDATE news SET status = 'publiée' WHERE id = _ne;
    INSERT INTO news(title, body, author, status) VALUES ('Actu deux équipes', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _nm;
    PERFORM public.save_news_audience(_nm, 'équipe', ARRAY[_team, 'ZZ Test fumée autre']);
    UPDATE news SET status = 'publiée' WHERE id = _nm;

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    INSERT INTO news(title, body, author, status) VALUES ('Brouillon du manager A', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _nd;

    _ids := ARRAY[_n, _nb, _ne, _nm, _nd];
    _with_teams := ARRAY[_n, _nb, _nm];
    -- L'écriture directe dans storage.objects dépend des droits du projet : sans elle, le détail le dit.
    BEGIN
      INSERT INTO storage.objects(bucket_id, name) VALUES ('news-media', _n || '/smoke.png'), ('news-media', _nb || '/smoke.png');
      _with_images := ARRAY[_n, _nb];
    EXCEPTION WHEN insufficient_privilege THEN
      NULL;
    END;

    FOR _reader IN
      SELECT * FROM (VALUES
        ('collaborateur équipe A', 'smoke.collab@test.invalid', ARRAY[_n, _ne, _nm]),
        ('manager équipe A', 'smoke.manager@test.invalid', ARRAY[_n, _ne, _nm, _nd]),
        ('manager équipe B', 'smoke.manager2@test.invalid', ARRAY[_nb, _ne, _nm]),
        ('admin', 'smoke.admin@test.invalid', _ids)
      ) AS v(label, email, ids)
    LOOP
      _want := ARRAY(SELECT unnest(_reader.ids) ORDER BY 1);
      SELECT * INTO _read FROM private.smoke_read_as(_reader.email, _ids);
      _res := _res || jsonb_build_object('t', 'Public des actus : lecture du ' || _reader.label, 'ok',
        _read._news = _want, 'd', cardinality(_read._news) || ' actu(s) lue(s)');
      _res := _res || jsonb_build_object('t', 'Public des actus : équipes ciblées lues par le ' || _reader.label, 'ok',
        _read._teams = ARRAY(SELECT unnest(_want) INTERSECT SELECT unnest(_with_teams) ORDER BY 1),
        'd', cardinality(_read._teams) || ' actu(s)');
      _res := _res || jsonb_build_object('t', 'Public des actus : images lues par le ' || _reader.label, 'ok',
        _read._images = ARRAY(SELECT unnest(_want) INTERSECT SELECT unnest(_with_images) ORDER BY 1),
        'd', CASE WHEN cardinality(_with_images) = 0 THEN 'NON TESTÉ : image de test impossible à créer'
             ELSE cardinality(_read._images) || ' image(s)' END);
    END LOOP;

    -- L'auteur garde ses actus même s'il n'est plus manager de l'équipe ciblée
    PERFORM set_config('request.jwt.claims', '', true);
    UPDATE allowed_user_roles SET role = 'collaborateur' WHERE allowed_user_id = _mgr2;
    DELETE FROM manager_teams WHERE allowed_user_id = _mgr2;
    SELECT * INTO _read FROM private.smoke_read_as('smoke.manager2@test.invalid', _ids);
    _res := _res || jsonb_build_object('t', 'Public des actus : l''auteur lit la sienne même sans rôle manager ni équipe', 'ok',
      _read._news = ARRAY(SELECT unnest(ARRAY[_nb, _ne]) ORDER BY 1), 'd', cardinality(_read._news) || ' actu(s) lue(s)');

    -- Modification d'une actu publiée : écriture réelle sous RLS (voir private.smoke_update_as).
    -- Actus créées dans le passé : dans une transaction, now() ne bouge pas et les dates se confondraient.
    -- Différée comme dans l'application : save_news_audience change le public avant d'écrire les équipes.
    SET CONSTRAINTS check_news_audience DEFERRED;
    PERFORM set_config('request.jwt.claims', '', true);
    INSERT INTO allowed_users(email) VALUES ('smoke.manager3@test.invalid') RETURNING id INTO _mgr3;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_mgr3, 'manager');

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    INSERT INTO news(title, body, author, status, audience, created_at)
    VALUES ('Actu publiée', 'Corps', 'Smoke', 'publiée', 'entreprise', now() - interval '2 days')
    RETURNING id, published_at INTO _np, _pub;

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager3@test.invalid"}', true);
    INSERT INTO news(title, body, author, status, audience, created_at)
    VALUES ('Actu d''un auteur parti', 'Corps', 'Smoke', 'publiée', 'entreprise', now() - interval '2 days')
    RETURNING id INTO _nq;

    SELECT * INTO _try FROM private.smoke_update_as('smoke.manager3@test.invalid', _np, 'Modifiée à tort');
    _res := _res || jsonb_build_object('t', 'Un autre manager ne modifie pas une actu publiée', 'ok',
      _try._rows = 0 AND (SELECT title FROM news WHERE id = _np) = 'Actu publiée', 'd', _try._rows || ' ligne(s)');
    SELECT * INTO _try FROM private.smoke_update_as('smoke.collab@test.invalid', _np, 'Modifiée à tort');
    _res := _res || jsonb_build_object('t', 'Un collaborateur ne modifie pas une actu publiée', 'ok',
      _try._rows = 0 AND (SELECT title FROM news WHERE id = _np) = 'Actu publiée', 'd', _try._rows || ' ligne(s)');

    SELECT * INTO _try FROM private.smoke_update_as('smoke.manager@test.invalid', _np, 'Actu publiée corrigée');
    _res := _res || jsonb_build_object('t', 'Le manager auteur modifie son actu : même date de publication, statut publiée', 'ok',
      _try._rows = 1 AND EXISTS (
        SELECT 1 FROM news WHERE id = _np AND title = 'Actu publiée corrigée' AND status = 'publiée'
          AND published_at = _pub AND updated_at > published_at),
      'd', COALESCE(_try._error, _try._rows || ' ligne(s)'));
    SELECT * INTO _try FROM private.smoke_update_as('smoke.manager@test.invalid', _np, '   ');
    _res := _res || jsonb_build_object('t', 'Une actu publiée ne perd pas son titre', 'ok',
      _try._error IS NOT NULL AND (SELECT title FROM news WHERE id = _np) = 'Actu publiée corrigée', 'd', COALESCE(_try._error, 'accepté à tort'));
    SELECT * INTO _try FROM private.smoke_update_as('smoke.admin@test.invalid', _np, 'Actu corrigée par l''admin');
    _res := _res || jsonb_build_object('t', 'L''admin modifie l''actu d''un manager : auteur et date de publication inchangés', 'ok',
      _try._rows = 1 AND EXISTS (
        SELECT 1 FROM news WHERE id = _np AND title = 'Actu corrigée par l''admin'
          AND author_email = 'smoke.manager@test.invalid' AND published_at = _pub),
      'd', COALESCE(_try._error, _try._rows || ' ligne(s)'));

    BEGIN
      UPDATE news SET author = 'Autre auteur' WHERE id = _np;
      _res := _res || jsonb_build_object('t', 'L''auteur d''une actu publiée ne change pas', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN insufficient_privilege THEN
        _res := _res || jsonb_build_object('t', 'L''auteur d''une actu publiée ne change pas', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'L''auteur d''une actu publiée ne change pas', 'ok', false, 'd', SQLERRM);
    END;

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    BEGIN
      PERFORM public.save_published_news(_np, 'Titre à ne pas garder', 'Corps', '[]', NULL, 'équipe', ARRAY['ZZ Test fumée autre']);
      _res := _res || jsonb_build_object('t', 'Enregistrement refusé : rien ne change, ni le titre ni le public', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN insufficient_privilege THEN
        _res := _res || jsonb_build_object('t', 'Enregistrement refusé : rien ne change, ni le titre ni le public', 'ok',
          EXISTS (SELECT 1 FROM news WHERE id = _np AND title = 'Actu corrigée par l''admin' AND audience = 'entreprise'), 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Enregistrement refusé : rien ne change, ni le titre ni le public', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      PERFORM public.save_published_news(_np, 'Titre et public', 'Corps', '[]', 'autre-actu/image.png', 'entreprise');
      _res := _res || jsonb_build_object('t', 'Une actu ne reprend pas l''image d''une autre', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN check_violation THEN
      _res := _res || jsonb_build_object('t', 'Une actu ne reprend pas l''image d''une autre', 'ok', true, 'd', 'refusé par la base');
    END;
    PERFORM public.save_published_news(_np, 'Titre et public', 'Corps', '[]', NULL, 'équipe', ARRAY[_team]);
    _res := _res || jsonb_build_object('t', 'Enregistrement accepté : le titre et le public changent ensemble', 'ok',
      EXISTS (SELECT 1 FROM news n JOIN news_teams t ON t.news_id = n.id
              WHERE n.id = _np AND n.title = 'Titre et public' AND n.audience = 'équipe' AND t.team = _team), 'd', 'équipe');

    -- Auteur parti : il perd d'abord son rôle, puis son compte. L'anonymisation ne compte pas comme une modification.
    PERFORM set_config('request.jwt.claims', '', true);
    UPDATE allowed_user_roles SET role = 'collaborateur' WHERE allowed_user_id = _mgr3;
    SELECT * INTO _try FROM private.smoke_update_as('smoke.manager3@test.invalid', _nq, 'Modifiée à tort');
    _res := _res || jsonb_build_object('t', 'L''auteur qui n''est plus manager ne modifie plus son actu', 'ok', _try._rows = 0, 'd', _try._rows || ' ligne(s)');
    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      DELETE FROM allowed_users WHERE id = _mgr3;
      _res := _res || jsonb_build_object('t', 'Compte supprimé : auteur anonymisé, sans mention « Modifiée le »', 'ok',
        EXISTS (SELECT 1 FROM news WHERE id = _nq AND author = 'Utilisateur supprimé' AND updated_at = published_at), 'd', 'Utilisateur supprimé');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Compte supprimé : auteur anonymisé, sans mention « Modifiée le »', 'ok', false, 'd', SQLERRM);
    END;
    SELECT * INTO _try FROM private.smoke_update_as('smoke.admin@test.invalid', _nq, 'Actu reprise par l''admin');
    _res := _res || jsonb_build_object('t', 'Auteur supprimé : l''admin modifie encore l''actu', 'ok', _try._rows = 1, 'd', COALESCE(_try._error, _try._rows || ' ligne(s)'));

    -- Centre de notifications : destinataires, puis droits réels sous RLS (voir private.smoke_notification_as).
    -- L'admin a une ligne dans manager_teams pour prouver que le rôle est bien contrôlé.
    PERFORM set_config('request.jwt.claims', '', true);
    -- Le second manager a perdu son rôle et son équipe dans le test « l'auteur lit la sienne ».
    UPDATE allowed_user_roles SET role = 'manager' WHERE allowed_user_id = _mgr2;
    INSERT INTO allowed_users(email, team) VALUES ('smoke.collab2@test.invalid', _team) RETURNING id INTO _collab2;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_collab2, 'collaborateur');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_mgr2, _team), (_adm, _team);

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab2@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 3') RETURNING id INTO _s3;
    SELECT COALESCE(array_agg(recipient_email), '{}') INTO _emails FROM notifications WHERE submission_id = _s3;
    _res := _res || jsonb_build_object('t', 'Une demande créée notifie les managers de son équipe', 'ok',
      _emails @> ARRAY['smoke.manager@test.invalid', 'smoke.manager2@test.invalid'], 'd', array_to_string(_emails, ', '));
    _res := _res || jsonb_build_object('t', 'Une demande créée ne notifie ni son auteur ni un admin', 'ok',
      NOT _emails && ARRAY['smoke.collab2@test.invalid', 'smoke.admin@test.invalid'], 'd', array_to_string(_emails, ', '));
    _res := _res || jsonb_build_object('t', 'Le texte de la notification nomme l''auteur et l''équipe', 'ok',
      EXISTS (SELECT 1 FROM notifications n JOIN submissions s ON s.id = n.submission_id
              WHERE s.id = _s3 AND n.kind = 'nouvelle_demande'
                AND n.message = format('Nouvelle demande de %s (%s)', s.author_name, s.team)), 'd', _team);

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', _team, 'Demande de test 4') RETURNING id INTO _s4;
    SELECT COALESCE(array_agg(recipient_email), '{}') INTO _emails FROM notifications WHERE submission_id = _s4;
    _res := _res || jsonb_build_object('t', 'Un manager n''est pas notifié de sa propre demande', 'ok',
      _emails = ARRAY['smoke.manager2@test.invalid'], 'd', array_to_string(_emails, ', '));

    SELECT id INTO _notif FROM notifications WHERE submission_id = _s3 AND recipient_email = 'smoke.manager@test.invalid';
    SELECT * INTO _notif_try FROM private.smoke_notification_as('smoke.manager2@test.invalid', _notif);
    _res := _res || jsonb_build_object('t', 'Un utilisateur ne lit ni ne marque les notifications d''un autre', 'ok',
      _notif_try._visible = 0 AND _notif_try._marked = 0
      AND (SELECT read_at FROM notifications WHERE id = _notif) IS NULL,
      'd', _notif_try._visible || ' lue(s), ' || _notif_try._marked || ' marquée(s)');
    SELECT * INTO _notif_try FROM private.smoke_notification_as('smoke.manager@test.invalid', _notif);
    _res := _res || jsonb_build_object('t', 'Le destinataire lit sa notification et la marque comme lue', 'ok',
      _notif_try._visible = 1 AND _notif_try._marked = 1
      AND (SELECT read_at FROM notifications WHERE id = _notif) IS NOT NULL,
      'd', _notif_try._visible || ' lue(s), ' || _notif_try._marked || ' marquée(s)');
    _res := _res || jsonb_build_object('t', 'Seul read_at est modifiable : ni autre colonne, ni création, ni suppression', 'ok',
      _notif_try._denied = 3 AND EXISTS (SELECT 1 FROM notifications WHERE id = _notif AND message <> 'Modifiée à tort'),
      'd', _notif_try._denied || ' écriture(s) refusée(s) sur 3');

    -- Préférences de notification : valeurs par défaut, effet de « Dans l'app », droits réels sous RLS
    -- (voir private.smoke_preference_as), puis notification d'un changement de statut.
    PERFORM set_config('request.jwt.claims', '', true);
    _res := _res || jsonb_build_object('t', 'Sans préférence enregistrée : dans l''app et par mail sont actifs', 'ok',
      NOT EXISTS (SELECT 1 FROM notification_preferences WHERE recipient_email = 'smoke.manager@test.invalid')
      AND private.wants_in_app('smoke.manager@test.invalid', 'nouvelle_demande')
      AND private.wants_by_email('smoke.manager@test.invalid', 'nouvelle_demande'), 'd', 'aucune ligne');
    INSERT INTO notification_preferences(recipient_email, kind, in_app)
      VALUES ('smoke.manager@test.invalid', 'nouvelle_demande', false);
    _res := _res || jsonb_build_object('t', 'Une préférence enregistrée sans « par mail » le garde actif', 'ok',
      private.wants_by_email('smoke.manager@test.invalid', 'nouvelle_demande'), 'd', 'by_email par défaut');

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab2@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 5') RETURNING id INTO _s5;
    SELECT COALESCE(array_agg(recipient_email), '{}') INTO _emails FROM notifications WHERE submission_id = _s5;
    _res := _res || jsonb_build_object('t', 'Dans l''app décoché : la notification « nouvelle demande » n''est plus créée', 'ok',
      NOT _emails && ARRAY['smoke.manager@test.invalid'] AND _emails @> ARRAY['smoke.manager2@test.invalid'],
      'd', array_to_string(_emails, ', '));
    _res := _res || jsonb_build_object('t', 'Dans l''app décoché : les notifications déjà reçues restent', 'ok',
      EXISTS (SELECT 1 FROM notifications WHERE id = _notif), 'd', 'notification de la demande 3');

    SELECT * INTO _pref_try FROM private.smoke_preference_as('smoke.manager2@test.invalid', 'smoke.manager@test.invalid');
    _res := _res || jsonb_build_object('t', 'Un utilisateur ne lit ni ne modifie les préférences d''un autre', 'ok',
      _pref_try._visible = 0 AND _pref_try._updated = 0 AND _pref_try._insert_denied
      AND (SELECT by_email FROM notification_preferences
            WHERE recipient_email = 'smoke.manager@test.invalid' AND kind = 'nouvelle_demande'),
      'd', _pref_try._visible || ' lue(s), ' || _pref_try._updated || ' modifiée(s), création '
           || CASE WHEN _pref_try._insert_denied THEN 'refusée' ELSE 'acceptée' END);
    SELECT * INTO _pref_try FROM private.smoke_preference_as('smoke.manager@test.invalid', 'smoke.manager@test.invalid');
    _res := _res || jsonb_build_object('t', 'Un utilisateur lit, modifie et crée ses propres préférences', 'ok',
      _pref_try._visible = 1 AND _pref_try._updated = 1 AND NOT _pref_try._insert_denied,
      'd', _pref_try._visible || ' lue(s), ' || _pref_try._updated || ' modifiée(s), création '
           || CASE WHEN _pref_try._insert_denied THEN 'refusée' ELSE 'acceptée' END);

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    UPDATE submissions SET status = 'validée' WHERE id = _s5;
    SELECT COALESCE(array_agg(recipient_email), '{}') INTO _emails
      FROM notifications WHERE submission_id = _s5 AND kind = 'changement_statut';
    _res := _res || jsonb_build_object('t', 'Un changement de statut notifie l''auteur de la demande, et lui seul', 'ok',
      _emails = ARRAY['smoke.collab2@test.invalid']
      AND EXISTS (SELECT 1 FROM notifications WHERE submission_id = _s5 AND kind = 'changement_statut'
                  AND message = 'Ta demande « Demande de test 5 » est maintenant validée'),
      'd', array_to_string(_emails, ', '));
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab2@test.invalid"}', true);
    UPDATE submissions SET status = 'en attente' WHERE id = _s5;
    SELECT count(*) INTO _cnt FROM notifications WHERE submission_id = _s5 AND kind = 'changement_statut';
    _res := _res || jsonb_build_object('t', 'L''auteur n''est pas notifié d''un statut qu''il change lui-même', 'ok',
      _cnt = 1, 'd', _cnt || ' notification(s)');
    PERFORM set_config('request.jwt.claims', '', true);
    INSERT INTO notification_preferences(recipient_email, kind, in_app)
      VALUES ('smoke.collab2@test.invalid', 'changement_statut', false);
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    UPDATE submissions SET status = 'refusée', rejection_category = 'doublon', rejection_note = 'Test' WHERE id = _s5;
    SELECT count(*) INTO _cnt FROM notifications WHERE submission_id = _s5 AND kind = 'changement_statut';
    _res := _res || jsonb_build_object('t', 'Dans l''app décoché : la notification de changement de statut n''est plus créée', 'ok',
      _cnt = 1, 'd', _cnt || ' notification(s)');

    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      DELETE FROM allowed_users WHERE id IN (_collab2, _mgr2);
      _res := _res || jsonb_build_object('t', 'Compte supprimé : son nom sort des messages, ses notifications disparaissent', 'ok',
        EXISTS (SELECT 1 FROM notifications WHERE id = _notif
                AND message = format('Nouvelle demande de Utilisateur supprimé (%s)', _team))
        AND NOT EXISTS (SELECT 1 FROM notifications WHERE recipient_email = 'smoke.manager2@test.invalid'),
        'd', 'Utilisateur supprimé');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Compte supprimé : son nom sort des messages, ses notifications disparaissent', 'ok', false, 'd', SQLERRM);
    END;
    _res := _res || jsonb_build_object('t', 'Compte supprimé : ses préférences de notification disparaissent', 'ok',
      NOT EXISTS (SELECT 1 FROM notification_preferences WHERE recipient_email = 'smoke.collab2@test.invalid'), 'd', 'smoke.collab2');
    DELETE FROM manager_teams WHERE allowed_user_id = _adm;

    INSERT INTO notifications(recipient_email, kind, message, created_at) VALUES
      ('smoke.manager@test.invalid', 'nouvelle_demande', 'Ancienne', now() - interval '31 days'),
      ('smoke.manager@test.invalid', 'nouvelle_demande', 'Récente', now() - interval '29 days');
    PERFORM private.purge_notifications();
    _res := _res || jsonb_build_object('t', 'La purge efface les notifications de plus de 30 jours, pas les autres', 'ok',
      NOT EXISTS (SELECT 1 FROM notifications WHERE message = 'Ancienne')
      AND EXISTS (SELECT 1 FROM notifications WHERE message = 'Récente'), 'd', '30 jours');

    -- Référentiel des équipes
    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      UPDATE teams SET name = 'ZZ Test fumée 2' WHERE name = _team;
      _res := _res || jsonb_build_object('t', 'Référentiel : renommer une équipe met à jour utilisateurs, managers et demandes', 'ok',
        (SELECT team FROM allowed_users WHERE id = _collab) = 'ZZ Test fumée 2'
        AND (SELECT team FROM manager_teams WHERE allowed_user_id = _mgr) = 'ZZ Test fumée 2'
        AND (SELECT team FROM submissions WHERE id = _s1) = 'ZZ Test fumée 2', 'd', 'ZZ Test fumée 2');
      _res := _res || jsonb_build_object('t', 'Référentiel : renommer une équipe met à jour le public des actus', 'ok',
        (SELECT team FROM news_teams WHERE news_id = _n) = 'ZZ Test fumée 2', 'd', 'ZZ Test fumée 2');
      _team := 'ZZ Test fumée 2';
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Référentiel : renommer une équipe met à jour utilisateurs, managers et demandes', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      DELETE FROM teams WHERE name = _team;
      _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN foreign_key_violation THEN
        _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', false, 'd', SQLERRM);
    END;

    RAISE EXCEPTION 'HP_SMOKE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'HP_SMOKE_ROLLBACK' THEN
      _res := _res || jsonb_build_object('t', 'Exécution du test de fumée', 'ok', false, 'd', 'Erreur inattendue : ' || SQLERRM);
    END IF;
  END;

  SELECT count(*) INTO _cnt FROM private.audit_enum_literals();
  _res := _res || jsonb_build_object('t', 'Aucune valeur d''ENUM obsolète dans les fonctions', 'ok', _cnt = 0, 'd', _cnt || ' anomalie(s)');

  RETURN QUERY SELECT x->>'t', (x->>'ok')::boolean, x->>'d' FROM jsonb_array_elements(_res) x;
END;
$function$;

DO $$
DECLARE _bad text;
BEGIN
  SELECT string_agg(test || ' : ' || COALESCE(detail, ''), ' | ') INTO _bad FROM private.run_smoke_tests() WHERE NOT ok;
  IF _bad IS NOT NULL THEN
    RAISE EXCEPTION 'Smoke tests failed: %', _bad;
  END IF;
END $$;
COMMIT;

-- ---------- 20261103120000_alertes_changement_etat.sql ----------
BEGIN;
-- Alertes de changement d'état (US14). L'auteur suit sa demande d'office, dès sa création,
-- et chaque nouvelle étape du fil lui crée une notification. L'US15 ajoutera les sources
-- « manager » et « volontaire » : leur alerte respectera « Dans l'app », pas celle de l'auteur.

CREATE TABLE public.submission_followers (
  submission_id uuid NOT NULL REFERENCES public.submissions(id) ON DELETE CASCADE,
  follower_email text NOT NULL CHECK (follower_email = lower(follower_email)),
  source text NOT NULL CHECK (source IN ('auteur', 'manager', 'volontaire')),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (submission_id, follower_email)
);
CREATE INDEX submission_followers_email_idx ON public.submission_followers (follower_email);

-- REVOKE d'abord : Supabase donne par défaut tous les droits sur une nouvelle table.
-- Lecture seule pour les utilisateurs : les lignes sont écrites par les triggers.
REVOKE ALL ON public.submission_followers FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.submission_followers TO authenticated;
GRANT ALL ON public.submission_followers TO service_role;

ALTER TABLE public.submission_followers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users read own follows" ON public.submission_followers
  FOR SELECT TO authenticated
  USING (private.is_allowed() AND follower_email = lower(auth.jwt() ->> 'email'));

-- Une ligne « auteur » ne se supprime pas tant que la demande et le compte existent :
-- la suppression de la demande (cascade) et celle du compte passent.
CREATE OR REPLACE FUNCTION private.keep_author_follower()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  IF OLD.source = 'auteur'
     AND EXISTS (SELECT 1 FROM public.submissions WHERE id = OLD.submission_id)
     AND EXISTS (SELECT 1 FROM public.allowed_users WHERE lower(email) = OLD.follower_email) THEN
    RAISE EXCEPTION 'L''auteur suit sa demande d''office : ce suivi ne peut pas être supprimé'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN OLD;
END
$function$;

CREATE TRIGGER keep_author_follower
  BEFORE DELETE ON public.submission_followers
  FOR EACH ROW EXECUTE FUNCTION private.keep_author_follower();

CREATE OR REPLACE FUNCTION private.follow_own_submission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  IF NEW.submitted_by_email LIKE '%@%' THEN
    INSERT INTO public.submission_followers (submission_id, follower_email, source)
    VALUES (NEW.id, lower(NEW.submitted_by_email), 'auteur')
    ON CONFLICT (submission_id, follower_email) DO UPDATE SET source = 'auteur';
  END IF;
  RETURN NEW;
END
$function$;

CREATE TRIGGER follow_own_submission
  AFTER INSERT ON public.submissions
  FOR EACH ROW EXECUTE FUNCTION private.follow_own_submission();

REVOKE ALL ON FUNCTION private.keep_author_follower() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.follow_own_submission() FROM PUBLIC, anon, authenticated;

-- Reprise : les demandes existantes sont suivies par leur auteur (sauf auteur supprimé).
INSERT INTO public.submission_followers (submission_id, follower_email, source)
SELECT id, lower(submitted_by_email), 'auteur'
  FROM public.submissions
 WHERE submitted_by_email LIKE '%@%'
ON CONFLICT (submission_id, follower_email) DO NOTHING;

-- Qui a fait le changement : un nom, ou « Automatique » pour la clôture au bout d'un an.
ALTER TABLE public.notifications ADD COLUMN actor_name text;

-- Extrait d'une demande rappelé dans une notification : 60 caractères, sans ponctuation avant « … ».
CREATE OR REPLACE FUNCTION private.submission_excerpt(_content text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public', 'private'
AS $function$
  SELECT CASE WHEN length(c.text) > 60 THEN rtrim(left(c.text, 59), ' ,;:.') || '…' ELSE c.text END
    FROM (SELECT btrim(regexp_replace(_content, '\s+', ' ', 'g')) AS text) c;
$function$;

REVOKE ALL ON FUNCTION private.submission_excerpt(text) FROM PUBLIC, anon, authenticated;

-- Une demande créée notifie les managers de son équipe, sauf son auteur.
-- Une nouvelle étape notifie chaque personne qui suit la demande, sauf celle qui a fait le
-- changement et sauf les admins. « Dans l'app » décoché est ignoré pour l'auteur. old_status vide = création.
CREATE OR REPLACE FUNCTION private.notify_submission_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _what text;
BEGIN
  IF NEW.old_status IS NULL THEN
    INSERT INTO public.notifications (recipient_email, kind, submission_id, message)
    SELECT lower(u.email),
           'nouvelle_demande'::public.notification_kind,
           s.id,
           format('Nouvelle demande de %s (%s)', s.author_name, s.team)
      FROM public.submissions s
      JOIN public.manager_teams mt ON mt.team = s.team
      JOIN public.allowed_users u ON u.id = mt.allowed_user_id
      JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id
     WHERE s.id = NEW.submission_id
       AND r.role = 'manager'::public.app_role
       AND lower(u.email) IS DISTINCT FROM lower(s.submitted_by_email)
       AND private.wants_in_app(u.email, 'nouvelle_demande'::public.notification_kind);
  ELSIF NEW.new_status IS DISTINCT FROM NEW.old_status THEN
    _what := CASE NEW.new_status
      WHEN 'validée'::public.submission_status THEN 'a été validée'
      WHEN 'refusée'::public.submission_status
        THEN 'a été refusée' || COALESCE(' (' || NEW.rejection_category::text || ')', '')
      WHEN 'clôturée'::public.submission_status THEN 'a été clôturée'
      ELSE 'est repassée en attente'
    END;
    INSERT INTO public.notifications (recipient_email, kind, submission_id, message, actor_name)
    SELECT f.follower_email,
           'changement_statut'::public.notification_kind,
           s.id,
           format('Ta demande %s : « %s »', _what, private.submission_excerpt(s.content)),
           CASE WHEN NEW.is_automatic THEN 'Automatique'
                ELSE COALESCE(NEW.changed_by_name, NEW.changed_by_email) END
      FROM public.submissions s
      JOIN public.submission_followers f ON f.submission_id = s.id
      JOIN public.allowed_users u ON lower(u.email) = f.follower_email
      JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id
     WHERE s.id = NEW.submission_id
       AND r.role <> 'admin'::public.app_role
       AND f.follower_email IS DISTINCT FROM lower(NEW.changed_by_email)
       AND (f.source = 'auteur'
            OR private.wants_in_app(f.follower_email, 'changement_statut'::public.notification_kind));
  END IF;
  RETURN NEW;
END
$function$;

-- Lit, puis tente de supprimer les lignes de suivi d'une demande sous le rôle authenticated, donc sous RLS.
CREATE OR REPLACE FUNCTION private.smoke_followers_as(
  _email text,
  _submission uuid,
  OUT _visible int,
  OUT _delete_denied boolean
)
LANGUAGE plpgsql
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('email', _email)::text, true);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO _visible FROM public.submission_followers WHERE submission_id = _submission;
  BEGIN
    DELETE FROM public.submission_followers WHERE submission_id = _submission;
    _delete_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN
    _delete_denied := true;
  END;
  RESET ROLE;
END
$function$;

REVOKE ALL ON FUNCTION private.smoke_followers_as(text, uuid) FROM PUBLIC, anon, authenticated;

-- Compte supprimé : ses suivis disparaissent et son nom sort des alertes qu'il a déclenchées.
CREATE OR REPLACE FUNCTION private.anonymize_removed_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'private' AS $function$
DECLARE _planned boolean := OLD.departure_date IS NOT NULL AND OLD.departure_date <= current_date;
BEGIN
  INSERT INTO public.attachment_deletion_queue (path, delete_after)
  SELECT attachment_path, CASE WHEN _planned THEN now() ELSE now() + interval '7 days' END
    FROM public.submissions
   WHERE lower(submitted_by_email) = lower(OLD.email) AND attachment_path IS NOT NULL
  ON CONFLICT (path) DO NOTHING;

  IF _planned THEN
    UPDATE public.departure_notices SET closed_at = now(), departing_label = 'Utilisateur supprimé'
     WHERE departing_user_id = OLD.id AND closed_at IS NULL;
  ELSE
    PERFORM private.notify_departure(OLD.id, OLD.email, OLD.team, current_date, 'sans préavis');
  END IF;

  DELETE FROM public.notifications WHERE recipient_email = lower(OLD.email);
  DELETE FROM public.notification_preferences WHERE recipient_email = lower(OLD.email);
  DELETE FROM public.submission_followers WHERE follower_email = lower(OLD.email);
  UPDATE public.notifications n
     SET message = format('Nouvelle demande de %s (%s)', 'Utilisateur supprimé', s.team)
    FROM public.submissions s
   WHERE n.submission_id = s.id
     AND n.kind = 'nouvelle_demande'::public.notification_kind
     AND lower(s.submitted_by_email) = lower(OLD.email);
  -- Avant l'anonymisation de l'historique, qui sert à retrouver ses changements.
  UPDATE public.notifications n
     SET actor_name = 'Utilisateur supprimé'
    FROM public.submission_status_history h
   WHERE h.submission_id = n.submission_id
     AND n.kind = 'changement_statut'::public.notification_kind
     AND lower(h.changed_by_email) = lower(OLD.email)
     AND n.actor_name IN (h.changed_by_name, h.changed_by_email);

  UPDATE public.submissions
     SET author_name = 'Utilisateur supprimé', submitted_by_email = 'Utilisateur supprimé'
   WHERE lower(submitted_by_email) = lower(OLD.email);
  UPDATE public.news
     SET author = 'Utilisateur supprimé', author_email = 'Utilisateur supprimé'
   WHERE lower(author_email) = lower(OLD.email);
  UPDATE public.submission_status_history
     SET changed_by_name = 'Utilisateur supprimé', changed_by_email = 'Utilisateur supprimé'
   WHERE lower(changed_by_email) = lower(OLD.email);
  RETURN OLD;
END $function$;

-- Test de fumée mis à jour pour ces règles
CREATE OR REPLACE FUNCTION private.run_smoke_tests()
 RETURNS TABLE(test text, ok boolean, detail text)
 LANGUAGE plpgsql
 SECURITY INVOKER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _res jsonb := '[]'::jsonb;
  _collab uuid; _mgr uuid; _adm uuid;
  _s1 uuid; _s2 uuid; _b uuid; _n uuid;
  _st text; _cnt int; _err text;
  _team text := 'ZZ Test fumée';
  _mgr2 uuid; _nb uuid; _ne uuid; _nm uuid; _nd uuid;
  _ids uuid[]; _with_teams uuid[]; _with_images uuid[] := '{}';
  _reader record; _read record; _want uuid[];
  _mgr3 uuid; _np uuid; _nq uuid; _pub timestamptz; _try record;
  _collab2 uuid; _s3 uuid; _s4 uuid; _notif uuid; _notif_try record; _emails text[];
  _s5 uuid; _pref_try record;
  _s6 uuid; _fol_try record;
BEGIN
  BEGIN
    INSERT INTO teams(name) VALUES (_team), ('ZZ Test fumée autre') ON CONFLICT DO NOTHING;
    INSERT INTO allowed_users(email, team) VALUES ('smoke.collab@test.invalid', _team) RETURNING id INTO _collab;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_collab, 'collaborateur');
    INSERT INTO allowed_users(email) VALUES ('smoke.manager@test.invalid') RETURNING id INTO _mgr;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_mgr, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_mgr, _team);
    INSERT INTO allowed_users(email) VALUES ('smoke.admin@test.invalid') RETURNING id INTO _adm;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_adm, 'admin');

    -- Collaborateur : soumission
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 1') RETURNING id, status::text INTO _s1, _st;
    _res := _res || jsonb_build_object('t', 'Soumission créée « en attente », dans l''équipe du collaborateur',
      'ok', _st = 'en attente' AND (SELECT team FROM submissions WHERE id = _s1) = _team, 'd', _st);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 2') RETURNING id INTO _s2;

    -- Manager : validation et refus
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    BEGIN
      UPDATE submissions SET status = 'validée' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager valide une demande en attente', 'ok', true, 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager valide une demande en attente', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'refusée', rejection_category = 'doublon', rejection_note = 'Test' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager refuse une demande avec un motif', 'ok', true, 'd', 'refusée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager refuse une demande avec un motif', 'ok', false, 'd', SQLERRM);
    END;
    -- Le manager change le statut librement, autant de fois que nécessaire (erreurs humaines)
    BEGIN
      UPDATE submissions SET status = 'clôturée' WHERE id = _s1;
      UPDATE submissions SET status = 'validée' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager corrige une clôture par erreur (clôturée puis validée)', 'ok',
        (SELECT status::text FROM submissions WHERE id = _s1) = 'validée', 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager corrige une clôture par erreur (clôturée puis validée)', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'validée' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager passe un refus en validée, le motif est effacé', 'ok',
        (SELECT rejection_category IS NULL AND rejection_note IS NULL FROM submissions WHERE id = _s2), 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager passe un refus en validée, le motif est effacé', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'en attente' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager remet une demande « en attente »', 'ok', true, 'd', 'en attente');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager remet une demande « en attente »', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET content = 'Contenu modifié par le manager' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager ne peut pas modifier le contenu d''une demande', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager ne peut pas modifier le contenu d''une demande', 'ok', true, 'd', 'refusé par la base');
    END;
    SELECT count(*) INTO _cnt FROM submission_status_history WHERE submission_id IN (_s1, _s2);
    _res := _res || jsonb_build_object('t', 'Historique : 8 lignes (2 créations, 6 changements de statut)', 'ok', _cnt = 8, 'd', _cnt || ' ligne(s)');

    -- Clôture automatique après un an sans modification
    PERFORM set_config('request.jwt.claims', '', true);
    UPDATE submissions SET revalidate_at = now() - interval '1 day' WHERE id = _s1;
    PERFORM private.expire_revalidations();
    SELECT status::text INTO _st FROM submissions WHERE id = _s1;
    _res := _res || jsonb_build_object('t', 'Clôture automatique : une demande validée échue passe « clôturée »', 'ok', _st = 'clôturée', 'd', _st);
    _res := _res || jsonb_build_object('t', 'Clôture automatique : l''historique la marque « Automatique »', 'ok',
      EXISTS (SELECT 1 FROM submission_status_history WHERE submission_id = _s1 AND new_status = 'clôturée' AND is_automatic), 'd', _st);

    -- Points bloquants
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.admin@test.invalid"}', true);
    INSERT INTO blockers(title, department) VALUES ('Blocage de test', 'Test') RETURNING id, status::text INTO _b, _st;
    _res := _res || jsonb_build_object('t', 'Point bloquant créé au statut OUVERT', 'ok', _st = 'OUVERT', 'd', _st);
    BEGIN
      UPDATE blockers SET status = 'RÉSOLU' WHERE id = _b;
      _res := _res || jsonb_build_object('t', 'OUVERT → RÉSOLU refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'OUVERT → RÉSOLU refusé', 'ok', true, 'd', 'refusé par la base');
    END;
    BEGIN
      UPDATE blockers SET status = 'EN COURS' WHERE id = _b;
      UPDATE blockers SET status = 'SURVEILLANCE' WHERE id = _b;
      UPDATE blockers SET status = 'RÉSOLU' WHERE id = _b;
      _res := _res || jsonb_build_object('t', 'OUVERT → EN COURS → SURVEILLANCE → RÉSOLU accepté', 'ok', true, 'd', 'RÉSOLU');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'OUVERT → EN COURS → SURVEILLANCE → RÉSOLU accepté', 'ok', false, 'd', SQLERRM);
    END;

    -- Actualités
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    -- Différée, la contrainte ne se déclencherait qu'au COMMIT, jamais atteint dans ce test.
    SET CONSTRAINTS check_news_audience IMMEDIATE;
    INSERT INTO news(title, body, author, status) VALUES ('Actu de test', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _n;
    BEGIN
      UPDATE news SET status = 'publiée' WHERE id = _n;
      _res := _res || jsonb_build_object('t', 'Publier une actu sans public est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN check_violation THEN
        _res := _res || jsonb_build_object('t', 'Publier une actu sans public est refusé', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Publier une actu sans public est refusé', 'ok', false, 'd', SQLERRM);
    END;
    UPDATE news SET audience = 'équipe' WHERE id = _n;
    BEGIN
      UPDATE news SET status = 'publiée' WHERE id = _n;
      _res := _res || jsonb_build_object('t', 'Publier une actu « équipe » sans équipe est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN check_violation THEN
        _res := _res || jsonb_build_object('t', 'Publier une actu « équipe » sans équipe est refusé', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Publier une actu « équipe » sans équipe est refusé', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      PERFORM public.save_news_audience(_n, 'équipe', ARRAY['ZZ Test fumée autre']);
      _res := _res || jsonb_build_object('t', 'Un manager ne cible pas une équipe qui n''est pas la sienne', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN insufficient_privilege THEN
        _res := _res || jsonb_build_object('t', 'Un manager ne cible pas une équipe qui n''est pas la sienne', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Un manager ne cible pas une équipe qui n''est pas la sienne', 'ok', false, 'd', SQLERRM);
    END;
    PERFORM public.save_news_audience(_n, 'équipe', ARRAY[_team]);
    UPDATE news SET status = 'publiée' WHERE id = _n;
    PERFORM private.expire_revalidations();
    SELECT status::text INTO _st FROM news WHERE id = _n;
    _res := _res || jsonb_build_object('t', 'Actualité : brouillon puis publiée, elle reste publiée après la tâche quotidienne', 'ok', _st = 'publiée', 'd', _st);
    BEGIN
      UPDATE news SET status = 'brouillon' WHERE id = _n;
      _res := _res || jsonb_build_object('t', 'Une actu publiée ne repasse pas en brouillon', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Une actu publiée ne repasse pas en brouillon', 'ok', true, 'd', 'refusé par la base');
    END;
    UPDATE news SET title = 'Actu de test corrigée' WHERE id = _n;
    SELECT status::text INTO _st FROM news WHERE id = _n;
    _res := _res || jsonb_build_object('t', 'Une actu publiée reste modifiable et reste publiée', 'ok', _st = 'publiée', 'd', _st);

    -- Public des actus : lecture réelle sous RLS (voir private.smoke_read_as)
    PERFORM set_config('request.jwt.claims', '', true);
    INSERT INTO allowed_users(email) VALUES ('smoke.manager2@test.invalid') RETURNING id INTO _mgr2;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_mgr2, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_mgr2, 'ZZ Test fumée autre');

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager2@test.invalid"}', true);
    INSERT INTO news(title, body, author, status) VALUES ('Actu équipe B', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _nb;
    PERFORM public.save_news_audience(_nb, 'équipe', ARRAY['ZZ Test fumée autre']);
    UPDATE news SET status = 'publiée' WHERE id = _nb;

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.admin@test.invalid"}', true);
    INSERT INTO news(title, body, author, status) VALUES ('Actu entreprise', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _ne;
    PERFORM public.save_news_audience(_ne, 'entreprise');
    UPDATE news SET status = 'publiée' WHERE id = _ne;
    INSERT INTO news(title, body, author, status) VALUES ('Actu deux équipes', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _nm;
    PERFORM public.save_news_audience(_nm, 'équipe', ARRAY[_team, 'ZZ Test fumée autre']);
    UPDATE news SET status = 'publiée' WHERE id = _nm;

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    INSERT INTO news(title, body, author, status) VALUES ('Brouillon du manager A', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _nd;

    _ids := ARRAY[_n, _nb, _ne, _nm, _nd];
    _with_teams := ARRAY[_n, _nb, _nm];
    -- L'écriture directe dans storage.objects dépend des droits du projet : sans elle, le détail le dit.
    BEGIN
      INSERT INTO storage.objects(bucket_id, name) VALUES ('news-media', _n || '/smoke.png'), ('news-media', _nb || '/smoke.png');
      _with_images := ARRAY[_n, _nb];
    EXCEPTION WHEN insufficient_privilege THEN
      NULL;
    END;

    FOR _reader IN
      SELECT * FROM (VALUES
        ('collaborateur équipe A', 'smoke.collab@test.invalid', ARRAY[_n, _ne, _nm]),
        ('manager équipe A', 'smoke.manager@test.invalid', ARRAY[_n, _ne, _nm, _nd]),
        ('manager équipe B', 'smoke.manager2@test.invalid', ARRAY[_nb, _ne, _nm]),
        ('admin', 'smoke.admin@test.invalid', _ids)
      ) AS v(label, email, ids)
    LOOP
      _want := ARRAY(SELECT unnest(_reader.ids) ORDER BY 1);
      SELECT * INTO _read FROM private.smoke_read_as(_reader.email, _ids);
      _res := _res || jsonb_build_object('t', 'Public des actus : lecture du ' || _reader.label, 'ok',
        _read._news = _want, 'd', cardinality(_read._news) || ' actu(s) lue(s)');
      _res := _res || jsonb_build_object('t', 'Public des actus : équipes ciblées lues par le ' || _reader.label, 'ok',
        _read._teams = ARRAY(SELECT unnest(_want) INTERSECT SELECT unnest(_with_teams) ORDER BY 1),
        'd', cardinality(_read._teams) || ' actu(s)');
      _res := _res || jsonb_build_object('t', 'Public des actus : images lues par le ' || _reader.label, 'ok',
        _read._images = ARRAY(SELECT unnest(_want) INTERSECT SELECT unnest(_with_images) ORDER BY 1),
        'd', CASE WHEN cardinality(_with_images) = 0 THEN 'NON TESTÉ : image de test impossible à créer'
             ELSE cardinality(_read._images) || ' image(s)' END);
    END LOOP;

    -- L'auteur garde ses actus même s'il n'est plus manager de l'équipe ciblée
    PERFORM set_config('request.jwt.claims', '', true);
    UPDATE allowed_user_roles SET role = 'collaborateur' WHERE allowed_user_id = _mgr2;
    DELETE FROM manager_teams WHERE allowed_user_id = _mgr2;
    SELECT * INTO _read FROM private.smoke_read_as('smoke.manager2@test.invalid', _ids);
    _res := _res || jsonb_build_object('t', 'Public des actus : l''auteur lit la sienne même sans rôle manager ni équipe', 'ok',
      _read._news = ARRAY(SELECT unnest(ARRAY[_nb, _ne]) ORDER BY 1), 'd', cardinality(_read._news) || ' actu(s) lue(s)');

    -- Modification d'une actu publiée : écriture réelle sous RLS (voir private.smoke_update_as).
    -- Actus créées dans le passé : dans une transaction, now() ne bouge pas et les dates se confondraient.
    -- Différée comme dans l'application : save_news_audience change le public avant d'écrire les équipes.
    SET CONSTRAINTS check_news_audience DEFERRED;
    PERFORM set_config('request.jwt.claims', '', true);
    INSERT INTO allowed_users(email) VALUES ('smoke.manager3@test.invalid') RETURNING id INTO _mgr3;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_mgr3, 'manager');

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    INSERT INTO news(title, body, author, status, audience, created_at)
    VALUES ('Actu publiée', 'Corps', 'Smoke', 'publiée', 'entreprise', now() - interval '2 days')
    RETURNING id, published_at INTO _np, _pub;

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager3@test.invalid"}', true);
    INSERT INTO news(title, body, author, status, audience, created_at)
    VALUES ('Actu d''un auteur parti', 'Corps', 'Smoke', 'publiée', 'entreprise', now() - interval '2 days')
    RETURNING id INTO _nq;

    SELECT * INTO _try FROM private.smoke_update_as('smoke.manager3@test.invalid', _np, 'Modifiée à tort');
    _res := _res || jsonb_build_object('t', 'Un autre manager ne modifie pas une actu publiée', 'ok',
      _try._rows = 0 AND (SELECT title FROM news WHERE id = _np) = 'Actu publiée', 'd', _try._rows || ' ligne(s)');
    SELECT * INTO _try FROM private.smoke_update_as('smoke.collab@test.invalid', _np, 'Modifiée à tort');
    _res := _res || jsonb_build_object('t', 'Un collaborateur ne modifie pas une actu publiée', 'ok',
      _try._rows = 0 AND (SELECT title FROM news WHERE id = _np) = 'Actu publiée', 'd', _try._rows || ' ligne(s)');

    SELECT * INTO _try FROM private.smoke_update_as('smoke.manager@test.invalid', _np, 'Actu publiée corrigée');
    _res := _res || jsonb_build_object('t', 'Le manager auteur modifie son actu : même date de publication, statut publiée', 'ok',
      _try._rows = 1 AND EXISTS (
        SELECT 1 FROM news WHERE id = _np AND title = 'Actu publiée corrigée' AND status = 'publiée'
          AND published_at = _pub AND updated_at > published_at),
      'd', COALESCE(_try._error, _try._rows || ' ligne(s)'));
    SELECT * INTO _try FROM private.smoke_update_as('smoke.manager@test.invalid', _np, '   ');
    _res := _res || jsonb_build_object('t', 'Une actu publiée ne perd pas son titre', 'ok',
      _try._error IS NOT NULL AND (SELECT title FROM news WHERE id = _np) = 'Actu publiée corrigée', 'd', COALESCE(_try._error, 'accepté à tort'));
    SELECT * INTO _try FROM private.smoke_update_as('smoke.admin@test.invalid', _np, 'Actu corrigée par l''admin');
    _res := _res || jsonb_build_object('t', 'L''admin modifie l''actu d''un manager : auteur et date de publication inchangés', 'ok',
      _try._rows = 1 AND EXISTS (
        SELECT 1 FROM news WHERE id = _np AND title = 'Actu corrigée par l''admin'
          AND author_email = 'smoke.manager@test.invalid' AND published_at = _pub),
      'd', COALESCE(_try._error, _try._rows || ' ligne(s)'));

    BEGIN
      UPDATE news SET author = 'Autre auteur' WHERE id = _np;
      _res := _res || jsonb_build_object('t', 'L''auteur d''une actu publiée ne change pas', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN insufficient_privilege THEN
        _res := _res || jsonb_build_object('t', 'L''auteur d''une actu publiée ne change pas', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'L''auteur d''une actu publiée ne change pas', 'ok', false, 'd', SQLERRM);
    END;

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    BEGIN
      PERFORM public.save_published_news(_np, 'Titre à ne pas garder', 'Corps', '[]', NULL, 'équipe', ARRAY['ZZ Test fumée autre']);
      _res := _res || jsonb_build_object('t', 'Enregistrement refusé : rien ne change, ni le titre ni le public', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN insufficient_privilege THEN
        _res := _res || jsonb_build_object('t', 'Enregistrement refusé : rien ne change, ni le titre ni le public', 'ok',
          EXISTS (SELECT 1 FROM news WHERE id = _np AND title = 'Actu corrigée par l''admin' AND audience = 'entreprise'), 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Enregistrement refusé : rien ne change, ni le titre ni le public', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      PERFORM public.save_published_news(_np, 'Titre et public', 'Corps', '[]', 'autre-actu/image.png', 'entreprise');
      _res := _res || jsonb_build_object('t', 'Une actu ne reprend pas l''image d''une autre', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN check_violation THEN
      _res := _res || jsonb_build_object('t', 'Une actu ne reprend pas l''image d''une autre', 'ok', true, 'd', 'refusé par la base');
    END;
    PERFORM public.save_published_news(_np, 'Titre et public', 'Corps', '[]', NULL, 'équipe', ARRAY[_team]);
    _res := _res || jsonb_build_object('t', 'Enregistrement accepté : le titre et le public changent ensemble', 'ok',
      EXISTS (SELECT 1 FROM news n JOIN news_teams t ON t.news_id = n.id
              WHERE n.id = _np AND n.title = 'Titre et public' AND n.audience = 'équipe' AND t.team = _team), 'd', 'équipe');

    -- Auteur parti : il perd d'abord son rôle, puis son compte. L'anonymisation ne compte pas comme une modification.
    PERFORM set_config('request.jwt.claims', '', true);
    UPDATE allowed_user_roles SET role = 'collaborateur' WHERE allowed_user_id = _mgr3;
    SELECT * INTO _try FROM private.smoke_update_as('smoke.manager3@test.invalid', _nq, 'Modifiée à tort');
    _res := _res || jsonb_build_object('t', 'L''auteur qui n''est plus manager ne modifie plus son actu', 'ok', _try._rows = 0, 'd', _try._rows || ' ligne(s)');
    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      DELETE FROM allowed_users WHERE id = _mgr3;
      _res := _res || jsonb_build_object('t', 'Compte supprimé : auteur anonymisé, sans mention « Modifiée le »', 'ok',
        EXISTS (SELECT 1 FROM news WHERE id = _nq AND author = 'Utilisateur supprimé' AND updated_at = published_at), 'd', 'Utilisateur supprimé');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Compte supprimé : auteur anonymisé, sans mention « Modifiée le »', 'ok', false, 'd', SQLERRM);
    END;
    SELECT * INTO _try FROM private.smoke_update_as('smoke.admin@test.invalid', _nq, 'Actu reprise par l''admin');
    _res := _res || jsonb_build_object('t', 'Auteur supprimé : l''admin modifie encore l''actu', 'ok', _try._rows = 1, 'd', COALESCE(_try._error, _try._rows || ' ligne(s)'));

    -- Centre de notifications : destinataires, puis droits réels sous RLS (voir private.smoke_notification_as).
    -- L'admin a une ligne dans manager_teams pour prouver que le rôle est bien contrôlé.
    PERFORM set_config('request.jwt.claims', '', true);
    -- Le second manager a perdu son rôle et son équipe dans le test « l'auteur lit la sienne ».
    UPDATE allowed_user_roles SET role = 'manager' WHERE allowed_user_id = _mgr2;
    INSERT INTO allowed_users(email, team) VALUES ('smoke.collab2@test.invalid', _team) RETURNING id INTO _collab2;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_collab2, 'collaborateur');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_mgr2, _team), (_adm, _team);

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab2@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 3') RETURNING id INTO _s3;
    SELECT COALESCE(array_agg(recipient_email), '{}') INTO _emails FROM notifications WHERE submission_id = _s3;
    _res := _res || jsonb_build_object('t', 'Une demande créée notifie les managers de son équipe', 'ok',
      _emails @> ARRAY['smoke.manager@test.invalid', 'smoke.manager2@test.invalid'], 'd', array_to_string(_emails, ', '));
    _res := _res || jsonb_build_object('t', 'Une demande créée ne notifie ni son auteur ni un admin', 'ok',
      NOT _emails && ARRAY['smoke.collab2@test.invalid', 'smoke.admin@test.invalid'], 'd', array_to_string(_emails, ', '));
    _res := _res || jsonb_build_object('t', 'Le texte de la notification nomme l''auteur et l''équipe', 'ok',
      EXISTS (SELECT 1 FROM notifications n JOIN submissions s ON s.id = n.submission_id
              WHERE s.id = _s3 AND n.kind = 'nouvelle_demande'
                AND n.message = format('Nouvelle demande de %s (%s)', s.author_name, s.team)), 'd', _team);

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', _team, 'Demande de test 4') RETURNING id INTO _s4;
    SELECT COALESCE(array_agg(recipient_email), '{}') INTO _emails FROM notifications WHERE submission_id = _s4;
    _res := _res || jsonb_build_object('t', 'Un manager n''est pas notifié de sa propre demande', 'ok',
      _emails = ARRAY['smoke.manager2@test.invalid'], 'd', array_to_string(_emails, ', '));

    SELECT id INTO _notif FROM notifications WHERE submission_id = _s3 AND recipient_email = 'smoke.manager@test.invalid';
    SELECT * INTO _notif_try FROM private.smoke_notification_as('smoke.manager2@test.invalid', _notif);
    _res := _res || jsonb_build_object('t', 'Un utilisateur ne lit ni ne marque les notifications d''un autre', 'ok',
      _notif_try._visible = 0 AND _notif_try._marked = 0
      AND (SELECT read_at FROM notifications WHERE id = _notif) IS NULL,
      'd', _notif_try._visible || ' lue(s), ' || _notif_try._marked || ' marquée(s)');
    SELECT * INTO _notif_try FROM private.smoke_notification_as('smoke.manager@test.invalid', _notif);
    _res := _res || jsonb_build_object('t', 'Le destinataire lit sa notification et la marque comme lue', 'ok',
      _notif_try._visible = 1 AND _notif_try._marked = 1
      AND (SELECT read_at FROM notifications WHERE id = _notif) IS NOT NULL,
      'd', _notif_try._visible || ' lue(s), ' || _notif_try._marked || ' marquée(s)');
    _res := _res || jsonb_build_object('t', 'Seul read_at est modifiable : ni autre colonne, ni création, ni suppression', 'ok',
      _notif_try._denied = 3 AND EXISTS (SELECT 1 FROM notifications WHERE id = _notif AND message <> 'Modifiée à tort'),
      'd', _notif_try._denied || ' écriture(s) refusée(s) sur 3');

    -- Préférences de notification : valeurs par défaut, effet de « Dans l'app », droits réels sous RLS
    -- (voir private.smoke_preference_as), puis notification d'un changement de statut.
    PERFORM set_config('request.jwt.claims', '', true);
    _res := _res || jsonb_build_object('t', 'Sans préférence enregistrée : dans l''app et par mail sont actifs', 'ok',
      NOT EXISTS (SELECT 1 FROM notification_preferences WHERE recipient_email = 'smoke.manager@test.invalid')
      AND private.wants_in_app('smoke.manager@test.invalid', 'nouvelle_demande')
      AND private.wants_by_email('smoke.manager@test.invalid', 'nouvelle_demande'), 'd', 'aucune ligne');
    INSERT INTO notification_preferences(recipient_email, kind, in_app)
      VALUES ('smoke.manager@test.invalid', 'nouvelle_demande', false);
    _res := _res || jsonb_build_object('t', 'Une préférence enregistrée sans « par mail » le garde actif', 'ok',
      private.wants_by_email('smoke.manager@test.invalid', 'nouvelle_demande'), 'd', 'by_email par défaut');

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab2@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 5') RETURNING id INTO _s5;
    SELECT COALESCE(array_agg(recipient_email), '{}') INTO _emails FROM notifications WHERE submission_id = _s5;
    _res := _res || jsonb_build_object('t', 'Dans l''app décoché : la notification « nouvelle demande » n''est plus créée', 'ok',
      NOT _emails && ARRAY['smoke.manager@test.invalid'] AND _emails @> ARRAY['smoke.manager2@test.invalid'],
      'd', array_to_string(_emails, ', '));
    _res := _res || jsonb_build_object('t', 'Dans l''app décoché : les notifications déjà reçues restent', 'ok',
      EXISTS (SELECT 1 FROM notifications WHERE id = _notif), 'd', 'notification de la demande 3');

    SELECT * INTO _pref_try FROM private.smoke_preference_as('smoke.manager2@test.invalid', 'smoke.manager@test.invalid');
    _res := _res || jsonb_build_object('t', 'Un utilisateur ne lit ni ne modifie les préférences d''un autre', 'ok',
      _pref_try._visible = 0 AND _pref_try._updated = 0 AND _pref_try._insert_denied
      AND (SELECT by_email FROM notification_preferences
            WHERE recipient_email = 'smoke.manager@test.invalid' AND kind = 'nouvelle_demande'),
      'd', _pref_try._visible || ' lue(s), ' || _pref_try._updated || ' modifiée(s), création '
           || CASE WHEN _pref_try._insert_denied THEN 'refusée' ELSE 'acceptée' END);
    SELECT * INTO _pref_try FROM private.smoke_preference_as('smoke.manager@test.invalid', 'smoke.manager@test.invalid');
    _res := _res || jsonb_build_object('t', 'Un utilisateur lit, modifie et crée ses propres préférences', 'ok',
      _pref_try._visible = 1 AND _pref_try._updated = 1 AND NOT _pref_try._insert_denied,
      'd', _pref_try._visible || ' lue(s), ' || _pref_try._updated || ' modifiée(s), création '
           || CASE WHEN _pref_try._insert_denied THEN 'refusée' ELSE 'acceptée' END);

    -- Alertes de changement d'état (US14) : l'auteur suit sa demande d'office, droits réels sous RLS
    -- (voir private.smoke_followers_as), puis une notification par nouvelle étape du fil.
    PERFORM set_config('request.jwt.claims', '', true);
    _res := _res || jsonb_build_object('t', 'L''auteur suit sa demande dès sa création', 'ok',
      EXISTS (SELECT 1 FROM submission_followers WHERE submission_id = _s5
              AND follower_email = 'smoke.collab2@test.invalid' AND source = 'auteur'), 'd', 'demande 5');
    SELECT * INTO _fol_try FROM private.smoke_followers_as('smoke.collab2@test.invalid', _s5);
    _res := _res || jsonb_build_object('t', 'L''auteur lit son suivi et ne peut pas le supprimer', 'ok',
      _fol_try._visible = 1 AND _fol_try._delete_denied,
      'd', _fol_try._visible || ' lue(s), suppression ' || CASE WHEN _fol_try._delete_denied THEN 'refusée' ELSE 'acceptée' END);
    SELECT * INTO _fol_try FROM private.smoke_followers_as('smoke.manager2@test.invalid', _s5);
    _res := _res || jsonb_build_object('t', 'Un autre utilisateur ne lit pas le suivi d''une demande', 'ok',
      _fol_try._visible = 0, 'd', _fol_try._visible || ' lue(s)');
    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      DELETE FROM submission_followers WHERE submission_id = _s5 AND source = 'auteur';
      _res := _res || jsonb_build_object('t', 'On ne peut pas supprimer une ligne « auteur »', 'ok', false, 'd', 'acceptée à tort');
    EXCEPTION WHEN insufficient_privilege THEN
      _res := _res || jsonb_build_object('t', 'On ne peut pas supprimer une ligne « auteur »', 'ok',
        EXISTS (SELECT 1 FROM submission_followers WHERE submission_id = _s5 AND source = 'auteur'), 'd', 'refusée par la base');
    END;

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    UPDATE submissions SET status = 'validée' WHERE id = _s5;
    SELECT COALESCE(array_agg(recipient_email), '{}') INTO _emails
      FROM notifications WHERE submission_id = _s5 AND kind = 'changement_statut';
    _res := _res || jsonb_build_object('t', 'Une validation notifie l''auteur, et lui seul, avec le nom du manager', 'ok',
      _emails = ARRAY['smoke.collab2@test.invalid']
      AND EXISTS (SELECT 1 FROM notifications WHERE submission_id = _s5 AND kind = 'changement_statut'
                  AND message = 'Ta demande a été validée : « Demande de test 5 »'
                  AND actor_name = 'smoke.manager@test.invalid'),
      'd', array_to_string(_emails, ', '));
    UPDATE submissions SET status = 'validée' WHERE id = _s4;
    SELECT count(*) INTO _cnt FROM notifications WHERE submission_id = _s4 AND kind = 'changement_statut';
    _res := _res || jsonb_build_object('t', 'Le manager qui valide n''est pas notifié de sa propre action', 'ok',
      _cnt = 0, 'd', _cnt || ' notification(s)');
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab2@test.invalid"}', true);
    UPDATE submissions SET status = 'en attente' WHERE id = _s5;
    SELECT count(*) INTO _cnt FROM notifications WHERE submission_id = _s5 AND kind = 'changement_statut';
    _res := _res || jsonb_build_object('t', 'L''auteur n''est pas notifié d''un statut qu''il change lui-même', 'ok',
      _cnt = 1, 'd', _cnt || ' notification(s)');

    PERFORM set_config('request.jwt.claims', '', true);
    INSERT INTO notification_preferences(recipient_email, kind, in_app)
      VALUES ('smoke.collab2@test.invalid', 'changement_statut', false);
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    UPDATE submissions SET status = 'refusée', rejection_category = 'doublon', rejection_note = 'Test' WHERE id = _s5;
    SELECT count(*) INTO _cnt FROM notifications WHERE submission_id = _s5 AND kind = 'changement_statut';
    _res := _res || jsonb_build_object('t', 'Dans l''app décoché n''empêche pas l''alerte de l''auteur (refus avec sa catégorie)', 'ok',
      _cnt = 2 AND EXISTS (SELECT 1 FROM notifications WHERE submission_id = _s5
                           AND message = 'Ta demande a été refusée (doublon) : « Demande de test 5 »'),
      'd', _cnt || ' notification(s)');
    UPDATE submissions SET status = 'validée' WHERE id = _s5;
    PERFORM set_config('request.jwt.claims', '', true);
    UPDATE submissions SET revalidate_at = now() - interval '1 day' WHERE id = _s5;
    PERFORM private.expire_revalidations();
    _res := _res || jsonb_build_object('t', 'La clôture automatique notifie l''auteur, signée « Automatique »', 'ok',
      EXISTS (SELECT 1 FROM notifications WHERE submission_id = _s5 AND kind = 'changement_statut'
              AND message = 'Ta demande a été clôturée : « Demande de test 5 »' AND actor_name = 'Automatique'),
      'd', (SELECT status::text FROM submissions WHERE id = _s5));

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.admin@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', _team, 'Demande de test 6') RETURNING id INTO _s6;
    -- Une demande d'admin est rangée dans l'équipe « Admin », hors de portée des managers :
    -- le changement est fait sous le compte du collaborateur (ce test tourne sans RLS).
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab@test.invalid"}', true);
    UPDATE submissions SET status = 'validée' WHERE id = _s6;
    _res := _res || jsonb_build_object('t', 'Un admin auteur suit sa demande mais n''est pas notifié', 'ok',
      EXISTS (SELECT 1 FROM submission_followers WHERE submission_id = _s6 AND follower_email = 'smoke.admin@test.invalid')
      AND NOT EXISTS (SELECT 1 FROM notifications WHERE submission_id = _s6 AND kind = 'changement_statut'),
      'd', 'demande 6');
    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      DELETE FROM submissions WHERE id = _s6;
      _res := _res || jsonb_build_object('t', 'Une demande supprimée emporte son suivi', 'ok',
        NOT EXISTS (SELECT 1 FROM submission_followers WHERE submission_id = _s6), 'd', 'demande 6');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Une demande supprimée emporte son suivi', 'ok', false, 'd', SQLERRM);
    END;

    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      DELETE FROM allowed_users WHERE id IN (_collab2, _mgr2);
      _res := _res || jsonb_build_object('t', 'Compte supprimé : son nom sort des messages, ses notifications disparaissent', 'ok',
        EXISTS (SELECT 1 FROM notifications WHERE id = _notif
                AND message = format('Nouvelle demande de Utilisateur supprimé (%s)', _team))
        AND NOT EXISTS (SELECT 1 FROM notifications WHERE recipient_email = 'smoke.manager2@test.invalid'),
        'd', 'Utilisateur supprimé');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Compte supprimé : son nom sort des messages, ses notifications disparaissent', 'ok', false, 'd', SQLERRM);
    END;
    _res := _res || jsonb_build_object('t', 'Compte supprimé : ses préférences de notification disparaissent', 'ok',
      NOT EXISTS (SELECT 1 FROM notification_preferences WHERE recipient_email = 'smoke.collab2@test.invalid'), 'd', 'smoke.collab2');
    _res := _res || jsonb_build_object('t', 'Compte supprimé : son suivi des demandes disparaît', 'ok',
      NOT EXISTS (SELECT 1 FROM submission_followers WHERE follower_email = 'smoke.collab2@test.invalid'), 'd', 'smoke.collab2');
    DELETE FROM manager_teams WHERE allowed_user_id = _adm;

    INSERT INTO notifications(recipient_email, kind, message, created_at) VALUES
      ('smoke.manager@test.invalid', 'nouvelle_demande', 'Ancienne', now() - interval '31 days'),
      ('smoke.manager@test.invalid', 'nouvelle_demande', 'Récente', now() - interval '29 days');
    PERFORM private.purge_notifications();
    _res := _res || jsonb_build_object('t', 'La purge efface les notifications de plus de 30 jours, pas les autres', 'ok',
      NOT EXISTS (SELECT 1 FROM notifications WHERE message = 'Ancienne')
      AND EXISTS (SELECT 1 FROM notifications WHERE message = 'Récente'), 'd', '30 jours');

    -- Référentiel des équipes
    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      UPDATE teams SET name = 'ZZ Test fumée 2' WHERE name = _team;
      _res := _res || jsonb_build_object('t', 'Référentiel : renommer une équipe met à jour utilisateurs, managers et demandes', 'ok',
        (SELECT team FROM allowed_users WHERE id = _collab) = 'ZZ Test fumée 2'
        AND (SELECT team FROM manager_teams WHERE allowed_user_id = _mgr) = 'ZZ Test fumée 2'
        AND (SELECT team FROM submissions WHERE id = _s1) = 'ZZ Test fumée 2', 'd', 'ZZ Test fumée 2');
      _res := _res || jsonb_build_object('t', 'Référentiel : renommer une équipe met à jour le public des actus', 'ok',
        (SELECT team FROM news_teams WHERE news_id = _n) = 'ZZ Test fumée 2', 'd', 'ZZ Test fumée 2');
      _team := 'ZZ Test fumée 2';
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Référentiel : renommer une équipe met à jour utilisateurs, managers et demandes', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      DELETE FROM teams WHERE name = _team;
      _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN foreign_key_violation THEN
        _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', false, 'd', SQLERRM);
    END;

    RAISE EXCEPTION 'HP_SMOKE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'HP_SMOKE_ROLLBACK' THEN
      _res := _res || jsonb_build_object('t', 'Exécution du test de fumée', 'ok', false, 'd', 'Erreur inattendue : ' || SQLERRM);
    END IF;
  END;

  SELECT count(*) INTO _cnt FROM private.audit_enum_literals();
  _res := _res || jsonb_build_object('t', 'Aucune valeur d''ENUM obsolète dans les fonctions', 'ok', _cnt = 0, 'd', _cnt || ' anomalie(s)');

  RETURN QUERY SELECT x->>'t', (x->>'ok')::boolean, x->>'d' FROM jsonb_array_elements(_res) x;
END;
$function$;

DO $$
DECLARE _bad text;
BEGIN
  SELECT string_agg(test || ' : ' || COALESCE(detail, ''), ' | ') INTO _bad FROM private.run_smoke_tests() WHERE NOT ok;
  IF _bad IS NOT NULL THEN
    RAISE EXCEPTION 'Smoke tests failed: %', _bad;
  END IF;
END $$;
COMMIT;

-- ---------- 20261103130000_type_demandes_suivies.sql ----------
BEGIN;
-- Alertes selon le contexte : un type distinct pour les demandes qu'on suit sans en être l'auteur.
-- Séparé de la migration suivante : une valeur d'ENUM ajoutée ne peut pas être
-- utilisée dans la même transaction.
ALTER TYPE public.notification_kind ADD VALUE IF NOT EXISTS 'changement_statut_suivi';
COMMIT;

-- ---------- 20261103130100_alertes_selon_contexte.sql ----------
BEGIN;
-- Alertes selon le contexte. L'auteur garde « Ta demande… », toujours dans l'app ; une personne
-- qui suit la demande sans en être l'auteur (sources de l'US15) reçoit « La demande de <auteur>… »,
-- de type changement_statut_suivi, et peut décocher « Dans l'app » pour ce type.

-- Une demande créée notifie les managers de son équipe, sauf son auteur.
-- Une nouvelle étape notifie chaque personne qui suit la demande, sauf celle qui a fait le
-- changement et sauf les admins. L'auteur reçoit « Ta demande… » (type changement_statut, toujours
-- dans l'app) ; les autres « La demande de <auteur>… » (type changement_statut_suivi, selon leur
-- choix « Dans l'app »). old_status vide = création.
CREATE OR REPLACE FUNCTION private.notify_submission_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _what text;
BEGIN
  IF NEW.old_status IS NULL THEN
    INSERT INTO public.notifications (recipient_email, kind, submission_id, message)
    SELECT lower(u.email),
           'nouvelle_demande'::public.notification_kind,
           s.id,
           format('Nouvelle demande de %s (%s)', s.author_name, s.team)
      FROM public.submissions s
      JOIN public.manager_teams mt ON mt.team = s.team
      JOIN public.allowed_users u ON u.id = mt.allowed_user_id
      JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id
     WHERE s.id = NEW.submission_id
       AND r.role = 'manager'::public.app_role
       AND lower(u.email) IS DISTINCT FROM lower(s.submitted_by_email)
       AND private.wants_in_app(u.email, 'nouvelle_demande'::public.notification_kind);
  ELSIF NEW.new_status IS DISTINCT FROM NEW.old_status THEN
    _what := CASE NEW.new_status
      WHEN 'validée'::public.submission_status THEN 'a été validée'
      WHEN 'refusée'::public.submission_status
        THEN 'a été refusée' || COALESCE(' (' || NEW.rejection_category::text || ')', '')
      WHEN 'clôturée'::public.submission_status THEN 'a été clôturée'
      ELSE 'est repassée en attente'
    END;
    INSERT INTO public.notifications (recipient_email, kind, submission_id, message, actor_name)
    SELECT f.follower_email,
           CASE WHEN f.source = 'auteur' THEN 'changement_statut'::public.notification_kind
                ELSE 'changement_statut_suivi'::public.notification_kind END,
           s.id,
           format('%s %s : « %s »',
                  CASE WHEN f.source = 'auteur' THEN 'Ta demande' ELSE 'La demande de ' || s.author_name END,
                  _what, private.submission_excerpt(s.content)),
           CASE WHEN NEW.is_automatic THEN 'Automatique'
                ELSE COALESCE(NEW.changed_by_name, NEW.changed_by_email) END
      FROM public.submissions s
      JOIN public.submission_followers f ON f.submission_id = s.id
      JOIN public.allowed_users u ON lower(u.email) = f.follower_email
      JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id
     WHERE s.id = NEW.submission_id
       AND r.role <> 'admin'::public.app_role
       AND f.follower_email IS DISTINCT FROM lower(NEW.changed_by_email)
       AND (f.source = 'auteur'
            OR private.wants_in_app(f.follower_email, 'changement_statut_suivi'::public.notification_kind));
  END IF;
  RETURN NEW;
END
$function$;

-- Compte supprimé : ses suivis disparaissent et son nom sort des alertes qu'il a déclenchées
-- comme de celles reçues par les personnes qui suivaient ses demandes.
CREATE OR REPLACE FUNCTION private.anonymize_removed_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'private' AS $function$
DECLARE _planned boolean := OLD.departure_date IS NOT NULL AND OLD.departure_date <= current_date;
BEGIN
  INSERT INTO public.attachment_deletion_queue (path, delete_after)
  SELECT attachment_path, CASE WHEN _planned THEN now() ELSE now() + interval '7 days' END
    FROM public.submissions
   WHERE lower(submitted_by_email) = lower(OLD.email) AND attachment_path IS NOT NULL
  ON CONFLICT (path) DO NOTHING;

  IF _planned THEN
    UPDATE public.departure_notices SET closed_at = now(), departing_label = 'Utilisateur supprimé'
     WHERE departing_user_id = OLD.id AND closed_at IS NULL;
  ELSE
    PERFORM private.notify_departure(OLD.id, OLD.email, OLD.team, current_date, 'sans préavis');
  END IF;

  DELETE FROM public.notifications WHERE recipient_email = lower(OLD.email);
  DELETE FROM public.notification_preferences WHERE recipient_email = lower(OLD.email);
  DELETE FROM public.submission_followers WHERE follower_email = lower(OLD.email);
  UPDATE public.notifications n
     SET message = format('Nouvelle demande de %s (%s)', 'Utilisateur supprimé', s.team)
    FROM public.submissions s
   WHERE n.submission_id = s.id
     AND n.kind = 'nouvelle_demande'::public.notification_kind
     AND lower(s.submitted_by_email) = lower(OLD.email);
  -- Avant l'anonymisation de ses demandes, dont le nom d'auteur sert à retrouver le début du texte.
  UPDATE public.notifications n
     SET message = 'La demande de Utilisateur supprimé'
                   || substr(n.message, length('La demande de ' || s.author_name) + 1)
    FROM public.submissions s
   WHERE n.submission_id = s.id
     AND n.kind = 'changement_statut_suivi'::public.notification_kind
     AND lower(s.submitted_by_email) = lower(OLD.email)
     AND starts_with(n.message, 'La demande de ' || s.author_name || ' ');
  -- Avant l'anonymisation de l'historique, qui sert à retrouver ses changements.
  UPDATE public.notifications n
     SET actor_name = 'Utilisateur supprimé'
    FROM public.submission_status_history h
   WHERE h.submission_id = n.submission_id
     AND n.kind IN ('changement_statut'::public.notification_kind,
                    'changement_statut_suivi'::public.notification_kind)
     AND lower(h.changed_by_email) = lower(OLD.email)
     AND n.actor_name IN (h.changed_by_name, h.changed_by_email);

  UPDATE public.submissions
     SET author_name = 'Utilisateur supprimé', submitted_by_email = 'Utilisateur supprimé'
   WHERE lower(submitted_by_email) = lower(OLD.email);
  UPDATE public.news
     SET author = 'Utilisateur supprimé', author_email = 'Utilisateur supprimé'
   WHERE lower(author_email) = lower(OLD.email);
  UPDATE public.submission_status_history
     SET changed_by_name = 'Utilisateur supprimé', changed_by_email = 'Utilisateur supprimé'
   WHERE lower(changed_by_email) = lower(OLD.email);
  RETURN OLD;
END $function$;

-- Test de fumée mis à jour pour ces règles
CREATE OR REPLACE FUNCTION private.run_smoke_tests()
 RETURNS TABLE(test text, ok boolean, detail text)
 LANGUAGE plpgsql
 SECURITY INVOKER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _res jsonb := '[]'::jsonb;
  _collab uuid; _mgr uuid; _adm uuid;
  _s1 uuid; _s2 uuid; _b uuid; _n uuid;
  _st text; _cnt int; _err text;
  _team text := 'ZZ Test fumée';
  _mgr2 uuid; _nb uuid; _ne uuid; _nm uuid; _nd uuid;
  _ids uuid[]; _with_teams uuid[]; _with_images uuid[] := '{}';
  _reader record; _read record; _want uuid[];
  _mgr3 uuid; _np uuid; _nq uuid; _pub timestamptz; _try record;
  _collab2 uuid; _s3 uuid; _s4 uuid; _notif uuid; _notif_try record; _emails text[];
  _s5 uuid; _pref_try record;
  _s6 uuid; _fol_try record; _cnt2 int;
BEGIN
  BEGIN
    INSERT INTO teams(name) VALUES (_team), ('ZZ Test fumée autre') ON CONFLICT DO NOTHING;
    INSERT INTO allowed_users(email, team) VALUES ('smoke.collab@test.invalid', _team) RETURNING id INTO _collab;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_collab, 'collaborateur');
    INSERT INTO allowed_users(email) VALUES ('smoke.manager@test.invalid') RETURNING id INTO _mgr;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_mgr, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_mgr, _team);
    INSERT INTO allowed_users(email) VALUES ('smoke.admin@test.invalid') RETURNING id INTO _adm;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_adm, 'admin');

    -- Collaborateur : soumission
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 1') RETURNING id, status::text INTO _s1, _st;
    _res := _res || jsonb_build_object('t', 'Soumission créée « en attente », dans l''équipe du collaborateur',
      'ok', _st = 'en attente' AND (SELECT team FROM submissions WHERE id = _s1) = _team, 'd', _st);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 2') RETURNING id INTO _s2;

    -- Manager : validation et refus
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    BEGIN
      UPDATE submissions SET status = 'validée' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager valide une demande en attente', 'ok', true, 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager valide une demande en attente', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'refusée', rejection_category = 'doublon', rejection_note = 'Test' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager refuse une demande avec un motif', 'ok', true, 'd', 'refusée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager refuse une demande avec un motif', 'ok', false, 'd', SQLERRM);
    END;
    -- Le manager change le statut librement, autant de fois que nécessaire (erreurs humaines)
    BEGIN
      UPDATE submissions SET status = 'clôturée' WHERE id = _s1;
      UPDATE submissions SET status = 'validée' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager corrige une clôture par erreur (clôturée puis validée)', 'ok',
        (SELECT status::text FROM submissions WHERE id = _s1) = 'validée', 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager corrige une clôture par erreur (clôturée puis validée)', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'validée' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager passe un refus en validée, le motif est effacé', 'ok',
        (SELECT rejection_category IS NULL AND rejection_note IS NULL FROM submissions WHERE id = _s2), 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager passe un refus en validée, le motif est effacé', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'en attente' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager remet une demande « en attente »', 'ok', true, 'd', 'en attente');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager remet une demande « en attente »', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET content = 'Contenu modifié par le manager' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager ne peut pas modifier le contenu d''une demande', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager ne peut pas modifier le contenu d''une demande', 'ok', true, 'd', 'refusé par la base');
    END;
    SELECT count(*) INTO _cnt FROM submission_status_history WHERE submission_id IN (_s1, _s2);
    _res := _res || jsonb_build_object('t', 'Historique : 8 lignes (2 créations, 6 changements de statut)', 'ok', _cnt = 8, 'd', _cnt || ' ligne(s)');

    -- Clôture automatique après un an sans modification
    PERFORM set_config('request.jwt.claims', '', true);
    UPDATE submissions SET revalidate_at = now() - interval '1 day' WHERE id = _s1;
    PERFORM private.expire_revalidations();
    SELECT status::text INTO _st FROM submissions WHERE id = _s1;
    _res := _res || jsonb_build_object('t', 'Clôture automatique : une demande validée échue passe « clôturée »', 'ok', _st = 'clôturée', 'd', _st);
    _res := _res || jsonb_build_object('t', 'Clôture automatique : l''historique la marque « Automatique »', 'ok',
      EXISTS (SELECT 1 FROM submission_status_history WHERE submission_id = _s1 AND new_status = 'clôturée' AND is_automatic), 'd', _st);

    -- Points bloquants
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.admin@test.invalid"}', true);
    INSERT INTO blockers(title, department) VALUES ('Blocage de test', 'Test') RETURNING id, status::text INTO _b, _st;
    _res := _res || jsonb_build_object('t', 'Point bloquant créé au statut OUVERT', 'ok', _st = 'OUVERT', 'd', _st);
    BEGIN
      UPDATE blockers SET status = 'RÉSOLU' WHERE id = _b;
      _res := _res || jsonb_build_object('t', 'OUVERT → RÉSOLU refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'OUVERT → RÉSOLU refusé', 'ok', true, 'd', 'refusé par la base');
    END;
    BEGIN
      UPDATE blockers SET status = 'EN COURS' WHERE id = _b;
      UPDATE blockers SET status = 'SURVEILLANCE' WHERE id = _b;
      UPDATE blockers SET status = 'RÉSOLU' WHERE id = _b;
      _res := _res || jsonb_build_object('t', 'OUVERT → EN COURS → SURVEILLANCE → RÉSOLU accepté', 'ok', true, 'd', 'RÉSOLU');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'OUVERT → EN COURS → SURVEILLANCE → RÉSOLU accepté', 'ok', false, 'd', SQLERRM);
    END;

    -- Actualités
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    -- Différée, la contrainte ne se déclencherait qu'au COMMIT, jamais atteint dans ce test.
    SET CONSTRAINTS check_news_audience IMMEDIATE;
    INSERT INTO news(title, body, author, status) VALUES ('Actu de test', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _n;
    BEGIN
      UPDATE news SET status = 'publiée' WHERE id = _n;
      _res := _res || jsonb_build_object('t', 'Publier une actu sans public est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN check_violation THEN
        _res := _res || jsonb_build_object('t', 'Publier une actu sans public est refusé', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Publier une actu sans public est refusé', 'ok', false, 'd', SQLERRM);
    END;
    UPDATE news SET audience = 'équipe' WHERE id = _n;
    BEGIN
      UPDATE news SET status = 'publiée' WHERE id = _n;
      _res := _res || jsonb_build_object('t', 'Publier une actu « équipe » sans équipe est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN check_violation THEN
        _res := _res || jsonb_build_object('t', 'Publier une actu « équipe » sans équipe est refusé', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Publier une actu « équipe » sans équipe est refusé', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      PERFORM public.save_news_audience(_n, 'équipe', ARRAY['ZZ Test fumée autre']);
      _res := _res || jsonb_build_object('t', 'Un manager ne cible pas une équipe qui n''est pas la sienne', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN insufficient_privilege THEN
        _res := _res || jsonb_build_object('t', 'Un manager ne cible pas une équipe qui n''est pas la sienne', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Un manager ne cible pas une équipe qui n''est pas la sienne', 'ok', false, 'd', SQLERRM);
    END;
    PERFORM public.save_news_audience(_n, 'équipe', ARRAY[_team]);
    UPDATE news SET status = 'publiée' WHERE id = _n;
    PERFORM private.expire_revalidations();
    SELECT status::text INTO _st FROM news WHERE id = _n;
    _res := _res || jsonb_build_object('t', 'Actualité : brouillon puis publiée, elle reste publiée après la tâche quotidienne', 'ok', _st = 'publiée', 'd', _st);
    BEGIN
      UPDATE news SET status = 'brouillon' WHERE id = _n;
      _res := _res || jsonb_build_object('t', 'Une actu publiée ne repasse pas en brouillon', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Une actu publiée ne repasse pas en brouillon', 'ok', true, 'd', 'refusé par la base');
    END;
    UPDATE news SET title = 'Actu de test corrigée' WHERE id = _n;
    SELECT status::text INTO _st FROM news WHERE id = _n;
    _res := _res || jsonb_build_object('t', 'Une actu publiée reste modifiable et reste publiée', 'ok', _st = 'publiée', 'd', _st);

    -- Public des actus : lecture réelle sous RLS (voir private.smoke_read_as)
    PERFORM set_config('request.jwt.claims', '', true);
    INSERT INTO allowed_users(email) VALUES ('smoke.manager2@test.invalid') RETURNING id INTO _mgr2;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_mgr2, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_mgr2, 'ZZ Test fumée autre');

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager2@test.invalid"}', true);
    INSERT INTO news(title, body, author, status) VALUES ('Actu équipe B', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _nb;
    PERFORM public.save_news_audience(_nb, 'équipe', ARRAY['ZZ Test fumée autre']);
    UPDATE news SET status = 'publiée' WHERE id = _nb;

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.admin@test.invalid"}', true);
    INSERT INTO news(title, body, author, status) VALUES ('Actu entreprise', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _ne;
    PERFORM public.save_news_audience(_ne, 'entreprise');
    UPDATE news SET status = 'publiée' WHERE id = _ne;
    INSERT INTO news(title, body, author, status) VALUES ('Actu deux équipes', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _nm;
    PERFORM public.save_news_audience(_nm, 'équipe', ARRAY[_team, 'ZZ Test fumée autre']);
    UPDATE news SET status = 'publiée' WHERE id = _nm;

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    INSERT INTO news(title, body, author, status) VALUES ('Brouillon du manager A', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _nd;

    _ids := ARRAY[_n, _nb, _ne, _nm, _nd];
    _with_teams := ARRAY[_n, _nb, _nm];
    -- L'écriture directe dans storage.objects dépend des droits du projet : sans elle, le détail le dit.
    BEGIN
      INSERT INTO storage.objects(bucket_id, name) VALUES ('news-media', _n || '/smoke.png'), ('news-media', _nb || '/smoke.png');
      _with_images := ARRAY[_n, _nb];
    EXCEPTION WHEN insufficient_privilege THEN
      NULL;
    END;

    FOR _reader IN
      SELECT * FROM (VALUES
        ('collaborateur équipe A', 'smoke.collab@test.invalid', ARRAY[_n, _ne, _nm]),
        ('manager équipe A', 'smoke.manager@test.invalid', ARRAY[_n, _ne, _nm, _nd]),
        ('manager équipe B', 'smoke.manager2@test.invalid', ARRAY[_nb, _ne, _nm]),
        ('admin', 'smoke.admin@test.invalid', _ids)
      ) AS v(label, email, ids)
    LOOP
      _want := ARRAY(SELECT unnest(_reader.ids) ORDER BY 1);
      SELECT * INTO _read FROM private.smoke_read_as(_reader.email, _ids);
      _res := _res || jsonb_build_object('t', 'Public des actus : lecture du ' || _reader.label, 'ok',
        _read._news = _want, 'd', cardinality(_read._news) || ' actu(s) lue(s)');
      _res := _res || jsonb_build_object('t', 'Public des actus : équipes ciblées lues par le ' || _reader.label, 'ok',
        _read._teams = ARRAY(SELECT unnest(_want) INTERSECT SELECT unnest(_with_teams) ORDER BY 1),
        'd', cardinality(_read._teams) || ' actu(s)');
      _res := _res || jsonb_build_object('t', 'Public des actus : images lues par le ' || _reader.label, 'ok',
        _read._images = ARRAY(SELECT unnest(_want) INTERSECT SELECT unnest(_with_images) ORDER BY 1),
        'd', CASE WHEN cardinality(_with_images) = 0 THEN 'NON TESTÉ : image de test impossible à créer'
             ELSE cardinality(_read._images) || ' image(s)' END);
    END LOOP;

    -- L'auteur garde ses actus même s'il n'est plus manager de l'équipe ciblée
    PERFORM set_config('request.jwt.claims', '', true);
    UPDATE allowed_user_roles SET role = 'collaborateur' WHERE allowed_user_id = _mgr2;
    DELETE FROM manager_teams WHERE allowed_user_id = _mgr2;
    SELECT * INTO _read FROM private.smoke_read_as('smoke.manager2@test.invalid', _ids);
    _res := _res || jsonb_build_object('t', 'Public des actus : l''auteur lit la sienne même sans rôle manager ni équipe', 'ok',
      _read._news = ARRAY(SELECT unnest(ARRAY[_nb, _ne]) ORDER BY 1), 'd', cardinality(_read._news) || ' actu(s) lue(s)');

    -- Modification d'une actu publiée : écriture réelle sous RLS (voir private.smoke_update_as).
    -- Actus créées dans le passé : dans une transaction, now() ne bouge pas et les dates se confondraient.
    -- Différée comme dans l'application : save_news_audience change le public avant d'écrire les équipes.
    SET CONSTRAINTS check_news_audience DEFERRED;
    PERFORM set_config('request.jwt.claims', '', true);
    INSERT INTO allowed_users(email) VALUES ('smoke.manager3@test.invalid') RETURNING id INTO _mgr3;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_mgr3, 'manager');

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    INSERT INTO news(title, body, author, status, audience, created_at)
    VALUES ('Actu publiée', 'Corps', 'Smoke', 'publiée', 'entreprise', now() - interval '2 days')
    RETURNING id, published_at INTO _np, _pub;

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager3@test.invalid"}', true);
    INSERT INTO news(title, body, author, status, audience, created_at)
    VALUES ('Actu d''un auteur parti', 'Corps', 'Smoke', 'publiée', 'entreprise', now() - interval '2 days')
    RETURNING id INTO _nq;

    SELECT * INTO _try FROM private.smoke_update_as('smoke.manager3@test.invalid', _np, 'Modifiée à tort');
    _res := _res || jsonb_build_object('t', 'Un autre manager ne modifie pas une actu publiée', 'ok',
      _try._rows = 0 AND (SELECT title FROM news WHERE id = _np) = 'Actu publiée', 'd', _try._rows || ' ligne(s)');
    SELECT * INTO _try FROM private.smoke_update_as('smoke.collab@test.invalid', _np, 'Modifiée à tort');
    _res := _res || jsonb_build_object('t', 'Un collaborateur ne modifie pas une actu publiée', 'ok',
      _try._rows = 0 AND (SELECT title FROM news WHERE id = _np) = 'Actu publiée', 'd', _try._rows || ' ligne(s)');

    SELECT * INTO _try FROM private.smoke_update_as('smoke.manager@test.invalid', _np, 'Actu publiée corrigée');
    _res := _res || jsonb_build_object('t', 'Le manager auteur modifie son actu : même date de publication, statut publiée', 'ok',
      _try._rows = 1 AND EXISTS (
        SELECT 1 FROM news WHERE id = _np AND title = 'Actu publiée corrigée' AND status = 'publiée'
          AND published_at = _pub AND updated_at > published_at),
      'd', COALESCE(_try._error, _try._rows || ' ligne(s)'));
    SELECT * INTO _try FROM private.smoke_update_as('smoke.manager@test.invalid', _np, '   ');
    _res := _res || jsonb_build_object('t', 'Une actu publiée ne perd pas son titre', 'ok',
      _try._error IS NOT NULL AND (SELECT title FROM news WHERE id = _np) = 'Actu publiée corrigée', 'd', COALESCE(_try._error, 'accepté à tort'));
    SELECT * INTO _try FROM private.smoke_update_as('smoke.admin@test.invalid', _np, 'Actu corrigée par l''admin');
    _res := _res || jsonb_build_object('t', 'L''admin modifie l''actu d''un manager : auteur et date de publication inchangés', 'ok',
      _try._rows = 1 AND EXISTS (
        SELECT 1 FROM news WHERE id = _np AND title = 'Actu corrigée par l''admin'
          AND author_email = 'smoke.manager@test.invalid' AND published_at = _pub),
      'd', COALESCE(_try._error, _try._rows || ' ligne(s)'));

    BEGIN
      UPDATE news SET author = 'Autre auteur' WHERE id = _np;
      _res := _res || jsonb_build_object('t', 'L''auteur d''une actu publiée ne change pas', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN insufficient_privilege THEN
        _res := _res || jsonb_build_object('t', 'L''auteur d''une actu publiée ne change pas', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'L''auteur d''une actu publiée ne change pas', 'ok', false, 'd', SQLERRM);
    END;

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    BEGIN
      PERFORM public.save_published_news(_np, 'Titre à ne pas garder', 'Corps', '[]', NULL, 'équipe', ARRAY['ZZ Test fumée autre']);
      _res := _res || jsonb_build_object('t', 'Enregistrement refusé : rien ne change, ni le titre ni le public', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN insufficient_privilege THEN
        _res := _res || jsonb_build_object('t', 'Enregistrement refusé : rien ne change, ni le titre ni le public', 'ok',
          EXISTS (SELECT 1 FROM news WHERE id = _np AND title = 'Actu corrigée par l''admin' AND audience = 'entreprise'), 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Enregistrement refusé : rien ne change, ni le titre ni le public', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      PERFORM public.save_published_news(_np, 'Titre et public', 'Corps', '[]', 'autre-actu/image.png', 'entreprise');
      _res := _res || jsonb_build_object('t', 'Une actu ne reprend pas l''image d''une autre', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN check_violation THEN
      _res := _res || jsonb_build_object('t', 'Une actu ne reprend pas l''image d''une autre', 'ok', true, 'd', 'refusé par la base');
    END;
    PERFORM public.save_published_news(_np, 'Titre et public', 'Corps', '[]', NULL, 'équipe', ARRAY[_team]);
    _res := _res || jsonb_build_object('t', 'Enregistrement accepté : le titre et le public changent ensemble', 'ok',
      EXISTS (SELECT 1 FROM news n JOIN news_teams t ON t.news_id = n.id
              WHERE n.id = _np AND n.title = 'Titre et public' AND n.audience = 'équipe' AND t.team = _team), 'd', 'équipe');

    -- Auteur parti : il perd d'abord son rôle, puis son compte. L'anonymisation ne compte pas comme une modification.
    PERFORM set_config('request.jwt.claims', '', true);
    UPDATE allowed_user_roles SET role = 'collaborateur' WHERE allowed_user_id = _mgr3;
    SELECT * INTO _try FROM private.smoke_update_as('smoke.manager3@test.invalid', _nq, 'Modifiée à tort');
    _res := _res || jsonb_build_object('t', 'L''auteur qui n''est plus manager ne modifie plus son actu', 'ok', _try._rows = 0, 'd', _try._rows || ' ligne(s)');
    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      DELETE FROM allowed_users WHERE id = _mgr3;
      _res := _res || jsonb_build_object('t', 'Compte supprimé : auteur anonymisé, sans mention « Modifiée le »', 'ok',
        EXISTS (SELECT 1 FROM news WHERE id = _nq AND author = 'Utilisateur supprimé' AND updated_at = published_at), 'd', 'Utilisateur supprimé');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Compte supprimé : auteur anonymisé, sans mention « Modifiée le »', 'ok', false, 'd', SQLERRM);
    END;
    SELECT * INTO _try FROM private.smoke_update_as('smoke.admin@test.invalid', _nq, 'Actu reprise par l''admin');
    _res := _res || jsonb_build_object('t', 'Auteur supprimé : l''admin modifie encore l''actu', 'ok', _try._rows = 1, 'd', COALESCE(_try._error, _try._rows || ' ligne(s)'));

    -- Centre de notifications : destinataires, puis droits réels sous RLS (voir private.smoke_notification_as).
    -- L'admin a une ligne dans manager_teams pour prouver que le rôle est bien contrôlé.
    PERFORM set_config('request.jwt.claims', '', true);
    -- Le second manager a perdu son rôle et son équipe dans le test « l'auteur lit la sienne ».
    UPDATE allowed_user_roles SET role = 'manager' WHERE allowed_user_id = _mgr2;
    INSERT INTO allowed_users(email, team) VALUES ('smoke.collab2@test.invalid', _team) RETURNING id INTO _collab2;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_collab2, 'collaborateur');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_mgr2, _team), (_adm, _team);

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab2@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 3') RETURNING id INTO _s3;
    SELECT COALESCE(array_agg(recipient_email), '{}') INTO _emails FROM notifications WHERE submission_id = _s3;
    _res := _res || jsonb_build_object('t', 'Une demande créée notifie les managers de son équipe', 'ok',
      _emails @> ARRAY['smoke.manager@test.invalid', 'smoke.manager2@test.invalid'], 'd', array_to_string(_emails, ', '));
    _res := _res || jsonb_build_object('t', 'Une demande créée ne notifie ni son auteur ni un admin', 'ok',
      NOT _emails && ARRAY['smoke.collab2@test.invalid', 'smoke.admin@test.invalid'], 'd', array_to_string(_emails, ', '));
    _res := _res || jsonb_build_object('t', 'Le texte de la notification nomme l''auteur et l''équipe', 'ok',
      EXISTS (SELECT 1 FROM notifications n JOIN submissions s ON s.id = n.submission_id
              WHERE s.id = _s3 AND n.kind = 'nouvelle_demande'
                AND n.message = format('Nouvelle demande de %s (%s)', s.author_name, s.team)), 'd', _team);

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', _team, 'Demande de test 4') RETURNING id INTO _s4;
    SELECT COALESCE(array_agg(recipient_email), '{}') INTO _emails FROM notifications WHERE submission_id = _s4;
    _res := _res || jsonb_build_object('t', 'Un manager n''est pas notifié de sa propre demande', 'ok',
      _emails = ARRAY['smoke.manager2@test.invalid'], 'd', array_to_string(_emails, ', '));

    SELECT id INTO _notif FROM notifications WHERE submission_id = _s3 AND recipient_email = 'smoke.manager@test.invalid';
    SELECT * INTO _notif_try FROM private.smoke_notification_as('smoke.manager2@test.invalid', _notif);
    _res := _res || jsonb_build_object('t', 'Un utilisateur ne lit ni ne marque les notifications d''un autre', 'ok',
      _notif_try._visible = 0 AND _notif_try._marked = 0
      AND (SELECT read_at FROM notifications WHERE id = _notif) IS NULL,
      'd', _notif_try._visible || ' lue(s), ' || _notif_try._marked || ' marquée(s)');
    SELECT * INTO _notif_try FROM private.smoke_notification_as('smoke.manager@test.invalid', _notif);
    _res := _res || jsonb_build_object('t', 'Le destinataire lit sa notification et la marque comme lue', 'ok',
      _notif_try._visible = 1 AND _notif_try._marked = 1
      AND (SELECT read_at FROM notifications WHERE id = _notif) IS NOT NULL,
      'd', _notif_try._visible || ' lue(s), ' || _notif_try._marked || ' marquée(s)');
    _res := _res || jsonb_build_object('t', 'Seul read_at est modifiable : ni autre colonne, ni création, ni suppression', 'ok',
      _notif_try._denied = 3 AND EXISTS (SELECT 1 FROM notifications WHERE id = _notif AND message <> 'Modifiée à tort'),
      'd', _notif_try._denied || ' écriture(s) refusée(s) sur 3');

    -- Préférences de notification : valeurs par défaut, effet de « Dans l'app », droits réels sous RLS
    -- (voir private.smoke_preference_as), puis notification d'un changement de statut.
    PERFORM set_config('request.jwt.claims', '', true);
    _res := _res || jsonb_build_object('t', 'Sans préférence enregistrée : dans l''app et par mail sont actifs', 'ok',
      NOT EXISTS (SELECT 1 FROM notification_preferences WHERE recipient_email = 'smoke.manager@test.invalid')
      AND private.wants_in_app('smoke.manager@test.invalid', 'nouvelle_demande')
      AND private.wants_by_email('smoke.manager@test.invalid', 'nouvelle_demande'), 'd', 'aucune ligne');
    INSERT INTO notification_preferences(recipient_email, kind, in_app)
      VALUES ('smoke.manager@test.invalid', 'nouvelle_demande', false);
    _res := _res || jsonb_build_object('t', 'Une préférence enregistrée sans « par mail » le garde actif', 'ok',
      private.wants_by_email('smoke.manager@test.invalid', 'nouvelle_demande'), 'd', 'by_email par défaut');

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab2@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 5') RETURNING id INTO _s5;
    SELECT COALESCE(array_agg(recipient_email), '{}') INTO _emails FROM notifications WHERE submission_id = _s5;
    _res := _res || jsonb_build_object('t', 'Dans l''app décoché : la notification « nouvelle demande » n''est plus créée', 'ok',
      NOT _emails && ARRAY['smoke.manager@test.invalid'] AND _emails @> ARRAY['smoke.manager2@test.invalid'],
      'd', array_to_string(_emails, ', '));
    _res := _res || jsonb_build_object('t', 'Dans l''app décoché : les notifications déjà reçues restent', 'ok',
      EXISTS (SELECT 1 FROM notifications WHERE id = _notif), 'd', 'notification de la demande 3');

    SELECT * INTO _pref_try FROM private.smoke_preference_as('smoke.manager2@test.invalid', 'smoke.manager@test.invalid');
    _res := _res || jsonb_build_object('t', 'Un utilisateur ne lit ni ne modifie les préférences d''un autre', 'ok',
      _pref_try._visible = 0 AND _pref_try._updated = 0 AND _pref_try._insert_denied
      AND (SELECT by_email FROM notification_preferences
            WHERE recipient_email = 'smoke.manager@test.invalid' AND kind = 'nouvelle_demande'),
      'd', _pref_try._visible || ' lue(s), ' || _pref_try._updated || ' modifiée(s), création '
           || CASE WHEN _pref_try._insert_denied THEN 'refusée' ELSE 'acceptée' END);
    SELECT * INTO _pref_try FROM private.smoke_preference_as('smoke.manager@test.invalid', 'smoke.manager@test.invalid');
    _res := _res || jsonb_build_object('t', 'Un utilisateur lit, modifie et crée ses propres préférences', 'ok',
      _pref_try._visible = 1 AND _pref_try._updated = 1 AND NOT _pref_try._insert_denied,
      'd', _pref_try._visible || ' lue(s), ' || _pref_try._updated || ' modifiée(s), création '
           || CASE WHEN _pref_try._insert_denied THEN 'refusée' ELSE 'acceptée' END);

    -- Alertes de changement d'état (US14) : l'auteur suit sa demande d'office, droits réels sous RLS
    -- (voir private.smoke_followers_as), puis une notification par nouvelle étape du fil.
    PERFORM set_config('request.jwt.claims', '', true);
    _res := _res || jsonb_build_object('t', 'L''auteur suit sa demande dès sa création', 'ok',
      EXISTS (SELECT 1 FROM submission_followers WHERE submission_id = _s5
              AND follower_email = 'smoke.collab2@test.invalid' AND source = 'auteur'), 'd', 'demande 5');
    SELECT * INTO _fol_try FROM private.smoke_followers_as('smoke.collab2@test.invalid', _s5);
    _res := _res || jsonb_build_object('t', 'L''auteur lit son suivi et ne peut pas le supprimer', 'ok',
      _fol_try._visible = 1 AND _fol_try._delete_denied,
      'd', _fol_try._visible || ' lue(s), suppression ' || CASE WHEN _fol_try._delete_denied THEN 'refusée' ELSE 'acceptée' END);
    SELECT * INTO _fol_try FROM private.smoke_followers_as('smoke.manager2@test.invalid', _s5);
    _res := _res || jsonb_build_object('t', 'Un autre utilisateur ne lit pas le suivi d''une demande', 'ok',
      _fol_try._visible = 0, 'd', _fol_try._visible || ' lue(s)');
    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      DELETE FROM submission_followers WHERE submission_id = _s5 AND source = 'auteur';
      _res := _res || jsonb_build_object('t', 'On ne peut pas supprimer une ligne « auteur »', 'ok', false, 'd', 'acceptée à tort');
    EXCEPTION WHEN insufficient_privilege THEN
      _res := _res || jsonb_build_object('t', 'On ne peut pas supprimer une ligne « auteur »', 'ok',
        EXISTS (SELECT 1 FROM submission_followers WHERE submission_id = _s5 AND source = 'auteur'), 'd', 'refusée par la base');
    END;

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    UPDATE submissions SET status = 'validée' WHERE id = _s5;
    SELECT COALESCE(array_agg(recipient_email), '{}') INTO _emails
      FROM notifications WHERE submission_id = _s5 AND kind = 'changement_statut';
    _res := _res || jsonb_build_object('t', 'Une validation notifie l''auteur, et lui seul, avec le nom du manager', 'ok',
      _emails = ARRAY['smoke.collab2@test.invalid']
      AND EXISTS (SELECT 1 FROM notifications WHERE submission_id = _s5 AND kind = 'changement_statut'
                  AND message = 'Ta demande a été validée : « Demande de test 5 »'
                  AND actor_name = 'smoke.manager@test.invalid'),
      'd', array_to_string(_emails, ', '));
    UPDATE submissions SET status = 'validée' WHERE id = _s4;
    SELECT count(*) INTO _cnt FROM notifications WHERE submission_id = _s4 AND kind = 'changement_statut';
    _res := _res || jsonb_build_object('t', 'Le manager qui valide n''est pas notifié de sa propre action', 'ok',
      _cnt = 0, 'd', _cnt || ' notification(s)');
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab2@test.invalid"}', true);
    UPDATE submissions SET status = 'en attente' WHERE id = _s5;
    SELECT count(*) INTO _cnt FROM notifications WHERE submission_id = _s5 AND kind = 'changement_statut';
    _res := _res || jsonb_build_object('t', 'L''auteur n''est pas notifié d''un statut qu''il change lui-même', 'ok',
      _cnt = 1, 'd', _cnt || ' notification(s)');

    PERFORM set_config('request.jwt.claims', '', true);
    INSERT INTO notification_preferences(recipient_email, kind, in_app)
      VALUES ('smoke.collab2@test.invalid', 'changement_statut', false);
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    UPDATE submissions SET status = 'refusée', rejection_category = 'doublon', rejection_note = 'Test' WHERE id = _s5;
    SELECT count(*) INTO _cnt FROM notifications WHERE submission_id = _s5 AND kind = 'changement_statut';
    _res := _res || jsonb_build_object('t', 'Dans l''app décoché n''empêche pas l''alerte de l''auteur (refus avec sa catégorie)', 'ok',
      _cnt = 2 AND EXISTS (SELECT 1 FROM notifications WHERE submission_id = _s5
                           AND message = 'Ta demande a été refusée (doublon) : « Demande de test 5 »'),
      'd', _cnt || ' notification(s)');
    UPDATE submissions SET status = 'validée' WHERE id = _s5;
    PERFORM set_config('request.jwt.claims', '', true);
    UPDATE submissions SET revalidate_at = now() - interval '1 day' WHERE id = _s5;
    PERFORM private.expire_revalidations();
    _res := _res || jsonb_build_object('t', 'La clôture automatique notifie l''auteur, signée « Automatique »', 'ok',
      EXISTS (SELECT 1 FROM notifications WHERE submission_id = _s5 AND kind = 'changement_statut'
              AND message = 'Ta demande a été clôturée : « Demande de test 5 »' AND actor_name = 'Automatique'),
      'd', (SELECT status::text FROM submissions WHERE id = _s5));

    -- Demande suivie sans en être l'auteur (sources de l'US15) : type et texte distincts,
    -- « Dans l'app » respecté pour elle, jamais pour l'auteur.
    PERFORM set_config('request.jwt.claims', '', true);
    INSERT INTO submission_followers(submission_id, follower_email, source)
      VALUES (_s5, 'smoke.manager2@test.invalid', 'manager');
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    UPDATE submissions SET status = 'en attente' WHERE id = _s5;
    _res := _res || jsonb_build_object('t', 'Une personne qui suit la demande reçoit « La demande de <auteur>… », l''auteur « Ta demande… »', 'ok',
      EXISTS (SELECT 1 FROM notifications WHERE submission_id = _s5 AND recipient_email = 'smoke.manager2@test.invalid'
              AND kind = 'changement_statut_suivi' AND message = 'La demande de Smoke est repassée en attente : « Demande de test 5 »')
      AND EXISTS (SELECT 1 FROM notifications WHERE submission_id = _s5 AND recipient_email = 'smoke.collab2@test.invalid'
              AND kind = 'changement_statut' AND message = 'Ta demande est repassée en attente : « Demande de test 5 »'),
      'd', 'demande 5');
    PERFORM set_config('request.jwt.claims', '', true);
    INSERT INTO notification_preferences(recipient_email, kind, in_app)
      VALUES ('smoke.manager2@test.invalid', 'changement_statut_suivi', false);
    SELECT count(*) INTO _cnt2 FROM notifications WHERE submission_id = _s5 AND recipient_email = 'smoke.collab2@test.invalid';
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    UPDATE submissions SET status = 'validée' WHERE id = _s5;
    SELECT count(*) INTO _cnt FROM notifications
     WHERE submission_id = _s5 AND recipient_email = 'smoke.manager2@test.invalid' AND kind = 'changement_statut_suivi';
    _res := _res || jsonb_build_object('t', 'Dans l''app décoché pour les demandes suivies : plus d''alerte, l''auteur reste alerté', 'ok',
      _cnt = 1 AND (SELECT count(*) FROM notifications WHERE submission_id = _s5 AND recipient_email = 'smoke.collab2@test.invalid') = _cnt2 + 1,
      'd', _cnt || ' alerte(s) pour la personne qui suit');

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.admin@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', _team, 'Demande de test 6') RETURNING id INTO _s6;
    -- Une demande d'admin est rangée dans l'équipe « Admin », hors de portée des managers :
    -- le changement est fait sous le compte du collaborateur (ce test tourne sans RLS).
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab@test.invalid"}', true);
    UPDATE submissions SET status = 'validée' WHERE id = _s6;
    _res := _res || jsonb_build_object('t', 'Un admin auteur suit sa demande mais n''est pas notifié', 'ok',
      EXISTS (SELECT 1 FROM submission_followers WHERE submission_id = _s6 AND follower_email = 'smoke.admin@test.invalid')
      AND NOT EXISTS (SELECT 1 FROM notifications WHERE submission_id = _s6 AND kind = 'changement_statut'),
      'd', 'demande 6');
    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      DELETE FROM submissions WHERE id = _s6;
      _res := _res || jsonb_build_object('t', 'Une demande supprimée emporte son suivi', 'ok',
        NOT EXISTS (SELECT 1 FROM submission_followers WHERE submission_id = _s6), 'd', 'demande 6');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Une demande supprimée emporte son suivi', 'ok', false, 'd', SQLERRM);
    END;

    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      DELETE FROM allowed_users WHERE id IN (_collab2, _mgr2);
      _res := _res || jsonb_build_object('t', 'Compte supprimé : son nom sort des messages, ses notifications disparaissent', 'ok',
        EXISTS (SELECT 1 FROM notifications WHERE id = _notif
                AND message = format('Nouvelle demande de Utilisateur supprimé (%s)', _team))
        AND NOT EXISTS (SELECT 1 FROM notifications WHERE recipient_email = 'smoke.manager2@test.invalid'),
        'd', 'Utilisateur supprimé');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Compte supprimé : son nom sort des messages, ses notifications disparaissent', 'ok', false, 'd', SQLERRM);
    END;
    _res := _res || jsonb_build_object('t', 'Compte supprimé : ses préférences de notification disparaissent', 'ok',
      NOT EXISTS (SELECT 1 FROM notification_preferences WHERE recipient_email = 'smoke.collab2@test.invalid'), 'd', 'smoke.collab2');
    _res := _res || jsonb_build_object('t', 'Compte supprimé : son suivi des demandes disparaît', 'ok',
      NOT EXISTS (SELECT 1 FROM submission_followers WHERE follower_email = 'smoke.collab2@test.invalid'), 'd', 'smoke.collab2');
    DELETE FROM manager_teams WHERE allowed_user_id = _adm;

    INSERT INTO notifications(recipient_email, kind, message, created_at) VALUES
      ('smoke.manager@test.invalid', 'nouvelle_demande', 'Ancienne', now() - interval '31 days'),
      ('smoke.manager@test.invalid', 'nouvelle_demande', 'Récente', now() - interval '29 days');
    PERFORM private.purge_notifications();
    _res := _res || jsonb_build_object('t', 'La purge efface les notifications de plus de 30 jours, pas les autres', 'ok',
      NOT EXISTS (SELECT 1 FROM notifications WHERE message = 'Ancienne')
      AND EXISTS (SELECT 1 FROM notifications WHERE message = 'Récente'), 'd', '30 jours');

    -- Référentiel des équipes
    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      UPDATE teams SET name = 'ZZ Test fumée 2' WHERE name = _team;
      _res := _res || jsonb_build_object('t', 'Référentiel : renommer une équipe met à jour utilisateurs, managers et demandes', 'ok',
        (SELECT team FROM allowed_users WHERE id = _collab) = 'ZZ Test fumée 2'
        AND (SELECT team FROM manager_teams WHERE allowed_user_id = _mgr) = 'ZZ Test fumée 2'
        AND (SELECT team FROM submissions WHERE id = _s1) = 'ZZ Test fumée 2', 'd', 'ZZ Test fumée 2');
      _res := _res || jsonb_build_object('t', 'Référentiel : renommer une équipe met à jour le public des actus', 'ok',
        (SELECT team FROM news_teams WHERE news_id = _n) = 'ZZ Test fumée 2', 'd', 'ZZ Test fumée 2');
      _team := 'ZZ Test fumée 2';
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Référentiel : renommer une équipe met à jour utilisateurs, managers et demandes', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      DELETE FROM teams WHERE name = _team;
      _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN foreign_key_violation THEN
        _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', false, 'd', SQLERRM);
    END;

    RAISE EXCEPTION 'HP_SMOKE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'HP_SMOKE_ROLLBACK' THEN
      _res := _res || jsonb_build_object('t', 'Exécution du test de fumée', 'ok', false, 'd', 'Erreur inattendue : ' || SQLERRM);
    END IF;
  END;

  SELECT count(*) INTO _cnt FROM private.audit_enum_literals();
  _res := _res || jsonb_build_object('t', 'Aucune valeur d''ENUM obsolète dans les fonctions', 'ok', _cnt = 0, 'd', _cnt || ' anomalie(s)');

  RETURN QUERY SELECT x->>'t', (x->>'ok')::boolean, x->>'d' FROM jsonb_array_elements(_res) x;
END;
$function$;

DO $$
DECLARE _bad text;
BEGIN
  SELECT string_agg(test || ' : ' || COALESCE(detail, ''), ' | ') INTO _bad FROM private.run_smoke_tests() WHERE NOT ok;
  IF _bad IS NOT NULL THEN
    RAISE EXCEPTION 'Smoke tests failed: %', _bad;
  END IF;
END $$;
COMMIT;


-- ---------- 20261103150000_suivi_des_demandes.sql ----------
BEGIN;
-- Suivi d'une demande (US15). Le manager de l'équipe suit d'office chaque demande, dès sa
-- création ; collaborateurs et managers peuvent suivre toute demande qu'ils peuvent lire
-- (source « volontaire »), l'admin aucune. Une alerte n'est créée que si la personne peut encore
-- lire la demande, et une notification d'une demande devenue illisible ne s'affiche plus.

-- La règle « Allowed read submissions », pour un autre utilisateur que celui connecté.
CREATE OR REPLACE FUNCTION private.can_read_submission(_email text, _submission uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
  SELECT EXISTS (
    SELECT 1
      FROM public.submissions s
      JOIN public.allowed_users u ON u.email = lower(_email)
      JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id
     WHERE s.id = _submission
       AND (r.role = 'admin'::public.app_role
            OR lower(s.submitted_by_email) = lower(_email)
            OR s.status = 'validée'::public.submission_status
            OR (r.role = 'manager'::public.app_role
                AND EXISTS (SELECT 1 FROM public.manager_teams mt
                             WHERE mt.allowed_user_id = u.id AND lower(mt.team) = lower(s.team))))
  );
$function$;

REVOKE ALL ON FUNCTION private.can_read_submission(text, uuid) FROM PUBLIC, anon, authenticated;

-- Les managers de l'équipe au moment de la création suivent la demande. Un nouveau manager
-- suit donc les demandes créées après son arrivée ; un admin n'est jamais ajouté.
CREATE OR REPLACE FUNCTION private.follow_team_submission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  INSERT INTO public.submission_followers (submission_id, follower_email, source)
  SELECT NEW.id, lower(u.email), 'manager'
    FROM public.manager_teams mt
    JOIN public.allowed_users u ON u.id = mt.allowed_user_id
    JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id
   WHERE lower(mt.team) = lower(NEW.team)
     AND r.role = 'manager'::public.app_role
  ON CONFLICT (submission_id, follower_email) DO NOTHING;
  RETURN NEW;
END
$function$;

-- Déclenché après follow_own_submission (ordre alphabétique) : un manager auteur garde « auteur ».
CREATE TRIGGER follow_team_submission
  AFTER INSERT ON public.submissions
  FOR EACH ROW EXECUTE FUNCTION private.follow_team_submission();

REVOKE ALL ON FUNCTION private.follow_team_submission() FROM PUBLIC, anon, authenticated;

-- Reprise : les managers actuels suivent les demandes existantes de leurs équipes.
INSERT INTO public.submission_followers (submission_id, follower_email, source)
SELECT s.id, lower(u.email), 'manager'
  FROM public.submissions s
  JOIN public.manager_teams mt ON lower(mt.team) = lower(s.team)
  JOIN public.allowed_users u ON u.id = mt.allowed_user_id
  JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id
 WHERE r.role = 'manager'::public.app_role
ON CONFLICT (submission_id, follower_email) DO NOTHING;

-- Suivre : seulement soi-même, en « volontaire », une demande lisible (le sous-select passe par
-- la RLS de submissions), et jamais en tant qu'admin.
-- Ne plus suivre : seulement son propre suivi ; keep_author_follower refuse la ligne « auteur ».
GRANT INSERT (submission_id, follower_email, source), DELETE ON public.submission_followers TO authenticated;

CREATE POLICY "Users follow readable submissions" ON public.submission_followers
  FOR INSERT TO authenticated
  WITH CHECK (
    private.is_allowed()
    AND NOT private.is_admin()
    AND follower_email = lower(auth.jwt() ->> 'email')
    AND source = 'volontaire'
    AND EXISTS (SELECT 1 FROM public.submissions s WHERE s.id = submission_followers.submission_id)
  );

CREATE POLICY "Users unfollow own follows" ON public.submission_followers
  FOR DELETE TO authenticated
  USING (private.is_allowed() AND follower_email = lower(auth.jwt() ->> 'email'));

-- Une notification liée à une demande ne s'affiche que si la demande est encore lisible.
DROP POLICY "Recipients read own notifications" ON public.notifications;
CREATE POLICY "Recipients read own notifications" ON public.notifications
  FOR SELECT TO authenticated
  USING (
    private.is_allowed()
    AND recipient_email = lower(auth.jwt() ->> 'email')
    AND (submission_id IS NULL
         OR EXISTS (SELECT 1 FROM public.submissions s WHERE s.id = notifications.submission_id))
  );

-- Une nouvelle étape notifie chaque personne qui suit la demande et peut encore la lire, sauf
-- celle qui a fait le changement et sauf les admins. L'auteur reçoit « Ta demande… » (type
-- changement_statut, toujours dans l'app) ; les autres « La demande de <auteur>… » (type
-- changement_statut_suivi, selon leur choix « Dans l'app »). old_status vide = création.
CREATE OR REPLACE FUNCTION private.notify_submission_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _what text;
BEGIN
  IF NEW.old_status IS NULL THEN
    INSERT INTO public.notifications (recipient_email, kind, submission_id, message)
    SELECT lower(u.email),
           'nouvelle_demande'::public.notification_kind,
           s.id,
           format('Nouvelle demande de %s (%s)', s.author_name, s.team)
      FROM public.submissions s
      JOIN public.manager_teams mt ON mt.team = s.team
      JOIN public.allowed_users u ON u.id = mt.allowed_user_id
      JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id
     WHERE s.id = NEW.submission_id
       AND r.role = 'manager'::public.app_role
       AND lower(u.email) IS DISTINCT FROM lower(s.submitted_by_email)
       AND private.wants_in_app(u.email, 'nouvelle_demande'::public.notification_kind);
  ELSIF NEW.new_status IS DISTINCT FROM NEW.old_status THEN
    _what := CASE NEW.new_status
      WHEN 'validée'::public.submission_status THEN 'a été validée'
      WHEN 'refusée'::public.submission_status
        THEN 'a été refusée' || COALESCE(' (' || NEW.rejection_category::text || ')', '')
      WHEN 'clôturée'::public.submission_status THEN 'a été clôturée'
      ELSE 'est repassée en attente'
    END;
    INSERT INTO public.notifications (recipient_email, kind, submission_id, message, actor_name)
    SELECT f.follower_email,
           CASE WHEN f.source = 'auteur' THEN 'changement_statut'::public.notification_kind
                ELSE 'changement_statut_suivi'::public.notification_kind END,
           s.id,
           format('%s %s : « %s »',
                  CASE WHEN f.source = 'auteur' THEN 'Ta demande' ELSE 'La demande de ' || s.author_name END,
                  _what, private.submission_excerpt(s.content)),
           CASE WHEN NEW.is_automatic THEN 'Automatique'
                ELSE COALESCE(NEW.changed_by_name, NEW.changed_by_email) END
      FROM public.submissions s
      JOIN public.submission_followers f ON f.submission_id = s.id
      JOIN public.allowed_users u ON lower(u.email) = f.follower_email
      JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id
     WHERE s.id = NEW.submission_id
       AND r.role <> 'admin'::public.app_role
       AND f.follower_email IS DISTINCT FROM lower(NEW.changed_by_email)
       AND private.can_read_submission(f.follower_email, s.id)
       AND (f.source = 'auteur'
            OR private.wants_in_app(f.follower_email, 'changement_statut_suivi'::public.notification_kind));
  END IF;
  RETURN NEW;
END
$function$;

-- Suit (ou ne suit plus) une demande sous le rôle authenticated, donc sous RLS.
CREATE OR REPLACE FUNCTION private.smoke_follow_as(
  _email text,
  _submission uuid,
  _follow boolean,
  OUT _done boolean,
  OUT _error text
)
LANGUAGE plpgsql
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _rows int;
BEGIN
  _done := false;
  PERFORM set_config('request.jwt.claims', json_build_object('email', _email)::text, true);
  SET LOCAL ROLE authenticated;
  BEGIN
    IF _follow THEN
      INSERT INTO public.submission_followers (submission_id, follower_email, source)
      VALUES (_submission, lower(_email), 'volontaire');
      _done := true;
    ELSE
      DELETE FROM public.submission_followers
       WHERE submission_id = _submission AND follower_email = lower(_email);
      GET DIAGNOSTICS _rows = ROW_COUNT;
      _done := _rows > 0;
    END IF;
  EXCEPTION WHEN insufficient_privilege THEN
    _error := 'refusé par la base';
  END;
  RESET ROLE;
END
$function$;

REVOKE ALL ON FUNCTION private.smoke_follow_as(text, uuid, boolean) FROM PUBLIC, anon, authenticated;

-- Test de fumée mis à jour pour ces règles
CREATE OR REPLACE FUNCTION private.run_smoke_tests()
 RETURNS TABLE(test text, ok boolean, detail text)
 LANGUAGE plpgsql
 SECURITY INVOKER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _res jsonb := '[]'::jsonb;
  _collab uuid; _mgr uuid; _adm uuid;
  _s1 uuid; _s2 uuid; _b uuid; _n uuid;
  _st text; _cnt int; _err text;
  _team text := 'ZZ Test fumée';
  _mgr2 uuid; _nb uuid; _ne uuid; _nm uuid; _nd uuid;
  _ids uuid[]; _with_teams uuid[]; _with_images uuid[] := '{}';
  _reader record; _read record; _want uuid[];
  _mgr3 uuid; _np uuid; _nq uuid; _pub timestamptz; _try record;
  _collab2 uuid; _s3 uuid; _s4 uuid; _notif uuid; _notif_try record; _emails text[];
  _s5 uuid; _pref_try record;
  _s6 uuid; _fol_try record; _cnt2 int;
  _s7 uuid; _f record; _notif7 uuid;
BEGIN
  BEGIN
    INSERT INTO teams(name) VALUES (_team), ('ZZ Test fumée autre') ON CONFLICT DO NOTHING;
    INSERT INTO allowed_users(email, team) VALUES ('smoke.collab@test.invalid', _team) RETURNING id INTO _collab;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_collab, 'collaborateur');
    INSERT INTO allowed_users(email) VALUES ('smoke.manager@test.invalid') RETURNING id INTO _mgr;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_mgr, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_mgr, _team);
    INSERT INTO allowed_users(email) VALUES ('smoke.admin@test.invalid') RETURNING id INTO _adm;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_adm, 'admin');

    -- Collaborateur : soumission
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 1') RETURNING id, status::text INTO _s1, _st;
    _res := _res || jsonb_build_object('t', 'Soumission créée « en attente », dans l''équipe du collaborateur',
      'ok', _st = 'en attente' AND (SELECT team FROM submissions WHERE id = _s1) = _team, 'd', _st);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 2') RETURNING id INTO _s2;

    -- Manager : validation et refus
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    BEGIN
      UPDATE submissions SET status = 'validée' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager valide une demande en attente', 'ok', true, 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager valide une demande en attente', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'refusée', rejection_category = 'doublon', rejection_note = 'Test' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager refuse une demande avec un motif', 'ok', true, 'd', 'refusée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager refuse une demande avec un motif', 'ok', false, 'd', SQLERRM);
    END;
    -- Le manager change le statut librement, autant de fois que nécessaire (erreurs humaines)
    BEGIN
      UPDATE submissions SET status = 'clôturée' WHERE id = _s1;
      UPDATE submissions SET status = 'validée' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager corrige une clôture par erreur (clôturée puis validée)', 'ok',
        (SELECT status::text FROM submissions WHERE id = _s1) = 'validée', 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager corrige une clôture par erreur (clôturée puis validée)', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'validée' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager passe un refus en validée, le motif est effacé', 'ok',
        (SELECT rejection_category IS NULL AND rejection_note IS NULL FROM submissions WHERE id = _s2), 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager passe un refus en validée, le motif est effacé', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'en attente' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager remet une demande « en attente »', 'ok', true, 'd', 'en attente');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager remet une demande « en attente »', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET content = 'Contenu modifié par le manager' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager ne peut pas modifier le contenu d''une demande', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager ne peut pas modifier le contenu d''une demande', 'ok', true, 'd', 'refusé par la base');
    END;
    SELECT count(*) INTO _cnt FROM submission_status_history WHERE submission_id IN (_s1, _s2);
    _res := _res || jsonb_build_object('t', 'Historique : 8 lignes (2 créations, 6 changements de statut)', 'ok', _cnt = 8, 'd', _cnt || ' ligne(s)');

    -- Clôture automatique après un an sans modification
    PERFORM set_config('request.jwt.claims', '', true);
    UPDATE submissions SET revalidate_at = now() - interval '1 day' WHERE id = _s1;
    PERFORM private.expire_revalidations();
    SELECT status::text INTO _st FROM submissions WHERE id = _s1;
    _res := _res || jsonb_build_object('t', 'Clôture automatique : une demande validée échue passe « clôturée »', 'ok', _st = 'clôturée', 'd', _st);
    _res := _res || jsonb_build_object('t', 'Clôture automatique : l''historique la marque « Automatique »', 'ok',
      EXISTS (SELECT 1 FROM submission_status_history WHERE submission_id = _s1 AND new_status = 'clôturée' AND is_automatic), 'd', _st);

    -- Points bloquants
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.admin@test.invalid"}', true);
    INSERT INTO blockers(title, department) VALUES ('Blocage de test', 'Test') RETURNING id, status::text INTO _b, _st;
    _res := _res || jsonb_build_object('t', 'Point bloquant créé au statut OUVERT', 'ok', _st = 'OUVERT', 'd', _st);
    BEGIN
      UPDATE blockers SET status = 'RÉSOLU' WHERE id = _b;
      _res := _res || jsonb_build_object('t', 'OUVERT → RÉSOLU refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'OUVERT → RÉSOLU refusé', 'ok', true, 'd', 'refusé par la base');
    END;
    BEGIN
      UPDATE blockers SET status = 'EN COURS' WHERE id = _b;
      UPDATE blockers SET status = 'SURVEILLANCE' WHERE id = _b;
      UPDATE blockers SET status = 'RÉSOLU' WHERE id = _b;
      _res := _res || jsonb_build_object('t', 'OUVERT → EN COURS → SURVEILLANCE → RÉSOLU accepté', 'ok', true, 'd', 'RÉSOLU');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'OUVERT → EN COURS → SURVEILLANCE → RÉSOLU accepté', 'ok', false, 'd', SQLERRM);
    END;

    -- Actualités
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    -- Différée, la contrainte ne se déclencherait qu'au COMMIT, jamais atteint dans ce test.
    SET CONSTRAINTS check_news_audience IMMEDIATE;
    INSERT INTO news(title, body, author, status) VALUES ('Actu de test', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _n;
    BEGIN
      UPDATE news SET status = 'publiée' WHERE id = _n;
      _res := _res || jsonb_build_object('t', 'Publier une actu sans public est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN check_violation THEN
        _res := _res || jsonb_build_object('t', 'Publier une actu sans public est refusé', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Publier une actu sans public est refusé', 'ok', false, 'd', SQLERRM);
    END;
    UPDATE news SET audience = 'équipe' WHERE id = _n;
    BEGIN
      UPDATE news SET status = 'publiée' WHERE id = _n;
      _res := _res || jsonb_build_object('t', 'Publier une actu « équipe » sans équipe est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN check_violation THEN
        _res := _res || jsonb_build_object('t', 'Publier une actu « équipe » sans équipe est refusé', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Publier une actu « équipe » sans équipe est refusé', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      PERFORM public.save_news_audience(_n, 'équipe', ARRAY['ZZ Test fumée autre']);
      _res := _res || jsonb_build_object('t', 'Un manager ne cible pas une équipe qui n''est pas la sienne', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN insufficient_privilege THEN
        _res := _res || jsonb_build_object('t', 'Un manager ne cible pas une équipe qui n''est pas la sienne', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Un manager ne cible pas une équipe qui n''est pas la sienne', 'ok', false, 'd', SQLERRM);
    END;
    PERFORM public.save_news_audience(_n, 'équipe', ARRAY[_team]);
    UPDATE news SET status = 'publiée' WHERE id = _n;
    PERFORM private.expire_revalidations();
    SELECT status::text INTO _st FROM news WHERE id = _n;
    _res := _res || jsonb_build_object('t', 'Actualité : brouillon puis publiée, elle reste publiée après la tâche quotidienne', 'ok', _st = 'publiée', 'd', _st);
    BEGIN
      UPDATE news SET status = 'brouillon' WHERE id = _n;
      _res := _res || jsonb_build_object('t', 'Une actu publiée ne repasse pas en brouillon', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Une actu publiée ne repasse pas en brouillon', 'ok', true, 'd', 'refusé par la base');
    END;
    UPDATE news SET title = 'Actu de test corrigée' WHERE id = _n;
    SELECT status::text INTO _st FROM news WHERE id = _n;
    _res := _res || jsonb_build_object('t', 'Une actu publiée reste modifiable et reste publiée', 'ok', _st = 'publiée', 'd', _st);

    -- Public des actus : lecture réelle sous RLS (voir private.smoke_read_as)
    PERFORM set_config('request.jwt.claims', '', true);
    INSERT INTO allowed_users(email) VALUES ('smoke.manager2@test.invalid') RETURNING id INTO _mgr2;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_mgr2, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_mgr2, 'ZZ Test fumée autre');

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager2@test.invalid"}', true);
    INSERT INTO news(title, body, author, status) VALUES ('Actu équipe B', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _nb;
    PERFORM public.save_news_audience(_nb, 'équipe', ARRAY['ZZ Test fumée autre']);
    UPDATE news SET status = 'publiée' WHERE id = _nb;

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.admin@test.invalid"}', true);
    INSERT INTO news(title, body, author, status) VALUES ('Actu entreprise', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _ne;
    PERFORM public.save_news_audience(_ne, 'entreprise');
    UPDATE news SET status = 'publiée' WHERE id = _ne;
    INSERT INTO news(title, body, author, status) VALUES ('Actu deux équipes', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _nm;
    PERFORM public.save_news_audience(_nm, 'équipe', ARRAY[_team, 'ZZ Test fumée autre']);
    UPDATE news SET status = 'publiée' WHERE id = _nm;

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    INSERT INTO news(title, body, author, status) VALUES ('Brouillon du manager A', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _nd;

    _ids := ARRAY[_n, _nb, _ne, _nm, _nd];
    _with_teams := ARRAY[_n, _nb, _nm];
    -- L'écriture directe dans storage.objects dépend des droits du projet : sans elle, le détail le dit.
    BEGIN
      INSERT INTO storage.objects(bucket_id, name) VALUES ('news-media', _n || '/smoke.png'), ('news-media', _nb || '/smoke.png');
      _with_images := ARRAY[_n, _nb];
    EXCEPTION WHEN insufficient_privilege THEN
      NULL;
    END;

    FOR _reader IN
      SELECT * FROM (VALUES
        ('collaborateur équipe A', 'smoke.collab@test.invalid', ARRAY[_n, _ne, _nm]),
        ('manager équipe A', 'smoke.manager@test.invalid', ARRAY[_n, _ne, _nm, _nd]),
        ('manager équipe B', 'smoke.manager2@test.invalid', ARRAY[_nb, _ne, _nm]),
        ('admin', 'smoke.admin@test.invalid', _ids)
      ) AS v(label, email, ids)
    LOOP
      _want := ARRAY(SELECT unnest(_reader.ids) ORDER BY 1);
      SELECT * INTO _read FROM private.smoke_read_as(_reader.email, _ids);
      _res := _res || jsonb_build_object('t', 'Public des actus : lecture du ' || _reader.label, 'ok',
        _read._news = _want, 'd', cardinality(_read._news) || ' actu(s) lue(s)');
      _res := _res || jsonb_build_object('t', 'Public des actus : équipes ciblées lues par le ' || _reader.label, 'ok',
        _read._teams = ARRAY(SELECT unnest(_want) INTERSECT SELECT unnest(_with_teams) ORDER BY 1),
        'd', cardinality(_read._teams) || ' actu(s)');
      _res := _res || jsonb_build_object('t', 'Public des actus : images lues par le ' || _reader.label, 'ok',
        _read._images = ARRAY(SELECT unnest(_want) INTERSECT SELECT unnest(_with_images) ORDER BY 1),
        'd', CASE WHEN cardinality(_with_images) = 0 THEN 'NON TESTÉ : image de test impossible à créer'
             ELSE cardinality(_read._images) || ' image(s)' END);
    END LOOP;

    -- L'auteur garde ses actus même s'il n'est plus manager de l'équipe ciblée
    PERFORM set_config('request.jwt.claims', '', true);
    UPDATE allowed_user_roles SET role = 'collaborateur' WHERE allowed_user_id = _mgr2;
    DELETE FROM manager_teams WHERE allowed_user_id = _mgr2;
    SELECT * INTO _read FROM private.smoke_read_as('smoke.manager2@test.invalid', _ids);
    _res := _res || jsonb_build_object('t', 'Public des actus : l''auteur lit la sienne même sans rôle manager ni équipe', 'ok',
      _read._news = ARRAY(SELECT unnest(ARRAY[_nb, _ne]) ORDER BY 1), 'd', cardinality(_read._news) || ' actu(s) lue(s)');

    -- Modification d'une actu publiée : écriture réelle sous RLS (voir private.smoke_update_as).
    -- Actus créées dans le passé : dans une transaction, now() ne bouge pas et les dates se confondraient.
    -- Différée comme dans l'application : save_news_audience change le public avant d'écrire les équipes.
    SET CONSTRAINTS check_news_audience DEFERRED;
    PERFORM set_config('request.jwt.claims', '', true);
    INSERT INTO allowed_users(email) VALUES ('smoke.manager3@test.invalid') RETURNING id INTO _mgr3;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_mgr3, 'manager');

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    INSERT INTO news(title, body, author, status, audience, created_at)
    VALUES ('Actu publiée', 'Corps', 'Smoke', 'publiée', 'entreprise', now() - interval '2 days')
    RETURNING id, published_at INTO _np, _pub;

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager3@test.invalid"}', true);
    INSERT INTO news(title, body, author, status, audience, created_at)
    VALUES ('Actu d''un auteur parti', 'Corps', 'Smoke', 'publiée', 'entreprise', now() - interval '2 days')
    RETURNING id INTO _nq;

    SELECT * INTO _try FROM private.smoke_update_as('smoke.manager3@test.invalid', _np, 'Modifiée à tort');
    _res := _res || jsonb_build_object('t', 'Un autre manager ne modifie pas une actu publiée', 'ok',
      _try._rows = 0 AND (SELECT title FROM news WHERE id = _np) = 'Actu publiée', 'd', _try._rows || ' ligne(s)');
    SELECT * INTO _try FROM private.smoke_update_as('smoke.collab@test.invalid', _np, 'Modifiée à tort');
    _res := _res || jsonb_build_object('t', 'Un collaborateur ne modifie pas une actu publiée', 'ok',
      _try._rows = 0 AND (SELECT title FROM news WHERE id = _np) = 'Actu publiée', 'd', _try._rows || ' ligne(s)');

    SELECT * INTO _try FROM private.smoke_update_as('smoke.manager@test.invalid', _np, 'Actu publiée corrigée');
    _res := _res || jsonb_build_object('t', 'Le manager auteur modifie son actu : même date de publication, statut publiée', 'ok',
      _try._rows = 1 AND EXISTS (
        SELECT 1 FROM news WHERE id = _np AND title = 'Actu publiée corrigée' AND status = 'publiée'
          AND published_at = _pub AND updated_at > published_at),
      'd', COALESCE(_try._error, _try._rows || ' ligne(s)'));
    SELECT * INTO _try FROM private.smoke_update_as('smoke.manager@test.invalid', _np, '   ');
    _res := _res || jsonb_build_object('t', 'Une actu publiée ne perd pas son titre', 'ok',
      _try._error IS NOT NULL AND (SELECT title FROM news WHERE id = _np) = 'Actu publiée corrigée', 'd', COALESCE(_try._error, 'accepté à tort'));
    SELECT * INTO _try FROM private.smoke_update_as('smoke.admin@test.invalid', _np, 'Actu corrigée par l''admin');
    _res := _res || jsonb_build_object('t', 'L''admin modifie l''actu d''un manager : auteur et date de publication inchangés', 'ok',
      _try._rows = 1 AND EXISTS (
        SELECT 1 FROM news WHERE id = _np AND title = 'Actu corrigée par l''admin'
          AND author_email = 'smoke.manager@test.invalid' AND published_at = _pub),
      'd', COALESCE(_try._error, _try._rows || ' ligne(s)'));

    BEGIN
      UPDATE news SET author = 'Autre auteur' WHERE id = _np;
      _res := _res || jsonb_build_object('t', 'L''auteur d''une actu publiée ne change pas', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN insufficient_privilege THEN
        _res := _res || jsonb_build_object('t', 'L''auteur d''une actu publiée ne change pas', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'L''auteur d''une actu publiée ne change pas', 'ok', false, 'd', SQLERRM);
    END;

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    BEGIN
      PERFORM public.save_published_news(_np, 'Titre à ne pas garder', 'Corps', '[]', NULL, 'équipe', ARRAY['ZZ Test fumée autre']);
      _res := _res || jsonb_build_object('t', 'Enregistrement refusé : rien ne change, ni le titre ni le public', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN insufficient_privilege THEN
        _res := _res || jsonb_build_object('t', 'Enregistrement refusé : rien ne change, ni le titre ni le public', 'ok',
          EXISTS (SELECT 1 FROM news WHERE id = _np AND title = 'Actu corrigée par l''admin' AND audience = 'entreprise'), 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Enregistrement refusé : rien ne change, ni le titre ni le public', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      PERFORM public.save_published_news(_np, 'Titre et public', 'Corps', '[]', 'autre-actu/image.png', 'entreprise');
      _res := _res || jsonb_build_object('t', 'Une actu ne reprend pas l''image d''une autre', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN check_violation THEN
      _res := _res || jsonb_build_object('t', 'Une actu ne reprend pas l''image d''une autre', 'ok', true, 'd', 'refusé par la base');
    END;
    PERFORM public.save_published_news(_np, 'Titre et public', 'Corps', '[]', NULL, 'équipe', ARRAY[_team]);
    _res := _res || jsonb_build_object('t', 'Enregistrement accepté : le titre et le public changent ensemble', 'ok',
      EXISTS (SELECT 1 FROM news n JOIN news_teams t ON t.news_id = n.id
              WHERE n.id = _np AND n.title = 'Titre et public' AND n.audience = 'équipe' AND t.team = _team), 'd', 'équipe');

    -- Auteur parti : il perd d'abord son rôle, puis son compte. L'anonymisation ne compte pas comme une modification.
    PERFORM set_config('request.jwt.claims', '', true);
    UPDATE allowed_user_roles SET role = 'collaborateur' WHERE allowed_user_id = _mgr3;
    SELECT * INTO _try FROM private.smoke_update_as('smoke.manager3@test.invalid', _nq, 'Modifiée à tort');
    _res := _res || jsonb_build_object('t', 'L''auteur qui n''est plus manager ne modifie plus son actu', 'ok', _try._rows = 0, 'd', _try._rows || ' ligne(s)');
    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      DELETE FROM allowed_users WHERE id = _mgr3;
      _res := _res || jsonb_build_object('t', 'Compte supprimé : auteur anonymisé, sans mention « Modifiée le »', 'ok',
        EXISTS (SELECT 1 FROM news WHERE id = _nq AND author = 'Utilisateur supprimé' AND updated_at = published_at), 'd', 'Utilisateur supprimé');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Compte supprimé : auteur anonymisé, sans mention « Modifiée le »', 'ok', false, 'd', SQLERRM);
    END;
    SELECT * INTO _try FROM private.smoke_update_as('smoke.admin@test.invalid', _nq, 'Actu reprise par l''admin');
    _res := _res || jsonb_build_object('t', 'Auteur supprimé : l''admin modifie encore l''actu', 'ok', _try._rows = 1, 'd', COALESCE(_try._error, _try._rows || ' ligne(s)'));

    -- Centre de notifications : destinataires, puis droits réels sous RLS (voir private.smoke_notification_as).
    -- L'admin a une ligne dans manager_teams pour prouver que le rôle est bien contrôlé.
    PERFORM set_config('request.jwt.claims', '', true);
    -- Le second manager a perdu son rôle et son équipe dans le test « l'auteur lit la sienne ».
    UPDATE allowed_user_roles SET role = 'manager' WHERE allowed_user_id = _mgr2;
    INSERT INTO allowed_users(email, team) VALUES ('smoke.collab2@test.invalid', _team) RETURNING id INTO _collab2;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_collab2, 'collaborateur');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_mgr2, _team), (_adm, _team);

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab2@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 3') RETURNING id INTO _s3;
    SELECT COALESCE(array_agg(recipient_email), '{}') INTO _emails FROM notifications WHERE submission_id = _s3;
    _res := _res || jsonb_build_object('t', 'Une demande créée notifie les managers de son équipe', 'ok',
      _emails @> ARRAY['smoke.manager@test.invalid', 'smoke.manager2@test.invalid'], 'd', array_to_string(_emails, ', '));
    _res := _res || jsonb_build_object('t', 'Une demande créée ne notifie ni son auteur ni un admin', 'ok',
      NOT _emails && ARRAY['smoke.collab2@test.invalid', 'smoke.admin@test.invalid'], 'd', array_to_string(_emails, ', '));
    _res := _res || jsonb_build_object('t', 'Le texte de la notification nomme l''auteur et l''équipe', 'ok',
      EXISTS (SELECT 1 FROM notifications n JOIN submissions s ON s.id = n.submission_id
              WHERE s.id = _s3 AND n.kind = 'nouvelle_demande'
                AND n.message = format('Nouvelle demande de %s (%s)', s.author_name, s.team)), 'd', _team);

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', _team, 'Demande de test 4') RETURNING id INTO _s4;
    SELECT COALESCE(array_agg(recipient_email), '{}') INTO _emails FROM notifications WHERE submission_id = _s4;
    _res := _res || jsonb_build_object('t', 'Un manager n''est pas notifié de sa propre demande', 'ok',
      _emails = ARRAY['smoke.manager2@test.invalid'], 'd', array_to_string(_emails, ', '));

    SELECT id INTO _notif FROM notifications WHERE submission_id = _s3 AND recipient_email = 'smoke.manager@test.invalid';
    SELECT * INTO _notif_try FROM private.smoke_notification_as('smoke.manager2@test.invalid', _notif);
    _res := _res || jsonb_build_object('t', 'Un utilisateur ne lit ni ne marque les notifications d''un autre', 'ok',
      _notif_try._visible = 0 AND _notif_try._marked = 0
      AND (SELECT read_at FROM notifications WHERE id = _notif) IS NULL,
      'd', _notif_try._visible || ' lue(s), ' || _notif_try._marked || ' marquée(s)');
    SELECT * INTO _notif_try FROM private.smoke_notification_as('smoke.manager@test.invalid', _notif);
    _res := _res || jsonb_build_object('t', 'Le destinataire lit sa notification et la marque comme lue', 'ok',
      _notif_try._visible = 1 AND _notif_try._marked = 1
      AND (SELECT read_at FROM notifications WHERE id = _notif) IS NOT NULL,
      'd', _notif_try._visible || ' lue(s), ' || _notif_try._marked || ' marquée(s)');
    _res := _res || jsonb_build_object('t', 'Seul read_at est modifiable : ni autre colonne, ni création, ni suppression', 'ok',
      _notif_try._denied = 3 AND EXISTS (SELECT 1 FROM notifications WHERE id = _notif AND message <> 'Modifiée à tort'),
      'd', _notif_try._denied || ' écriture(s) refusée(s) sur 3');

    -- Préférences de notification : valeurs par défaut, effet de « Dans l'app », droits réels sous RLS
    -- (voir private.smoke_preference_as), puis notification d'un changement de statut.
    PERFORM set_config('request.jwt.claims', '', true);
    _res := _res || jsonb_build_object('t', 'Sans préférence enregistrée : dans l''app et par mail sont actifs', 'ok',
      NOT EXISTS (SELECT 1 FROM notification_preferences WHERE recipient_email = 'smoke.manager@test.invalid')
      AND private.wants_in_app('smoke.manager@test.invalid', 'nouvelle_demande')
      AND private.wants_by_email('smoke.manager@test.invalid', 'nouvelle_demande'), 'd', 'aucune ligne');
    INSERT INTO notification_preferences(recipient_email, kind, in_app)
      VALUES ('smoke.manager@test.invalid', 'nouvelle_demande', false);
    _res := _res || jsonb_build_object('t', 'Une préférence enregistrée sans « par mail » le garde actif', 'ok',
      private.wants_by_email('smoke.manager@test.invalid', 'nouvelle_demande'), 'd', 'by_email par défaut');

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab2@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 5') RETURNING id INTO _s5;
    SELECT COALESCE(array_agg(recipient_email), '{}') INTO _emails FROM notifications WHERE submission_id = _s5;
    _res := _res || jsonb_build_object('t', 'Dans l''app décoché : la notification « nouvelle demande » n''est plus créée', 'ok',
      NOT _emails && ARRAY['smoke.manager@test.invalid'] AND _emails @> ARRAY['smoke.manager2@test.invalid'],
      'd', array_to_string(_emails, ', '));
    _res := _res || jsonb_build_object('t', 'Dans l''app décoché : les notifications déjà reçues restent', 'ok',
      EXISTS (SELECT 1 FROM notifications WHERE id = _notif), 'd', 'notification de la demande 3');

    SELECT * INTO _pref_try FROM private.smoke_preference_as('smoke.manager2@test.invalid', 'smoke.manager@test.invalid');
    _res := _res || jsonb_build_object('t', 'Un utilisateur ne lit ni ne modifie les préférences d''un autre', 'ok',
      _pref_try._visible = 0 AND _pref_try._updated = 0 AND _pref_try._insert_denied
      AND (SELECT by_email FROM notification_preferences
            WHERE recipient_email = 'smoke.manager@test.invalid' AND kind = 'nouvelle_demande'),
      'd', _pref_try._visible || ' lue(s), ' || _pref_try._updated || ' modifiée(s), création '
           || CASE WHEN _pref_try._insert_denied THEN 'refusée' ELSE 'acceptée' END);
    SELECT * INTO _pref_try FROM private.smoke_preference_as('smoke.manager@test.invalid', 'smoke.manager@test.invalid');
    _res := _res || jsonb_build_object('t', 'Un utilisateur lit, modifie et crée ses propres préférences', 'ok',
      _pref_try._visible = 1 AND _pref_try._updated = 1 AND NOT _pref_try._insert_denied,
      'd', _pref_try._visible || ' lue(s), ' || _pref_try._updated || ' modifiée(s), création '
           || CASE WHEN _pref_try._insert_denied THEN 'refusée' ELSE 'acceptée' END);

    -- Alertes de changement d'état (US14) : l'auteur suit sa demande d'office, droits réels sous RLS
    -- (voir private.smoke_followers_as), puis une notification par nouvelle étape du fil.
    PERFORM set_config('request.jwt.claims', '', true);
    _res := _res || jsonb_build_object('t', 'L''auteur suit sa demande dès sa création', 'ok',
      EXISTS (SELECT 1 FROM submission_followers WHERE submission_id = _s5
              AND follower_email = 'smoke.collab2@test.invalid' AND source = 'auteur'), 'd', 'demande 5');
    SELECT * INTO _fol_try FROM private.smoke_followers_as('smoke.collab2@test.invalid', _s5);
    _res := _res || jsonb_build_object('t', 'L''auteur lit son suivi et ne peut pas le supprimer', 'ok',
      _fol_try._visible = 1 AND _fol_try._delete_denied,
      'd', _fol_try._visible || ' lue(s), suppression ' || CASE WHEN _fol_try._delete_denied THEN 'refusée' ELSE 'acceptée' END);
    SELECT * INTO _fol_try FROM private.smoke_followers_as('smoke.collab@test.invalid', _s5);
    _res := _res || jsonb_build_object('t', 'Un autre utilisateur ne lit pas le suivi d''une demande', 'ok',
      _fol_try._visible = 0, 'd', _fol_try._visible || ' lue(s)');
    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      DELETE FROM submission_followers WHERE submission_id = _s5 AND source = 'auteur';
      _res := _res || jsonb_build_object('t', 'On ne peut pas supprimer une ligne « auteur »', 'ok', false, 'd', 'acceptée à tort');
    EXCEPTION WHEN insufficient_privilege THEN
      _res := _res || jsonb_build_object('t', 'On ne peut pas supprimer une ligne « auteur »', 'ok',
        EXISTS (SELECT 1 FROM submission_followers WHERE submission_id = _s5 AND source = 'auteur'), 'd', 'refusée par la base');
    END;

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    UPDATE submissions SET status = 'validée' WHERE id = _s5;
    SELECT COALESCE(array_agg(recipient_email), '{}') INTO _emails
      FROM notifications WHERE submission_id = _s5 AND kind = 'changement_statut';
    _res := _res || jsonb_build_object('t', 'Une validation notifie l''auteur, et lui seul, avec le nom du manager', 'ok',
      _emails = ARRAY['smoke.collab2@test.invalid']
      AND EXISTS (SELECT 1 FROM notifications WHERE submission_id = _s5 AND kind = 'changement_statut'
                  AND message = 'Ta demande a été validée : « Demande de test 5 »'
                  AND actor_name = 'smoke.manager@test.invalid'),
      'd', array_to_string(_emails, ', '));
    UPDATE submissions SET status = 'validée' WHERE id = _s4;
    SELECT count(*) INTO _cnt FROM notifications WHERE submission_id = _s4 AND kind = 'changement_statut';
    _res := _res || jsonb_build_object('t', 'Le manager qui valide n''est pas notifié de sa propre action', 'ok',
      _cnt = 0, 'd', _cnt || ' notification(s)');
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab2@test.invalid"}', true);
    UPDATE submissions SET status = 'en attente' WHERE id = _s5;
    SELECT count(*) INTO _cnt FROM notifications WHERE submission_id = _s5 AND kind = 'changement_statut';
    _res := _res || jsonb_build_object('t', 'L''auteur n''est pas notifié d''un statut qu''il change lui-même', 'ok',
      _cnt = 1, 'd', _cnt || ' notification(s)');

    PERFORM set_config('request.jwt.claims', '', true);
    INSERT INTO notification_preferences(recipient_email, kind, in_app)
      VALUES ('smoke.collab2@test.invalid', 'changement_statut', false);
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    UPDATE submissions SET status = 'refusée', rejection_category = 'doublon', rejection_note = 'Test' WHERE id = _s5;
    SELECT count(*) INTO _cnt FROM notifications WHERE submission_id = _s5 AND kind = 'changement_statut';
    _res := _res || jsonb_build_object('t', 'Dans l''app décoché n''empêche pas l''alerte de l''auteur (refus avec sa catégorie)', 'ok',
      _cnt = 2 AND EXISTS (SELECT 1 FROM notifications WHERE submission_id = _s5
                           AND message = 'Ta demande a été refusée (doublon) : « Demande de test 5 »'),
      'd', _cnt || ' notification(s)');
    UPDATE submissions SET status = 'validée' WHERE id = _s5;
    PERFORM set_config('request.jwt.claims', '', true);
    UPDATE submissions SET revalidate_at = now() - interval '1 day' WHERE id = _s5;
    PERFORM private.expire_revalidations();
    _res := _res || jsonb_build_object('t', 'La clôture automatique notifie l''auteur, signée « Automatique »', 'ok',
      EXISTS (SELECT 1 FROM notifications WHERE submission_id = _s5 AND kind = 'changement_statut'
              AND message = 'Ta demande a été clôturée : « Demande de test 5 »' AND actor_name = 'Automatique'),
      'd', (SELECT status::text FROM submissions WHERE id = _s5));

    -- Demande suivie sans en être l'auteur : type et texte distincts, « Dans l'app » respecté
    -- pour elle, jamais pour l'auteur. Le second manager la suit d'office depuis sa création (US15).
    PERFORM set_config('request.jwt.claims', '', true);
    INSERT INTO submission_followers(submission_id, follower_email, source)
      VALUES (_s5, 'smoke.manager2@test.invalid', 'manager')
    ON CONFLICT (submission_id, follower_email) DO NOTHING;
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    UPDATE submissions SET status = 'en attente' WHERE id = _s5;
    _res := _res || jsonb_build_object('t', 'Une personne qui suit la demande reçoit « La demande de <auteur>… », l''auteur « Ta demande… »', 'ok',
      EXISTS (SELECT 1 FROM notifications WHERE submission_id = _s5 AND recipient_email = 'smoke.manager2@test.invalid'
              AND kind = 'changement_statut_suivi' AND message = 'La demande de Smoke est repassée en attente : « Demande de test 5 »')
      AND EXISTS (SELECT 1 FROM notifications WHERE submission_id = _s5 AND recipient_email = 'smoke.collab2@test.invalid'
              AND kind = 'changement_statut' AND message = 'Ta demande est repassée en attente : « Demande de test 5 »'),
      'd', 'demande 5');
    PERFORM set_config('request.jwt.claims', '', true);
    INSERT INTO notification_preferences(recipient_email, kind, in_app)
      VALUES ('smoke.manager2@test.invalid', 'changement_statut_suivi', false);
    SELECT count(*) INTO _cnt2 FROM notifications WHERE submission_id = _s5 AND recipient_email = 'smoke.collab2@test.invalid';
    SELECT count(*) INTO _cnt FROM notifications
     WHERE submission_id = _s5 AND recipient_email = 'smoke.manager2@test.invalid' AND kind = 'changement_statut_suivi';
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    UPDATE submissions SET status = 'validée' WHERE id = _s5;
    _res := _res || jsonb_build_object('t', 'Dans l''app décoché pour les demandes suivies : plus d''alerte, l''auteur reste alerté', 'ok',
      _cnt = (SELECT count(*) FROM notifications WHERE submission_id = _s5
               AND recipient_email = 'smoke.manager2@test.invalid' AND kind = 'changement_statut_suivi') AND (SELECT count(*) FROM notifications WHERE submission_id = _s5 AND recipient_email = 'smoke.collab2@test.invalid') = _cnt2 + 1,
      'd', _cnt || ' alerte(s) pour la personne qui suit');

    -- Suivi d'une demande (US15) : suivi d'office du manager, suivi volontaire sous RLS
    -- (voir private.smoke_follow_as), puis perte du droit de lire la demande.
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab2@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 7') RETURNING id INTO _s7;
    PERFORM set_config('request.jwt.claims', '', true);
    _res := _res || jsonb_build_object('t', 'Le manager suit d''office une nouvelle demande de son équipe, pas l''admin', 'ok',
      EXISTS (SELECT 1 FROM submission_followers WHERE submission_id = _s7
              AND follower_email = 'smoke.manager@test.invalid' AND source = 'manager')
      AND NOT EXISTS (SELECT 1 FROM submission_followers WHERE submission_id = _s7
                      AND follower_email = 'smoke.admin@test.invalid'),
      'd', 'demande 7');
    SELECT * INTO _f FROM private.smoke_follow_as('smoke.manager@test.invalid', _s7, false);
    _res := _res || jsonb_build_object('t', 'Le manager peut arrêter de suivre une demande de son équipe', 'ok',
      _f._done AND NOT EXISTS (SELECT 1 FROM submission_followers WHERE submission_id = _s7
                               AND follower_email = 'smoke.manager@test.invalid'),
      'd', COALESCE(_f._error, 'suivi supprimé'));
    SELECT * INTO _f FROM private.smoke_follow_as('smoke.manager@test.invalid', _s7, true);
    _res := _res || jsonb_build_object('t', 'Il peut la suivre à nouveau (suivi volontaire)', 'ok',
      _f._done AND EXISTS (SELECT 1 FROM submission_followers WHERE submission_id = _s7
                           AND follower_email = 'smoke.manager@test.invalid' AND source = 'volontaire'),
      'd', COALESCE(_f._error, 'suivi créé'));
    SELECT * INTO _f FROM private.smoke_follow_as('smoke.admin@test.invalid', _s7, true);
    _res := _res || jsonb_build_object('t', 'Un admin ne peut suivre aucune demande', 'ok',
      NOT _f._done AND NOT EXISTS (SELECT 1 FROM submission_followers WHERE submission_id = _s7
                                   AND follower_email = 'smoke.admin@test.invalid'),
      'd', COALESCE(_f._error, 'accepté à tort'));
    SELECT * INTO _f FROM private.smoke_follow_as('smoke.collab@test.invalid', _s7, true);
    _res := _res || jsonb_build_object('t', 'On ne peut pas suivre une demande qu''on ne peut pas lire', 'ok',
      NOT _f._done AND NOT EXISTS (SELECT 1 FROM submission_followers WHERE submission_id = _s7
                                   AND follower_email = 'smoke.collab@test.invalid'),
      'd', COALESCE(_f._error, 'accepté à tort'));
    SELECT * INTO _fol_try FROM private.smoke_followers_as('smoke.collab@test.invalid', _s7);
    _res := _res || jsonb_build_object('t', 'On ne supprime pas le suivi d''une autre personne', 'ok',
      EXISTS (SELECT 1 FROM submission_followers WHERE submission_id = _s7
              AND follower_email = 'smoke.manager2@test.invalid'),
      'd', _fol_try._visible || ' lue(s)');
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager2@test.invalid"}', true);
    UPDATE submissions SET status = 'validée' WHERE id = _s7;
    SELECT * INTO _f FROM private.smoke_follow_as('smoke.collab@test.invalid', _s7, true);
    _res := _res || jsonb_build_object('t', 'Un collaborateur suit une demande validée d''une autre personne', 'ok',
      _f._done AND EXISTS (SELECT 1 FROM submission_followers WHERE submission_id = _s7
                           AND follower_email = 'smoke.collab@test.invalid' AND source = 'volontaire'),
      'd', COALESCE(_f._error, 'suivi créé'));
    PERFORM set_config('request.jwt.claims', '', true);
    INSERT INTO notifications(recipient_email, kind, submission_id, message)
      VALUES ('smoke.collab@test.invalid', 'changement_statut_suivi', _s7,
              'La demande de Smoke a été validée : « Demande de test 7 »')
    RETURNING id INTO _notif7;
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager2@test.invalid"}', true);
    UPDATE submissions SET status = 'clôturée' WHERE id = _s7;
    _res := _res || jsonb_build_object('t', 'Une personne qui a perdu l''accès n''est plus notifiée', 'ok',
      NOT EXISTS (SELECT 1 FROM notifications WHERE submission_id = _s7
                  AND recipient_email = 'smoke.collab@test.invalid' AND id <> _notif7)
      AND EXISTS (SELECT 1 FROM notifications WHERE submission_id = _s7
                  AND recipient_email = 'smoke.manager@test.invalid'
                  AND message = 'La demande de Smoke a été clôturée : « Demande de test 7 »'),
      'd', (SELECT status::text FROM submissions WHERE id = _s7));
    SELECT * INTO _notif_try FROM private.smoke_notification_as('smoke.collab@test.invalid', _notif7);
    _res := _res || jsonb_build_object('t', 'Ses notifications d''une demande devenue illisible ne s''affichent plus', 'ok',
      _notif_try._visible = 0, 'd', _notif_try._visible || ' lue(s)');

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.admin@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', _team, 'Demande de test 6') RETURNING id INTO _s6;
    -- Une demande d'admin est rangée dans l'équipe « Admin », hors de portée des managers :
    -- le changement est fait sous le compte du collaborateur (ce test tourne sans RLS).
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab@test.invalid"}', true);
    UPDATE submissions SET status = 'validée' WHERE id = _s6;
    _res := _res || jsonb_build_object('t', 'Un admin auteur suit sa demande mais n''est pas notifié', 'ok',
      EXISTS (SELECT 1 FROM submission_followers WHERE submission_id = _s6 AND follower_email = 'smoke.admin@test.invalid')
      AND NOT EXISTS (SELECT 1 FROM notifications WHERE submission_id = _s6 AND kind = 'changement_statut'),
      'd', 'demande 6');
    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      DELETE FROM submissions WHERE id = _s6;
      _res := _res || jsonb_build_object('t', 'Une demande supprimée emporte son suivi', 'ok',
        NOT EXISTS (SELECT 1 FROM submission_followers WHERE submission_id = _s6), 'd', 'demande 6');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Une demande supprimée emporte son suivi', 'ok', false, 'd', SQLERRM);
    END;

    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      DELETE FROM allowed_users WHERE id IN (_collab2, _mgr2);
      _res := _res || jsonb_build_object('t', 'Compte supprimé : son nom sort des messages, ses notifications disparaissent', 'ok',
        EXISTS (SELECT 1 FROM notifications WHERE id = _notif
                AND message = format('Nouvelle demande de Utilisateur supprimé (%s)', _team))
        AND NOT EXISTS (SELECT 1 FROM notifications WHERE recipient_email = 'smoke.manager2@test.invalid'),
        'd', 'Utilisateur supprimé');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Compte supprimé : son nom sort des messages, ses notifications disparaissent', 'ok', false, 'd', SQLERRM);
    END;
    _res := _res || jsonb_build_object('t', 'Compte supprimé : ses préférences de notification disparaissent', 'ok',
      NOT EXISTS (SELECT 1 FROM notification_preferences WHERE recipient_email = 'smoke.collab2@test.invalid'), 'd', 'smoke.collab2');
    _res := _res || jsonb_build_object('t', 'Compte supprimé : son suivi des demandes disparaît', 'ok',
      NOT EXISTS (SELECT 1 FROM submission_followers WHERE follower_email = 'smoke.collab2@test.invalid'), 'd', 'smoke.collab2');
    DELETE FROM manager_teams WHERE allowed_user_id = _adm;

    INSERT INTO notifications(recipient_email, kind, message, created_at) VALUES
      ('smoke.manager@test.invalid', 'nouvelle_demande', 'Ancienne', now() - interval '31 days'),
      ('smoke.manager@test.invalid', 'nouvelle_demande', 'Récente', now() - interval '29 days');
    PERFORM private.purge_notifications();
    _res := _res || jsonb_build_object('t', 'La purge efface les notifications de plus de 30 jours, pas les autres', 'ok',
      NOT EXISTS (SELECT 1 FROM notifications WHERE message = 'Ancienne')
      AND EXISTS (SELECT 1 FROM notifications WHERE message = 'Récente'), 'd', '30 jours');

    -- Référentiel des équipes
    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      UPDATE teams SET name = 'ZZ Test fumée 2' WHERE name = _team;
      _res := _res || jsonb_build_object('t', 'Référentiel : renommer une équipe met à jour utilisateurs, managers et demandes', 'ok',
        (SELECT team FROM allowed_users WHERE id = _collab) = 'ZZ Test fumée 2'
        AND (SELECT team FROM manager_teams WHERE allowed_user_id = _mgr) = 'ZZ Test fumée 2'
        AND (SELECT team FROM submissions WHERE id = _s1) = 'ZZ Test fumée 2', 'd', 'ZZ Test fumée 2');
      _res := _res || jsonb_build_object('t', 'Référentiel : renommer une équipe met à jour le public des actus', 'ok',
        (SELECT team FROM news_teams WHERE news_id = _n) = 'ZZ Test fumée 2', 'd', 'ZZ Test fumée 2');
      _team := 'ZZ Test fumée 2';
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Référentiel : renommer une équipe met à jour utilisateurs, managers et demandes', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      DELETE FROM teams WHERE name = _team;
      _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN foreign_key_violation THEN
        _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', false, 'd', SQLERRM);
    END;

    RAISE EXCEPTION 'HP_SMOKE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'HP_SMOKE_ROLLBACK' THEN
      _res := _res || jsonb_build_object('t', 'Exécution du test de fumée', 'ok', false, 'd', 'Erreur inattendue : ' || SQLERRM);
    END IF;
  END;

  SELECT count(*) INTO _cnt FROM private.audit_enum_literals();
  _res := _res || jsonb_build_object('t', 'Aucune valeur d''ENUM obsolète dans les fonctions', 'ok', _cnt = 0, 'd', _cnt || ' anomalie(s)');

  RETURN QUERY SELECT x->>'t', (x->>'ok')::boolean, x->>'d' FROM jsonb_array_elements(_res) x;
END;
$function$;

DO $$
DECLARE _bad text;
BEGIN
  SELECT string_agg(test || ' : ' || COALESCE(detail, ''), ' | ') INTO _bad FROM private.run_smoke_tests() WHERE NOT ok;
  IF _bad IS NOT NULL THEN
    RAISE EXCEPTION 'Smoke tests failed: %', _bad;
  END IF;
END $$;
COMMIT;


-- ---------- 20261103170000_type_point_bloquant_a_revoir.sql ----------
BEGIN;
-- Points bloquants à revoir (US16).
-- Séparé de la migration suivante : une valeur d'ENUM ajoutée ne peut pas être
-- utilisée dans la même transaction.
ALTER TYPE public.notification_kind ADD VALUE IF NOT EXISTS 'point_bloquant_a_revoir';
COMMIT;


-- ---------- 20261103170100_points_bloquants_a_revoir.sql ----------
BEGIN;
-- Points bloquants à revoir (US16). Chaque jour, chaque admin est prévenu des points non résolus
-- sans mise à jour depuis plus de 3 jours ; il n'est pas prévenu à nouveau pour un même point
-- tant que celui-ci n'a pas été modifié depuis sa dernière notification. Les notifications ne
-- sont plus purgées après 30 jours : une notification non lue reste dans la cloche.

-- updated_at est désormais rempli par la base à chaque modification, même faite hors de l'app.
-- Seule la simulation de démo (private.fast_forward_blocker) le recule elle-même.
CREATE OR REPLACE FUNCTION private.touch_blocker_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  IF current_setting('happy_place.simulation', true) IS DISTINCT FROM 'on' THEN
    NEW.updated_at := now();
  END IF;
  RETURN NEW;
END
$function$;

REVOKE ALL ON FUNCTION private.touch_blocker_updated_at() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS touch_blocker_updated_at ON public.blockers;
CREATE TRIGGER touch_blocker_updated_at
  BEFORE UPDATE ON public.blockers
  FOR EACH ROW EXECUTE FUNCTION private.touch_blocker_updated_at();

-- Fin de la purge des notifications de plus de 30 jours (US12).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'purge-notifications-daily') THEN
    PERFORM cron.unschedule('purge-notifications-daily');
  END IF;
END $$;
DROP FUNCTION IF EXISTS private.purge_notifications();

-- Passage quotidien. Chaque admin reçoit une notification par point non résolu sans mise à jour
-- depuis plus de 3 jours, sauf s'il en a déjà une créée depuis la dernière modification du point,
-- ou s'il a décoché « Dans l'app ». N est arrondi au jour inférieur. _only limite le passage à un
-- point (simulation de démo). Renvoie le nombre de notifications créées.
CREATE OR REPLACE FUNCTION private.notify_stale_blockers(_only uuid DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE _count integer;
BEGIN
  INSERT INTO public.notifications (recipient_email, kind, blocker_id, message)
  SELECT a.email,
         'point_bloquant_a_revoir'::public.notification_kind,
         b.id,
         format('Point bloquant à revoir : %s (sans mise à jour depuis %s jours)',
                b.title, floor(extract(epoch FROM now() - b.updated_at) / 86400)::int)
    FROM public.blockers b
   CROSS JOIN (SELECT DISTINCT lower(u.email) AS email
                 FROM public.allowed_users u
                 JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id
                WHERE r.role = 'admin'::public.app_role) a
   WHERE b.status <> 'RÉSOLU'::public.blocker_status
     AND b.updated_at < now() - interval '3 days'
     AND (_only IS NULL OR b.id = _only)
     AND private.wants_in_app(a.email, 'point_bloquant_a_revoir'::public.notification_kind)
     AND NOT EXISTS (
       SELECT 1 FROM public.notifications n
        WHERE n.blocker_id = b.id
          AND n.recipient_email = a.email
          AND n.kind = 'point_bloquant_a_revoir'::public.notification_kind
          AND n.created_at >= b.updated_at);
  GET DIAGNOSTICS _count = ROW_COUNT;
  RETURN _count;
END
$function$;

REVOKE ALL ON FUNCTION private.notify_stale_blockers(uuid) FROM PUBLIC, anon, authenticated;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'notify-stale-blockers-daily') THEN
    PERFORM cron.unschedule('notify-stale-blockers-daily');
  END IF;
END $$;
SELECT cron.schedule('notify-stale-blockers-daily', '45 3 * * *', 'SELECT private.notify_stale_blockers()');

-- Simulation de démo : fait avancer le temps de _by pour un point, sa dernière modification
-- comme ses notifications « à revoir », pour garder leur ordre.
CREATE OR REPLACE FUNCTION private.fast_forward_blocker(_blocker uuid, _by interval)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  PERFORM set_config('happy_place.simulation', 'on', true);
  UPDATE public.blockers SET updated_at = updated_at - _by WHERE id = _blocker;
  PERFORM set_config('happy_place.simulation', '', true);
  UPDATE public.notifications SET created_at = created_at - _by
   WHERE blocker_id = _blocker AND kind = 'point_bloquant_a_revoir'::public.notification_kind;
END
$function$;

REVOKE ALL ON FUNCTION private.fast_forward_blocker(uuid, interval) FROM PUBLIC, anon, authenticated;

-- Pour la présentation : un admin fait comme si 4 jours avaient passé pour un point, puis lance
-- le passage quotidien sur ce point. Renvoie le nombre de notifications créées.
CREATE OR REPLACE FUNCTION public.simuler_point_bloquant_a_revoir(_blocker_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  IF NOT private.is_admin() THEN
    RAISE EXCEPTION 'Seul un admin peut lancer la simulation.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.blockers
                  WHERE id = _blocker_id AND status <> 'RÉSOLU'::public.blocker_status) THEN
    RAISE EXCEPTION 'Ce point bloquant est résolu ou n''existe plus.';
  END IF;
  PERFORM private.fast_forward_blocker(_blocker_id, interval '4 days');
  RETURN private.notify_stale_blockers(_blocker_id);
END
$function$;

REVOKE ALL ON FUNCTION public.simuler_point_bloquant_a_revoir(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.simuler_point_bloquant_a_revoir(uuid) TO authenticated;

-- Test de fumée mis à jour pour les points bloquants à revoir
CREATE OR REPLACE FUNCTION private.run_smoke_tests()
 RETURNS TABLE(test text, ok boolean, detail text)
 LANGUAGE plpgsql
 SECURITY INVOKER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _res jsonb := '[]'::jsonb;
  _collab uuid; _mgr uuid; _adm uuid;
  _s1 uuid; _s2 uuid; _b uuid; _n uuid;
  _st text; _cnt int; _err text;
  _team text := 'ZZ Test fumée';
  _mgr2 uuid; _nb uuid; _ne uuid; _nm uuid; _nd uuid;
  _ids uuid[]; _with_teams uuid[]; _with_images uuid[] := '{}';
  _reader record; _read record; _want uuid[];
  _mgr3 uuid; _np uuid; _nq uuid; _pub timestamptz; _try record;
  _collab2 uuid; _s3 uuid; _s4 uuid; _notif uuid; _notif_try record; _emails text[];
  _s5 uuid; _pref_try record;
  _s6 uuid; _fol_try record; _cnt2 int;
  _s7 uuid; _f record; _notif7 uuid;
  _adm2 uuid; _b16 uuid; _b16r uuid; _b16p uuid; _b16s uuid; _cnt16 int; _sim16 int;
BEGIN
  BEGIN
    INSERT INTO teams(name) VALUES (_team), ('ZZ Test fumée autre') ON CONFLICT DO NOTHING;
    INSERT INTO allowed_users(email, team) VALUES ('smoke.collab@test.invalid', _team) RETURNING id INTO _collab;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_collab, 'collaborateur');
    INSERT INTO allowed_users(email) VALUES ('smoke.manager@test.invalid') RETURNING id INTO _mgr;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_mgr, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_mgr, _team);
    INSERT INTO allowed_users(email) VALUES ('smoke.admin@test.invalid') RETURNING id INTO _adm;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_adm, 'admin');

    -- Collaborateur : soumission
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 1') RETURNING id, status::text INTO _s1, _st;
    _res := _res || jsonb_build_object('t', 'Soumission créée « en attente », dans l''équipe du collaborateur',
      'ok', _st = 'en attente' AND (SELECT team FROM submissions WHERE id = _s1) = _team, 'd', _st);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 2') RETURNING id INTO _s2;

    -- Manager : validation et refus
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    BEGIN
      UPDATE submissions SET status = 'validée' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager valide une demande en attente', 'ok', true, 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager valide une demande en attente', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'refusée', rejection_category = 'doublon', rejection_note = 'Test' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager refuse une demande avec un motif', 'ok', true, 'd', 'refusée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager refuse une demande avec un motif', 'ok', false, 'd', SQLERRM);
    END;
    -- Le manager change le statut librement, autant de fois que nécessaire (erreurs humaines)
    BEGIN
      UPDATE submissions SET status = 'clôturée' WHERE id = _s1;
      UPDATE submissions SET status = 'validée' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager corrige une clôture par erreur (clôturée puis validée)', 'ok',
        (SELECT status::text FROM submissions WHERE id = _s1) = 'validée', 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager corrige une clôture par erreur (clôturée puis validée)', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'validée' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager passe un refus en validée, le motif est effacé', 'ok',
        (SELECT rejection_category IS NULL AND rejection_note IS NULL FROM submissions WHERE id = _s2), 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager passe un refus en validée, le motif est effacé', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'en attente' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager remet une demande « en attente »', 'ok', true, 'd', 'en attente');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager remet une demande « en attente »', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET content = 'Contenu modifié par le manager' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager ne peut pas modifier le contenu d''une demande', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager ne peut pas modifier le contenu d''une demande', 'ok', true, 'd', 'refusé par la base');
    END;
    SELECT count(*) INTO _cnt FROM submission_status_history WHERE submission_id IN (_s1, _s2);
    _res := _res || jsonb_build_object('t', 'Historique : 8 lignes (2 créations, 6 changements de statut)', 'ok', _cnt = 8, 'd', _cnt || ' ligne(s)');

    -- Clôture automatique après un an sans modification
    PERFORM set_config('request.jwt.claims', '', true);
    UPDATE submissions SET revalidate_at = now() - interval '1 day' WHERE id = _s1;
    PERFORM private.expire_revalidations();
    SELECT status::text INTO _st FROM submissions WHERE id = _s1;
    _res := _res || jsonb_build_object('t', 'Clôture automatique : une demande validée échue passe « clôturée »', 'ok', _st = 'clôturée', 'd', _st);
    _res := _res || jsonb_build_object('t', 'Clôture automatique : l''historique la marque « Automatique »', 'ok',
      EXISTS (SELECT 1 FROM submission_status_history WHERE submission_id = _s1 AND new_status = 'clôturée' AND is_automatic), 'd', _st);

    -- Points bloquants
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.admin@test.invalid"}', true);
    INSERT INTO blockers(title, department) VALUES ('Blocage de test', 'Test') RETURNING id, status::text INTO _b, _st;
    _res := _res || jsonb_build_object('t', 'Point bloquant créé au statut OUVERT', 'ok', _st = 'OUVERT', 'd', _st);
    BEGIN
      UPDATE blockers SET status = 'RÉSOLU' WHERE id = _b;
      _res := _res || jsonb_build_object('t', 'OUVERT → RÉSOLU refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'OUVERT → RÉSOLU refusé', 'ok', true, 'd', 'refusé par la base');
    END;
    BEGIN
      UPDATE blockers SET status = 'EN COURS' WHERE id = _b;
      UPDATE blockers SET status = 'SURVEILLANCE' WHERE id = _b;
      UPDATE blockers SET status = 'RÉSOLU' WHERE id = _b;
      _res := _res || jsonb_build_object('t', 'OUVERT → EN COURS → SURVEILLANCE → RÉSOLU accepté', 'ok', true, 'd', 'RÉSOLU');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'OUVERT → EN COURS → SURVEILLANCE → RÉSOLU accepté', 'ok', false, 'd', SQLERRM);
    END;

    -- Actualités
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    -- Différée, la contrainte ne se déclencherait qu'au COMMIT, jamais atteint dans ce test.
    SET CONSTRAINTS check_news_audience IMMEDIATE;
    INSERT INTO news(title, body, author, status) VALUES ('Actu de test', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _n;
    BEGIN
      UPDATE news SET status = 'publiée' WHERE id = _n;
      _res := _res || jsonb_build_object('t', 'Publier une actu sans public est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN check_violation THEN
        _res := _res || jsonb_build_object('t', 'Publier une actu sans public est refusé', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Publier une actu sans public est refusé', 'ok', false, 'd', SQLERRM);
    END;
    UPDATE news SET audience = 'équipe' WHERE id = _n;
    BEGIN
      UPDATE news SET status = 'publiée' WHERE id = _n;
      _res := _res || jsonb_build_object('t', 'Publier une actu « équipe » sans équipe est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN check_violation THEN
        _res := _res || jsonb_build_object('t', 'Publier une actu « équipe » sans équipe est refusé', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Publier une actu « équipe » sans équipe est refusé', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      PERFORM public.save_news_audience(_n, 'équipe', ARRAY['ZZ Test fumée autre']);
      _res := _res || jsonb_build_object('t', 'Un manager ne cible pas une équipe qui n''est pas la sienne', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN insufficient_privilege THEN
        _res := _res || jsonb_build_object('t', 'Un manager ne cible pas une équipe qui n''est pas la sienne', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Un manager ne cible pas une équipe qui n''est pas la sienne', 'ok', false, 'd', SQLERRM);
    END;
    PERFORM public.save_news_audience(_n, 'équipe', ARRAY[_team]);
    UPDATE news SET status = 'publiée' WHERE id = _n;
    PERFORM private.expire_revalidations();
    SELECT status::text INTO _st FROM news WHERE id = _n;
    _res := _res || jsonb_build_object('t', 'Actualité : brouillon puis publiée, elle reste publiée après la tâche quotidienne', 'ok', _st = 'publiée', 'd', _st);
    BEGIN
      UPDATE news SET status = 'brouillon' WHERE id = _n;
      _res := _res || jsonb_build_object('t', 'Une actu publiée ne repasse pas en brouillon', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Une actu publiée ne repasse pas en brouillon', 'ok', true, 'd', 'refusé par la base');
    END;
    UPDATE news SET title = 'Actu de test corrigée' WHERE id = _n;
    SELECT status::text INTO _st FROM news WHERE id = _n;
    _res := _res || jsonb_build_object('t', 'Une actu publiée reste modifiable et reste publiée', 'ok', _st = 'publiée', 'd', _st);

    -- Public des actus : lecture réelle sous RLS (voir private.smoke_read_as)
    PERFORM set_config('request.jwt.claims', '', true);
    INSERT INTO allowed_users(email) VALUES ('smoke.manager2@test.invalid') RETURNING id INTO _mgr2;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_mgr2, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_mgr2, 'ZZ Test fumée autre');

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager2@test.invalid"}', true);
    INSERT INTO news(title, body, author, status) VALUES ('Actu équipe B', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _nb;
    PERFORM public.save_news_audience(_nb, 'équipe', ARRAY['ZZ Test fumée autre']);
    UPDATE news SET status = 'publiée' WHERE id = _nb;

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.admin@test.invalid"}', true);
    INSERT INTO news(title, body, author, status) VALUES ('Actu entreprise', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _ne;
    PERFORM public.save_news_audience(_ne, 'entreprise');
    UPDATE news SET status = 'publiée' WHERE id = _ne;
    INSERT INTO news(title, body, author, status) VALUES ('Actu deux équipes', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _nm;
    PERFORM public.save_news_audience(_nm, 'équipe', ARRAY[_team, 'ZZ Test fumée autre']);
    UPDATE news SET status = 'publiée' WHERE id = _nm;

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    INSERT INTO news(title, body, author, status) VALUES ('Brouillon du manager A', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _nd;

    _ids := ARRAY[_n, _nb, _ne, _nm, _nd];
    _with_teams := ARRAY[_n, _nb, _nm];
    -- L'écriture directe dans storage.objects dépend des droits du projet : sans elle, le détail le dit.
    BEGIN
      INSERT INTO storage.objects(bucket_id, name) VALUES ('news-media', _n || '/smoke.png'), ('news-media', _nb || '/smoke.png');
      _with_images := ARRAY[_n, _nb];
    EXCEPTION WHEN insufficient_privilege THEN
      NULL;
    END;

    FOR _reader IN
      SELECT * FROM (VALUES
        ('collaborateur équipe A', 'smoke.collab@test.invalid', ARRAY[_n, _ne, _nm]),
        ('manager équipe A', 'smoke.manager@test.invalid', ARRAY[_n, _ne, _nm, _nd]),
        ('manager équipe B', 'smoke.manager2@test.invalid', ARRAY[_nb, _ne, _nm]),
        ('admin', 'smoke.admin@test.invalid', _ids)
      ) AS v(label, email, ids)
    LOOP
      _want := ARRAY(SELECT unnest(_reader.ids) ORDER BY 1);
      SELECT * INTO _read FROM private.smoke_read_as(_reader.email, _ids);
      _res := _res || jsonb_build_object('t', 'Public des actus : lecture du ' || _reader.label, 'ok',
        _read._news = _want, 'd', cardinality(_read._news) || ' actu(s) lue(s)');
      _res := _res || jsonb_build_object('t', 'Public des actus : équipes ciblées lues par le ' || _reader.label, 'ok',
        _read._teams = ARRAY(SELECT unnest(_want) INTERSECT SELECT unnest(_with_teams) ORDER BY 1),
        'd', cardinality(_read._teams) || ' actu(s)');
      _res := _res || jsonb_build_object('t', 'Public des actus : images lues par le ' || _reader.label, 'ok',
        _read._images = ARRAY(SELECT unnest(_want) INTERSECT SELECT unnest(_with_images) ORDER BY 1),
        'd', CASE WHEN cardinality(_with_images) = 0 THEN 'NON TESTÉ : image de test impossible à créer'
             ELSE cardinality(_read._images) || ' image(s)' END);
    END LOOP;

    -- L'auteur garde ses actus même s'il n'est plus manager de l'équipe ciblée
    PERFORM set_config('request.jwt.claims', '', true);
    UPDATE allowed_user_roles SET role = 'collaborateur' WHERE allowed_user_id = _mgr2;
    DELETE FROM manager_teams WHERE allowed_user_id = _mgr2;
    SELECT * INTO _read FROM private.smoke_read_as('smoke.manager2@test.invalid', _ids);
    _res := _res || jsonb_build_object('t', 'Public des actus : l''auteur lit la sienne même sans rôle manager ni équipe', 'ok',
      _read._news = ARRAY(SELECT unnest(ARRAY[_nb, _ne]) ORDER BY 1), 'd', cardinality(_read._news) || ' actu(s) lue(s)');

    -- Modification d'une actu publiée : écriture réelle sous RLS (voir private.smoke_update_as).
    -- Actus créées dans le passé : dans une transaction, now() ne bouge pas et les dates se confondraient.
    -- Différée comme dans l'application : save_news_audience change le public avant d'écrire les équipes.
    SET CONSTRAINTS check_news_audience DEFERRED;
    PERFORM set_config('request.jwt.claims', '', true);
    INSERT INTO allowed_users(email) VALUES ('smoke.manager3@test.invalid') RETURNING id INTO _mgr3;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_mgr3, 'manager');

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    INSERT INTO news(title, body, author, status, audience, created_at)
    VALUES ('Actu publiée', 'Corps', 'Smoke', 'publiée', 'entreprise', now() - interval '2 days')
    RETURNING id, published_at INTO _np, _pub;

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager3@test.invalid"}', true);
    INSERT INTO news(title, body, author, status, audience, created_at)
    VALUES ('Actu d''un auteur parti', 'Corps', 'Smoke', 'publiée', 'entreprise', now() - interval '2 days')
    RETURNING id INTO _nq;

    SELECT * INTO _try FROM private.smoke_update_as('smoke.manager3@test.invalid', _np, 'Modifiée à tort');
    _res := _res || jsonb_build_object('t', 'Un autre manager ne modifie pas une actu publiée', 'ok',
      _try._rows = 0 AND (SELECT title FROM news WHERE id = _np) = 'Actu publiée', 'd', _try._rows || ' ligne(s)');
    SELECT * INTO _try FROM private.smoke_update_as('smoke.collab@test.invalid', _np, 'Modifiée à tort');
    _res := _res || jsonb_build_object('t', 'Un collaborateur ne modifie pas une actu publiée', 'ok',
      _try._rows = 0 AND (SELECT title FROM news WHERE id = _np) = 'Actu publiée', 'd', _try._rows || ' ligne(s)');

    SELECT * INTO _try FROM private.smoke_update_as('smoke.manager@test.invalid', _np, 'Actu publiée corrigée');
    _res := _res || jsonb_build_object('t', 'Le manager auteur modifie son actu : même date de publication, statut publiée', 'ok',
      _try._rows = 1 AND EXISTS (
        SELECT 1 FROM news WHERE id = _np AND title = 'Actu publiée corrigée' AND status = 'publiée'
          AND published_at = _pub AND updated_at > published_at),
      'd', COALESCE(_try._error, _try._rows || ' ligne(s)'));
    SELECT * INTO _try FROM private.smoke_update_as('smoke.manager@test.invalid', _np, '   ');
    _res := _res || jsonb_build_object('t', 'Une actu publiée ne perd pas son titre', 'ok',
      _try._error IS NOT NULL AND (SELECT title FROM news WHERE id = _np) = 'Actu publiée corrigée', 'd', COALESCE(_try._error, 'accepté à tort'));
    SELECT * INTO _try FROM private.smoke_update_as('smoke.admin@test.invalid', _np, 'Actu corrigée par l''admin');
    _res := _res || jsonb_build_object('t', 'L''admin modifie l''actu d''un manager : auteur et date de publication inchangés', 'ok',
      _try._rows = 1 AND EXISTS (
        SELECT 1 FROM news WHERE id = _np AND title = 'Actu corrigée par l''admin'
          AND author_email = 'smoke.manager@test.invalid' AND published_at = _pub),
      'd', COALESCE(_try._error, _try._rows || ' ligne(s)'));

    BEGIN
      UPDATE news SET author = 'Autre auteur' WHERE id = _np;
      _res := _res || jsonb_build_object('t', 'L''auteur d''une actu publiée ne change pas', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN insufficient_privilege THEN
        _res := _res || jsonb_build_object('t', 'L''auteur d''une actu publiée ne change pas', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'L''auteur d''une actu publiée ne change pas', 'ok', false, 'd', SQLERRM);
    END;

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    BEGIN
      PERFORM public.save_published_news(_np, 'Titre à ne pas garder', 'Corps', '[]', NULL, 'équipe', ARRAY['ZZ Test fumée autre']);
      _res := _res || jsonb_build_object('t', 'Enregistrement refusé : rien ne change, ni le titre ni le public', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN insufficient_privilege THEN
        _res := _res || jsonb_build_object('t', 'Enregistrement refusé : rien ne change, ni le titre ni le public', 'ok',
          EXISTS (SELECT 1 FROM news WHERE id = _np AND title = 'Actu corrigée par l''admin' AND audience = 'entreprise'), 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Enregistrement refusé : rien ne change, ni le titre ni le public', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      PERFORM public.save_published_news(_np, 'Titre et public', 'Corps', '[]', 'autre-actu/image.png', 'entreprise');
      _res := _res || jsonb_build_object('t', 'Une actu ne reprend pas l''image d''une autre', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN check_violation THEN
      _res := _res || jsonb_build_object('t', 'Une actu ne reprend pas l''image d''une autre', 'ok', true, 'd', 'refusé par la base');
    END;
    PERFORM public.save_published_news(_np, 'Titre et public', 'Corps', '[]', NULL, 'équipe', ARRAY[_team]);
    _res := _res || jsonb_build_object('t', 'Enregistrement accepté : le titre et le public changent ensemble', 'ok',
      EXISTS (SELECT 1 FROM news n JOIN news_teams t ON t.news_id = n.id
              WHERE n.id = _np AND n.title = 'Titre et public' AND n.audience = 'équipe' AND t.team = _team), 'd', 'équipe');

    -- Auteur parti : il perd d'abord son rôle, puis son compte. L'anonymisation ne compte pas comme une modification.
    PERFORM set_config('request.jwt.claims', '', true);
    UPDATE allowed_user_roles SET role = 'collaborateur' WHERE allowed_user_id = _mgr3;
    SELECT * INTO _try FROM private.smoke_update_as('smoke.manager3@test.invalid', _nq, 'Modifiée à tort');
    _res := _res || jsonb_build_object('t', 'L''auteur qui n''est plus manager ne modifie plus son actu', 'ok', _try._rows = 0, 'd', _try._rows || ' ligne(s)');
    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      DELETE FROM allowed_users WHERE id = _mgr3;
      _res := _res || jsonb_build_object('t', 'Compte supprimé : auteur anonymisé, sans mention « Modifiée le »', 'ok',
        EXISTS (SELECT 1 FROM news WHERE id = _nq AND author = 'Utilisateur supprimé' AND updated_at = published_at), 'd', 'Utilisateur supprimé');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Compte supprimé : auteur anonymisé, sans mention « Modifiée le »', 'ok', false, 'd', SQLERRM);
    END;
    SELECT * INTO _try FROM private.smoke_update_as('smoke.admin@test.invalid', _nq, 'Actu reprise par l''admin');
    _res := _res || jsonb_build_object('t', 'Auteur supprimé : l''admin modifie encore l''actu', 'ok', _try._rows = 1, 'd', COALESCE(_try._error, _try._rows || ' ligne(s)'));

    -- Centre de notifications : destinataires, puis droits réels sous RLS (voir private.smoke_notification_as).
    -- L'admin a une ligne dans manager_teams pour prouver que le rôle est bien contrôlé.
    PERFORM set_config('request.jwt.claims', '', true);
    -- Le second manager a perdu son rôle et son équipe dans le test « l'auteur lit la sienne ».
    UPDATE allowed_user_roles SET role = 'manager' WHERE allowed_user_id = _mgr2;
    INSERT INTO allowed_users(email, team) VALUES ('smoke.collab2@test.invalid', _team) RETURNING id INTO _collab2;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_collab2, 'collaborateur');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_mgr2, _team), (_adm, _team);

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab2@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 3') RETURNING id INTO _s3;
    SELECT COALESCE(array_agg(recipient_email), '{}') INTO _emails FROM notifications WHERE submission_id = _s3;
    _res := _res || jsonb_build_object('t', 'Une demande créée notifie les managers de son équipe', 'ok',
      _emails @> ARRAY['smoke.manager@test.invalid', 'smoke.manager2@test.invalid'], 'd', array_to_string(_emails, ', '));
    _res := _res || jsonb_build_object('t', 'Une demande créée ne notifie ni son auteur ni un admin', 'ok',
      NOT _emails && ARRAY['smoke.collab2@test.invalid', 'smoke.admin@test.invalid'], 'd', array_to_string(_emails, ', '));
    _res := _res || jsonb_build_object('t', 'Le texte de la notification nomme l''auteur et l''équipe', 'ok',
      EXISTS (SELECT 1 FROM notifications n JOIN submissions s ON s.id = n.submission_id
              WHERE s.id = _s3 AND n.kind = 'nouvelle_demande'
                AND n.message = format('Nouvelle demande de %s (%s)', s.author_name, s.team)), 'd', _team);

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', _team, 'Demande de test 4') RETURNING id INTO _s4;
    SELECT COALESCE(array_agg(recipient_email), '{}') INTO _emails FROM notifications WHERE submission_id = _s4;
    _res := _res || jsonb_build_object('t', 'Un manager n''est pas notifié de sa propre demande', 'ok',
      _emails = ARRAY['smoke.manager2@test.invalid'], 'd', array_to_string(_emails, ', '));

    SELECT id INTO _notif FROM notifications WHERE submission_id = _s3 AND recipient_email = 'smoke.manager@test.invalid';
    SELECT * INTO _notif_try FROM private.smoke_notification_as('smoke.manager2@test.invalid', _notif);
    _res := _res || jsonb_build_object('t', 'Un utilisateur ne lit ni ne marque les notifications d''un autre', 'ok',
      _notif_try._visible = 0 AND _notif_try._marked = 0
      AND (SELECT read_at FROM notifications WHERE id = _notif) IS NULL,
      'd', _notif_try._visible || ' lue(s), ' || _notif_try._marked || ' marquée(s)');
    SELECT * INTO _notif_try FROM private.smoke_notification_as('smoke.manager@test.invalid', _notif);
    _res := _res || jsonb_build_object('t', 'Le destinataire lit sa notification et la marque comme lue', 'ok',
      _notif_try._visible = 1 AND _notif_try._marked = 1
      AND (SELECT read_at FROM notifications WHERE id = _notif) IS NOT NULL,
      'd', _notif_try._visible || ' lue(s), ' || _notif_try._marked || ' marquée(s)');
    _res := _res || jsonb_build_object('t', 'Seul read_at est modifiable : ni autre colonne, ni création, ni suppression', 'ok',
      _notif_try._denied = 3 AND EXISTS (SELECT 1 FROM notifications WHERE id = _notif AND message <> 'Modifiée à tort'),
      'd', _notif_try._denied || ' écriture(s) refusée(s) sur 3');

    -- Préférences de notification : valeurs par défaut, effet de « Dans l'app », droits réels sous RLS
    -- (voir private.smoke_preference_as), puis notification d'un changement de statut.
    PERFORM set_config('request.jwt.claims', '', true);
    _res := _res || jsonb_build_object('t', 'Sans préférence enregistrée : dans l''app et par mail sont actifs', 'ok',
      NOT EXISTS (SELECT 1 FROM notification_preferences WHERE recipient_email = 'smoke.manager@test.invalid')
      AND private.wants_in_app('smoke.manager@test.invalid', 'nouvelle_demande')
      AND private.wants_by_email('smoke.manager@test.invalid', 'nouvelle_demande'), 'd', 'aucune ligne');
    INSERT INTO notification_preferences(recipient_email, kind, in_app)
      VALUES ('smoke.manager@test.invalid', 'nouvelle_demande', false);
    _res := _res || jsonb_build_object('t', 'Une préférence enregistrée sans « par mail » le garde actif', 'ok',
      private.wants_by_email('smoke.manager@test.invalid', 'nouvelle_demande'), 'd', 'by_email par défaut');

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab2@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 5') RETURNING id INTO _s5;
    SELECT COALESCE(array_agg(recipient_email), '{}') INTO _emails FROM notifications WHERE submission_id = _s5;
    _res := _res || jsonb_build_object('t', 'Dans l''app décoché : la notification « nouvelle demande » n''est plus créée', 'ok',
      NOT _emails && ARRAY['smoke.manager@test.invalid'] AND _emails @> ARRAY['smoke.manager2@test.invalid'],
      'd', array_to_string(_emails, ', '));
    _res := _res || jsonb_build_object('t', 'Dans l''app décoché : les notifications déjà reçues restent', 'ok',
      EXISTS (SELECT 1 FROM notifications WHERE id = _notif), 'd', 'notification de la demande 3');

    SELECT * INTO _pref_try FROM private.smoke_preference_as('smoke.manager2@test.invalid', 'smoke.manager@test.invalid');
    _res := _res || jsonb_build_object('t', 'Un utilisateur ne lit ni ne modifie les préférences d''un autre', 'ok',
      _pref_try._visible = 0 AND _pref_try._updated = 0 AND _pref_try._insert_denied
      AND (SELECT by_email FROM notification_preferences
            WHERE recipient_email = 'smoke.manager@test.invalid' AND kind = 'nouvelle_demande'),
      'd', _pref_try._visible || ' lue(s), ' || _pref_try._updated || ' modifiée(s), création '
           || CASE WHEN _pref_try._insert_denied THEN 'refusée' ELSE 'acceptée' END);
    SELECT * INTO _pref_try FROM private.smoke_preference_as('smoke.manager@test.invalid', 'smoke.manager@test.invalid');
    _res := _res || jsonb_build_object('t', 'Un utilisateur lit, modifie et crée ses propres préférences', 'ok',
      _pref_try._visible = 1 AND _pref_try._updated = 1 AND NOT _pref_try._insert_denied,
      'd', _pref_try._visible || ' lue(s), ' || _pref_try._updated || ' modifiée(s), création '
           || CASE WHEN _pref_try._insert_denied THEN 'refusée' ELSE 'acceptée' END);

    -- Alertes de changement d'état (US14) : l'auteur suit sa demande d'office, droits réels sous RLS
    -- (voir private.smoke_followers_as), puis une notification par nouvelle étape du fil.
    PERFORM set_config('request.jwt.claims', '', true);
    _res := _res || jsonb_build_object('t', 'L''auteur suit sa demande dès sa création', 'ok',
      EXISTS (SELECT 1 FROM submission_followers WHERE submission_id = _s5
              AND follower_email = 'smoke.collab2@test.invalid' AND source = 'auteur'), 'd', 'demande 5');
    SELECT * INTO _fol_try FROM private.smoke_followers_as('smoke.collab2@test.invalid', _s5);
    _res := _res || jsonb_build_object('t', 'L''auteur lit son suivi et ne peut pas le supprimer', 'ok',
      _fol_try._visible = 1 AND _fol_try._delete_denied,
      'd', _fol_try._visible || ' lue(s), suppression ' || CASE WHEN _fol_try._delete_denied THEN 'refusée' ELSE 'acceptée' END);
    SELECT * INTO _fol_try FROM private.smoke_followers_as('smoke.collab@test.invalid', _s5);
    _res := _res || jsonb_build_object('t', 'Un autre utilisateur ne lit pas le suivi d''une demande', 'ok',
      _fol_try._visible = 0, 'd', _fol_try._visible || ' lue(s)');
    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      DELETE FROM submission_followers WHERE submission_id = _s5 AND source = 'auteur';
      _res := _res || jsonb_build_object('t', 'On ne peut pas supprimer une ligne « auteur »', 'ok', false, 'd', 'acceptée à tort');
    EXCEPTION WHEN insufficient_privilege THEN
      _res := _res || jsonb_build_object('t', 'On ne peut pas supprimer une ligne « auteur »', 'ok',
        EXISTS (SELECT 1 FROM submission_followers WHERE submission_id = _s5 AND source = 'auteur'), 'd', 'refusée par la base');
    END;

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    UPDATE submissions SET status = 'validée' WHERE id = _s5;
    SELECT COALESCE(array_agg(recipient_email), '{}') INTO _emails
      FROM notifications WHERE submission_id = _s5 AND kind = 'changement_statut';
    _res := _res || jsonb_build_object('t', 'Une validation notifie l''auteur, et lui seul, avec le nom du manager', 'ok',
      _emails = ARRAY['smoke.collab2@test.invalid']
      AND EXISTS (SELECT 1 FROM notifications WHERE submission_id = _s5 AND kind = 'changement_statut'
                  AND message = 'Ta demande a été validée : « Demande de test 5 »'
                  AND actor_name = 'smoke.manager@test.invalid'),
      'd', array_to_string(_emails, ', '));
    UPDATE submissions SET status = 'validée' WHERE id = _s4;
    SELECT count(*) INTO _cnt FROM notifications WHERE submission_id = _s4 AND kind = 'changement_statut';
    _res := _res || jsonb_build_object('t', 'Le manager qui valide n''est pas notifié de sa propre action', 'ok',
      _cnt = 0, 'd', _cnt || ' notification(s)');
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab2@test.invalid"}', true);
    UPDATE submissions SET status = 'en attente' WHERE id = _s5;
    SELECT count(*) INTO _cnt FROM notifications WHERE submission_id = _s5 AND kind = 'changement_statut';
    _res := _res || jsonb_build_object('t', 'L''auteur n''est pas notifié d''un statut qu''il change lui-même', 'ok',
      _cnt = 1, 'd', _cnt || ' notification(s)');

    PERFORM set_config('request.jwt.claims', '', true);
    INSERT INTO notification_preferences(recipient_email, kind, in_app)
      VALUES ('smoke.collab2@test.invalid', 'changement_statut', false);
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    UPDATE submissions SET status = 'refusée', rejection_category = 'doublon', rejection_note = 'Test' WHERE id = _s5;
    SELECT count(*) INTO _cnt FROM notifications WHERE submission_id = _s5 AND kind = 'changement_statut';
    _res := _res || jsonb_build_object('t', 'Dans l''app décoché n''empêche pas l''alerte de l''auteur (refus avec sa catégorie)', 'ok',
      _cnt = 2 AND EXISTS (SELECT 1 FROM notifications WHERE submission_id = _s5
                           AND message = 'Ta demande a été refusée (doublon) : « Demande de test 5 »'),
      'd', _cnt || ' notification(s)');
    UPDATE submissions SET status = 'validée' WHERE id = _s5;
    PERFORM set_config('request.jwt.claims', '', true);
    UPDATE submissions SET revalidate_at = now() - interval '1 day' WHERE id = _s5;
    PERFORM private.expire_revalidations();
    _res := _res || jsonb_build_object('t', 'La clôture automatique notifie l''auteur, signée « Automatique »', 'ok',
      EXISTS (SELECT 1 FROM notifications WHERE submission_id = _s5 AND kind = 'changement_statut'
              AND message = 'Ta demande a été clôturée : « Demande de test 5 »' AND actor_name = 'Automatique'),
      'd', (SELECT status::text FROM submissions WHERE id = _s5));

    -- Demande suivie sans en être l'auteur : type et texte distincts, « Dans l'app » respecté
    -- pour elle, jamais pour l'auteur. Le second manager la suit d'office depuis sa création (US15).
    PERFORM set_config('request.jwt.claims', '', true);
    INSERT INTO submission_followers(submission_id, follower_email, source)
      VALUES (_s5, 'smoke.manager2@test.invalid', 'manager')
    ON CONFLICT (submission_id, follower_email) DO NOTHING;
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    UPDATE submissions SET status = 'en attente' WHERE id = _s5;
    _res := _res || jsonb_build_object('t', 'Une personne qui suit la demande reçoit « La demande de <auteur>… », l''auteur « Ta demande… »', 'ok',
      EXISTS (SELECT 1 FROM notifications WHERE submission_id = _s5 AND recipient_email = 'smoke.manager2@test.invalid'
              AND kind = 'changement_statut_suivi' AND message = 'La demande de Smoke est repassée en attente : « Demande de test 5 »')
      AND EXISTS (SELECT 1 FROM notifications WHERE submission_id = _s5 AND recipient_email = 'smoke.collab2@test.invalid'
              AND kind = 'changement_statut' AND message = 'Ta demande est repassée en attente : « Demande de test 5 »'),
      'd', 'demande 5');
    PERFORM set_config('request.jwt.claims', '', true);
    INSERT INTO notification_preferences(recipient_email, kind, in_app)
      VALUES ('smoke.manager2@test.invalid', 'changement_statut_suivi', false);
    SELECT count(*) INTO _cnt2 FROM notifications WHERE submission_id = _s5 AND recipient_email = 'smoke.collab2@test.invalid';
    SELECT count(*) INTO _cnt FROM notifications
     WHERE submission_id = _s5 AND recipient_email = 'smoke.manager2@test.invalid' AND kind = 'changement_statut_suivi';
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    UPDATE submissions SET status = 'validée' WHERE id = _s5;
    _res := _res || jsonb_build_object('t', 'Dans l''app décoché pour les demandes suivies : plus d''alerte, l''auteur reste alerté', 'ok',
      _cnt = (SELECT count(*) FROM notifications WHERE submission_id = _s5
               AND recipient_email = 'smoke.manager2@test.invalid' AND kind = 'changement_statut_suivi') AND (SELECT count(*) FROM notifications WHERE submission_id = _s5 AND recipient_email = 'smoke.collab2@test.invalid') = _cnt2 + 1,
      'd', _cnt || ' alerte(s) pour la personne qui suit');

    -- Suivi d'une demande (US15) : suivi d'office du manager, suivi volontaire sous RLS
    -- (voir private.smoke_follow_as), puis perte du droit de lire la demande.
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab2@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 7') RETURNING id INTO _s7;
    PERFORM set_config('request.jwt.claims', '', true);
    _res := _res || jsonb_build_object('t', 'Le manager suit d''office une nouvelle demande de son équipe, pas l''admin', 'ok',
      EXISTS (SELECT 1 FROM submission_followers WHERE submission_id = _s7
              AND follower_email = 'smoke.manager@test.invalid' AND source = 'manager')
      AND NOT EXISTS (SELECT 1 FROM submission_followers WHERE submission_id = _s7
                      AND follower_email = 'smoke.admin@test.invalid'),
      'd', 'demande 7');
    SELECT * INTO _f FROM private.smoke_follow_as('smoke.manager@test.invalid', _s7, false);
    _res := _res || jsonb_build_object('t', 'Le manager peut arrêter de suivre une demande de son équipe', 'ok',
      _f._done AND NOT EXISTS (SELECT 1 FROM submission_followers WHERE submission_id = _s7
                               AND follower_email = 'smoke.manager@test.invalid'),
      'd', COALESCE(_f._error, 'suivi supprimé'));
    SELECT * INTO _f FROM private.smoke_follow_as('smoke.manager@test.invalid', _s7, true);
    _res := _res || jsonb_build_object('t', 'Il peut la suivre à nouveau (suivi volontaire)', 'ok',
      _f._done AND EXISTS (SELECT 1 FROM submission_followers WHERE submission_id = _s7
                           AND follower_email = 'smoke.manager@test.invalid' AND source = 'volontaire'),
      'd', COALESCE(_f._error, 'suivi créé'));
    SELECT * INTO _f FROM private.smoke_follow_as('smoke.admin@test.invalid', _s7, true);
    _res := _res || jsonb_build_object('t', 'Un admin ne peut suivre aucune demande', 'ok',
      NOT _f._done AND NOT EXISTS (SELECT 1 FROM submission_followers WHERE submission_id = _s7
                                   AND follower_email = 'smoke.admin@test.invalid'),
      'd', COALESCE(_f._error, 'accepté à tort'));
    SELECT * INTO _f FROM private.smoke_follow_as('smoke.collab@test.invalid', _s7, true);
    _res := _res || jsonb_build_object('t', 'On ne peut pas suivre une demande qu''on ne peut pas lire', 'ok',
      NOT _f._done AND NOT EXISTS (SELECT 1 FROM submission_followers WHERE submission_id = _s7
                                   AND follower_email = 'smoke.collab@test.invalid'),
      'd', COALESCE(_f._error, 'accepté à tort'));
    SELECT * INTO _fol_try FROM private.smoke_followers_as('smoke.collab@test.invalid', _s7);
    _res := _res || jsonb_build_object('t', 'On ne supprime pas le suivi d''une autre personne', 'ok',
      EXISTS (SELECT 1 FROM submission_followers WHERE submission_id = _s7
              AND follower_email = 'smoke.manager2@test.invalid'),
      'd', _fol_try._visible || ' lue(s)');
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager2@test.invalid"}', true);
    UPDATE submissions SET status = 'validée' WHERE id = _s7;
    SELECT * INTO _f FROM private.smoke_follow_as('smoke.collab@test.invalid', _s7, true);
    _res := _res || jsonb_build_object('t', 'Un collaborateur suit une demande validée d''une autre personne', 'ok',
      _f._done AND EXISTS (SELECT 1 FROM submission_followers WHERE submission_id = _s7
                           AND follower_email = 'smoke.collab@test.invalid' AND source = 'volontaire'),
      'd', COALESCE(_f._error, 'suivi créé'));
    PERFORM set_config('request.jwt.claims', '', true);
    INSERT INTO notifications(recipient_email, kind, submission_id, message)
      VALUES ('smoke.collab@test.invalid', 'changement_statut_suivi', _s7,
              'La demande de Smoke a été validée : « Demande de test 7 »')
    RETURNING id INTO _notif7;
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager2@test.invalid"}', true);
    UPDATE submissions SET status = 'clôturée' WHERE id = _s7;
    _res := _res || jsonb_build_object('t', 'Une personne qui a perdu l''accès n''est plus notifiée', 'ok',
      NOT EXISTS (SELECT 1 FROM notifications WHERE submission_id = _s7
                  AND recipient_email = 'smoke.collab@test.invalid' AND id <> _notif7)
      AND EXISTS (SELECT 1 FROM notifications WHERE submission_id = _s7
                  AND recipient_email = 'smoke.manager@test.invalid'
                  AND message = 'La demande de Smoke a été clôturée : « Demande de test 7 »'),
      'd', (SELECT status::text FROM submissions WHERE id = _s7));
    SELECT * INTO _notif_try FROM private.smoke_notification_as('smoke.collab@test.invalid', _notif7);
    _res := _res || jsonb_build_object('t', 'Ses notifications d''une demande devenue illisible ne s''affichent plus', 'ok',
      _notif_try._visible = 0, 'd', _notif_try._visible || ' lue(s)');

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.admin@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', _team, 'Demande de test 6') RETURNING id INTO _s6;
    -- Une demande d'admin est rangée dans l'équipe « Admin », hors de portée des managers :
    -- le changement est fait sous le compte du collaborateur (ce test tourne sans RLS).
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab@test.invalid"}', true);
    UPDATE submissions SET status = 'validée' WHERE id = _s6;
    _res := _res || jsonb_build_object('t', 'Un admin auteur suit sa demande mais n''est pas notifié', 'ok',
      EXISTS (SELECT 1 FROM submission_followers WHERE submission_id = _s6 AND follower_email = 'smoke.admin@test.invalid')
      AND NOT EXISTS (SELECT 1 FROM notifications WHERE submission_id = _s6 AND kind = 'changement_statut'),
      'd', 'demande 6');
    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      DELETE FROM submissions WHERE id = _s6;
      _res := _res || jsonb_build_object('t', 'Une demande supprimée emporte son suivi', 'ok',
        NOT EXISTS (SELECT 1 FROM submission_followers WHERE submission_id = _s6), 'd', 'demande 6');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Une demande supprimée emporte son suivi', 'ok', false, 'd', SQLERRM);
    END;

    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      DELETE FROM allowed_users WHERE id IN (_collab2, _mgr2);
      _res := _res || jsonb_build_object('t', 'Compte supprimé : son nom sort des messages, ses notifications disparaissent', 'ok',
        EXISTS (SELECT 1 FROM notifications WHERE id = _notif
                AND message = format('Nouvelle demande de Utilisateur supprimé (%s)', _team))
        AND NOT EXISTS (SELECT 1 FROM notifications WHERE recipient_email = 'smoke.manager2@test.invalid'),
        'd', 'Utilisateur supprimé');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Compte supprimé : son nom sort des messages, ses notifications disparaissent', 'ok', false, 'd', SQLERRM);
    END;
    _res := _res || jsonb_build_object('t', 'Compte supprimé : ses préférences de notification disparaissent', 'ok',
      NOT EXISTS (SELECT 1 FROM notification_preferences WHERE recipient_email = 'smoke.collab2@test.invalid'), 'd', 'smoke.collab2');
    _res := _res || jsonb_build_object('t', 'Compte supprimé : son suivi des demandes disparaît', 'ok',
      NOT EXISTS (SELECT 1 FROM submission_followers WHERE follower_email = 'smoke.collab2@test.invalid'), 'd', 'smoke.collab2');
    DELETE FROM manager_teams WHERE allowed_user_id = _adm;

    _res := _res || jsonb_build_object('t', 'Les notifications ne sont plus purgées après 30 jours', 'ok',
      NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'purge-notifications-daily')
      AND to_regprocedure('private.purge_notifications()') IS NULL, 'd', 'purge supprimée');

    -- Points bloquants à revoir (US16). private.fast_forward_blocker fait avancer le temps d'un point.
    PERFORM set_config('request.jwt.claims', '', true);
    INSERT INTO allowed_users(email) VALUES ('smoke.admin2@test.invalid') RETURNING id INTO _adm2;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_adm2, 'admin');
    INSERT INTO blockers(title, department, status) VALUES ('Blocage figé', 'Test', 'EN COURS') RETURNING id INTO _b16;
    INSERT INTO blockers(title, department, status) VALUES ('Blocage résolu', 'Test', 'EN COURS') RETURNING id INTO _b16r;
    UPDATE blockers SET status = 'RÉSOLU' WHERE id = _b16r;
    PERFORM private.fast_forward_blocker(_b16, interval '4 days');
    PERFORM private.fast_forward_blocker(_b16r, interval '4 days');
    PERFORM private.notify_stale_blockers();
    PERFORM private.notify_stale_blockers();
    SELECT count(*) INTO _cnt16 FROM notifications
     WHERE blocker_id = _b16 AND kind = 'point_bloquant_a_revoir'
       AND recipient_email IN ('smoke.admin@test.invalid', 'smoke.admin2@test.invalid');
    _res := _res || jsonb_build_object('t', 'Un point non résolu sans mise à jour depuis 4 jours notifie chaque admin, une seule fois', 'ok',
      _cnt16 = 2
      AND EXISTS (SELECT 1 FROM notifications WHERE blocker_id = _b16 AND recipient_email = 'smoke.admin@test.invalid')
      AND EXISTS (SELECT 1 FROM notifications WHERE blocker_id = _b16 AND recipient_email = 'smoke.admin2@test.invalid'),
      'd', _cnt16 || ' notification(s)');
    _res := _res || jsonb_build_object('t', 'Le texte dit « Point bloquant à revoir : <titre> (sans mise à jour depuis N jours) »', 'ok',
      EXISTS (SELECT 1 FROM notifications WHERE blocker_id = _b16 AND recipient_email = 'smoke.admin@test.invalid'
              AND message = 'Point bloquant à revoir : Blocage figé (sans mise à jour depuis 4 jours)'),
      'd', (SELECT message FROM notifications WHERE blocker_id = _b16 AND recipient_email = 'smoke.admin@test.invalid' LIMIT 1));
    _res := _res || jsonb_build_object('t', 'Un point résolu ne notifie personne', 'ok',
      NOT EXISTS (SELECT 1 FROM notifications WHERE blocker_id = _b16r), 'd', 'Blocage résolu');
    _res := _res || jsonb_build_object('t', 'Un manager ou un collaborateur ne reçoit jamais « point bloquant à revoir »', 'ok',
      NOT EXISTS (SELECT 1 FROM notifications n
                   WHERE n.blocker_id = _b16
                     AND NOT EXISTS (SELECT 1 FROM allowed_users u
                                       JOIN allowed_user_roles r ON r.allowed_user_id = u.id
                                      WHERE lower(u.email) = n.recipient_email AND r.role = 'admin'))
      AND NOT EXISTS (SELECT 1 FROM notifications
                       WHERE blocker_id = _b16 AND recipient_email = 'smoke.manager@test.invalid'),
      'd', 'admins seulement');

    PERFORM private.fast_forward_blocker(_b16, interval '4 days');
    PERFORM private.notify_stale_blockers();
    SELECT count(*) INTO _cnt16 FROM notifications WHERE blocker_id = _b16 AND recipient_email = 'smoke.admin@test.invalid';
    _res := _res || jsonb_build_object('t', 'Sans modification, un point déjà signalé ne notifie pas à nouveau', 'ok',
      _cnt16 = 1, 'd', _cnt16 || ' notification(s)');

    UPDATE blockers SET description = 'Modifié hors de l''app' WHERE id = _b16;
    _res := _res || jsonb_build_object('t', 'Une modification faite en base remet updated_at à maintenant', 'ok',
      (SELECT updated_at FROM blockers WHERE id = _b16) = now(), 'd', 'trigger');
    PERFORM private.notify_stale_blockers();
    SELECT count(*) INTO _cnt16 FROM notifications WHERE blocker_id = _b16 AND recipient_email = 'smoke.admin@test.invalid';
    _res := _res || jsonb_build_object('t', 'Un point modifié récemment ne notifie pas', 'ok',
      _cnt16 = 1, 'd', _cnt16 || ' notification(s)');
    PERFORM private.fast_forward_blocker(_b16, interval '3 days 1 hour');
    PERFORM private.notify_stale_blockers();
    SELECT count(*) INTO _cnt16 FROM notifications
     WHERE blocker_id = _b16 AND recipient_email IN ('smoke.admin@test.invalid', 'smoke.admin2@test.invalid');
    _res := _res || jsonb_build_object('t', 'Une nouvelle modification puis 3 jours sans mise à jour créent une nouvelle notification', 'ok',
      _cnt16 = 4
      AND EXISTS (SELECT 1 FROM notifications WHERE blocker_id = _b16 AND recipient_email = 'smoke.admin@test.invalid'
                  AND message = 'Point bloquant à revoir : Blocage figé (sans mise à jour depuis 3 jours)'),
      'd', _cnt16 || ' notification(s) pour les 2 admins');

    INSERT INTO notification_preferences(recipient_email, kind, in_app, by_email)
      VALUES ('smoke.admin2@test.invalid', 'point_bloquant_a_revoir', false, true);
    INSERT INTO blockers(title, department) VALUES ('Blocage préférences', 'Test') RETURNING id INTO _b16p;
    PERFORM private.fast_forward_blocker(_b16p, interval '4 days');
    PERFORM private.notify_stale_blockers();
    _res := _res || jsonb_build_object('t', 'Un admin qui a décoché « Dans l''app » ne reçoit rien', 'ok',
      EXISTS (SELECT 1 FROM notifications WHERE blocker_id = _b16p AND recipient_email = 'smoke.admin@test.invalid')
      AND NOT EXISTS (SELECT 1 FROM notifications WHERE blocker_id = _b16p AND recipient_email = 'smoke.admin2@test.invalid'),
      'd', 'smoke.admin2');

    DELETE FROM blockers WHERE id = _b16;
    _res := _res || jsonb_build_object('t', 'Un point supprimé garde ses notifications, sans lien vers lui', 'ok',
      EXISTS (SELECT 1 FROM notifications WHERE kind = 'point_bloquant_a_revoir' AND blocker_id IS NULL
              AND message LIKE 'Point bloquant à revoir : Blocage figé %'), 'd', 'blocker_id vide');

    INSERT INTO blockers(title, department) VALUES ('Blocage démo', 'Test') RETURNING id INTO _b16s;
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    BEGIN
      PERFORM public.simuler_point_bloquant_a_revoir(_b16s);
      _res := _res || jsonb_build_object('t', 'Un manager ne peut pas lancer la simulation', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Un manager ne peut pas lancer la simulation', 'ok', true, 'd', 'refusé par la base');
    END;
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.admin@test.invalid"}', true);
    BEGIN
      _sim16 := public.simuler_point_bloquant_a_revoir(_b16s);
      _res := _res || jsonb_build_object('t', 'La simulation d''un admin notifie les admins pour ce point', 'ok',
        _sim16 >= 1
        AND EXISTS (SELECT 1 FROM notifications WHERE blocker_id = _b16s AND recipient_email = 'smoke.admin@test.invalid'
                    AND message = 'Point bloquant à revoir : Blocage démo (sans mise à jour depuis 4 jours)'),
        'd', _sim16 || ' notification(s)');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'La simulation d''un admin notifie les admins pour ce point', 'ok', false, 'd', SQLERRM);
    END;
    PERFORM set_config('request.jwt.claims', '', true);

    -- Référentiel des équipes
    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      UPDATE teams SET name = 'ZZ Test fumée 2' WHERE name = _team;
      _res := _res || jsonb_build_object('t', 'Référentiel : renommer une équipe met à jour utilisateurs, managers et demandes', 'ok',
        (SELECT team FROM allowed_users WHERE id = _collab) = 'ZZ Test fumée 2'
        AND (SELECT team FROM manager_teams WHERE allowed_user_id = _mgr) = 'ZZ Test fumée 2'
        AND (SELECT team FROM submissions WHERE id = _s1) = 'ZZ Test fumée 2', 'd', 'ZZ Test fumée 2');
      _res := _res || jsonb_build_object('t', 'Référentiel : renommer une équipe met à jour le public des actus', 'ok',
        (SELECT team FROM news_teams WHERE news_id = _n) = 'ZZ Test fumée 2', 'd', 'ZZ Test fumée 2');
      _team := 'ZZ Test fumée 2';
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Référentiel : renommer une équipe met à jour utilisateurs, managers et demandes', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      DELETE FROM teams WHERE name = _team;
      _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN foreign_key_violation THEN
        _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', false, 'd', SQLERRM);
    END;

    RAISE EXCEPTION 'HP_SMOKE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'HP_SMOKE_ROLLBACK' THEN
      _res := _res || jsonb_build_object('t', 'Exécution du test de fumée', 'ok', false, 'd', 'Erreur inattendue : ' || SQLERRM);
    END IF;
  END;

  SELECT count(*) INTO _cnt FROM private.audit_enum_literals();
  _res := _res || jsonb_build_object('t', 'Aucune valeur d''ENUM obsolète dans les fonctions', 'ok', _cnt = 0, 'd', _cnt || ' anomalie(s)');

  RETURN QUERY SELECT x->>'t', (x->>'ok')::boolean, x->>'d' FROM jsonb_array_elements(_res) x;
END;
$function$;

DO $$
DECLARE _bad text;
BEGIN
  SELECT string_agg(test || ' : ' || COALESCE(detail, ''), ' | ') INTO _bad FROM private.run_smoke_tests() WHERE NOT ok;
  IF _bad IS NOT NULL THEN
    RAISE EXCEPTION 'Smoke tests failed: %', _bad;
  END IF;
END $$;
COMMIT;

-- ---------- 20261103190000_definitions_kpi.sql ----------
-- Définitions de KPI (US18). Chaque indicateur porte deux textes : « Ce que ça mesure »
-- (definition) et « Ce que ça change pour toi » (impact), 200 caractères maximum chacun.
-- Lecture par tous (« Allowed read »), écriture par les admins (« Admin write »), politiques
-- existantes. Le trigger d'historique ne réagit qu'à la valeur : modifier un texte n'ajoute
-- aucun point d'historique.
BEGIN;

ALTER TABLE public.metrics
  ADD COLUMN definition text,
  ADD COLUMN impact text,
  ADD CONSTRAINT metrics_definition_length CHECK (char_length(definition) <= 200),
  ADD CONSTRAINT metrics_impact_length CHECK (char_length(impact) <= 200);

-- Les nouvelles colonnes sont ajoutées en fin de vue, comme l'exige CREATE OR REPLACE VIEW.
CREATE OR REPLACE VIEW public.metrics_with_trend
WITH (security_invoker = true) AS
SELECT m.key,
    m.label,
    m.value,
    m.unit,
    m.updated_at,
    p.value AS previous_value,
    CASE
        WHEN p.value IS NULL OR p.value = m.value THEN 'stable'::text
        WHEN m.value > p.value THEN 'hausse'::text
        ELSE 'baisse'::text
    END AS trend,
    CASE WHEN p.value IS NULL THEN NULL ELSE m.value - p.value END AS delta,
    m.definition,
    m.impact
FROM public.metrics m
LEFT JOIN LATERAL (
    SELECT h.value
    FROM public.metrics_history h
    WHERE h.metric_key = m.key
    ORDER BY h.recorded_at DESC
    OFFSET 1
    LIMIT 1
) p ON true;

-- Textes fictifs des trois KPI de la vue d'ensemble, validés par Louis le 2026-11-03.
UPDATE public.metrics SET
  definition = 'Part des candidats accompagnés qui ont signé une mission dans les 30 derniers jours (fictif).',
  impact = 'Il fixe les priorités de l''équipe : s''il baisse, l''effort va aux candidats sans mission, et tes demandes qui les aident passent en premier (fictif).'
WHERE key = 'training_kpi';

UPDATE public.metrics SET
  definition = 'Nombre de missions en cours aujourd''hui, de la signature du contrat à la fin de la mission (fictif).',
  impact = 'Il montre la charge de suivi : plus il monte, plus tes managers ont de missions à suivre, et plus une demande qui fait gagner du temps compte (fictif).'
WHERE key = 'active_users';

UPDATE public.metrics SET
  definition = 'Note de recommandation donnée par les candidats à la fin de leur mission, de −100 à +100 (fictif).',
  impact = 'Il dit si les candidats recommandent Happy Place : une demande qui améliore leur accueil ou leur suivi le fait monter (fictif).'
WHERE key = 'nps';

COMMIT;

-- Vérification finale : toutes les lignes doivent indiquer ok = true
SELECT * FROM private.run_smoke_tests();
