-- Third research pass — 8 August 2026.
--
-- Prompted by the founder pointing out that around 12 California cities are
-- commonly reported as having an ordinance, against 10 recorded here. Three
-- more confirmed, taking the total to 13.
--
-- WHY THESE WERE MISSED: all three sit in the desert and mountain communities
-- around Joshua Tree and Big Bear, and their codes are titled "Lighting
-- Standards" or "Outdoor Lighting Requirements" rather than "dark sky". The
-- same failure mode that hid San Diego's 1997 ordinance in the first pass —
-- searching by the phrase advocates use rather than by what the chapter does.

begin;

update cities set status = 'passed'
 where place_fips in (
   '87056',  -- Yucca Valley,  San Bernardino
   '06434',  -- Big Bear Lake, San Bernardino
   '55184'   -- Palm Desert,   Riverside
 );

insert into ordinances (city_id, title, summary, date_passed, legal_text_url)
values
  ((select id from cities where place_fips = '87056'),
   'Municipal Code Chapter 8.70 — Outdoor Lighting',
   'First adopted in 1998, explicitly to "minimize light pollution which has a '
   || 'detrimental effect on the environment and the enjoyment of the night '
   || 'sky". One of the oldest dark sky ordinances in California and a useful '
   || 'precedent for the desert communities around Joshua Tree, since it has '
   || 'been on the books and survived for over twenty-five years.',
   '1998-01-01',
   'https://codelibrary.amlegal.com/codes/yuccavalleyca/latest/yuccavalley_ca/0-0-0-2462'),

  ((select id from cities where place_fips = '06434'),
   'Municipal Code — outdoor and security lighting standards',
   'Requires luminaires in commercial zones to have a cutoff of 90 degrees or '
   || 'less, with exterior lighting reduced where feasible outside business '
   || 'hours expressly "to preserve views of the night sky". Security lighting '
   || 'must be directed downward with the bulb not visible off site, and light '
   || 'at the property line capped at 1.0 foot-candle. Note the city sits inside '
   || 'San Bernardino County, whose 2021 Light Trespass Ordinance reaches only '
   || 'unincorporated land and does NOT apply here — a distinction several '
   || 'sources blur.',
   null,
   'https://library.municode.com/ca/big_bear_lake/codes/code_of_ordinances'),

  ((select id from cities where place_fips = '55184'),
   'Municipal Code Chapter 24.16 — Outdoor Lighting Requirements',
   'Stated purpose is to minimize light pollution and light trespass and '
   || 'preserve the night-time environment. Requires full-cutoff luminaires for '
   || 'anything above 4,000 mean lamp lumens, defines light pollution in terms '
   || 'of sky glow, trespass and glare, and prohibits high pressure sodium '
   || 'sources outright.',
   null,
   'https://ecode360.com/43848533');

-- Notes for the city pages.
update cities set
  ordinance_notes =
    'Chapter 8.70 dates from 1998, which makes it one of the oldest surviving '
    || 'dark sky ordinances in the state. Its age is the argument: it is proof '
    || 'to a neighboring council that these rules are workable long-term rather '
    || 'than experimental.',
  code_reviewed_at = '2026-08-08',
  code_review_source = 'https://codelibrary.amlegal.com/codes/yuccavalleyca/latest/yuccavalley_ca/0-0-0-2462'
where place_fips = '87056';

update cities set
  ordinance_notes =
    'Has real shielding requirements — 90-degree cutoff in commercial zones and '
    || 'downward-directed security lighting with a 1.0 foot-candle property-line '
    || 'cap — but the strongest provisions are limited to commercial zones, and '
    || 'there is no colour temperature cap or amortization. Amendment territory '
    || 'rather than a new ordinance.',
  code_reviewed_at = '2026-08-08',
  code_review_source = 'https://library.municode.com/ca/big_bear_lake/codes/code_of_ordinances'
where place_fips = '06434';

update cities set
  ordinance_notes =
    'Full-cutoff requirement kicks in only above 4,000 mean lamp lumens, so a '
    || 'great many residential fixtures fall below the threshold entirely. No '
    || 'colour temperature cap. The purpose language is strong and the structure '
    || 'is sound; the numbers are where the work is.',
  code_reviewed_at = '2026-08-08',
  code_review_source = 'https://ecode360.com/43848533'
where place_fips = '55184';

-- Twentynine Palms — a GSSA target county seat. Chapter 19.78 "Lighting
-- Standards" exists in its code and Joshua Tree National Park has supported
-- updating it, but the chapter text could not be retrieved (Municode blocks
-- automated access) so its substance is unverified. Left NOT marked, in line
-- with how Poway is handled.
update cities set
  ordinance_notes =
    'Municipal Code Chapter 19.78, "Lighting Standards", exists and Joshua Tree '
    || 'National Park has supported efforts to update it — but the chapter text '
    || 'could not be retrieved, so whether it meets the shielding or colour '
    || 'temperature criterion is unconfirmed. Worth reading directly: this is a '
    || 'priority county seat and the answer changes whether the ask is a new '
    || 'ordinance or an amendment.',
  code_review_source = 'https://library.municode.com/ca/twentynine_palms/codes/code_of_ordinances?nodeId=CD_ORD_ART4SIDERE_CH19.78LIST'
where place_fips = '80994';

commit;

select
  (select count(*) from cities where status = 'passed') as cities_passed,
  (select count(*) from ordinances)                     as ordinance_records,
  (select count(*) from cities where code_reviewed_at is not null) as code_reviewed;
