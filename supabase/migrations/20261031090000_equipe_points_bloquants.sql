-- Équipe concernée par un point bloquant (31 oct. 2026).
-- Le pôle reste un texte libre : seule l'équipe permet de savoir quel manager est concerné.
-- Sans équipe, le point concerne toutes les équipes.

ALTER TABLE public.blockers
  ADD COLUMN team text REFERENCES public.teams(name) ON UPDATE CASCADE ON DELETE SET NULL;

-- Points existants : on ne rattache que les pôles qui correspondent à une équipe.
UPDATE public.blockers b
SET team = m.team
FROM (VALUES
  ('PRODUCT TEAM', 'Product'),
  ('RELATIONS CLIENTS', 'Relation clients'),
  ('DATA & IA', 'Pôle Data et IA'),
  ('DIRECTION RECRUTEMENT', 'Direction recrutement'),
  ('OPÉRATIONS', 'Opérations')
) AS m(department, team)
JOIN public.teams t ON t.name = m.team
WHERE b.department = m.department;
