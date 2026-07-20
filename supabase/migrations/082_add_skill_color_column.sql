ALTER TABLE public.skills
ADD COLUMN IF NOT EXISTS color BIGINT;

UPDATE public.skills
SET color = CASE lower(trim(name))
  WHEN 'electrical' THEN 4294953984
  WHEN 'plumbing' THEN 4281888767
  WHEN 'hvac' THEN 4278238420
  WHEN 'carpentry' THEN 4287137928
  WHEN 'drywall' THEN 4289246907
  WHEN 'painting' THEN 4294948011
  WHEN 'roofing' THEN 4293402623
  WHEN 'concrete' THEN 4287137928
  ELSE color
END
WHERE color IS NULL;
