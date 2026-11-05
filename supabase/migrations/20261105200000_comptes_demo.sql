-- ============================================================
-- Comptes de démo (connexion par mot de passe)
-- ============================================================
-- Inscrit les 4 comptes de la démo : profil, rôle, équipe gérée et adresse de réception des mails.
-- Les comptes Supabase Auth (adresse + mot de passe) se créent à la main dans le Dashboard :
-- aucune donnée d'authentification ici. Rejouable sans doublon.
BEGIN;

WITH comptes(email, first_name, last_name, role, team) AS (
  VALUES
    ('guecheff.louis+kesha@gmail.com',   'Kesha',   'Démo', 'manager'::public.app_role,       'Product'),
    ('guecheff.louis+marc@gmail.com',    'Marc',    'Démo', 'manager'::public.app_role,       'Product'),
    ('guecheff.louis+gontran@gmail.com', 'Gontran', 'Démo', 'collaborateur'::public.app_role, 'Product'),
    ('guecheff.louis+olivia@gmail.com',  'Olivia',  'Démo', 'admin'::public.app_role,         NULL)
),
profils AS (
  -- Comme public.choisir_mon_role : seule la ligne d'un collaborateur porte l'équipe.
  INSERT INTO public.allowed_users (email, first_name, last_name, team)
  SELECT c.email, c.first_name, c.last_name, CASE WHEN c.role = 'collaborateur' THEN c.team END
  FROM comptes c
  ON CONFLICT (email) DO UPDATE
    SET first_name = excluded.first_name,
        last_name = excluded.last_name,
        team = excluded.team
  RETURNING id, email
)
INSERT INTO public.allowed_user_roles (allowed_user_id, role)
SELECT p.id, c.role FROM profils p JOIN comptes c USING (email)
ON CONFLICT (allowed_user_id) DO UPDATE SET role = excluded.role, updated_at = now();

-- Kesha et Marc gèrent Product ; l'admin reste sans équipe (« Admin » est réservée).
INSERT INTO public.manager_teams (allowed_user_id, team)
SELECT u.id, 'Product'
FROM public.allowed_users u
WHERE u.email IN ('guecheff.louis+kesha@gmail.com', 'guecheff.louis+marc@gmail.com')
ON CONFLICT (allowed_user_id, team) DO NOTHING;

-- Les mails Make arrivent à l'adresse de connexion, sans passer par les préférences.
INSERT INTO public.notification_mail_addresses (recipient_email, address)
SELECT e, e
FROM unnest(ARRAY[
  'guecheff.louis+kesha@gmail.com',
  'guecheff.louis+marc@gmail.com',
  'guecheff.louis+gontran@gmail.com',
  'guecheff.louis+olivia@gmail.com'
]) AS e
ON CONFLICT (recipient_email) DO UPDATE SET address = excluded.address, updated_at = now();

COMMIT;
