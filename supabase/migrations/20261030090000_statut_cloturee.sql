-- Nouveau statut de demande « clôturée » (30 oct. 2026).
-- Séparé de la migration suivante : une valeur d'ENUM ajoutée ne peut pas être
-- utilisée dans la même transaction.
ALTER TYPE public.submission_status ADD VALUE IF NOT EXISTS 'clôturée';
