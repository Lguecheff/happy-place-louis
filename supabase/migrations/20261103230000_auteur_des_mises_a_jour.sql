-- Auteur des mises à jour (US20).
-- 1. metrics et blockers gagnent updated_by (uuid du compte, sans lien vers auth.users pour
--    survivre à sa suppression) et updated_by_name (nom copié au moment de la modification).
--    Les lignes existantes gardent ces colonnes vides : l'app n'affiche alors que la date.
-- 2. Un seul trigger, avant chaque création ou modification, remplit updated_at, updated_by et
--    updated_by_name et écrase ce que l'interface envoie. Le nom suit la règle de l'historique des
--    demandes : full_name, puis name du compte, puis e-mail. Sans utilisateur connecté (tâche
--    planifiée, script) : « Automatique ». Il remplace touch_blocker_updated_at (US16) ; la
--    simulation de démo recule toujours la date et garde l'auteur.
-- 3. Le départ d'une personne ne touche pas ces colonnes : son nom reste affiché.
-- 4. metrics_history n'a toujours pas d'auteur.
BEGIN;

ALTER TABLE public.metrics
  ADD COLUMN updated_by uuid,
  ADD COLUMN updated_by_name text;

ALTER TABLE public.blockers
  ADD COLUMN updated_by uuid,
  ADD COLUMN updated_by_name text;

CREATE OR REPLACE FUNCTION private.stamp_last_update()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _email text := lower(nullif(auth.jwt() ->> 'email', ''));
  _meta jsonb := auth.jwt() -> 'user_metadata';
BEGIN
  IF TG_OP = 'UPDATE' AND current_setting('happy_place.simulation', true) = 'on' THEN
    NEW.updated_by := OLD.updated_by;
    NEW.updated_by_name := OLD.updated_by_name;
    RETURN NEW;
  END IF;
  NEW.updated_at := now();
  IF _email IS NULL THEN
    NEW.updated_by := NULL;
    NEW.updated_by_name := 'Automatique';
  ELSE
    NEW.updated_by := auth.uid();
    NEW.updated_by_name := coalesce(nullif(btrim(_meta ->> 'full_name'), ''),
                                    nullif(btrim(_meta ->> 'name'), ''),
                                    _email);
  END IF;
  RETURN NEW;
END
$function$;

REVOKE ALL ON FUNCTION private.stamp_last_update() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS touch_blocker_updated_at ON public.blockers;
DROP FUNCTION IF EXISTS private.touch_blocker_updated_at();

CREATE TRIGGER stamp_last_update
  BEFORE INSERT OR UPDATE ON public.blockers
  FOR EACH ROW EXECUTE FUNCTION private.stamp_last_update();

CREATE TRIGGER stamp_last_update
  BEFORE INSERT OR UPDATE ON public.metrics
  FOR EACH ROW EXECUTE FUNCTION private.stamp_last_update();

-- Nouvelle colonne en dernier : CREATE OR REPLACE VIEW ne peut qu'ajouter à la fin.
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
    m.impact,
    m.updated_by_name
FROM public.metrics m
LEFT JOIN LATERAL (
    SELECT h.value
    FROM public.metrics_history h
    WHERE h.metric_key = m.key
    ORDER BY h.recorded_at DESC
    OFFSET 1
    LIMIT 1
) p ON true;

-- Test de fumée mis à jour pour l'auteur des mises à jour
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
  _uid20 uuid := gen_random_uuid(); _b20 uuid; _m20 record; _b20r record;
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

    -- Auteur des mises à jour (US20) : la base copie le nom à chaque création ou modification.
    PERFORM set_config('request.jwt.claims', json_build_object('sub', _uid20, 'email', 'smoke.admin@test.invalid',
      'user_metadata', json_build_object('full_name', 'Admin Fumée'))::text, true);
    INSERT INTO metrics(key, label, value) VALUES ('zz_smoke_us20', 'KPI de test', 1);
    INSERT INTO blockers(title, updated_by_name) VALUES ('Blocage auteur', 'Pirate') RETURNING id INTO _b20;
    SELECT updated_by, updated_by_name INTO _m20 FROM metrics WHERE key = 'zz_smoke_us20';
    SELECT updated_by, updated_by_name INTO _b20r FROM blockers WHERE id = _b20;
    _res := _res || jsonb_build_object('t', 'US20 : une création par un admin enregistre son nom (KPI et point bloquant)', 'ok',
      _m20.updated_by = _uid20 AND _m20.updated_by_name = 'Admin Fumée'
      AND _b20r.updated_by = _uid20 AND _b20r.updated_by_name = 'Admin Fumée',
      'd', coalesce(_m20.updated_by_name, '∅') || ' / ' || coalesce(_b20r.updated_by_name, '∅'));

    UPDATE metrics SET value = 2, updated_by = gen_random_uuid(), updated_by_name = 'Pirate',
                       updated_at = now() - interval '10 days'
     WHERE key = 'zz_smoke_us20';
    UPDATE blockers SET description = 'Modifié', updated_by = NULL, updated_by_name = 'Pirate' WHERE id = _b20;
    SELECT updated_by, updated_by_name, updated_at INTO _m20 FROM metrics WHERE key = 'zz_smoke_us20';
    SELECT updated_by, updated_by_name INTO _b20r FROM blockers WHERE id = _b20;
    _res := _res || jsonb_build_object('t', 'US20 : une valeur d''auteur ou de date envoyée par l''interface est écrasée', 'ok',
      _m20.updated_by = _uid20 AND _m20.updated_by_name = 'Admin Fumée' AND _m20.updated_at = now()
      AND _b20r.updated_by = _uid20 AND _b20r.updated_by_name = 'Admin Fumée',
      'd', coalesce(_m20.updated_by_name, '∅') || ' / ' || coalesce(_b20r.updated_by_name, '∅'));

    PERFORM set_config('request.jwt.claims', '', true);
    PERFORM private.fast_forward_blocker(_b20, interval '4 days');
    _res := _res || jsonb_build_object('t', 'US20 : la simulation de démo garde l''auteur du point', 'ok',
      (SELECT updated_by_name FROM blockers WHERE id = _b20) = 'Admin Fumée',
      'd', (SELECT coalesce(updated_by_name, '∅') FROM blockers WHERE id = _b20));

    UPDATE metrics SET value = 3, updated_by_name = 'Pirate' WHERE key = 'zz_smoke_us20';
    UPDATE blockers SET description = 'Modifié par un script' WHERE id = _b20;
    SELECT updated_by, updated_by_name INTO _m20 FROM metrics WHERE key = 'zz_smoke_us20';
    SELECT updated_by, updated_by_name INTO _b20r FROM blockers WHERE id = _b20;
    _res := _res || jsonb_build_object('t', 'US20 : une modification sans utilisateur enregistre « Automatique »', 'ok',
      _m20.updated_by IS NULL AND _m20.updated_by_name = 'Automatique'
      AND _b20r.updated_by IS NULL AND _b20r.updated_by_name = 'Automatique',
      'd', coalesce(_m20.updated_by_name, '∅') || ' / ' || coalesce(_b20r.updated_by_name, '∅'));

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.admin2@test.invalid"}', true);
    UPDATE metrics SET value = 4 WHERE key = 'zz_smoke_us20';
    _res := _res || jsonb_build_object('t', 'US20 : sans nom dans le compte, l''e-mail sert de nom', 'ok',
      (SELECT updated_by_name FROM metrics WHERE key = 'zz_smoke_us20') = 'smoke.admin2@test.invalid',
      'd', (SELECT coalesce(updated_by_name, '∅') FROM metrics WHERE key = 'zz_smoke_us20'));
    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      DELETE FROM allowed_users WHERE id = _adm2;
      _res := _res || jsonb_build_object('t', 'US20 : le nom de l''auteur reste affiché après son départ', 'ok',
        (SELECT updated_by_name FROM metrics WHERE key = 'zz_smoke_us20') = 'smoke.admin2@test.invalid',
        'd', (SELECT coalesce(updated_by_name, '∅') FROM metrics WHERE key = 'zz_smoke_us20'));
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'US20 : le nom de l''auteur reste affiché après son départ', 'ok', false, 'd', SQLERRM);
    END;
    _res := _res || jsonb_build_object('t', 'US20 : la vue des KPI expose l''auteur', 'ok',
      (SELECT updated_by_name FROM metrics_with_trend WHERE key = 'zz_smoke_us20') = 'smoke.admin2@test.invalid',
      'd', 'metrics_with_trend');

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
