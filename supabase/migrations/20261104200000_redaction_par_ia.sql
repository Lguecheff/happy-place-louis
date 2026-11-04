-- Rédaction d'une actu par l'IA (US27). Limite de 20 générations par utilisateur et par jour
-- (heure de Paris), partagée avec l'US28 : Régénérer compte aussi.
-- La table n'est écrite que par la fonction ai-writer (clé service_role, côté serveur) :
-- aucun droit pour anon ni authenticated, pas de politique RLS.
BEGIN;

CREATE TABLE public.ai_usage (
  user_id uuid NOT NULL,
  day date NOT NULL,
  count int NOT NULL DEFAULT 0 CHECK (count BETWEEN 0 AND 20),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, day)
);

-- REVOKE d'abord : Supabase donne par défaut tous les droits sur une nouvelle table.
REVOKE ALL ON public.ai_usage FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.ai_usage TO service_role;
ALTER TABLE public.ai_usage ENABLE ROW LEVEL SECURITY;

-- Vérifie le rôle (manager ou admin) à partir de l'email du jeton déjà vérifié par la fonction,
-- puis compte une génération si la limite du jour n'est pas atteinte, en une seule écriture.
-- Renvoie {"status": "ok" | "forbidden" | "limit", "remaining": n}.
CREATE OR REPLACE FUNCTION public.ai_usage_consume(_user_id uuid, _email text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $function$
DECLARE
  _limit constant int := 20;
  _today date := (now() AT TIME ZONE 'Europe/Paris')::date;
  _role public.app_role;
  _count int;
BEGIN
  SELECT aur.role INTO _role
  FROM public.allowed_users au
  JOIN public.allowed_user_roles aur ON aur.allowed_user_id = au.id
  WHERE au.email = lower(_email)
  LIMIT 1;

  IF _role IS NULL OR _role NOT IN ('admin'::public.app_role, 'manager'::public.app_role) THEN
    RETURN jsonb_build_object('status', 'forbidden', 'remaining', 0);
  END IF;

  INSERT INTO public.ai_usage AS u (user_id, day, count)
  VALUES (_user_id, _today, 1)
  ON CONFLICT (user_id, day) DO UPDATE
    SET count = u.count + 1, updated_at = now()
    WHERE u.count < _limit
  RETURNING u.count INTO _count;

  IF _count IS NULL THEN
    RETURN jsonb_build_object('status', 'limit', 'remaining', 0);
  END IF;
  RETURN jsonb_build_object('status', 'ok', 'remaining', _limit - _count);
END;
$function$;

-- Rend la génération comptée quand le service d'IA n'a pas répondu : seul un texte reçu compte.
CREATE OR REPLACE FUNCTION public.ai_usage_refund(_user_id uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, private
AS $function$
  UPDATE public.ai_usage
  SET count = count - 1, updated_at = now()
  WHERE user_id = _user_id
    AND day = (now() AT TIME ZONE 'Europe/Paris')::date
    AND count > 0;
$function$;

REVOKE ALL ON FUNCTION public.ai_usage_consume(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ai_usage_refund(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ai_usage_consume(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.ai_usage_refund(uuid) TO service_role;

COMMENT ON TABLE public.ai_usage IS
  'Générations par IA par utilisateur et par jour (US27, partagé avec l''US28). Écrite par la fonction ai-writer seulement.';

COMMIT;

-- Vérification : les deux lignes doivent indiquer false (aucun droit pour les utilisateurs).
SELECT 'authenticated peut écrire ai_usage' AS test,
       has_table_privilege('authenticated', 'public.ai_usage', 'INSERT') AS valeur
UNION ALL
SELECT 'authenticated peut appeler ai_usage_consume',
       has_function_privilege('authenticated', 'public.ai_usage_consume(uuid, text)', 'EXECUTE');
