-- Second research pass — 8 August 2026.
--
-- The first pass found five cities. It missed San Diego, which the founder
-- flagged: the city has had outdoor lighting regulations since 2012, entirely
-- separate from the county's Light Pollution Code. Worth noting why the miss
-- happened — searching for "dark sky ordinance" finds cities that use that
-- phrase, and misses cities whose equivalent rules are titled "Outdoor
-- Lighting Regulations" inside a zoning code. This pass searched for the
-- function rather than the name.

begin;

update cities set status = 'passed'
 where place_fips in (
   '66000',  -- San Diego,      San Diego
   '53476',  -- Ojai,           Ventura
   '45358'   -- Mammoth Lakes,  Mono
 );

insert into ordinances (city_id, title, summary, date_passed, date_effective, legal_text_url)
values
  ((select id from cities where place_fips = '66000'),
   'Municipal Code §142.0740 — Outdoor Lighting Regulations',
   'The city updated its outdoor lighting regulations in 2012. Ordinance '
   || 'O-20186 N.S. was adopted 31 July 2012 and took effect 6 September 2012, '
   || 'adding light pollution reduction requirements for non-residential '
   || 'buildings. The regulations apply to all new outdoor lighting fixtures and '
   || 'cover shields and flat lenses, light trespass, lighting color, hours of '
   || 'lighting, and sensitive biological resource areas. Entirely separate from '
   || 'San Diego County''s Light Pollution Code, which covers only '
   || 'unincorporated land.',
   '2012-07-31', '2012-09-06',
   'https://docs.sandiego.gov/municode/MuniCodeChapter14/Ch14Art02Division07.pdf'),

  ((select id from cities where place_fips = '53476'),
   'City of Ojai Dark Sky Ordinance',
   'Adopted by the Ojai City Council in April 2013 to limit light pollution. '
   || 'Distinct from — and five years earlier than — the county''s Ojai Valley '
   || 'Dark Sky Overlay of 2018, which covers the unincorporated valley around '
   || 'the city rather than the city itself.',
   '2013-04-01', null,
   'https://www.pbssocal.org/socal-focus/let-there-be-dark-why-ojais-dark-sky-ordinance-is-important'),

  ((select id from cities where place_fips = '45358'),
   'Municipal Code Chapter 17.36.030 — Outdoor Lighting Ordinance',
   'The Town of Mammoth Lakes Outdoor Lighting Ordinance. Restricts upward '
   || 'light projection to protect views of the night sky, alongside limits on '
   || 'light intensity and glare, and energy conservation goals.',
   null, null,
   'https://www.codepublishing.com/CA/MammothLakes/');

commit;

-- ---------------------------------------------------------------------------
-- CHECKED, NOT MARKED
--
-- Big Bear Lake — its municipal code does contain exterior lighting rules
--   (downward direction, 1.0 foot-candle at property lines, reduced lighting
--   outside business hours). But the compliance timelines reported for it
--   (18 months commercial / 24 months other) are identical to San Bernardino
--   COUNTY's 2021 ordinance, which suggests the sources are conflating the
--   two. Big Bear Lake is an incorporated city, so the county ordinance does
--   NOT apply there. Needs someone to read the city code directly.
--
-- Santa Barbara and Goleta — named in advocacy summaries as addressing
--   exterior lighting, but I found nothing distinguishing a dark sky ordinance
--   from ordinary zoning glare standards. Most cities have the latter, and
--   counting them would make the map meaningless.
-- ---------------------------------------------------------------------------

select
  (select count(*) from cities where status = 'passed') as cities_passed,
  (select count(*) from ordinances)                     as ordinance_records;
