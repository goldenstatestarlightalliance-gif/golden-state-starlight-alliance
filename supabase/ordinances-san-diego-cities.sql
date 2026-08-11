-- San Diego County city-by-city review — 8 August 2026.
--
-- The founder asked for all 18 cities in the county to be checked. This records
-- what could be verified and, just as importantly, what could not.
--
-- CRITERION USED
-- The coalition's definition of dark sky policy (spec §1): shielded fixtures,
-- warmer color temperatures, lighting curfews. A city qualifies when its code
-- REQUIRES full shielding and/or caps color temperature. Discretionary
-- language ("minimize glare to the maximum extent feasible") does not qualify,
-- because almost every city zoning code contains something like it, and
-- counting those would make the map meaningless.

begin;

update cities set status = 'passed'
 where place_fips in (
   '22804',  -- Escondido
   '22678'   -- Encinitas
 );

insert into ordinances (city_id, title, summary, date_passed, legal_text_url)
values
  ((select id from cities where place_fips = '22804'),
   'Municipal Code Article 35 — Outdoor Lighting',
   'Requires shielded low-pressure sodium, shielded narrow-spectrum amber LEDs, '
   || 'or other shielded energy-efficient fixtures with a correlated color '
   || 'temperature of 3,000 Kelvin or less. Also requires that fixture types, '
   || 'locations and controls for single-family and small multifamily homes '
   || 'minimize glare, light trespass and artificial sky glow. The clearest '
   || 'city-level dark sky ordinance in the county after San Diego itself — it '
   || 'has both a shielding mandate and a color temperature cap.',
   null,
   'https://ecode360.com/43266390'),

  ((select id from cities where place_fips = '22678'),
   'Municipal Code Chapter 30.40 — Performance Standards (outdoor lighting)',
   'Requires outdoor lighting fixtures to be fully shielded so that all emitted '
   || 'sustained light is projected below an imaginary horizontal plane passing '
   || 'through the lowest point of the luminaire, and that light be directed '
   || 'away from streets and adjoining properties. Full cutoff is the defining '
   || 'dark sky requirement, so this qualifies even though it sits inside a '
   || 'general performance-standards chapter rather than a standalone ordinance.',
   null,
   'https://ecode360.com/44483877');

commit;

-- ---------------------------------------------------------------------------
-- POWAY — a judgment call, deliberately left unmarked
--
-- Poway Municipal Code 17.08.220(L) and 17.10.150(H) say that "in order to
-- preserve the night sky, the types, locations and controlling devices of
-- outdoor light fixtures shall minimize glare, upward light, artificial sky
-- glow, and light pollution and light trespass", require visors or louvers to
-- reduce spill light, and require photocells.
--
-- That is genuine dark sky intent, and stronger than boilerplate. But the
-- operative wording is "to the maximum extent feasible" — discretionary rather
-- than a hard shielding mandate, and there is no color temperature cap or
-- curfew. Someone from the coalition should read the section and decide; it is
-- a defensible "yes" under a looser criterion.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- NOT VERIFIED — the remaining 12 cities
--
-- Carlsbad, Chula Vista, Coronado, Del Mar, El Cajon, Imperial Beach, La Mesa,
-- Lemon Grove, National City, Oceanside, San Marcos, Santee.
--
-- No dark sky ordinance found for these, but that is NOT the same as
-- confirming they have none. Web search reaches city codes unevenly, and
-- several of these cities publish their codes on platforms that block
-- automated access. Each needs its municipal code read directly — the
-- reliable route is the city planning department, searching the zoning code
-- for "outdoor lighting" rather than "dark sky", which is how San Diego's own
-- 2012 ordinance was missed the first time.
-- ---------------------------------------------------------------------------

select c.name, c.status
from cities c
join counties co on co.id = c.county_id
where co.slug = 'san-diego'
order by (c.status = 'not_started'), c.name;
