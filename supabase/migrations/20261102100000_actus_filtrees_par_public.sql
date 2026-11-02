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
