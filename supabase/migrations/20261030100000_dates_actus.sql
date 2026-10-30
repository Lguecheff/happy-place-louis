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
