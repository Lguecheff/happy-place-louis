-- ============================================================
-- Socle d'envoi des mails
-- ============================================================
-- La base prépare chaque mail dans public.mail_outbox, dans la même transaction que
-- l'événement, puis le transmet à un webhook Make avec pg_net. L'app n'envoie aucun mail.
-- Les destinataires restent ceux des notifications : leur calcul est extrait dans
-- private.submission_event_recipients et private.blocker_reminder_recipients, partagés
-- par la notification dans l'app (si « Dans l'app ») et le mail (si « Par mail » et une adresse).
-- Webhook : secrets Vault « make_mail_webhook_url » et « make_mail_webhook_secret ».
BEGIN;

CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- ---------- Adresse publique de l'app (une seule source côté base) ----------
CREATE OR REPLACE FUNCTION private.app_base_url()
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT 'https://happy-place-louis.guecheff-louis.workers.dev'::text;
$function$;

-- ---------- Adresse de réception ----------
-- Une forme simple, sans espace ; les domaines réservés (.test, .example, .invalid, .localhost)
-- ne reçoivent pas de mail : ce sont ceux des comptes internes.
CREATE OR REPLACE FUNCTION private.is_valid_mail_address(_address text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT _address IS NOT NULL
     AND length(_address) <= 254
     AND _address ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]{2,}$';
$function$;

CREATE OR REPLACE FUNCTION private.is_internal_mail_address(_address text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT lower(_address) ~ '\.(test|example|invalid|localhost)$';
$function$;

CREATE TABLE public.notification_mail_addresses (
  recipient_email text PRIMARY KEY CHECK (recipient_email = lower(recipient_email)),
  address text NOT NULL CHECK (
    address = lower(address)
    AND private.is_valid_mail_address(address)
    AND NOT private.is_internal_mail_address(address)
  ),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- REVOKE d'abord : Supabase donne par défaut tous les droits sur une nouvelle table.
-- Lecture de sa propre ligne seulement ; l'écriture passe par public.set_my_mail_address.
REVOKE ALL ON public.notification_mail_addresses FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.notification_mail_addresses TO authenticated;
GRANT ALL ON public.notification_mail_addresses TO service_role;

ALTER TABLE public.notification_mail_addresses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users read own mail address" ON public.notification_mail_addresses
  FOR SELECT TO authenticated
  USING (private.is_allowed() AND recipient_email = lower(auth.jwt() ->> 'email'));

COMMENT ON TABLE public.notification_mail_addresses IS
  'Adresse où chaque utilisateur reçoit ses mails (l''adresse de connexion est interne). Sans ligne, aucun mail n''est préparé.';

-- Enregistre l'adresse du compte connecté ; une adresse vide la retire. Renvoie l'adresse enregistrée.
CREATE OR REPLACE FUNCTION public.set_my_mail_address(_address text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _email text := lower(nullif(auth.jwt() ->> 'email', ''));
  _a text := lower(btrim(coalesce(_address, '')));
BEGIN
  IF _email IS NULL OR NOT private.is_allowed() THEN
    RAISE EXCEPTION 'Session introuvable : recharge la page.' USING ERRCODE = '42501';
  END IF;
  IF _a = '' THEN
    DELETE FROM public.notification_mail_addresses WHERE recipient_email = _email;
    RETURN NULL;
  END IF;
  IF NOT private.is_valid_mail_address(_a) THEN
    RAISE EXCEPTION 'Cette adresse n''est pas valide. Vérifie qu''elle a la forme prenom.nom@exemple.fr.'
      USING ERRCODE = '22023';
  END IF;
  IF private.is_internal_mail_address(_a) THEN
    RAISE EXCEPTION 'Cette adresse ne reçoit pas de mail. Saisis une adresse que tu consultes.'
      USING ERRCODE = '22023';
  END IF;
  INSERT INTO public.notification_mail_addresses (recipient_email, address)
  VALUES (_email, _a)
  ON CONFLICT (recipient_email) DO UPDATE SET address = excluded.address, updated_at = now();
  RETURN _a;
END
$function$;

REVOKE ALL ON FUNCTION public.set_my_mail_address(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_my_mail_address(text) TO authenticated;

CREATE OR REPLACE FUNCTION private.mail_address_of(_email text)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
  SELECT address FROM public.notification_mail_addresses WHERE recipient_email = lower(_email);
$function$;

REVOKE ALL ON FUNCTION private.mail_address_of(text) FROM PUBLIC, anon, authenticated;

-- ---------- Table d'envoi ----------
CREATE TYPE public.mail_status AS ENUM ('en attente', 'transmis', 'ignoré');

CREATE TABLE public.mail_outbox (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind public.notification_kind NOT NULL,
  -- Adresse de connexion (interne) du destinataire.
  recipient_email text NOT NULL CHECK (recipient_email = lower(recipient_email)),
  -- Adresse de réception.
  to_address text NOT NULL,
  to_name text,
  payload jsonb NOT NULL,
  notification_id uuid REFERENCES public.notifications(id) ON DELETE SET NULL,
  status public.mail_status NOT NULL DEFAULT 'en attente',
  request_id bigint,
  created_at timestamptz NOT NULL DEFAULT now(),
  posted_at timestamptz
);
CREATE INDEX mail_outbox_status_created_idx ON public.mail_outbox (status, created_at);
CREATE INDEX mail_outbox_recipient_idx ON public.mail_outbox (recipient_email);

-- Aucun droit côté app : service_role seulement, et aucune politique.
REVOKE ALL ON public.mail_outbox FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.mail_outbox TO service_role;
ALTER TABLE public.mail_outbox ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.mail_outbox IS
  'Mails préparés par la base, une ligne par destinataire et par événement, transmis à Make (pg_net). Aucun texte : seulement des données.';

-- ---------- Préparation d'un mail ----------
CREATE OR REPLACE FUNCTION private.text_excerpt(_content text, _max integer)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public', 'private'
AS $function$
  SELECT CASE WHEN length(c.text) > _max THEN rtrim(left(c.text, _max - 1), ' ,;:.') || '…' ELSE c.text END
    FROM (SELECT btrim(regexp_replace(_content, '\s+', ' ', 'g')) AS text) c;
$function$;

CREATE OR REPLACE FUNCTION private.display_name_of(_email text)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
  SELECT nullif(btrim(concat_ws(' ', u.first_name, u.last_name)), '')
    FROM public.allowed_users u WHERE lower(u.email) = lower(_email);
$function$;

REVOKE ALL ON FUNCTION private.display_name_of(text) FROM PUBLIC, anon, authenticated;

-- Crée la ligne d'envoi si la personne veut ce type par mail et a une adresse.
-- Ne lève jamais d'erreur : l'action de l'utilisateur doit réussir quoi qu'il arrive.
CREATE OR REPLACE FUNCTION private.queue_mail(
  _recipient text,
  _kind public.notification_kind,
  _payload jsonb,
  _notification_id uuid,
  _app_path text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _to text;
  _name text;
BEGIN
  IF NOT private.wants_by_email(_recipient, _kind) THEN
    RETURN false;
  END IF;
  _to := private.mail_address_of(_recipient);
  IF _to IS NULL THEN
    RETURN false;
  END IF;
  _name := COALESCE(private.display_name_of(_recipient), split_part(_to, '@', 1));
  INSERT INTO public.mail_outbox (kind, recipient_email, to_address, to_name, payload, notification_id)
  VALUES (
    _kind, lower(_recipient), _to, _name,
    COALESCE(_payload, '{}'::jsonb) || jsonb_build_object(
      'kind', _kind,
      'to_name', _name,
      'app_url', private.app_base_url() || _app_path,
      'preferences_url', private.app_base_url() || '/?preferences',
      'created_at', now()
    ),
    _notification_id
  );
  RETURN true;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'Mail non préparé pour % (%) : %', _recipient, _kind, SQLERRM;
  RETURN false;
END
$function$;

REVOKE ALL ON FUNCTION private.queue_mail(text, public.notification_kind, jsonb, uuid, text) FROM PUBLIC, anon, authenticated;

-- Données d'une demande communes aux trois types ; les compteurs seulement pour nouvelle_demande.
CREATE OR REPLACE FUNCTION private.submission_mail_payload(_s public.submissions, _with_pending boolean)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
  SELECT jsonb_build_object(
           'submission_id', _s.id,
           'author_name', _s.author_name,
           'team', _s.team,
           'excerpt', private.submission_excerpt(_s.content),
           'excerpt_long', private.text_excerpt(_s.content, 200),
           'submission_created_at', _s.created_at,
           'attachment_name', _s.attachment_name,
           'status', _s.status)
      || CASE WHEN _with_pending THEN (
           SELECT jsonb_build_object(
                    'pending_count', count(*),
                    'pending_over_7_days', count(*) FILTER (WHERE p.since < now() - interval '7 days'))
             FROM (SELECT COALESCE((SELECT max(h.changed_at) FROM public.submission_status_history h
                                     WHERE h.submission_id = x.id), x.created_at) AS since
                     FROM public.submissions x
                    WHERE x.team = _s.team AND x.status = 'en attente'::public.submission_status) p)
         ELSE '{}'::jsonb END;
$function$;

REVOKE ALL ON FUNCTION private.submission_mail_payload(public.submissions, boolean) FROM PUBLIC, anon, authenticated;

-- ---------- Destinataires d'un événement de demande (règles inchangées) ----------
-- nouvelle_demande : managers de l'équipe, sauf l'auteur.
-- changement d'état : abonnés qui peuvent encore lire la demande, sauf qui a fait le changement
-- et sauf les admins ; l'auteur reçoit changement_statut, les autres changement_statut_suivi.
CREATE OR REPLACE FUNCTION private.submission_event_recipients(_h public.submission_status_history)
RETURNS TABLE(email text, kind public.notification_kind, follow_source text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
  SELECT lower(u.email), 'nouvelle_demande'::public.notification_kind, NULL::text
    FROM public.submissions s
    JOIN public.manager_teams mt ON mt.team = s.team
    JOIN public.allowed_users u ON u.id = mt.allowed_user_id
    JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id
   WHERE _h.old_status IS NULL
     AND s.id = _h.submission_id
     AND r.role = 'manager'::public.app_role
     AND lower(u.email) IS DISTINCT FROM lower(s.submitted_by_email)
  UNION ALL
  SELECT f.follower_email,
         CASE WHEN f.source = 'auteur' THEN 'changement_statut'::public.notification_kind
              ELSE 'changement_statut_suivi'::public.notification_kind END,
         f.source::text
    FROM public.submissions s
    JOIN public.submission_followers f ON f.submission_id = s.id
    JOIN public.allowed_users u ON lower(u.email) = f.follower_email
    JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id
   WHERE _h.old_status IS NOT NULL
     AND _h.new_status IS DISTINCT FROM _h.old_status
     AND s.id = _h.submission_id
     AND r.role <> 'admin'::public.app_role
     AND f.follower_email IS DISTINCT FROM lower(_h.changed_by_email)
     AND private.can_read_submission(f.follower_email, s.id);
$function$;

REVOKE ALL ON FUNCTION private.submission_event_recipients(public.submission_status_history) FROM PUBLIC, anon, authenticated;

-- Notification dans l'app : comme avant (« Dans l'app », toujours pour l'auteur sur changement_statut).
-- Mail : « Par mail » et une adresse, sauf clôture automatique.
CREATE OR REPLACE FUNCTION private.notify_submission_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _s public.submissions%ROWTYPE;
  _what text;
  _actor text;
  _payload jsonb;
  _r record;
  _notif uuid;
BEGIN
  IF NEW.old_status IS NOT NULL AND NEW.new_status IS NOT DISTINCT FROM NEW.old_status THEN
    RETURN NEW;
  END IF;
  SELECT * INTO _s FROM public.submissions WHERE id = NEW.submission_id;
  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  IF NEW.old_status IS NULL THEN
    _payload := private.submission_mail_payload(_s, true);
  ELSE
    _what := CASE NEW.new_status
      WHEN 'validée'::public.submission_status THEN 'a été validée'
      WHEN 'refusée'::public.submission_status
        THEN 'a été refusée' || COALESCE(' (' || NEW.rejection_category::text || ')', '')
      WHEN 'clôturée'::public.submission_status THEN 'a été clôturée'
      ELSE 'est repassée en attente'
    END;
    _actor := CASE WHEN NEW.is_automatic THEN 'Automatique'
                   ELSE COALESCE(NEW.changed_by_name, NEW.changed_by_email) END;
    _payload := private.submission_mail_payload(_s, false) || jsonb_build_object(
      'old_status', NEW.old_status,
      'new_status', NEW.new_status,
      'actor_name', _actor,
      'rejection_category', NEW.rejection_category,
      'rejection_note', NEW.rejection_note);
  END IF;

  FOR _r IN SELECT * FROM private.submission_event_recipients(NEW) LOOP
    _notif := NULL;
    IF NEW.old_status IS NULL THEN
      IF private.wants_in_app(_r.email, _r.kind) THEN
        INSERT INTO public.notifications (recipient_email, kind, submission_id, message)
        VALUES (_r.email, _r.kind, _s.id, format('Nouvelle demande de %s (%s)', _s.author_name, _s.team))
        RETURNING id INTO _notif;
      END IF;
    ELSIF _r.follow_source = 'auteur' OR private.wants_in_app(_r.email, _r.kind) THEN
      INSERT INTO public.notifications (recipient_email, kind, submission_id, message, actor_name)
      VALUES (
        _r.email, _r.kind, _s.id,
        format('%s %s : « %s »',
               CASE WHEN _r.follow_source = 'auteur' THEN 'Ta demande' ELSE 'La demande de ' || _s.author_name END,
               _what, private.submission_excerpt(_s.content)),
        _actor)
      RETURNING id INTO _notif;
    END IF;

    IF NOT NEW.is_automatic THEN
      PERFORM private.queue_mail(
        _r.email, _r.kind,
        _payload || CASE WHEN _r.follow_source IS NULL THEN '{}'::jsonb
                         ELSE jsonb_build_object('follow_source', _r.follow_source) END,
        _notif,
        '/?demande=' || _s.id);
    END IF;
  END LOOP;
  RETURN NEW;
END
$function$;

-- ---------- Destinataires d'une relance (règles inchangées) ----------
-- Point d'équipes : managers et collaborateurs de ces équipes. Toutes les équipes : tous les managers.
-- Jamais l'auteur de la relance.
CREATE OR REPLACE FUNCTION private.blocker_reminder_recipients(_blocker_id uuid, _actor_email text)
RETURNS SETOF text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
  WITH scope AS (
    SELECT NOT EXISTS (SELECT 1 FROM public.blocker_teams WHERE blocker_id = _blocker_id) AS all_teams
  )
  SELECT r.email FROM (
    SELECT lower(u.email) AS email
      FROM public.allowed_users u
      JOIN public.allowed_user_roles ur ON ur.allowed_user_id = u.id, scope
     WHERE ur.role = 'manager'::public.app_role
       AND (scope.all_teams OR EXISTS (SELECT 1
                                         FROM public.manager_teams mt
                                         JOIN public.blocker_teams bt ON lower(bt.team) = lower(mt.team)
                                        WHERE mt.allowed_user_id = u.id AND bt.blocker_id = _blocker_id))
    UNION
    SELECT lower(u.email)
      FROM public.allowed_users u
      JOIN public.allowed_user_roles ur ON ur.allowed_user_id = u.id, scope
     WHERE ur.role = 'collaborateur'::public.app_role
       AND NOT scope.all_teams
       AND EXISTS (SELECT 1 FROM public.blocker_teams bt
                    WHERE bt.blocker_id = _blocker_id AND lower(bt.team) = lower(u.team))
  ) r
  WHERE r.email IS DISTINCT FROM lower(_actor_email);
$function$;

REVOKE ALL ON FUNCTION private.blocker_reminder_recipients(uuid, text) FROM PUBLIC, anon, authenticated;

-- Renvoie toujours le nombre de notifications créées dans l'app.
CREATE OR REPLACE FUNCTION public.remind_blocker_teams(_blocker_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _role public.app_role := private.current_app_role();
  _email text := lower(nullif(auth.jwt() ->> 'email', ''));
  _name text := private.current_actor_name();
  _b public.blockers%ROWTYPE;
  _count integer := 0;
  _recipient text;
  _notif uuid;
  _payload jsonb;
BEGIN
  IF NOT (_role = 'admin'::public.app_role
          OR (_role = 'manager'::public.app_role AND NOT private.concerns_blocker(_blocker_id))) THEN
    RAISE EXCEPTION 'Tu ne peux pas relancer les équipes de ce point bloquant.';
  END IF;
  SELECT * INTO _b FROM public.blockers WHERE id = _blocker_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ce point bloquant n''existe plus.';
  END IF;
  IF _b.status = 'RÉSOLU'::public.blocker_status THEN
    RAISE EXCEPTION 'Ce point bloquant est résolu.';
  END IF;
  IF _b.updated_at >= now() - interval '3 days' THEN
    RAISE EXCEPTION 'Ce point bloquant a été mis à jour il y a moins de 3 jours.';
  END IF;
  IF _b.reminded_at IS NOT NULL AND _b.reminded_at >= _b.updated_at THEN
    RAISE EXCEPTION 'Les équipes ont déjà été relancées depuis la dernière mise à jour du point.';
  END IF;

  _payload := jsonb_build_object(
    'blocker_id', _b.id,
    'title', _b.title,
    'description', _b.description,
    'impact', _b.impact,
    'severity', _b.severity,
    'status', _b.status,
    'teams', COALESCE((SELECT string_agg(bt.team, ', ' ORDER BY bt.team)
                         FROM public.blocker_teams bt WHERE bt.blocker_id = _b.id), 'Toutes les équipes'),
    'updated_at', _b.updated_at,
    'updated_by_name', _b.updated_by_name,
    'days_without_update', floor(extract(epoch FROM now() - _b.updated_at) / 86400)::integer,
    'reminded_by_name', _name,
    'reminded_by_address', private.mail_address_of(_email));

  FOR _recipient IN SELECT x FROM private.blocker_reminder_recipients(_blocker_id, _email) x LOOP
    _notif := NULL;
    IF private.wants_in_app(_recipient, 'relance_point_bloquant'::public.notification_kind) THEN
      INSERT INTO public.notifications (recipient_email, kind, blocker_id, message, actor_name, actor_email)
      VALUES (_recipient, 'relance_point_bloquant'::public.notification_kind, _b.id,
              format('%s te relance sur le point bloquant : %s', _name, _b.title), _name, _email)
      RETURNING id INTO _notif;
      _count := _count + 1;
    END IF;
    PERFORM private.queue_mail(_recipient, 'relance_point_bloquant'::public.notification_kind,
                               _payload, _notif, '/?point=' || _b.id);
  END LOOP;

  PERFORM set_config('happy_place.keep_last_update', 'on', true);
  UPDATE public.blockers SET reminded_at = now(), reminded_by_name = _name WHERE id = _blocker_id;
  PERFORM set_config('happy_place.keep_last_update', '', true);
  RETURN _count;
END
$function$;

REVOKE ALL ON FUNCTION public.remind_blocker_teams(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.remind_blocker_teams(uuid) TO authenticated;

-- ---------- Transmission à Make ----------
-- Adresse et secret du webhook, lus dans Vault. « happy_place.mail_webhook_mode » sert aux tests :
-- « off » fait comme sans secret, « test » donne une adresse factice (jamais appelée : tout est annulé).
CREATE OR REPLACE FUNCTION private.mail_webhook(OUT url text, OUT secret text)
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
  SELECT decrypted_secret INTO url FROM vault.decrypted_secrets WHERE name = 'make_mail_webhook_url' LIMIT 1;
  SELECT decrypted_secret INTO secret FROM vault.decrypted_secrets WHERE name = 'make_mail_webhook_secret' LIMIT 1;
END
$function$;

REVOKE ALL ON FUNCTION private.mail_webhook() FROM PUBLIC, anon, authenticated;

-- Transmet une ligne « en attente ». Sans secret ou en cas d'échec, la ligne reste « en attente »,
-- sans erreur. pg_net n'envoie la requête qu'après la validation de la transaction.
CREATE OR REPLACE FUNCTION private.transmit_mail(_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _m public.mail_outbox%ROWTYPE;
  _hook record;
  _request bigint;
BEGIN
  SELECT * INTO _m FROM public.mail_outbox WHERE id = _id AND status = 'en attente' FOR UPDATE SKIP LOCKED;
  IF NOT FOUND THEN
    RETURN false;
  END IF;
  SELECT * INTO _hook FROM private.mail_webhook();
  IF nullif(_hook.url, '') IS NULL OR nullif(_hook.secret, '') IS NULL THEN
    RETURN false;
  END IF;
  _request := net.http_post(
    url := _hook.url,
    body := _m.payload || jsonb_build_object('id', _m.id, 'kind', _m.kind, 'to_address', _m.to_address),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-happy-place-secret', _hook.secret),
    timeout_milliseconds := 5000
  );
  UPDATE public.mail_outbox SET status = 'transmis', posted_at = now(), request_id = _request WHERE id = _id;
  RETURN true;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'Mail % non transmis : %', _id, SQLERRM;
  RETURN false;
END
$function$;

REVOKE ALL ON FUNCTION private.transmit_mail(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION private.transmit_new_mail()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  PERFORM private.transmit_mail(NEW.id);
  RETURN NULL;
END
$function$;

REVOKE ALL ON FUNCTION private.transmit_new_mail() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER transmit_new_mail
  AFTER INSERT ON public.mail_outbox
  FOR EACH ROW EXECUTE FUNCTION private.transmit_new_mail();

-- À lancer à la main : renvoie les lignes « en attente » de moins de 24 heures.
-- Renvoie le nombre de lignes transmises.
CREATE OR REPLACE FUNCTION private.retransmit_pending_mails()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _id uuid;
  _sent integer := 0;
BEGIN
  FOR _id IN SELECT id FROM public.mail_outbox
              WHERE status = 'en attente' AND created_at > now() - interval '24 hours'
              ORDER BY created_at LOOP
    IF private.transmit_mail(_id) THEN
      _sent := _sent + 1;
    END IF;
  END LOOP;
  RETURN _sent;
END
$function$;

REVOKE ALL ON FUNCTION private.retransmit_pending_mails() FROM PUBLIC, anon, authenticated;

-- ---------- Départ d'un utilisateur ----------
-- Ses mails en attente passent à « ignoré » et son adresse de réception est effacée.
CREATE OR REPLACE FUNCTION private.forget_mail_recipient()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  UPDATE public.mail_outbox SET status = 'ignoré'
   WHERE recipient_email = lower(OLD.email) AND status = 'en attente';
  DELETE FROM public.notification_mail_addresses WHERE recipient_email = lower(OLD.email);
  RETURN OLD;
END
$function$;

REVOKE ALL ON FUNCTION private.forget_mail_recipient() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER forget_mail_recipient
  AFTER DELETE ON public.allowed_users
  FOR EACH ROW EXECUTE FUNCTION private.forget_mail_recipient();

-- ---------- Tests de fumée ----------
-- Lit mail_outbox et les adresses sous le rôle authenticated, donc sous RLS, puis tente d'écrire
-- l'adresse de _target.
CREATE OR REPLACE FUNCTION private.smoke_mail_as(
  _email text,
  _target text,
  OUT _outbox_denied boolean,
  OUT _own int,
  OUT _other int,
  OUT _write_denied boolean
)
LANGUAGE plpgsql
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('email', _email)::text, true);
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM count(*) FROM public.mail_outbox;
    _outbox_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN
    _outbox_denied := true;
  END;
  SELECT count(*) INTO _own FROM public.notification_mail_addresses WHERE recipient_email = lower(_email);
  SELECT count(*) INTO _other FROM public.notification_mail_addresses WHERE recipient_email = lower(_target);
  BEGIN
    INSERT INTO public.notification_mail_addresses (recipient_email, address)
    VALUES (lower(_target), 'pirate@exemple.fr')
    ON CONFLICT (recipient_email) DO UPDATE SET address = excluded.address;
    _write_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN
    _write_denied := true;
  END;
  RESET ROLE;
END
$function$;

REVOKE ALL ON FUNCTION private.smoke_mail_as(text, text) FROM PUBLIC, anon, authenticated;

-- Tests du socle d'envoi, appelés par private.run_smoke_tests() avant son annulation finale :
-- rien n'est gardé, et aucune requête pg_net n'est envoyée (elle est annulée avec le reste).
CREATE OR REPLACE FUNCTION private.smoke_mail_tests()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _res jsonb := '[]'::jsonb;
  _team text := 'ZZ Test mails';
  _other text := 'ZZ Test mails autre';
  _m1 uuid; _m2 uuid; _m3 uuid; _m4 uuid; _m5 uuid; _c1 uuid; _c2 uuid; _adm uuid;
  _s1 uuid; _s2 uuid; _s3 uuid; _b uuid;
  _emails text[]; _row record; _cnt int; _cnt2 int; _try record; _addr text;
  M1 constant text := 'smoke.mail.m1@test.invalid';
  M2 constant text := 'smoke.mail.m2@test.invalid';
  M3 constant text := 'smoke.mail.m3@test.invalid';
  M4 constant text := 'smoke.mail.m4@test.invalid';
  M5 constant text := 'smoke.mail.m5@test.invalid';
  C1 constant text := 'smoke.mail.c1@test.invalid';
  C2 constant text := 'smoke.mail.c2@test.invalid';
  ADM constant text := 'smoke.mail.admin@test.invalid';
BEGIN
  PERFORM set_config('happy_place.mail_webhook_mode', 'off', true);
  PERFORM set_config('request.jwt.claims', '', true);

  -- Équipe : 4 managers (m4 sans adresse), 2 collaborateurs, un admin rattaché à l'équipe ;
  -- m5 manage une autre équipe.
  INSERT INTO teams(name) VALUES (_team), (_other) ON CONFLICT DO NOTHING;
  INSERT INTO allowed_users(email, first_name, last_name) VALUES (M1, 'Kesha', 'Test') RETURNING id INTO _m1;
  INSERT INTO allowed_users(email, first_name, last_name) VALUES (M2, 'Manager', 'Deux') RETURNING id INTO _m2;
  INSERT INTO allowed_users(email, first_name, last_name) VALUES (M3, 'Manager', 'Trois') RETURNING id INTO _m3;
  INSERT INTO allowed_users(email, first_name, last_name) VALUES (M4, 'Manager', 'Quatre') RETURNING id INTO _m4;
  INSERT INTO allowed_users(email, first_name, last_name) VALUES (M5, 'Manager', 'Cinq') RETURNING id INTO _m5;
  INSERT INTO allowed_users(email, team, first_name, last_name) VALUES (C1, _team, 'Gontran', 'Test') RETURNING id INTO _c1;
  INSERT INTO allowed_users(email, team, first_name, last_name) VALUES (C2, _team, 'Collab', 'Deux') RETURNING id INTO _c2;
  INSERT INTO allowed_users(email, first_name, last_name) VALUES (ADM, 'Admin', 'Test') RETURNING id INTO _adm;
  INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES
    (_m1, 'manager'), (_m2, 'manager'), (_m3, 'manager'), (_m4, 'manager'), (_m5, 'manager'),
    (_c1, 'collaborateur'), (_c2, 'collaborateur'), (_adm, 'admin');
  INSERT INTO manager_teams(allowed_user_id, team) VALUES
    (_m1, _team), (_m2, _team), (_m3, _team), (_m4, _team), (_m5, _other), (_adm, _team);
  INSERT INTO notification_mail_addresses(recipient_email, address) VALUES
    (M1, 'm1@exemple.fr'), (M2, 'm2@exemple.fr'), (M3, 'm3@exemple.fr'), (M5, 'm5@exemple.fr'),
    (C1, 'c1@exemple.fr'), (C2, 'c2@exemple.fr'), (ADM, 'admin@exemple.fr');
  -- m2 : « Par mail » décoché ; m3 : « Dans l'app » décoché, « Par mail » coché.
  INSERT INTO notification_preferences(recipient_email, kind, in_app, by_email) VALUES
    (M2, 'nouvelle_demande', true, false), (M3, 'nouvelle_demande', false, true);

  -- Nouvelle demande
  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('email', C1)::text, true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Gontran Test', 'x', 'Demande pour les mails 1') RETURNING id INTO _s1;
    PERFORM set_config('request.jwt.claims', '', true);
    SELECT COALESCE(array_agg(recipient_email ORDER BY recipient_email), '{}') INTO _emails
      FROM mail_outbox WHERE kind = 'nouvelle_demande' AND payload->>'submission_id' = _s1::text;
    _res := _res || jsonb_build_object('t', 'Mails : une demande créée en prépare un pour chaque manager de l''équipe avec adresse et « Par mail », aucun pour l''auteur', 'ok',
      _emails @> ARRAY[M1] AND NOT _emails && ARRAY[C1, ADM], 'd', array_to_string(_emails, ', '));
    _res := _res || jsonb_build_object('t', 'Mails : « Par mail » décoché n''en prépare aucun', 'ok',
      NOT _emails && ARRAY[M2], 'd', array_to_string(_emails, ', '));
    _res := _res || jsonb_build_object('t', 'Mails : « Dans l''app » décoché et « Par mail » coché en prépare un, sans notification', 'ok',
      _emails @> ARRAY[M3]
      AND NOT EXISTS (SELECT 1 FROM notifications WHERE submission_id = _s1 AND recipient_email = M3)
      AND (SELECT notification_id FROM mail_outbox WHERE recipient_email = M3 AND payload->>'submission_id' = _s1::text) IS NULL,
      'd', array_to_string(_emails, ', '));
    _res := _res || jsonb_build_object('t', 'Mails : sans adresse, aucun mail (la notification reste)', 'ok',
      NOT _emails && ARRAY[M4]
      AND EXISTS (SELECT 1 FROM notifications WHERE submission_id = _s1 AND recipient_email = M4),
      'd', array_to_string(_emails, ', '));
    _res := _res || jsonb_build_object('t', 'Mails : sans secret Vault, la ligne reste « en attente » et la demande est créée', 'ok',
      EXISTS (SELECT 1 FROM submissions WHERE id = _s1)
      AND NOT EXISTS (SELECT 1 FROM mail_outbox WHERE payload->>'submission_id' = _s1::text
                      AND (status <> 'en attente' OR posted_at IS NOT NULL OR request_id IS NOT NULL)),
      'd', 'en attente');
    SELECT * INTO _row FROM mail_outbox WHERE recipient_email = M1 AND payload->>'submission_id' = _s1::text;
    _res := _res || jsonb_build_object('t', 'Mails : le contenu préparé porte le lien profond, l''adresse de réception et les compteurs', 'ok',
      _row.to_address = 'm1@exemple.fr' AND _row.to_name = 'Kesha Test'
      AND _row.payload->>'app_url' = private.app_base_url() || '/?demande=' || _s1
      AND _row.payload->>'preferences_url' = private.app_base_url() || '/?preferences'
      AND _row.payload->>'author_name' = 'Gontran Test' AND _row.payload->>'team' = _team
      AND _row.payload->>'excerpt' = 'Demande pour les mails 1'
      AND _row.payload ? 'excerpt_long' AND _row.payload ? 'created_at'
      AND (_row.payload->>'pending_count')::int >= 1 AND (_row.payload->>'pending_over_7_days')::int = 0
      AND _row.notification_id = (SELECT id FROM notifications WHERE submission_id = _s1 AND recipient_email = M1),
      'd', COALESCE(_row.payload::text, 'aucune ligne'));
  EXCEPTION WHEN OTHERS THEN
    _res := _res || jsonb_build_object('t', 'Mails : une demande créée en prépare un pour chaque manager de l''équipe avec adresse et « Par mail », aucun pour l''auteur', 'ok', false, 'd', SQLERRM);
  END;

  -- Changements d'état : les managers de l'équipe suivent la demande depuis sa création.
  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('email', M1)::text, true);
    UPDATE submissions SET status = 'validée' WHERE id = _s1;
    PERFORM set_config('request.jwt.claims', '', true);
    SELECT COALESCE(array_agg(recipient_email ORDER BY recipient_email), '{}') INTO _emails
      FROM mail_outbox WHERE payload->>'submission_id' = _s1::text AND payload->>'new_status' = 'validée'
       AND payload->>'old_status' = 'en attente';
    _res := _res || jsonb_build_object('t', 'Mails : un changement d''état en prépare un pour l''auteur et chaque abonné, pas pour qui l''a fait', 'ok',
      _emails = ARRAY[C1, M2, M3], 'd', array_to_string(_emails, ', '));
    _res := _res || jsonb_build_object('t', 'Mails : l''auteur reçoit changement_statut, un abonné changement_statut_suivi', 'ok',
      EXISTS (SELECT 1 FROM mail_outbox WHERE recipient_email = C1 AND kind = 'changement_statut'
              AND payload->>'submission_id' = _s1::text AND payload->>'follow_source' = 'auteur'
              AND payload->>'actor_name' IS NOT NULL)
      AND EXISTS (SELECT 1 FROM mail_outbox WHERE recipient_email = M2 AND kind = 'changement_statut_suivi'
              AND payload->>'submission_id' = _s1::text AND payload->>'follow_source' = 'manager'),
      'd', 'auteur / manager');

    INSERT INTO submission_followers(submission_id, follower_email, source)
    VALUES (_s1, C2, 'volontaire'), (_s1, ADM, 'volontaire') ON CONFLICT DO NOTHING;
    PERFORM set_config('request.jwt.claims', json_build_object('email', M2)::text, true);
    UPDATE submissions SET status = 'clôturée' WHERE id = _s1;
    PERFORM set_config('request.jwt.claims', '', true);
    SELECT COALESCE(array_agg(recipient_email ORDER BY recipient_email), '{}') INTO _emails
      FROM mail_outbox WHERE payload->>'submission_id' = _s1::text AND payload->>'new_status' = 'clôturée';
    _res := _res || jsonb_build_object('t', 'Mails : un abonné qui ne peut plus lire la demande ne reçoit rien, un admin jamais', 'ok',
      _emails = ARRAY[C1, M1, M3], 'd', array_to_string(_emails, ', '));

    PERFORM set_config('request.jwt.claims', json_build_object('email', M1)::text, true);
    UPDATE submissions SET status = 'validée' WHERE id = _s1;
    PERFORM set_config('request.jwt.claims', '', true);
    SELECT COALESCE(array_agg(recipient_email ORDER BY recipient_email), '{}') INTO _emails
      FROM mail_outbox WHERE payload->>'submission_id' = _s1::text AND payload->>'new_status' = 'validée'
       AND payload->>'old_status' = 'clôturée';
    _res := _res || jsonb_build_object('t', 'Mails : un abonné volontaire en reçoit un, jamais un admin abonné', 'ok',
      _emails = ARRAY[C1, C2, M2, M3], 'd', array_to_string(_emails, ', '));
  EXCEPTION WHEN OTHERS THEN
    _res := _res || jsonb_build_object('t', 'Mails : un changement d''état en prépare un pour l''auteur et chaque abonné, pas pour qui l''a fait', 'ok', false, 'd', SQLERRM);
  END;

  -- Clôture automatique : la notification reste, aucun mail.
  BEGIN
    SELECT count(*) INTO _cnt FROM mail_outbox WHERE payload->>'submission_id' = _s1::text;
    SELECT count(*) INTO _cnt2 FROM notifications WHERE submission_id = _s1;
    UPDATE submissions SET revalidate_at = now() - interval '1 day' WHERE id = _s1;
    PERFORM private.expire_revalidations();
    _res := _res || jsonb_build_object('t', 'Mails : une clôture automatique n''en prépare aucun, la notification reste', 'ok',
      (SELECT status::text FROM submissions WHERE id = _s1) = 'clôturée'
      AND (SELECT count(*) FROM mail_outbox WHERE payload->>'submission_id' = _s1::text) = _cnt
      AND (SELECT count(*) FROM notifications WHERE submission_id = _s1) > _cnt2,
      'd', (SELECT count(*) FROM mail_outbox WHERE payload->>'submission_id' = _s1::text) - _cnt || ' mail(s) ajouté(s)');
  EXCEPTION WHEN OTHERS THEN
    _res := _res || jsonb_build_object('t', 'Mails : une clôture automatique n''en prépare aucun, la notification reste', 'ok', false, 'd', SQLERRM);
  END;

  -- Transmission : avec un webhook (factice), la ligne passe « transmis » ; renvoi à la main.
  BEGIN
    PERFORM set_config('happy_place.mail_webhook_mode', 'test', true);
    PERFORM set_config('request.jwt.claims', json_build_object('email', C1)::text, true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Gontran Test', 'x', 'Demande pour les mails 2') RETURNING id INTO _s2;
    PERFORM set_config('request.jwt.claims', '', true);
    SELECT * INTO _row FROM mail_outbox WHERE recipient_email = M1 AND payload->>'submission_id' = _s2::text;
    _res := _res || jsonb_build_object('t', 'Mails : avec un webhook, la ligne passe « transmis » avec posted_at et request_id', 'ok',
      _row.status = 'transmis' AND _row.posted_at IS NOT NULL AND _row.request_id IS NOT NULL,
      'd', COALESCE(_row.status::text, 'aucune ligne') || ' / ' || COALESCE(_row.request_id::text, 'sans request_id'));

    PERFORM set_config('happy_place.mail_webhook_mode', 'off', true);
    PERFORM set_config('request.jwt.claims', json_build_object('email', C1)::text, true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Gontran Test', 'x', 'Demande pour les mails 3') RETURNING id INTO _s3;
    PERFORM set_config('request.jwt.claims', '', true);
    PERFORM set_config('happy_place.mail_webhook_mode', 'test', true);
    _cnt := private.retransmit_pending_mails();
    _res := _res || jsonb_build_object('t', 'Mails : private.retransmit_pending_mails renvoie les lignes en attente', 'ok',
      _cnt >= 2 AND NOT EXISTS (SELECT 1 FROM mail_outbox WHERE payload->>'submission_id' = _s3::text AND status <> 'transmis'),
      'd', _cnt || ' ligne(s) transmise(s)');
    PERFORM set_config('happy_place.mail_webhook_mode', 'off', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('happy_place.mail_webhook_mode', 'off', true);
    _res := _res || jsonb_build_object('t', 'Mails : avec un webhook, la ligne passe « transmis » avec posted_at et request_id', 'ok', false, 'd', SQLERRM);
  END;

  -- Relance d'un point bloquant de l'équipe, par le manager d'une autre équipe.
  BEGIN
    INSERT INTO blockers(title, department, description) VALUES ('Blocage mails', 'Test', 'Point de test')
      RETURNING id INTO _b;
    INSERT INTO blocker_teams(blocker_id, team) VALUES (_b, _team);
    PERFORM private.fast_forward_blocker(_b, interval '4 days');
    PERFORM set_config('request.jwt.claims', json_build_object('email', M5)::text, true);
    _cnt := public.remind_blocker_teams(_b);
    PERFORM set_config('request.jwt.claims', '', true);
    SELECT COALESCE(array_agg(recipient_email ORDER BY recipient_email), '{}') INTO _emails
      FROM mail_outbox WHERE kind = 'relance_point_bloquant' AND payload->>'blocker_id' = _b::text;
    _res := _res || jsonb_build_object('t', 'Mails : une relance en prépare un par destinataire avec adresse, jamais pour son auteur', 'ok',
      _emails = ARRAY[C1, C2, M1, M2, M3], 'd', array_to_string(_emails, ', '));
    SELECT * INTO _row FROM mail_outbox WHERE recipient_email = C1 AND payload->>'blocker_id' = _b::text;
    _res := _res || jsonb_build_object('t', 'Mails : la relance porte le point, ses équipes et l''adresse de qui relance', 'ok',
      _row.payload->>'app_url' = private.app_base_url() || '/?point=' || _b
      AND _row.payload->>'teams' = _team AND _row.payload->>'title' = 'Blocage mails'
      AND _row.payload->>'reminded_by_address' = 'm5@exemple.fr'
      AND _row.payload->>'reminded_by_name' IS NOT NULL
      AND (_row.payload->>'days_without_update')::int >= 4
      AND _cnt = (SELECT count(*) FROM notifications WHERE blocker_id = _b),
      'd', COALESCE(_row.payload::text, 'aucune ligne'));
  EXCEPTION WHEN OTHERS THEN
    _res := _res || jsonb_build_object('t', 'Mails : une relance en prépare un par destinataire avec adresse, jamais pour son auteur', 'ok', false, 'd', SQLERRM);
  END;

  -- Droits : sous RLS, ni mail_outbox ni l'adresse d'un autre.
  BEGIN
    SELECT * INTO _try FROM private.smoke_mail_as(C2, C1);
    _res := _res || jsonb_build_object('t', 'Mails : un utilisateur connecté ne lit ni mail_outbox ni l''adresse d''un autre', 'ok',
      _try._outbox_denied AND _try._own = 1 AND _try._other = 0 AND _try._write_denied
      AND (SELECT address FROM notification_mail_addresses WHERE recipient_email = C1) = 'c1@exemple.fr',
      'd', 'outbox refusée : ' || _try._outbox_denied || ', la sienne : ' || _try._own
           || ', celle d''un autre : ' || _try._other || ', écriture refusée : ' || _try._write_denied);
  EXCEPTION WHEN OTHERS THEN
    _res := _res || jsonb_build_object('t', 'Mails : un utilisateur connecté ne lit ni mail_outbox ni l''adresse d''un autre', 'ok', false, 'd', SQLERRM);
  END;

  -- Saisie de l'adresse : format vérifié par la base, adresse vide retirée.
  PERFORM set_config('request.jwt.claims', json_build_object('email', M4)::text, true);
  BEGIN
    PERFORM public.set_my_mail_address('kesha@exemple');
    _res := _res || jsonb_build_object('t', 'Mails : une adresse mal formée est refusée', 'ok', false, 'd', 'acceptée à tort');
  EXCEPTION WHEN invalid_parameter_value THEN
    _res := _res || jsonb_build_object('t', 'Mails : une adresse mal formée est refusée', 'ok', true, 'd', SQLERRM);
  END;
  BEGIN
    PERFORM public.set_my_mail_address('eleve-abc@happyplace.test');
    _res := _res || jsonb_build_object('t', 'Mails : une adresse interne est refusée', 'ok', false, 'd', 'acceptée à tort');
  EXCEPTION WHEN invalid_parameter_value THEN
    _res := _res || jsonb_build_object('t', 'Mails : une adresse interne est refusée', 'ok', true, 'd', SQLERRM);
  END;
  BEGIN
    _addr := public.set_my_mail_address('  M4@Exemple.FR ');
    _cnt := (SELECT count(*) FROM notification_mail_addresses WHERE recipient_email = M4 AND address = 'm4@exemple.fr');
    PERFORM public.set_my_mail_address('');
    _res := _res || jsonb_build_object('t', 'Mails : une adresse valide est enregistrée en minuscules, une adresse vide la retire', 'ok',
      _addr = 'm4@exemple.fr' AND _cnt = 1
      AND NOT EXISTS (SELECT 1 FROM notification_mail_addresses WHERE recipient_email = M4),
      'd', COALESCE(_addr, 'vide'));
  EXCEPTION WHEN OTHERS THEN
    _res := _res || jsonb_build_object('t', 'Mails : une adresse valide est enregistrée en minuscules, une adresse vide la retire', 'ok', false, 'd', SQLERRM);
  END;
  PERFORM set_config('request.jwt.claims', '', true);

  -- Départ : mails en attente ignorés, adresse effacée.
  BEGIN
    PERFORM private.queue_mail(C2, 'relance_point_bloquant', '{}'::jsonb, NULL, '/');
    SELECT count(*) INTO _cnt FROM mail_outbox WHERE recipient_email = C2 AND status = 'en attente';
    DELETE FROM allowed_users WHERE id = _c2;
    _res := _res || jsonb_build_object('t', 'Mails : au départ d''un utilisateur, ses mails en attente sont ignorés et son adresse effacée', 'ok',
      _cnt > 0
      AND NOT EXISTS (SELECT 1 FROM mail_outbox WHERE recipient_email = C2 AND status = 'en attente')
      AND (SELECT count(*) FROM mail_outbox WHERE recipient_email = C2 AND status = 'ignoré') = _cnt
      AND NOT EXISTS (SELECT 1 FROM notification_mail_addresses WHERE recipient_email = C2),
      'd', _cnt || ' ligne(s) ignorée(s)');
  EXCEPTION WHEN OTHERS THEN
    _res := _res || jsonb_build_object('t', 'Mails : au départ d''un utilisateur, ses mails en attente sont ignorés et son adresse effacée', 'ok', false, 'd', SQLERRM);
  END;

  PERFORM set_config('request.jwt.claims', '', true);
  RETURN _res;
END
$function$;

REVOKE ALL ON FUNCTION private.smoke_mail_tests() FROM PUBLIC, anon, authenticated;

-- Ajout des tests du socle d'envoi à la suite existante.
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
