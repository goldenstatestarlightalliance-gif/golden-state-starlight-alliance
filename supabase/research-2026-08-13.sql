-- Golden State Starlight Alliance — research pass, 13 August 2026.
--
-- Closing out the data gaps: certified dark sky places, ordinance provenance,
-- and the first code reviews of the two largest unexamined cities.
--
-- METHOD NOTE. Everything below was read from a primary source — the code text
-- itself on eCode360 / American Legal, or DarkSky International's own place
-- record. Where only a year could be established, the year goes in the summary
-- and date_passed stays null: a fabricated 1 January would render on the city
-- page as though it were the real adoption date.

begin;

-- ---------------------------------------------------------------------------
-- 1. Certified dark sky places
-- ---------------------------------------------------------------------------
--
-- The table held three, all in San Diego County, which badly understated
-- California — the two national parks below are the state's most visible dark
-- sky designations and both were missing.

insert into dark_sky_places (county_id, name, slug, designation, designated_year, source_url)
values
  -- Gold-tier, and at the time of designation the largest dark sky park in the
  -- world. Headquarters at Furnace Creek puts it in Inyo County.
  (7, 'Death Valley National Park', 'death-valley-national-park',
   'International Dark Sky Park', 2013,
   'https://darksky.org/places/death-valley-national-park-dark-sky-park/'),

  -- Spans Riverside and San Bernardino counties. Filed under San Bernardino
  -- because the park headquarters sits in Twentynine Palms, which is also a
  -- GSSA target city — the adjacency is the argument to that council.
  (12, 'Joshua Tree National Park', 'joshua-tree-national-park',
   'International Dark Sky Park', 2017,
   'https://darksky.org/places/joshua-tree-national-park-dark-sky-park/')
on conflict (slug) do nothing;

-- DarkSky's own record dates the Anza-Borrego certification 19 January 2018.
-- The stored 2017 was wrong.
update dark_sky_places
   set designated_year = 2018
 where slug = 'anza-borrego-desert-state-park';

-- Borrego Springs is left at 2009 deliberately. DarkSky's page carries a
-- January 2015 timestamp, but that is a CMS date — the designation is
-- independently documented as 2009, when Borrego became the first certified
-- Dark Sky Community in California and the second in the world after
-- Flagstaff. The stored value was already right.

-- ---------------------------------------------------------------------------
-- 2. Ordinance provenance
-- ---------------------------------------------------------------------------

-- Palm Desert. The chapter is not new: eCode360 records it as enacted by
-- Ord. 1272 in 2014, amended by Ord. 1355 (2020) and Ord. 1382 (2022), and
-- carrying prior history from Ord. 826. Only years are established, so
-- date_passed stays null.
update ordinances set summary = summary ||
  ' Enacted in its current form by Ordinance 1272 (2014), amended by '
  || 'Ordinance 1355 (2020) and Ordinance 1382 (2022), and carrying prior '
  || 'history from Ordinance 826. The chapter has therefore survived three '
  || 'councils, which is the durability argument for a neighboring city.'
where city_id = 356;

-- Palo Alto. Already correctly dated 8 December 2025; this adds what the
-- adopted text actually says, which matters because the council went further
-- than staff proposed.
update ordinances set summary = summary ||
  ' Codified at Municipal Code section 18.40.250. The council adopted a '
  || 'stricter version than staff recommended: the curfew moved from midnight '
  || 'to 11:00 p.m., the standards apply to all new and replacement outdoor '
  || 'lighting regardless of whether a building permit is required, and the '
  || 'compliance window for adjustable existing fixtures was halved from two '
  || 'years to one. The Santa Clara Valley Bird Alliance and Sierra Club Loma '
  || 'Prieta had asked for exactly those first and last changes — useful '
  || 'evidence that a well-argued comment letter moves a council.'
where city_id = 1;

-- ---------------------------------------------------------------------------
-- 3. Code reviews — reviewed, no qualifying ordinance found
-- ---------------------------------------------------------------------------
--
-- Both are recorded as reviewed but NOT passed. That distinction is the whole
-- point of code_reviewed_at: "someone looked and there is nothing" is a
-- different fact from "nobody has looked", and only the first one stops the
-- next volunteer repeating the work.

-- Los Angeles — the largest city in the state, never examined until now.
update cities set
  ordinance_notes =
    'Municipal Code section 93.0117, "Outdoor Lighting Affecting Residential '
    || 'Property" (amended by Ord. 184,692, effective 30 December 2016), is a '
    || 'light trespass rule rather than a dark sky ordinance. It caps light '
    || 'crossing onto a neighboring residential window, deck or yard at two '
    || 'foot-candles and forbids direct glare, and it requires full cut-off '
    || 'luminaires with a 10 p.m. curfew — but only for tennis courts. There '
    || 'is no general shielding requirement, no color temperature cap and '
    || 'nothing addressing sky glow, and an exemption releases any light '
    || 'source more than 2,000 feet from a residence. '
    || 'STRATEGIC READ: Los Angeles is an amendment target, not a new-ordinance '
    || 'target. The hook already exists in Chapter IX and the city already '
    || 'accepts full cut-off language for one use case, which is a far shorter '
    || 'ask than drafting from nothing.',
  code_reviewed_at = '2026-08-13',
  code_review_source = 'https://codelibrary.amlegal.com/codes/los_angeles/latest/lamc/0-0-0-183817'
where id = 38;

-- Mountain View — an active effort, currently stalled.
update cities set
  ordinance_notes =
    'No ordinance adopted. The city made a Dark Sky Ordinance a council '
    || 'priority and began drafting objective lighting standards, but on '
    || '27 January 2026 the council placed the project on temporary hold to '
    || 'deal with SB 79, the state law setting maximum density near major '
    || 'transit stops. '
    || 'STRATEGIC READ: the substantive work is done and the hold is about '
    || 'staff capacity, not opposition. This is a calendar problem — the ask '
    || 'is to get it back on the docket once SB 79 work clears, not to '
    || 'persuade anyone of the merits.',
  code_reviewed_at = '2026-08-13',
  code_review_source = 'https://www.mountainview.gov/our-city/departments/community-development/planning/dark-sky-ordinance'
where id = 2;

commit;

select
  (select count(*) from dark_sky_places)                            as dark_sky_places,
  (select count(*) from cities where status = 'passed')             as cities_passed,
  (select count(*) from cities where code_reviewed_at is not null)  as code_reviewed;
