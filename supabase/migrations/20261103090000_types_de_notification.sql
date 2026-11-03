-- Préférences de notification (US13) : nouveaux types de notification.
-- Séparé de la migration suivante : une valeur d'ENUM ajoutée ne peut pas être
-- utilisée dans la même transaction.
-- 'resume_hebdo' ne crée aucune notification dans l'app : il sert seulement à enregistrer le choix « Par mail ».
ALTER TYPE public.notification_kind ADD VALUE IF NOT EXISTS 'changement_statut';
ALTER TYPE public.notification_kind ADD VALUE IF NOT EXISTS 'resume_hebdo';
