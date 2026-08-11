-- City-level ordinance detail, and a correction to the San Diego record.
--
-- CORRECTION: San Diego's ordinance was recorded as "O-20186, adopted 2012".
-- That is one amendment, not the origin. SDMC §142.0740 was adopted 9 December
-- 1997 by O-18451, effective 1 January 2000, and has been amended seven times,
-- most recently by O-21771 effective 12 April 2024. Recording the 2012
-- amendment as the adoption date understates it by 15 years and would be
-- embarrassing in front of a City Attorney.

begin;

update ordinances set
  title = 'Municipal Code §142.0740 — Outdoor Lighting Regulations',
  summary =
    'Adopted 9 December 1997 by Ordinance O-18451, effective 1 January 2000, '
    || 'and amended seven times since — most recently by O-21771, effective '
    || '12 April 2024. Covers shielding, light trespass, lighting colour, hours '
    || 'of operation and sensitive biological resource areas, and requires BUG '
    || 'ratings at permit intake. Separate from San Diego County''s Light '
    || 'Pollution Code, which reaches only unincorporated land.',
  date_passed = '1997-12-09',
  date_effective = '2000-01-01'
where city_id = (select id from cities where place_fips = '66000');

-- ---------------------------------------------------------------------------
-- Notes explaining each city's status, including the cities with no ordinance
-- ---------------------------------------------------------------------------

update cities set
  ordinance_notes =
    'In force since 2000 and amended seven times, but with real gaps. The '
    || 'shielding threshold sits at 6,200 / 4,050 lumens rather than 1,000; '
    || 'colour temperature is capped at 4000K rather than 3000K; sports and '
    || 'sign lighting are exempt from shielding entirely; the City exempts its '
    || 'own streetlights; and the observatory provision at (c)(5)(A)(ii) reads '
    || '"4,050 lumens OR 2500K" — a choice, not a mandate. There is no '
    || 'amortization schedule, so existing non-compliant fixtures stay legal '
    || 'indefinitely, and §142.0740 carries no penalty provision at all.',
  code_reviewed_at = '2026-08-08',
  code_review_source = 'https://docs.sandiego.gov/municode/MuniCodeChapter14/Ch14Art02Division07.pdf'
where place_fips = '66000';

update cities set
  ordinance_notes =
    'Article 35 requires shielded low-pressure sodium, shielded narrow-spectrum '
    || 'amber LEDs, or other shielded efficient fixtures at 3,000 Kelvin or '
    || 'less, and requires fixture types, locations and controls to minimise '
    || 'glare, light trespass and artificial sky glow. Both a shielding mandate '
    || 'and a colour temperature cap, which is more than most California city '
    || 'codes carry.',
  code_reviewed_at = '2026-08-08',
  code_review_source = 'https://ecode360.com/43266390'
where place_fips = '22804';

update cities set
  ordinance_notes =
    'Chapter 30.40 requires outdoor fixtures to be fully shielded so all '
    || 'emitted light falls below an imaginary horizontal plane through the '
    || 'lowest point of the luminaire, directed away from streets and '
    || 'neighbouring properties. Full cutoff is the defining dark sky '
    || 'requirement. No colour temperature cap or curfew, so there is room to '
    || 'amend rather than start from nothing.',
  code_reviewed_at = '2026-08-08',
  code_review_source = 'https://ecode360.com/44483877'
where place_fips = '22678';

-- Poway: checked, deliberately not marked passed. The page should say why.
update cities set
  ordinance_notes =
    'Poway Municipal Code 17.08.220(L) and 17.10.150(H) state that "in order to '
    || 'preserve the night sky" outdoor fixtures shall minimise glare, upward '
    || 'light, artificial sky glow, light pollution and light trespass, and '
    || 'require visors or louvres and photocells. Genuine dark sky intent, but '
    || 'the operative wording is "to the maximum extent feasible" — '
    || 'discretionary rather than a shielding mandate, with no colour '
    || 'temperature cap or curfew. Not counted as passed under the coalition''s '
    || 'criterion; a strong candidate for amendment rather than a new ordinance.',
  code_reviewed_at = '2026-08-08',
  code_review_source = 'https://www.codepublishing.com/CA/Poway/'
where place_fips = '58520';

commit;

select
  (select count(*) from cities where ordinance_notes is not null) as cities_with_notes,
  (select count(*) from cities where code_reviewed_at is not null) as cities_code_reviewed,
  (select count(*) from cities where slides_url is not null) as cities_with_deck;
