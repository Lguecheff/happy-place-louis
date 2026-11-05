-- ============================================================
-- Résumé hebdomadaire
-- ============================================================
-- La base prépare le résumé de la semaine (actus, demandes, points bloquants) et le transmet
-- en UN SEUL appel à un second webhook Make : une partie commune (« global », lisible par tous,
-- envoyée à l'IA) et une entrée par destinataire (« recipients »). Make rédige l'insight une fois,
-- puis envoie un mail par destinataire.
-- Webhook : secrets Vault « make_digest_webhook_url » et « make_digest_webhook_secret ».
-- Envoi planifié : tâche pg_cron « weekly-digest », lundi 07:00 UTC (08:00 à Paris l'hiver,
-- 09:00 l'été : le changement d'heure n'est pas géré, choix validé pour la présentation).
BEGIN;

-- ---------- Webhook : lecture des secrets et transmission partagées ----------
-- Reprend private.mail_webhook avec les noms des secrets en paramètre. Même mode de test :
-- « happy_place.mail_webhook_mode » à « off » fait comme sans secret, « test » donne une adresse factice.
CREATE OR REPLACE FUNCTION private.vault_webhook(_url_name text, _secret_name text, OUT url text, OUT secret text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _mode text := current_setting('happy_place.mail_webhook_mode', true);
BEGIN
  IF _mode = 'off' THEN
    RETURN;
  ELSIF _mode = 'test' THEN
    url := 'https://example.invalid/happy-place-smoke';
    secret := 'smoke';
    RETURN;
  END IF;
  SELECT decrypted_secret INTO url FROM vault.decrypted_secrets WHERE name = _url_name LIMIT 1;
  SELECT decrypted_secret INTO secret FROM vault.decrypted_secrets WHERE name = _secret_name LIMIT 1;
END
$function$;

REVOKE ALL ON FUNCTION private.vault_webhook(text, text) FROM PUBLIC, anon, authenticated;

-- Même signature et même résultat qu'avant : les mails instantanés ne changent pas.
CREATE OR REPLACE FUNCTION private.mail_webhook(OUT url text, OUT secret text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  SELECT h.url, h.secret INTO url, secret
    FROM private.vault_webhook('make_mail_webhook_url', 'make_mail_webhook_secret') h;
END
$function$;

-- Poste un corps JSON au webhook nommé, avec l'en-tête x-happy-place-secret.
-- Renvoie l'identifiant de la requête pg_net, ou NULL sans adresse ou sans secret.
-- pg_net n'envoie la requête qu'après la validation de la transaction.
CREATE OR REPLACE FUNCTION private.post_webhook(_url_name text, _secret_name text, _body jsonb)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _hook record;
BEGIN
  SELECT * INTO _hook FROM private.vault_webhook(_url_name, _secret_name);
  IF nullif(_hook.url, '') IS NULL OR nullif(_hook.secret, '') IS NULL THEN
    RETURN NULL;
  END IF;
  RETURN net.http_post(
    url := _hook.url,
    body := _body,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-happy-place-secret', _hook.secret),
    timeout_milliseconds := 5000
  );
END
$function$;

REVOKE ALL ON FUNCTION private.post_webhook(text, text, jsonb) FROM PUBLIC, anon, authenticated;

-- Comportement inchangé ; la transmission passe par private.post_webhook.
CREATE OR REPLACE FUNCTION private.transmit_mail(_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _m public.mail_outbox%ROWTYPE;
  _request bigint;
BEGIN
  SELECT * INTO _m FROM public.mail_outbox WHERE id = _id AND status = 'en attente' FOR UPDATE SKIP LOCKED;
  IF NOT FOUND THEN
    RETURN false;
  END IF;
  _request := private.post_webhook(
    'make_mail_webhook_url', 'make_mail_webhook_secret',
    _m.payload || jsonb_build_object('id', _m.id, 'kind', _m.kind, 'to_address', _m.to_address));
  IF _request IS NULL THEN
    RETURN false;
  END IF;
  UPDATE public.mail_outbox SET status = 'transmis', posted_at = now(), request_id = _request WHERE id = _id;
  RETURN true;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'Mail % non transmis : %', _id, SQLERRM;
  RETURN false;
END
$function$;

-- ---------- Mise en forme ----------
-- Échappe un texte saisi par un utilisateur avant de l'insérer dans du HTML.
CREATE OR REPLACE FUNCTION private.html_escape(_text text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT replace(replace(replace(replace(replace(
           COALESCE(_text, ''), '&', '&amp;'), '<', '&lt;'), '>', '&gt;'), '"', '&quot;'), '''', '&#39;');
$function$;

-- « 4 novembre », « 1er décembre », avec l'année si demandée. Date de Paris.
CREATE OR REPLACE FUNCTION private.fr_date(_day date, _with_year boolean DEFAULT false)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT CASE WHEN extract(day FROM _day) = 1 THEN '1er' ELSE extract(day FROM _day)::int::text END
      || ' ' || (ARRAY['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août',
                       'septembre', 'octobre', 'novembre', 'décembre'])[extract(month FROM _day)::int]
      || CASE WHEN _with_year THEN ' ' || extract(year FROM _day)::int ELSE '' END;
$function$;

-- « du 2 au 8 novembre 2026 », « du 29 octobre au 4 novembre 2026 », « du 28 décembre 2026 au 3 janvier 2027 ».
-- _to est exclu : la période planifiée finit le dimanche à 23:59.
CREATE OR REPLACE FUNCTION private.digest_period_label(_from timestamptz, _to timestamptz)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public', 'private'
AS $function$
  SELECT CASE
           WHEN extract(year FROM d.a) <> extract(year FROM d.b)
             THEN 'du ' || private.fr_date(d.a, true) || ' au ' || private.fr_date(d.b, true)
           WHEN extract(month FROM d.a) <> extract(month FROM d.b)
             THEN 'du ' || private.fr_date(d.a) || ' au ' || private.fr_date(d.b, true)
           ELSE 'du ' || CASE WHEN extract(day FROM d.a) = 1 THEN '1er' ELSE extract(day FROM d.a)::int::text END
                || ' au ' || private.fr_date(d.b, true)
         END
    FROM (SELECT (_from AT TIME ZONE 'Europe/Paris')::date AS a,
                 ((_to - interval '1 second') AT TIME ZONE 'Europe/Paris')::date AS b) d;
$function$;

-- Une ligne de liste : titre en lien (Georgia), méta et extrait. Tout le texte est échappé ici.
-- Couleurs des mails existants : fond #eeede9, texte #2b2a30.
CREATE OR REPLACE FUNCTION private.digest_html_item(_title text, _url text, _meta text, _excerpt text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public', 'private'
AS $function$
  SELECT '<p style="margin:0 0 12px;padding:12px 16px;background:#eeede9;color:#2b2a30;font-size:14px;line-height:1.5">'
      || '<a href="' || private.html_escape(_url) || '" style="font-family:Georgia,serif;font-size:16px;color:#2b2a30;text-decoration:underline">'
      || private.html_escape(_title) || '</a>'
      || CASE WHEN nullif(_meta, '') IS NULL THEN ''
              ELSE '<br><span style="font-size:13px;color:#2b2a30">' || private.html_escape(_meta) || '</span>' END
      || CASE WHEN nullif(_excerpt, '') IS NULL THEN ''
              ELSE '<br>' || private.html_escape(_excerpt) END
      || '</p>';
$function$;

-- Lignes HTML d'une liste, plus « Et N autres dans Happy Place. » au-delà de ce qui est listé.
-- Liste vide : chaîne vide.
CREATE OR REPLACE FUNCTION private.digest_html_list(_items text[], _total integer)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public', 'private'
AS $function$
  SELECT COALESCE(array_to_string(_items, ''), '')
      || CASE WHEN _total > COALESCE(cardinality(_items), 0)
              THEN '<p style="margin:0 0 12px;color:#2b2a30;font-size:14px">Et '
                   || (_total - COALESCE(cardinality(_items), 0))
                   || CASE WHEN _total - COALESCE(cardinality(_items), 0) > 1 THEN ' autres' ELSE ' autre' END
                   || ' dans <a href="' || private.html_escape(private.app_base_url())
                   || '" style="color:#2b2a30;text-decoration:underline">Happy Place</a>.</p>'
              ELSE '' END;
$function$;

REVOKE ALL ON FUNCTION private.html_escape(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.fr_date(date, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.digest_period_label(timestamptz, timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.digest_html_item(text, text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.digest_html_list(text[], integer) FROM PUBLIC, anon, authenticated;

-- ---------- Destinataires ----------
-- Collaborateurs et managers actifs (pas de date de départ passée), avec une adresse de réception
-- et « Par mail » coché (ou jamais décoché) sur « Résumé hebdomadaire ». Jamais les admins.
CREATE OR REPLACE FUNCTION private.digest_recipients()
RETURNS TABLE(email text, to_address text, to_name text, role public.app_role, teams text[])
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
  SELECT lower(u.email),
         a.address,
         COALESCE(private.display_name_of(u.email), split_part(a.address, '@', 1)),
         r.role,
         CASE WHEN r.role = 'manager'::public.app_role
              THEN COALESCE((SELECT array_agg(mt.team ORDER BY mt.team) FROM public.manager_teams mt
                              WHERE mt.allowed_user_id = u.id), '{}')
              ELSE CASE WHEN u.team IS NULL THEN '{}'::text[] ELSE ARRAY[u.team] END
         END
    FROM public.allowed_users u
    JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id
    JOIN public.notification_mail_addresses a ON a.recipient_email = lower(u.email)
   WHERE r.role IN ('collaborateur'::public.app_role, 'manager'::public.app_role)
     AND (u.departure_date IS NULL OR u.departure_date > (now() AT TIME ZONE 'Europe/Paris')::date)
     AND private.wants_by_email(u.email, 'resume_hebdo'::public.notification_kind)
   ORDER BY lower(u.email);
$function$;

REVOKE ALL ON FUNCTION private.digest_recipients() FROM PUBLIC, anon, authenticated;

-- ---------- Données du résumé ----------
-- Partie « global » : seulement ce que tout utilisateur peut lire (elle part à l'IA).
-- Partie « recipients » : une entrée par destinataire, avec les règles de lecture de la RLS.
-- Listes limitées à 10 éléments (points bloquants : 5), avec leur total à côté.
CREATE OR REPLACE FUNCTION private.weekly_digest_payload(_from timestamptz, _to timestamptz)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _base text := private.app_base_url();
  _month_start timestamptz := date_trunc('month', now() AT TIME ZONE 'Europe/Paris') AT TIME ZONE 'Europe/Paris';
  _global jsonb;
  _recipients jsonb := '[]'::jsonb;
  r record;
  _team_news jsonb;
  _mine jsonb;
  _manager jsonb;
BEGIN
  WITH
  published AS (
    SELECT n.*, COALESCE(n.published_at, n.created_at) AS pub,
           COALESCE(n.audience, 'entreprise'::public.news_audience) AS aud
      FROM public.news n
     WHERE n.status = 'publiée'::public.news_status
       AND COALESCE(n.published_at, n.created_at) >= _from
       AND COALESCE(n.published_at, n.created_at) < _to
  ),
  company AS (
    SELECT p.*, row_number() OVER (ORDER BY p.pub DESC, p.id) AS rn, count(*) OVER () AS total
      FROM published p WHERE p.aud = 'entreprise'::public.news_audience
  ),
  -- Encore « validée » aujourd'hui : sinon, tout le monde ne peut plus la lire.
  validated AS (
    SELECT s.*, v.validated_at,
           row_number() OVER (ORDER BY v.validated_at DESC, s.id) AS rn, count(*) OVER () AS total
      FROM public.submissions s
      JOIN (SELECT h.submission_id, max(h.changed_at) AS validated_at
              FROM public.submission_status_history h
             WHERE h.new_status = 'validée'::public.submission_status
               AND h.changed_at >= _from AND h.changed_at < _to
             GROUP BY h.submission_id) v ON v.submission_id = s.id
     WHERE s.status = 'validée'::public.submission_status
  ),
  open_blockers AS (
    SELECT b.*,
           COALESCE((SELECT array_agg(bt.team ORDER BY bt.team) FROM public.blocker_teams bt
                      WHERE bt.blocker_id = b.id), ARRAY['Toutes les équipes']) AS team_names,
           floor(extract(epoch FROM now() - b.updated_at) / 86400)::int AS idle_days
      FROM public.blockers b
     WHERE b.status <> 'RÉSOLU'::public.blocker_status
  ),
  top_blockers AS (
    SELECT ob.*, row_number() OVER (
             ORDER BY CASE ob.severity WHEN 'critical'::public.blocker_severity THEN 0
                                       WHEN 'warning'::public.blocker_severity THEN 1 ELSE 2 END,
                      ob.updated_at, ob.id) AS rn
      FROM open_blockers ob
  ),
  pending AS (
    SELECT s.id, COALESCE((SELECT max(h.changed_at) FROM public.submission_status_history h
                            WHERE h.submission_id = s.id), s.created_at) AS since
      FROM public.submissions s WHERE s.status = 'en attente'::public.submission_status
  )
  SELECT jsonb_build_object(
    'stats', jsonb_build_object(
      'news_published', (SELECT count(*) FROM published),
      'submissions_created', (SELECT count(*) FROM public.submissions s
                               WHERE s.created_at >= _from AND s.created_at < _to),
      'submissions_processed', (SELECT count(*) FROM public.submission_status_history h
                                 WHERE h.new_status IN ('validée'::public.submission_status,
                                                        'refusée'::public.submission_status,
                                                        'clôturée'::public.submission_status)
                                   AND h.changed_at >= _from AND h.changed_at < _to),
      'submissions_pending_over_7_days', (SELECT count(*) FROM pending p WHERE p.since < _to - interval '7 days'),
      'blockers_open', (SELECT count(*) FROM open_blockers),
      'blockers_critical_open', (SELECT count(*) FROM open_blockers ob
                                  WHERE ob.severity = 'critical'::public.blocker_severity)),
    'company_news', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', c.id, 'title', c.title, 'excerpt', private.text_excerpt(c.body, 200),
        'author', c.author, 'published_at', c.pub, 'url', _base || '/?actu=' || c.id) ORDER BY c.rn)
      FROM company c WHERE c.rn <= 10), '[]'::jsonb),
    'company_news_total', COALESCE((SELECT max(c.total) FROM company c), 0),
    'company_news_html', private.digest_html_list(
      (SELECT array_agg(private.digest_html_item(
                c.title, _base || '/?actu=' || c.id,
                c.author || ' · ' || private.fr_date((c.pub AT TIME ZONE 'Europe/Paris')::date),
                private.text_excerpt(c.body, 200)) ORDER BY c.rn)
         FROM company c WHERE c.rn <= 10),
      COALESCE((SELECT max(c.total) FROM company c), 0)::int),
    'validated_submissions', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', v.id, 'excerpt', private.text_excerpt(v.content, 200), 'team', v.team,
        'author_name', v.author_name, 'validated_at', v.validated_at,
        'url', _base || '/?demande=' || v.id) ORDER BY v.rn)
      FROM validated v WHERE v.rn <= 10), '[]'::jsonb),
    'validated_submissions_total', COALESCE((SELECT max(v.total) FROM validated v), 0),
    'validated_submissions_html', private.digest_html_list(
      (SELECT array_agg(private.digest_html_item(
                private.submission_excerpt(v.content), _base || '/?demande=' || v.id,
                v.team || ' · ' || v.author_name || ' · validée le '
                  || private.fr_date((v.validated_at AT TIME ZONE 'Europe/Paris')::date),
                private.text_excerpt(v.content, 200)) ORDER BY v.rn)
         FROM validated v WHERE v.rn <= 10),
      COALESCE((SELECT max(v.total) FROM validated v), 0)::int),
    'open_blockers', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', t.id, 'title', t.title, 'severity', t.severity, 'status', t.status,
        'teams', to_jsonb(t.team_names), 'days_without_update', t.idle_days,
        'url', _base || '/?point=' || t.id) ORDER BY t.rn)
      FROM top_blockers t WHERE t.rn <= 5), '[]'::jsonb),
    'open_blockers_html', private.digest_html_list(
      (SELECT array_agg(private.digest_html_item(
                t.title, _base || '/?point=' || t.id,
                CASE WHEN t.severity = 'critical'::public.blocker_severity THEN 'Critique' ELSE 'À surveiller' END
                  || ' · ' || upper(left(lower(t.status::text), 1)) || substr(lower(t.status::text), 2)
                  || ' · ' || array_to_string(t.team_names, ', ')
                  || CASE WHEN t.idle_days >= 1
                          THEN ' · sans mise à jour depuis ' || t.idle_days
                               || CASE WHEN t.idle_days > 1 THEN ' jours' ELSE ' jour' END
                          ELSE '' END,
                NULL) ORDER BY t.rn)
         FROM top_blockers t WHERE t.rn <= 5),
      (SELECT count(*) FROM open_blockers)::int)
  ) INTO _global;

  FOR r IN SELECT * FROM private.digest_recipients() LOOP
    -- Actus « équipe » lisibles (règle « Allowed read published news ») : une de ses équipes
    -- est ciblée, ou il en est l'auteur.
    WITH tn AS (
      SELECT n.id, n.title, n.body, n.author, COALESCE(n.published_at, n.created_at) AS pub,
             row_number() OVER (ORDER BY COALESCE(n.published_at, n.created_at) DESC, n.id) AS rn,
             count(*) OVER () AS total
        FROM public.news n
       WHERE n.status = 'publiée'::public.news_status
         AND n.audience = 'équipe'::public.news_audience
         AND COALESCE(n.published_at, n.created_at) >= _from
         AND COALESCE(n.published_at, n.created_at) < _to
         AND (lower(n.author_email) = r.email
              OR EXISTS (SELECT 1 FROM public.news_teams nt WHERE nt.news_id = n.id AND nt.team = ANY (r.teams)))
    )
    SELECT jsonb_build_object(
             'team_news', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                 'id', x.id, 'title', x.title, 'excerpt', private.text_excerpt(x.body, 200),
                 'author', x.author, 'published_at', x.pub, 'url', _base || '/?actu=' || x.id) ORDER BY x.rn)
               FROM tn x WHERE x.rn <= 10), '[]'::jsonb),
             'team_news_total', COALESCE((SELECT max(x.total) FROM tn x), 0),
             'team_news_html', private.digest_html_list(
               (SELECT array_agg(private.digest_html_item(
                         x.title, _base || '/?actu=' || x.id,
                         x.author || ' · ' || private.fr_date((x.pub AT TIME ZONE 'Europe/Paris')::date),
                         private.text_excerpt(x.body, 200)) ORDER BY x.rn)
                  FROM tn x WHERE x.rn <= 10),
               COALESCE((SELECT max(x.total) FROM tn x), 0)::int))
      INTO _team_news;

    -- Ses demandes dont le statut a changé sur la période : le dernier changement de chacune.
    WITH last_change AS (
      SELECT DISTINCT ON (s.id) s.id, s.content, h.new_status, h.changed_at, h.is_automatic
        FROM public.submissions s
        JOIN public.submission_status_history h ON h.submission_id = s.id
       WHERE lower(s.submitted_by_email) = r.email
         AND h.old_status IS NOT NULL
         AND h.changed_at >= _from AND h.changed_at < _to
       ORDER BY s.id, h.changed_at DESC
    ),
    ms AS (
      SELECT c.*, row_number() OVER (ORDER BY c.changed_at DESC, c.id) AS rn, count(*) OVER () AS total
        FROM last_change c
    )
    SELECT jsonb_build_object(
             'my_submissions', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                 'id', m.id, 'excerpt', private.text_excerpt(m.content, 200), 'new_status', m.new_status,
                 'changed_at', m.changed_at, 'is_automatic', m.is_automatic,
                 'url', _base || '/?demande=' || m.id) ORDER BY m.rn)
               FROM ms m WHERE m.rn <= 10), '[]'::jsonb),
             'my_submissions_total', COALESCE((SELECT max(m.total) FROM ms m), 0),
             'my_submissions_html', private.digest_html_list(
               (SELECT array_agg(private.digest_html_item(
                         private.submission_excerpt(m.content), _base || '/?demande=' || m.id,
                         upper(left(m.new_status::text, 1)) || substr(m.new_status::text, 2)
                           || CASE WHEN m.is_automatic THEN ' automatiquement' ELSE '' END
                           || ' le ' || private.fr_date((m.changed_at AT TIME ZONE 'Europe/Paris')::date),
                         private.text_excerpt(m.content, 200)) ORDER BY m.rn)
                  FROM ms m WHERE m.rn <= 10),
               COALESCE((SELECT max(m.total) FROM ms m), 0)::int))
      INTO _mine;

    _manager := '{}'::jsonb;
    IF r.role = 'manager'::public.app_role THEN
      WITH pt AS (
        SELECT s.id, s.content, s.team, s.author_name, s.created_at,
               row_number() OVER (ORDER BY s.created_at, s.id) AS rn, count(*) OVER () AS total
          FROM public.submissions s
         WHERE s.status = 'en attente'::public.submission_status
           AND lower(s.team) IN (SELECT lower(t) FROM unnest(r.teams) t)
      )
      SELECT jsonb_build_object(
               'pending_in_my_teams', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                   'id', p.id, 'excerpt', private.text_excerpt(p.content, 200), 'team', p.team,
                   'author_name', p.author_name, 'created_at', p.created_at,
                   'url', _base || '/?demande=' || p.id) ORDER BY p.rn)
                 FROM pt p WHERE p.rn <= 10), '[]'::jsonb),
               'pending_in_my_teams_total', COALESCE((SELECT max(p.total) FROM pt p), 0),
               'pending_in_my_teams_html', private.digest_html_list(
                 (SELECT array_agg(private.digest_html_item(
                           private.submission_excerpt(p.content), _base || '/?demande=' || p.id,
                           p.team || ' · ' || p.author_name || ' · envoyée le '
                             || private.fr_date((p.created_at AT TIME ZONE 'Europe/Paris')::date),
                           private.text_excerpt(p.content, 200)) ORDER BY p.rn)
                    FROM pt p WHERE p.rn <= 10),
                 COALESCE((SELECT max(p.total) FROM pt p), 0)::int),
               -- Même règle que le compteur de l'US5 : publiées par lui depuis le 1er du mois (Paris).
               'news_this_month', (SELECT count(*) FROM public.news n
                                    WHERE lower(n.author_email) = r.email
                                      AND n.status = 'publiée'::public.news_status
                                      AND COALESCE(n.published_at, n.created_at) >= _month_start),
               'news_monthly_target', 4)
        INTO _manager;
    END IF;

    _recipients := _recipients || jsonb_build_array(
      jsonb_build_object('to_address', r.to_address, 'to_name', r.to_name, 'role', r.role, 'teams', to_jsonb(r.teams))
      || _team_news || _mine || _manager);
  END LOOP;

  RETURN jsonb_build_object(
    'period_from', _from,
    'period_to', _to,
    'period_label', private.digest_period_label(_from, _to),
    'week_number', extract(week FROM (_from AT TIME ZONE 'Europe/Paris'))::int,
    'app_url', _base,
    'preferences_url', _base || '/?preferences',
    'global', _global,
    'recipients', _recipients);
END
$function$;

REVOKE ALL ON FUNCTION private.weekly_digest_payload(timestamptz, timestamptz) FROM PUBLIC, anon, authenticated;

-- ---------- Historique des envois ----------
CREATE TABLE public.weekly_digests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  period_from timestamptz NOT NULL,
  period_to timestamptz NOT NULL,
  mode text NOT NULL CHECK (mode IN ('manuel', 'planifié')),
  sent_by_name text,
  recipients_count integer NOT NULL DEFAULT 0,
  payload jsonb NOT NULL,
  -- « en attente » : pas encore transmis (secret absent) ; « ignoré » : aucun destinataire.
  status public.mail_status NOT NULL DEFAULT 'en attente',
  request_id bigint,
  created_at timestamptz NOT NULL DEFAULT now(),
  posted_at timestamptz
);
CREATE INDEX weekly_digests_created_idx ON public.weekly_digests (created_at DESC);

-- REVOKE d'abord : Supabase donne par défaut tous les droits sur une nouvelle table.
-- Admins : lecture de toutes les colonnes sauf payload (noms et adresses des destinataires).
REVOKE ALL ON public.weekly_digests FROM PUBLIC, anon, authenticated;
GRANT SELECT (id, period_from, period_to, mode, sent_by_name, recipients_count, status, request_id, created_at, posted_at)
  ON public.weekly_digests TO authenticated;
GRANT ALL ON public.weekly_digests TO service_role;
ALTER TABLE public.weekly_digests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins read weekly digests" ON public.weekly_digests
  FOR SELECT TO authenticated
  USING (private.is_admin());

COMMENT ON TABLE public.weekly_digests IS
  'Résumés hebdomadaires préparés par la base et transmis en un seul appel au webhook Make du résumé (pg_net).';

-- ---------- Envoi ----------
-- Construit, enregistre et transmet un résumé. Sans destinataire : ligne « ignoré », rien n'est transmis.
-- Sans secret ou en cas d'échec de pg_net : la ligne reste « en attente », sans erreur.
CREATE OR REPLACE FUNCTION private.send_weekly_digest_for(
  _from timestamptz,
  _to timestamptz,
  _mode text,
  _by_name text,
  OUT recipients integer,
  OUT transmitted boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _id uuid := gen_random_uuid();
  _payload jsonb;
  _request bigint;
BEGIN
  _payload := private.weekly_digest_payload(_from, _to)
              || jsonb_build_object('digest_id', _id, 'mode', _mode, 'created_at', now());
  recipients := jsonb_array_length(_payload->'recipients');
  transmitted := false;
  INSERT INTO public.weekly_digests (id, period_from, period_to, mode, sent_by_name, recipients_count, payload, status)
  VALUES (_id, _from, _to, _mode, _by_name, recipients, _payload,
          CASE WHEN recipients = 0 THEN 'ignoré'::public.mail_status ELSE 'en attente'::public.mail_status END);
  IF recipients = 0 THEN
    RETURN;
  END IF;
  BEGIN
    _request := private.post_webhook('make_digest_webhook_url', 'make_digest_webhook_secret', _payload);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Résumé % non transmis : %', _id, SQLERRM;
    _request := NULL;
  END;
  IF _request IS NOT NULL THEN
    UPDATE public.weekly_digests SET status = 'transmis', posted_at = now(), request_id = _request WHERE id = _id;
    transmitted := true;
  END IF;
END
$function$;

REVOKE ALL ON FUNCTION private.send_weekly_digest_for(timestamptz, timestamptz, text, text) FROM PUBLIC, anon, authenticated;

-- Envoi manuel, réservé aux admins : les 7 derniers jours glissants.
-- Refusé si un envoi manuel a eu lieu dans la dernière minute (double clic, deux onglets).
CREATE OR REPLACE FUNCTION public.send_weekly_digest()
RETURNS TABLE(recipients integer, transmitted boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _email text := lower(auth.jwt() ->> 'email');
BEGIN
  IF NOT COALESCE(private.is_admin(), false) THEN
    RAISE EXCEPTION 'Seul un admin peut envoyer le résumé hebdomadaire.' USING ERRCODE = '42501';
  END IF;
  IF EXISTS (SELECT 1 FROM public.weekly_digests
              WHERE mode = 'manuel' AND created_at > now() - interval '1 minute') THEN
    RAISE EXCEPTION 'Un résumé vient d''être envoyé. Réessaie dans une minute.';
  END IF;
  RETURN QUERY
    SELECT d.recipients, d.transmitted
      FROM private.send_weekly_digest_for(now() - interval '7 days', now(), 'manuel',
                                          COALESCE(private.display_name_of(_email), _email)) d;
END
$function$;

REVOKE ALL ON FUNCTION public.send_weekly_digest() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_weekly_digest() TO authenticated;

-- Nombre de destinataires, sans construire le résumé (confirmation de /manage). Admins seulement.
CREATE OR REPLACE FUNCTION public.weekly_digest_recipients_count()
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  IF NOT COALESCE(private.is_admin(), false) THEN
    RAISE EXCEPTION 'Seul un admin peut voir les destinataires du résumé hebdomadaire.' USING ERRCODE = '42501';
  END IF;
  RETURN (SELECT count(*) FROM private.digest_recipients());
END
$function$;

REVOKE ALL ON FUNCTION public.weekly_digest_recipients_count() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.weekly_digest_recipients_count() TO authenticated;

-- Envoi planifié : la semaine calendaire précédente, du lundi 00:00 au dimanche 23:59, heure de Paris.
CREATE OR REPLACE FUNCTION private.send_weekly_digest_scheduled()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _monday timestamp := date_trunc('week', now() AT TIME ZONE 'Europe/Paris');
  _sent record;
BEGIN
  SELECT * INTO _sent FROM private.send_weekly_digest_for(
    (_monday - interval '7 days') AT TIME ZONE 'Europe/Paris',
    _monday AT TIME ZONE 'Europe/Paris',
    'planifié', NULL);
  RETURN _sent.recipients;
END
$function$;

REVOKE ALL ON FUNCTION private.send_weekly_digest_scheduled() FROM PUBLIC, anon, authenticated;

-- Lundi 07:00 UTC : 08:00 à Paris l'hiver, 09:00 l'été. Heure distincte des tâches de 03:00 à 03:45.
SELECT cron.schedule('weekly-digest', '0 7 * * 1', 'SELECT private.send_weekly_digest_scheduled()');

-- ---------- Tests de fumée ----------
-- Appelés par private.run_smoke_tests() avant son annulation finale : rien n'est gardé.
CREATE OR REPLACE FUNCTION private.smoke_digest_tests()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _res jsonb := '[]'::jsonb;
  _team text := 'ZZ Test résumé';
  _other text := 'ZZ Test résumé autre';
  _c1 uuid; _c2 uuid; _c3 uuid; _m1 uuid; _adm uuid;
  _nt uuid; _nc uuid; _p jsonb; _g text; _c1_entry jsonb; _m1_entry jsonb;
  _addresses text[]; _digest record; _status text;
  C1 constant text := 'smoke.digest.c1@test.invalid';
  C2 constant text := 'smoke.digest.c2@test.invalid';
  C3 constant text := 'smoke.digest.c3@test.invalid';
  M1 constant text := 'smoke.digest.m1@test.invalid';
  ADM constant text := 'smoke.digest.admin@test.invalid';
BEGIN
  PERFORM set_config('happy_place.mail_webhook_mode', 'off', true);
  PERFORM set_config('request.jwt.claims', '', true);

  -- c1 : collaborateur de l'équipe, avec adresse ; c2 : « Par mail » décoché ; c3 : sans adresse ;
  -- m1 : manager de l'autre équipe ; un admin avec adresse.
  INSERT INTO teams(name) VALUES (_team), (_other) ON CONFLICT DO NOTHING;
  INSERT INTO allowed_users(email, team, first_name, last_name) VALUES (C1, _team, 'Gontran', 'Résumé') RETURNING id INTO _c1;
  INSERT INTO allowed_users(email, team, first_name, last_name) VALUES (C2, _team, 'Collab', 'Deux') RETURNING id INTO _c2;
  INSERT INTO allowed_users(email, team, first_name, last_name) VALUES (C3, _team, 'Collab', 'Trois') RETURNING id INTO _c3;
  INSERT INTO allowed_users(email, first_name, last_name) VALUES (M1, 'Kesha', 'Résumé') RETURNING id INTO _m1;
  INSERT INTO allowed_users(email, first_name, last_name) VALUES (ADM, 'Olivia', 'Résumé') RETURNING id INTO _adm;
  INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES
    (_c1, 'collaborateur'), (_c2, 'collaborateur'), (_c3, 'collaborateur'), (_m1, 'manager'), (_adm, 'admin');
  INSERT INTO manager_teams(allowed_user_id, team) VALUES (_m1, _other);
  INSERT INTO notification_mail_addresses(recipient_email, address) VALUES
    (C1, 'digest.c1@exemple.fr'), (C2, 'digest.c2@exemple.fr'), (M1, 'digest.m1@exemple.fr'),
    (ADM, 'digest.admin@exemple.fr');
  INSERT INTO notification_preferences(recipient_email, kind, in_app, by_email) VALUES
    (C2, 'resume_hebdo', true, false);

  -- Une actu « équipe » de l'autre équipe (titre avec <script>), une actu « entreprise ».
  PERFORM set_config('request.jwt.claims', json_build_object('email', M1)::text, true);
  INSERT INTO news(title, body, author, status) VALUES ('Résumé équipe <script>alert(1)</script>', 'Corps', 'Kesha', 'brouillon') RETURNING id INTO _nt;
  PERFORM public.save_news_audience(_nt, 'équipe', ARRAY[_other]);
  UPDATE news SET status = 'publiée' WHERE id = _nt;
  PERFORM set_config('request.jwt.claims', json_build_object('email', ADM)::text, true);
  INSERT INTO news(title, body, author, status) VALUES ('Résumé entreprise <script>alert(2)</script>', 'Corps', 'Olivia', 'brouillon') RETURNING id INTO _nc;
  PERFORM public.save_news_audience(_nc, 'entreprise');
  UPDATE news SET status = 'publiée' WHERE id = _nc;
  PERFORM set_config('request.jwt.claims', '', true);

  _p := private.weekly_digest_payload(now() - interval '1 day', now() + interval '1 minute');
  _g := (_p->'global')::text;
  SELECT x INTO _c1_entry FROM jsonb_array_elements(_p->'recipients') x WHERE x->>'to_address' = 'digest.c1@exemple.fr';
  SELECT x INTO _m1_entry FROM jsonb_array_elements(_p->'recipients') x WHERE x->>'to_address' = 'digest.m1@exemple.fr';
  SELECT COALESCE(array_agg(x->>'to_address'), '{}') INTO _addresses FROM jsonb_array_elements(_p->'recipients') x;

  _res := _res || jsonb_build_object('t', 'Résumé : une actu « équipe » d''une autre équipe n''est ni dans global ni dans les actus d''équipe d''un collaborateur hors de cette équipe', 'ok',
    position(_nt::text IN _g) = 0
    AND _c1_entry IS NOT NULL
    AND position(_nt::text IN (_c1_entry->'team_news')::text) = 0
    AND position(_nt::text IN (_m1_entry->'team_news')::text) > 0,
    'd', COALESCE(jsonb_array_length(_c1_entry->'team_news'), -1) || ' actu(s) d''équipe pour c1');
  _res := _res || jsonb_build_object('t', 'Résumé : une actu « entreprise » apparaît dans company_news', 'ok',
    EXISTS (SELECT 1 FROM jsonb_array_elements(_p->'global'->'company_news') x WHERE x->>'id' = _nc::text),
    'd', jsonb_array_length(_p->'global'->'company_news') || ' actu(s) entreprise');
  _res := _res || jsonb_build_object('t', 'Résumé : un admin n''est jamais destinataire', 'ok',
    NOT 'digest.admin@exemple.fr' = ANY (_addresses), 'd', array_length(_addresses, 1) || ' destinataire(s)');
  _res := _res || jsonb_build_object('t', 'Résumé : « Par mail » décoché ou sans adresse, pas destinataire', 'ok',
    NOT 'digest.c2@exemple.fr' = ANY (_addresses)
    AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(_p->'recipients') x WHERE x->>'to_name' = 'Collab Trois')
    AND 'digest.c1@exemple.fr' = ANY (_addresses),
    'd', array_to_string(_addresses, ', '));
  _res := _res || jsonb_build_object('t', 'Résumé : un titre contenant <script> est échappé dans les champs _html', 'ok',
    position('&lt;script&gt;alert(2)' IN _p->'global'->>'company_news_html') > 0
    AND position('<script' IN _p->'global'->>'company_news_html') = 0
    AND position('&lt;script&gt;alert(1)' IN _m1_entry->>'team_news_html') > 0
    AND position('<script' IN _m1_entry->>'team_news_html') = 0,
    'd', left(_p->'global'->>'company_news_html', 120));

  -- Un collaborateur ne peut pas lancer l'envoi.
  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('email', C1)::text, true);
    PERFORM * FROM public.send_weekly_digest();
    _res := _res || jsonb_build_object('t', 'Résumé : un non-admin ne peut pas appeler send_weekly_digest', 'ok', false, 'd', 'envoi accepté');
  EXCEPTION WHEN insufficient_privilege THEN
    _res := _res || jsonb_build_object('t', 'Résumé : un non-admin ne peut pas appeler send_weekly_digest', 'ok', true, 'd', SQLERRM);
  WHEN OTHERS THEN
    _res := _res || jsonb_build_object('t', 'Résumé : un non-admin ne peut pas appeler send_weekly_digest', 'ok', false, 'd', SQLERRM);
  END;
  PERFORM set_config('request.jwt.claims', '', true);

  -- Sans secret Vault (mode « off »), la ligne reste « en attente ».
  BEGIN
    SELECT * INTO _digest FROM private.send_weekly_digest_for(now() - interval '1 day', now() + interval '1 minute', 'manuel', 'Smoke');
    SELECT status::text INTO _status FROM weekly_digests
     WHERE sent_by_name = 'Smoke' LIMIT 1;
    _res := _res || jsonb_build_object('t', 'Résumé : sans secret Vault, la ligne reste « en attente »', 'ok',
      _digest.recipients > 0 AND NOT _digest.transmitted AND _status = 'en attente',
      'd', _digest.recipients || ' destinataire(s), ' || COALESCE(_status, 'aucune ligne'));
  EXCEPTION WHEN OTHERS THEN
    _res := _res || jsonb_build_object('t', 'Résumé : sans secret Vault, la ligne reste « en attente »', 'ok', false, 'd', SQLERRM);
  END;

  RETURN _res;
END
$function$;

REVOKE ALL ON FUNCTION private.smoke_digest_tests() FROM PUBLIC, anon, authenticated;

-- Ajout des tests du résumé hebdomadaire à la suite existante.
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
  _mgr21 uuid; _b21 uuid; _b21a uuid; _b21o uuid; _s21 uuid; _m21 record; _b21r record;
  _cnt21 int; _hist21 int; _notif21 int; _upd21 timestamptz;
  _since21 timestamptz; _sim21 int; _auth21 text;
  _uid26a uuid := gen_random_uuid(); _uid26b uuid := gen_random_uuid(); _idea26 record;
BEGIN
  BEGIN
    -- Aucun mail transmis pendant les tests, même si les secrets Vault existent.
    PERFORM set_config('happy_place.mail_webhook_mode', 'off', true);
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
    INSERT INTO metrics(key, label, value, stale_after_days, threshold_max) VALUES ('zz_smoke_us20', 'KPI de test', 1, 7, 100);
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

    -- Signal à vérifier (US21)
    PERFORM set_config('request.jwt.claims', '', true);
    INSERT INTO allowed_users(email) VALUES ('smoke.manager21@test.invalid') RETURNING id INTO _mgr21;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_mgr21, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_mgr21, 'ZZ Test fumée autre');

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.admin@test.invalid"}', true);
    BEGIN
      INSERT INTO metrics(key, label, value) VALUES ('zz_smoke_us21_sans', 'KPI sans seuil', 1);
      _res := _res || jsonb_build_object('t', 'US21 : un KPI ne se crée pas sans seuil « à vérifier »', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'US21 : un KPI ne se crée pas sans seuil « à vérifier »', 'ok', true, 'd', 'refusé par la base');
    END;
    BEGIN
      INSERT INTO metrics(key, label, value, stale_after_days) VALUES ('zz_smoke_us21_hors', 'KPI hors bornes', 1, 366);
      _res := _res || jsonb_build_object('t', 'US21 : un seuil hors de 1 à 365 est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'US21 : un seuil hors de 1 à 365 est refusé', 'ok', true, 'd', 'refusé par la base');
    END;
    INSERT INTO metrics(key, label, value, stale_after_days, threshold_min) VALUES ('zz_smoke_us21', 'KPI vérifié', 5, 3, 1);
    SELECT count(*) INTO _cnt21 FROM metrics_history WHERE metric_key = 'zz_smoke_us21';

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab@test.invalid"}', true);
    BEGIN
      PERFORM public.verify_metric('zz_smoke_us21');
      _res := _res || jsonb_build_object('t', 'US21 : un collaborateur ne peut pas marquer un KPI comme vérifié', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'US21 : un collaborateur ne peut pas marquer un KPI comme vérifié', 'ok', true, 'd', 'refusé par la base');
    END;
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager21@test.invalid"}', true);
    BEGIN
      PERFORM public.verify_metric('zz_smoke_us21');
      SELECT value, stale_after_days, updated_at, verified_at, updated_by_name INTO _m21
        FROM metrics WHERE key = 'zz_smoke_us21';
      _res := _res || jsonb_build_object('t', 'US21 : un manager marque un KPI comme vérifié (date et auteur, rien d''autre)', 'ok',
        _m21.verified_at = now() AND _m21.updated_at = _m21.verified_at
        AND _m21.updated_by_name = 'smoke.manager21@test.invalid'
        AND _m21.value = 5 AND _m21.stale_after_days = 3
        AND (SELECT count(*) FROM metrics_history WHERE metric_key = 'zz_smoke_us21') = _cnt21
        AND (SELECT verified_at FROM metrics_with_trend WHERE key = 'zz_smoke_us21') = now(),
        'd', coalesce(_m21.updated_by_name, '∅'));
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'US21 : un manager marque un KPI comme vérifié (date et auteur, rien d''autre)', 'ok', false, 'd', SQLERRM);
    END;
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.admin@test.invalid"}', true);
    BEGIN
      UPDATE metrics SET stale_after_days = NULL WHERE key = 'zz_smoke_us21';
      _res := _res || jsonb_build_object('t', 'US21 : un seuil défini ne peut pas être effacé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'US21 : un seuil défini ne peut pas être effacé', 'ok', true, 'd', 'refusé par la base');
    END;

    -- Seuil de valeur des KPI : plage, compteur depuis le franchissement ou le changement de seuils.
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.admin@test.invalid"}', true);
    BEGIN
      INSERT INTO metrics(key, label, value, stale_after_days) VALUES ('zz_smoke_plage_sans', 'Sans borne', 1, 7);
      _res := _res || jsonb_build_object('t', 'US21 : un KPI ne se crée pas sans seuil minimum ni maximum', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'US21 : un KPI ne se crée pas sans seuil minimum ni maximum', 'ok', true, 'd', 'refusé par la base');
    END;
    BEGIN
      INSERT INTO metrics(key, label, value, stale_after_days, threshold_min, threshold_max)
      VALUES ('zz_smoke_plage_inv', 'Plage inversée', 1, 7, 50, 10);
      _res := _res || jsonb_build_object('t', 'US21 : un minimum plus grand que le maximum est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'US21 : un minimum plus grand que le maximum est refusé', 'ok', true, 'd', 'refusé par la base');
    END;
    INSERT INTO metrics(key, label, value, stale_after_days, threshold_min)
    VALUES ('zz_smoke_plage', 'KPI plage', 5, 3, 10);
    BEGIN
      UPDATE metrics SET threshold_min = NULL WHERE key = 'zz_smoke_plage';
      _res := _res || jsonb_build_object('t', 'US21 : la dernière borne d''un KPI ne peut pas être retirée', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'US21 : la dernière borne d''un KPI ne peut pas être retirée', 'ok', true, 'd', 'refusé par la base');
    END;
    -- Historique reculé : sous le minimum depuis 10 jours, seuils posés il y a 20 jours.
    UPDATE metrics_history SET recorded_at = now() - interval '10 days' WHERE metric_key = 'zz_smoke_plage';
    UPDATE metrics SET thresholds_updated_at = now() - interval '20 days' WHERE key = 'zz_smoke_plage';
    SELECT out_of_range_since INTO _since21 FROM metrics_with_trend WHERE key = 'zz_smoke_plage';
    _res := _res || jsonb_build_object('t', 'US21 : sous le minimum, le compteur part de la première valeur hors plage', 'ok',
      _since21 = now() - interval '10 days', 'd', coalesce(_since21::text, '∅'));
    INSERT INTO metrics_history(metric_key, value, recorded_at)
    VALUES ('zz_smoke_plage', 15, now() - interval '6 days'), ('zz_smoke_plage', 4, now() - interval '2 days');
    UPDATE metrics SET value = 4 WHERE key = 'zz_smoke_plage';
    SELECT out_of_range_since INTO _since21 FROM metrics_with_trend WHERE key = 'zz_smoke_plage';
    _res := _res || jsonb_build_object('t', 'US21 : un retour dans la plage remet le compteur à zéro', 'ok',
      _since21 = now() - interval '2 days', 'd', coalesce(_since21::text, '∅'));
    UPDATE metrics SET value = 10 WHERE key = 'zz_smoke_plage';
    SELECT out_of_range_since INTO _since21 FROM metrics_with_trend WHERE key = 'zz_smoke_plage';
    _res := _res || jsonb_build_object('t', 'US21 : une valeur égale au minimum compte comme hors plage', 'ok',
      _since21 = now() - interval '2 days', 'd', coalesce(_since21::text, '∅'));
    UPDATE metrics SET threshold_max = 50 WHERE key = 'zz_smoke_plage';
    SELECT out_of_range_since INTO _since21 FROM metrics_with_trend WHERE key = 'zz_smoke_plage';
    _res := _res || jsonb_build_object('t', 'US21 : changer les seuils fait repartir le compteur de ce changement', 'ok',
      _since21 = now()
      AND (SELECT thresholds_updated_at FROM metrics WHERE key = 'zz_smoke_plage') = now(),
      'd', coalesce(_since21::text, '∅'));
    UPDATE metrics SET value = 60 WHERE key = 'zz_smoke_plage';
    SELECT out_of_range_since INTO _since21 FROM metrics_with_trend WHERE key = 'zz_smoke_plage';
    _res := _res || jsonb_build_object('t', 'US21 : au maximum ou au-delà, le KPI est hors plage', 'ok',
      _since21 IS NOT NULL, 'd', coalesce(_since21::text, '∅'));
    UPDATE metrics SET value = 30 WHERE key = 'zz_smoke_plage';
    _res := _res || jsonb_build_object('t', 'US21 : dans la plage, pas de compteur', 'ok',
      (SELECT out_of_range_since FROM metrics_with_trend WHERE key = 'zz_smoke_plage') IS NULL, 'd', 'vide');

    -- Simulation de démo : admin seulement, KPI hors plage seulement.
    BEGIN
      PERFORM public.simuler_kpi_hors_plage('zz_smoke_plage');
      _res := _res || jsonb_build_object('t', 'US21 : pas de simulation sur un KPI dans sa plage', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'US21 : pas de simulation sur un KPI dans sa plage', 'ok', true, 'd', 'refusé par la base');
    END;
    UPDATE metrics SET value = 70 WHERE key = 'zz_smoke_plage';
    SELECT updated_by_name INTO _auth21 FROM metrics WHERE key = 'zz_smoke_plage';
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    BEGIN
      PERFORM public.simuler_kpi_hors_plage('zz_smoke_plage');
      _res := _res || jsonb_build_object('t', 'US21 : un manager ne peut pas simuler un KPI hors plage', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'US21 : un manager ne peut pas simuler un KPI hors plage', 'ok', true, 'd', 'refusé par la base');
    END;
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.admin@test.invalid"}', true);
    BEGIN
      _sim21 := public.simuler_kpi_hors_plage('zz_smoke_plage');
      SELECT out_of_range_since INTO _since21 FROM metrics_with_trend WHERE key = 'zz_smoke_plage';
      _res := _res || jsonb_build_object('t', 'US21 : la simulation d''un admin recule le compteur de la durée + 1 jour, sans changer l''auteur', 'ok',
        _sim21 = 4 AND _since21 = now() - interval '4 days'
        AND (SELECT updated_by_name FROM metrics WHERE key = 'zz_smoke_plage') = _auth21
        AND (SELECT value FROM metrics WHERE key = 'zz_smoke_plage') = 70,
        'd', _sim21 || ' jours, depuis ' || coalesce(_since21::text, '∅'));
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'US21 : la simulation d''un admin recule le compteur de la durée + 1 jour, sans changer l''auteur', 'ok', false, 'd', SQLERRM);
    END;

    -- Points bloquants : b21 (équipe du test), b21o (autre équipe), b21a (toutes les équipes).
    INSERT INTO blockers(title, department) VALUES ('Blocage équipe', 'Test') RETURNING id INTO _b21;
    INSERT INTO blocker_teams(blocker_id, team) VALUES (_b21, _team);
    INSERT INTO blockers(title, department) VALUES ('Blocage autre équipe', 'Test') RETURNING id INTO _b21o;
    INSERT INTO blocker_teams(blocker_id, team) VALUES (_b21o, 'ZZ Test fumée autre');
    INSERT INTO blockers(title, department) VALUES ('Blocage toutes équipes', 'Test') RETURNING id INTO _b21a;

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    BEGIN
      PERFORM public.set_blocker_status(_b21, 'EN COURS');
      PERFORM public.set_blocker_status(_b21a, 'EN COURS');
      _res := _res || jsonb_build_object('t', 'US21 : un manager change le statut d''un point de son équipe et d''un point de toutes les équipes', 'ok',
        (SELECT status::text FROM blockers WHERE id = _b21) = 'EN COURS'
        AND (SELECT status::text FROM blockers WHERE id = _b21a) = 'EN COURS'
        AND (SELECT updated_by_name FROM blockers WHERE id = _b21) = 'smoke.manager@test.invalid',
        'd', 'EN COURS');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'US21 : un manager change le statut d''un point de son équipe et d''un point de toutes les équipes', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      PERFORM public.set_blocker_status(_b21o, 'EN COURS');
      _res := _res || jsonb_build_object('t', 'US21 : un manager ne change pas le statut du point d''une autre équipe', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'US21 : un manager ne change pas le statut du point d''une autre équipe', 'ok', true, 'd', 'refusé par la base');
    END;
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab@test.invalid"}', true);
    BEGIN
      PERFORM public.set_blocker_status(_b21, 'SURVEILLANCE');
      _res := _res || jsonb_build_object('t', 'US21 : un collaborateur ne change aucun statut de point bloquant', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'US21 : un collaborateur ne change aucun statut de point bloquant', 'ok', true, 'd', 'refusé par la base');
    END;

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager21@test.invalid"}', true);
    BEGIN
      PERFORM public.remind_blocker_teams(_b21);
      _res := _res || jsonb_build_object('t', 'US21 : pas de relance d''un point mis à jour il y a moins de 3 jours', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'US21 : pas de relance d''un point mis à jour il y a moins de 3 jours', 'ok', true, 'd', 'refusé par la base');
    END;
    PERFORM set_config('request.jwt.claims', '', true);
    PERFORM private.fast_forward_blocker(_b21, interval '4 days');
    PERFORM private.fast_forward_blocker(_b21a, interval '4 days');
    SELECT updated_at INTO _upd21 FROM blockers WHERE id = _b21;

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    BEGIN
      PERFORM public.remind_blocker_teams(_b21);
      _res := _res || jsonb_build_object('t', 'US21 : un manager ne relance pas un point qui le concerne', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'US21 : un manager ne relance pas un point qui le concerne', 'ok', true, 'd', 'refusé par la base');
    END;
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab@test.invalid"}', true);
    BEGIN
      PERFORM public.remind_blocker_teams(_b21);
      _res := _res || jsonb_build_object('t', 'US21 : un collaborateur ne relance personne', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'US21 : un collaborateur ne relance personne', 'ok', true, 'd', 'refusé par la base');
    END;
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager21@test.invalid"}', true);
    BEGIN
      _notif21 := public.remind_blocker_teams(_b21);
      SELECT updated_at, reminded_at, reminded_by_name INTO _b21r FROM blockers WHERE id = _b21;
      _res := _res || jsonb_build_object('t', 'US21 : un manager relance les collaborateurs et managers d''un point d''une autre équipe', 'ok',
        EXISTS (SELECT 1 FROM notifications WHERE blocker_id = _b21 AND recipient_email = 'smoke.collab@test.invalid'
                AND kind = 'relance_point_bloquant'
                AND message = 'smoke.manager21@test.invalid te relance sur le point bloquant : Blocage équipe'
                AND actor_name = 'smoke.manager21@test.invalid')
        AND EXISTS (SELECT 1 FROM notifications WHERE blocker_id = _b21 AND recipient_email = 'smoke.manager@test.invalid'
                    AND kind = 'relance_point_bloquant')
        AND NOT EXISTS (SELECT 1 FROM notifications WHERE blocker_id = _b21 AND recipient_email = 'smoke.manager21@test.invalid')
        AND NOT EXISTS (SELECT 1 FROM notifications WHERE blocker_id = _b21 AND recipient_email = 'smoke.admin@test.invalid'
                        AND kind = 'relance_point_bloquant'),
        'd', _notif21 || ' notification(s)');
      _res := _res || jsonb_build_object('t', 'US21 : une relance enregistre son auteur sans changer la date de mise à jour', 'ok',
        _b21r.updated_at = _upd21 AND _b21r.reminded_at = now()
        AND _b21r.reminded_by_name = 'smoke.manager21@test.invalid',
        'd', coalesce(_b21r.reminded_by_name, '∅'));
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'US21 : un manager relance les collaborateurs et managers d''un point d''une autre équipe', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      PERFORM public.remind_blocker_teams(_b21);
      _res := _res || jsonb_build_object('t', 'US21 : une seule relance tant que le point n''a pas été modifié', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'US21 : une seule relance tant que le point n''a pas été modifié', 'ok', true, 'd', 'refusé par la base');
    END;
    BEGIN
      PERFORM public.remind_blocker_teams(_b21a);
      _res := _res || jsonb_build_object('t', 'US21 : un manager ne relance pas un point de toutes les équipes', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'US21 : un manager ne relance pas un point de toutes les équipes', 'ok', true, 'd', 'refusé par la base');
    END;
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.admin@test.invalid"}', true);
    BEGIN
      PERFORM public.remind_blocker_teams(_b21a);
      _res := _res || jsonb_build_object('t', 'US21 : point de toutes les équipes : l''admin ne relance que les managers', 'ok',
        EXISTS (SELECT 1 FROM notifications WHERE blocker_id = _b21a AND recipient_email = 'smoke.manager@test.invalid')
        AND EXISTS (SELECT 1 FROM notifications WHERE blocker_id = _b21a AND recipient_email = 'smoke.manager21@test.invalid')
        AND NOT EXISTS (SELECT 1 FROM notifications WHERE blocker_id = _b21a AND recipient_email = 'smoke.collab@test.invalid'),
        'd', 'managers seulement');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'US21 : point de toutes les équipes : l''admin ne relance que les managers', 'ok', false, 'd', SQLERRM);
    END;
    -- Tout se passe à la même date dans le test : la relance est reculée d'une heure, comme si
    -- la modification venait après.
    PERFORM set_config('happy_place.keep_last_update', 'on', true);
    UPDATE blockers SET reminded_at = reminded_at - interval '1 hour' WHERE id = _b21;
    PERFORM set_config('happy_place.keep_last_update', '', true);
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    PERFORM public.set_blocker_status(_b21, 'SURVEILLANCE');
    PERFORM set_config('request.jwt.claims', '', true);
    PERFORM private.fast_forward_blocker(_b21, interval '4 days');
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager21@test.invalid"}', true);
    BEGIN
      PERFORM public.remind_blocker_teams(_b21);
      _res := _res || jsonb_build_object('t', 'US21 : après une modification puis 3 jours, une nouvelle relance est possible', 'ok',
        (SELECT count(*) FROM notifications WHERE blocker_id = _b21 AND recipient_email = 'smoke.collab@test.invalid'
          AND kind = 'relance_point_bloquant') = 2, 'd', '2 relances');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'US21 : après une modification puis 3 jours, une nouvelle relance est possible', 'ok', false, 'd', SQLERRM);
    END;

    -- Demandes : confirmation d'une demande clôturée.
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande US21') RETURNING id INTO _s21;
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    UPDATE submissions SET status = 'validée' WHERE id = _s21;
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab@test.invalid"}', true);
    BEGIN
      PERFORM public.confirm_submission_up_to_date(_s21);
      _res := _res || jsonb_build_object('t', 'US21 : une demande validée ne se confirme pas à jour', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'US21 : une demande validée ne se confirme pas à jour', 'ok', true, 'd', 'refusé par la base');
    END;
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    UPDATE submissions SET status = 'clôturée' WHERE id = _s21;
    SELECT count(*) INTO _hist21 FROM submission_status_history WHERE submission_id = _s21;
    SELECT count(*) INTO _notif21 FROM notifications WHERE submission_id = _s21;

    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager21@test.invalid"}', true);
    BEGIN
      PERFORM public.confirm_submission_up_to_date(_s21);
      _res := _res || jsonb_build_object('t', 'US21 : le manager d''une autre équipe ne confirme pas une demande', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'US21 : le manager d''une autre équipe ne confirme pas une demande', 'ok', true, 'd', 'refusé par la base');
    END;
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab@test.invalid"}', true);
    BEGIN
      PERFORM public.confirm_submission_up_to_date(_s21);
      _res := _res || jsonb_build_object('t', 'US21 : l''auteur confirme sa demande clôturée, sans changement de statut ni notification', 'ok',
        (SELECT verified_at FROM submissions WHERE id = _s21) = now()
        AND (SELECT status::text FROM submissions WHERE id = _s21) = 'clôturée'
        AND EXISTS (SELECT 1 FROM submission_verifications WHERE submission_id = _s21
                    AND verified_by_name = 'smoke.collab@test.invalid')
        AND (SELECT count(*) FROM submission_status_history WHERE submission_id = _s21) = _hist21
        AND (SELECT count(*) FROM notifications WHERE submission_id = _s21) = _notif21,
        'd', 'verified_at');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'US21 : l''auteur confirme sa demande clôturée, sans changement de statut ni notification', 'ok', false, 'd', SQLERRM);
    END;
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    BEGIN
      PERFORM public.confirm_submission_up_to_date(_s21);
      _res := _res || jsonb_build_object('t', 'US21 : le manager de l''équipe confirme une demande clôturée', 'ok',
        (SELECT count(*) FROM submission_verifications WHERE submission_id = _s21) = 2, 'd', '2 confirmations');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'US21 : le manager de l''équipe confirme une demande clôturée', 'ok', false, 'd', SQLERRM);
    END;

    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      DELETE FROM allowed_users WHERE id = _mgr21;
      _res := _res || jsonb_build_object('t', 'US21 : le départ de qui a relancé anonymise ses relances', 'ok',
        EXISTS (SELECT 1 FROM notifications WHERE blocker_id = _b21 AND recipient_email = 'smoke.collab@test.invalid'
                AND message = 'Utilisateur supprimé te relance sur le point bloquant : Blocage équipe'
                AND actor_name = 'Utilisateur supprimé' AND actor_email IS NULL)
        AND NOT EXISTS (SELECT 1 FROM notifications WHERE kind = 'relance_point_bloquant'
                        AND lower(actor_email) = 'smoke.manager21@test.invalid'),
        'd', 'Utilisateur supprimé');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'US21 : le départ de qui a relancé anonymise ses relances', 'ok', false, 'd', SQLERRM);
    END;

    -- US26 : idées de sujets masquées ou utilisées, chacun ne voit que les siennes
    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      INSERT INTO news_idea_dismissals(user_id, idea_key, reason) VALUES (_uid26a, 'demande:zz-smoke', 'masquée');
      SELECT * INTO _idea26 FROM private.smoke_idea_dismissal_as('smoke.collab@test.invalid', _uid26b, _uid26a);
      _res := _res || jsonb_build_object('t', 'US26 : un utilisateur ne lit pas les idées masquées d''un autre', 'ok',
        _idea26._visible = 0, 'd', _idea26._visible || ' ligne(s) lue(s)');
      _res := _res || jsonb_build_object('t', 'US26 : un utilisateur ne crée ni ne supprime les idées masquées d''un autre', 'ok',
        _idea26._insert_denied AND _idea26._deleted = 0
        AND EXISTS (SELECT 1 FROM news_idea_dismissals WHERE user_id = _uid26a AND idea_key = 'demande:zz-smoke'),
        'd', 'refus : ' || _idea26._insert_denied || ', supprimées : ' || _idea26._deleted);
      SELECT * INTO _idea26 FROM private.smoke_idea_dismissal_as('smoke.manager@test.invalid', _uid26a, _uid26a);
      _res := _res || jsonb_build_object('t', 'US26 : un utilisateur lit ses propres idées masquées', 'ok',
        _idea26._visible = 1, 'd', _idea26._visible || ' ligne(s) lue(s)');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'US26 : un utilisateur ne lit pas les idées masquées d''un autre', 'ok', false, 'd', SQLERRM);
    END;

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

    -- Socle d'envoi des mails (voir private.smoke_mail_tests)
    _res := _res || private.smoke_mail_tests();

    -- Résumé hebdomadaire (voir private.smoke_digest_tests)
    _res := _res || private.smoke_digest_tests();

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
