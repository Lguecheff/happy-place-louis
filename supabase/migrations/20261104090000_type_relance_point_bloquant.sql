-- Signal à vérifier (US21) : relance des équipes d'un point bloquant.
-- Séparé de la migration suivante : une valeur d'ENUM ajoutée ne peut pas être
-- utilisée dans la même transaction.
ALTER TYPE public.notification_kind ADD VALUE IF NOT EXISTS 'relance_point_bloquant';
