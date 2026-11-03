-- Définitions de KPI (US18). Chaque indicateur porte deux textes : « Ce que ça mesure »
-- (definition) et « Ce que ça change pour toi » (impact), 200 caractères maximum chacun.
-- Lecture par tous (« Allowed read »), écriture par les admins (« Admin write »), politiques
-- existantes. Le trigger d'historique ne réagit qu'à la valeur : modifier un texte n'ajoute
-- aucun point d'historique.
BEGIN;

ALTER TABLE public.metrics
  ADD COLUMN definition text,
  ADD COLUMN impact text,
  ADD CONSTRAINT metrics_definition_length CHECK (char_length(definition) <= 200),
  ADD CONSTRAINT metrics_impact_length CHECK (char_length(impact) <= 200);

-- Les nouvelles colonnes sont ajoutées en fin de vue, comme l'exige CREATE OR REPLACE VIEW.
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
    m.impact
FROM public.metrics m
LEFT JOIN LATERAL (
    SELECT h.value
    FROM public.metrics_history h
    WHERE h.metric_key = m.key
    ORDER BY h.recorded_at DESC
    OFFSET 1
    LIMIT 1
) p ON true;

-- Textes fictifs des trois KPI de la vue d'ensemble, validés par Louis le 2026-11-03.
UPDATE public.metrics SET
  definition = 'Part des candidats accompagnés qui ont signé une mission dans les 30 derniers jours (fictif).',
  impact = 'Il fixe les priorités de l''équipe : s''il baisse, l''effort va aux candidats sans mission, et tes demandes qui les aident passent en premier (fictif).'
WHERE key = 'training_kpi';

UPDATE public.metrics SET
  definition = 'Nombre de missions en cours aujourd''hui, de la signature du contrat à la fin de la mission (fictif).',
  impact = 'Il montre la charge de suivi : plus il monte, plus tes managers ont de missions à suivre, et plus une demande qui fait gagner du temps compte (fictif).'
WHERE key = 'active_users';

UPDATE public.metrics SET
  definition = 'Note de recommandation donnée par les candidats à la fin de leur mission, de −100 à +100 (fictif).',
  impact = 'Il dit si les candidats recommandent Happy Place : une demande qui améliore leur accueil ou leur suivi le fait monter (fictif).'
WHERE key = 'nps';

COMMIT;
