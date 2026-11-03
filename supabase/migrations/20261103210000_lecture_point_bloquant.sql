-- Lecture d'un point bloquant (US19).
-- 1. « Ce que ça change pour toi » (impact), 300 caractères maximum, saisi par les admins
--    (politique « Admin write » existante).
-- 2. Un point concerne une ou plusieurs équipes (blocker_teams) ; sans équipe, il concerne
--    toutes les équipes. La colonne team (une seule équipe) disparaît après reprise.
-- 3. Le pôle (department) n'est plus saisi ni affiché : la colonne devient facultative.
BEGIN;

ALTER TABLE public.blockers
  ADD COLUMN impact text,
  ADD CONSTRAINT blockers_impact_length CHECK (char_length(impact) <= 300);

ALTER TABLE public.blockers
  ALTER COLUMN department DROP NOT NULL,
  ALTER COLUMN department DROP DEFAULT;

-- Supprimer une équipe la retire des points : un point sans équipe concerne toutes les équipes,
-- comme le faisait ON DELETE SET NULL sur team.
CREATE TABLE public.blocker_teams (
  blocker_id uuid NOT NULL REFERENCES public.blockers(id) ON DELETE CASCADE,
  team text NOT NULL REFERENCES public.teams(name) ON UPDATE CASCADE ON DELETE CASCADE,
  PRIMARY KEY (blocker_id, team)
);
CREATE INDEX blocker_teams_team_idx ON public.blocker_teams (team);

-- Supabase donne tous les droits à authenticated sur une nouvelle table : on repart de zéro.
REVOKE ALL ON public.blocker_teams FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, DELETE ON public.blocker_teams TO authenticated;
GRANT ALL ON public.blocker_teams TO service_role;

ALTER TABLE public.blocker_teams ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allowed read blocker teams" ON public.blocker_teams
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.blockers b WHERE b.id = blocker_id));

CREATE POLICY "Admin write" ON public.blocker_teams
  FOR ALL TO authenticated
  USING (private.is_admin())
  WITH CHECK (private.is_admin());

-- Reprise des équipes déjà saisies.
INSERT INTO public.blocker_teams (blocker_id, team)
SELECT id, team FROM public.blockers WHERE team IS NOT NULL;

ALTER TABLE public.blockers DROP COLUMN team;

-- Remplace les équipes d'un point en une fois (liste vide : toutes les équipes).
CREATE OR REPLACE FUNCTION public.save_blocker_teams(_blocker_id uuid, _teams text[] DEFAULT '{}')
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  IF NOT private.is_admin() THEN
    RAISE EXCEPTION 'Seuls les admins modifient les points bloquants.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  DELETE FROM public.blocker_teams WHERE blocker_id = _blocker_id;
  INSERT INTO public.blocker_teams (blocker_id, team)
  SELECT DISTINCT _blocker_id, t FROM unnest(_teams) AS t;
END
$function$;

REVOKE ALL ON FUNCTION public.save_blocker_teams(uuid, text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_blocker_teams(uuid, text[]) TO authenticated;

COMMIT;
