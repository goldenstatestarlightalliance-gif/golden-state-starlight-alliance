-- Clean up five bad city rows created by the original research seed.
--
-- 1. Three rows are not cities at all. The research JSON used the `cities`
--    field to carry an explanatory note for counties that have none, e.g.
--      "(no incorporated cities – county seat Markleeville is unincorporated)"
--    and the seed generator inserted those strings as city names.
--
-- 2. Two rows duplicate a real Census place under its common name rather than
--    its official one:
--      Angels Camp = "Angels"                    (Calaveras, place 02112)
--      Ventura     = "San Buenaventura (Ventura)" (Ventura,   place 65042)
--    Both were seeded as priority targets, so the flag moves to the Census row
--    before the duplicate goes.

begin;

-- Move the priority flag onto the real Census rows first, so the outreach
-- targets survive the delete.
update cities set is_priority = true
 where place_fips in ('02112', '65042');

-- Drop the duplicates (the ones with no Census place code).
delete from cities
 where place_fips is null
   and name in ('Angels Camp', 'Ventura');

-- Drop the explanatory notes. Matching on the leading parenthesis is precise
-- here: no real California city name starts with one.
delete from cities
 where place_fips is null
   and name like '(%';

commit;

-- Expect: 483 cities, 60 priority, 55 counties with cities.
-- (60 not 63 — Alpine, Mariposa and Trinity have no city to target, which is
--  why the research left a note there in the first place.)
select
  (select count(*) from cities)                               as total_cities,
  (select count(*) from cities where is_priority)             as priority_cities,
  (select count(distinct county_id) from cities)              as counties_with_cities,
  (select count(*) from cities where place_fips is null)      as rows_without_census_id;
