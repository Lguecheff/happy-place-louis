-- Points bloquants à revoir (US16).
-- Séparé de la migration suivante : une valeur d'ENUM ajoutée ne peut pas être
-- utilisée dans la même transaction.
ALTER TYPE public.notification_kind ADD VALUE IF NOT EXISTS 'point_bloquant_a_revoir';
