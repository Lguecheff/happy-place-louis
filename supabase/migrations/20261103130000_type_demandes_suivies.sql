-- Alertes selon le contexte : un type distinct pour les demandes qu'on suit sans en être l'auteur.
-- Séparé de la migration suivante : une valeur d'ENUM ajoutée ne peut pas être
-- utilisée dans la même transaction.
ALTER TYPE public.notification_kind ADD VALUE IF NOT EXISTS 'changement_statut_suivi';
