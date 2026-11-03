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
