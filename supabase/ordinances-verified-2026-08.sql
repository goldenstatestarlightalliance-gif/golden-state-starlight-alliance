-- Verified dark sky ordinances — research pass of 8 August 2026.
--
-- METHOD
-- Each city below was checked against an official city source (the city's own
-- website or its published ordinance document), not against a news article or
-- an advocacy group's summary. Where only secondary sources existed, the city
-- is NOT marked as passed — see the "checked and NOT marked" list at the end,
-- which is the more useful half of this file.
--
-- SCOPE — READ THIS BEFORE TRUSTING THE MAP
-- This is NOT an exhaustive audit of all 483 California cities. Verifying every
-- city against its own municipal code is a far larger job than one pass. What
-- this covers is every city I could find documented evidence for, verified.
-- Cities left at not_started mean "no ordinance found", NOT "confirmed none" —
-- absence of evidence, not evidence of absence.
--
-- CRITERION
-- A dedicated outdoor lighting / dark sky ordinance with real substance:
-- shielding requirements, and usually a curfew and/or colour temperature cap.
-- General zoning glare rules do not count — most cities have those, and
-- counting them would make the map meaningless.

begin;

-- ---------------------------------------------------------------------------
-- Cities with a verified adopted ordinance
-- ---------------------------------------------------------------------------

update cities set status = 'passed'
 where place_fips in (
   '55282',  -- Palo Alto,  Santa Clara
   '17610',  -- Cupertino,  Santa Clara
   '08310',  -- Brisbane,   San Mateo
   '45246',  -- Malibu,     Los Angeles
   '46842'   -- Menifee,    Riverside
 );

-- ---------------------------------------------------------------------------
-- Ordinance detail, so every "passed" on the map is auditable
-- ---------------------------------------------------------------------------

insert into ordinances (city_id, title, summary, date_passed, date_effective, legal_text_url)
values
  ((select id from cities where place_fips = '55282'),
   'Ordinance No. 5692 — Outdoor Lighting (Dark Sky)',
   'Adopted December 2025 after a year of revisions. Council strengthened the '
   || 'staff draft: the curfew moved from midnight to 11pm, the rules apply to '
   || 'new and replacement lighting whether or not a permit is required, and the '
   || 'compliance window for existing adjustable fixtures was halved from two '
   || 'years to one. Follows DarkSky International and IES practice — lighting '
   || 'shielded, directed, and used only where and when needed.',
   '2025-12-08', null,
   'https://www.paloalto.gov/files/assets/public/v/1/planning-amp-development-services/current-planning/ordinances/bird/ord_5692_lighting.pdf'),

  ((select id from cities where place_fips = '17610'),
   'Municipal Code Chapter 19.102 — Glass and Lighting Standards',
   'Adopted 6 April 2021 as a combined bird-safe and dark sky measure. All '
   || 'outdoor lighting must be fully shielded and directed downward, away from '
   || 'adjacent properties. Also requires time-switch or occupancy controls on '
   || 'non-emergency interior lighting in non-residential buildings. Uses a '
   || '0.1 foot-candle standard with an 11pm residential curfew.',
   '2021-04-06', null,
   'https://www.cupertino.gov/Your-City/Departments/Community-Development/Planning/Non-Residential/Ordinances/Bird-Safe-and-Dark-Sky'),

  ((select id from cities where place_fips = '08310'),
   'Ordinance 687 — Chapter 15.88 Outdoor Lighting Standards',
   'Adopted 18 January 2024, effective 1 March 2024 for new installations with '
   || 'phased compliance for existing lighting. Fully shielded fixtures required '
   || '(opaque covering over the source), correlated colour temperature capped at '
   || '3000K, and a 10pm curfew for residential and commercial alike (or close of '
   || 'business, whichever is later). Motion-sensor lights exempt if they '
   || 'extinguish within 10 minutes. Zero light trespass standard.',
   '2024-01-18', '2024-03-01',
   'https://www.brisbaneca.gov/744/Dark-Sky-Ordinance'),

  ((select id from cities where place_fips = '45246'),
   'Municipal Code Chapter 17.41 — Dark Sky Ordinance',
   'Long-standing dark sky standards codified at Chapter 17.41, framed by the '
   || 'city as protecting wildlife, habitat and quality of life from light '
   || 'pollution. Amended by Ordinance No. 502, introduced on first reading '
   || '8 August 2022.',
   '2022-08-08', null,
   'https://www.malibucity.org/705/Dark-Sky-Ordinance'),

  ((select id from cities where place_fips = '46842'),
   'Ordinance No. 2009-24 — Dark Sky, regulating light pollution',
   'Dark sky ordinance regulating light pollution, published in the city''s own '
   || 'document archive. NOTE: lower confidence than the others here — the '
   || 'archived PDF would not render, so the title and number come from the '
   || 'city''s document listing rather than from the ordinance text. Worth a '
   || 'volunteer confirming the current provisions before this is cited publicly.',
   '2009-01-01', null,
   'https://www.cityofmenifee.us/Archive/ViewFile/Item/369');

commit;

-- ---------------------------------------------------------------------------
-- CHECKED AND DELIBERATELY *NOT* MARKED
--
-- Mountain View — commonly listed as having a dark sky ordinance. It does not.
--   The city adopted a work plan in June 2023 that *included* developing one,
--   which several summaries misread as adoption. Council put the project on
--   hold on 27 January 2026 to deal with SB 79, and work resumes in 2027.
--   The seed research also described it as "began developing in 2025-26".
--   https://www.mountainview.gov/our-city/departments/community-development/planning/dark-sky-ordinance
--
-- Los Altos — draft heard by council April 2025 and referred to the
--   Environmental Commission. No confirmation of adoption found. Belongs at
--   'ordinance_drafted' once a volunteer confirms the current stage.
--
-- Rancho Palos Verdes — advocacy sources cite a 10pm lighting curfew, but I
--   could not confirm a dedicated dark sky ordinance from the city or its code.
--
-- Borrego Springs and Julian — DarkSky International certified communities,
--   and the two most famous dark sky places in California. Both are
--   UNINCORPORATED, so neither is a city and neither appears in this table.
--   Their protection comes from San Diego County's Light Pollution Code.
--   Counting them as cities would be wrong; crediting San Diego County at the
--   county level would be right.
--
-- COUNTY-LEVEL ordinances exist in Los Angeles, Kern, San Luis Obispo,
--   San Diego and San Bernardino counties, plus Ventura County for
--   unincorporated Ojai and the Santa Monica Mountains. These are county
--   government action, not city, so they do not belong in this table — but
--   they are real progress and the county records should reflect them.
-- ---------------------------------------------------------------------------

select
  (select count(*) from cities where status = 'passed')    as cities_passed,
  (select count(*) from ordinances)                        as ordinance_records,
  (select count(*) from cities)                            as total_cities;
