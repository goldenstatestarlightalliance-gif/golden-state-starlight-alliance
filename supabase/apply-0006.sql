-- County-level ordinances and certified dark sky places.
--
-- WHY THIS EXISTS
-- In California a county's zoning and lighting ordinances apply ONLY to the
-- unincorporated area — incorporated cities have their own land use authority.
-- So a county ordinance does not cover the cities inside it, and must never be
-- folded into the city-coverage percentage.
--
-- But it is real protection, often over most of a rural county's land area,
-- and the coalition's own goal is an ordinance from "at least one city OR
-- county government" per county. Tracking it separately is the only way to
-- show both truths at once.

-- counties.status already runs the six-stage pipeline and was previously
-- unused by the UI. These columns carry the evidence alongside it.
alter table counties add column ordinance_title       text;
alter table counties add column ordinance_summary     text;
alter table counties add column ordinance_date_passed date;
alter table counties add column ordinance_url         text;

comment on column counties.status is
  'Stage of the COUNTY GOVERNMENT''s own ordinance, which in California covers '
  'only the unincorporated area. City coverage is computed separately from the '
  'cities table.';

-- ---------------------------------------------------------------------------
-- Certified dark sky places
-- ---------------------------------------------------------------------------

-- DarkSky International certified places. These are mostly unincorporated
-- communities and parks, so they are not cities and cannot appear in the
-- cities table — but they are the most visible dark sky wins in the state.
create table dark_sky_places (
  id           bigint generated always as identity primary key,
  county_id    bigint not null references counties(id) on delete cascade,
  name         text not null,
  slug         text not null unique,
  -- 'International Dark Sky Community', 'International Dark Sky Park', etc.
  designation  text not null,
  designated_year smallint,
  -- Census CDP GEOID, joining to app/public/geo/ca-darksky-places.geojson.
  -- Null for places with no Census boundary — a state park, for instance,
  -- which is listed but not drawn.
  place_geoid  text,
  source_url   text,
  created_at   timestamptz not null default now()
);

create index dark_sky_places_county_idx on dark_sky_places(county_id);

alter table dark_sky_places enable row level security;

-- Public: these are the showcase entries on a public accountability map.
create policy dark_sky_places_public_read on dark_sky_places
  for select using (true);

create policy dark_sky_places_write on dark_sky_places
  for all using (is_admin()) with check (is_admin());
-- County-level ordinance data — verified 8 August 2026 against official county
-- planning department sources.
--
-- IMPORTANT: every one of these covers the UNINCORPORATED area only. None of
-- them applies inside the incorporated cities of that county. That is why they
-- live on counties.status and never touch the city coverage percentage.

begin;

-- Kern — Zoning Ordinance Chapter 19.81, "Outdoor Lighting (Dark Skies Ordinance)"
update counties set
  status = 'passed',
  ordinance_title = 'Zoning Ordinance Chapter 19.81 — Outdoor Lighting "Dark Skies Ordinance"',
  ordinance_summary =
    'County zoning chapter intended to reduce unnecessary night lighting and '
    || 'minimise lighting impacts on surrounding properties, explicitly to protect '
    || 'Kern County''s rural character of access to a natural dark sky environment. '
    || 'Applies in unincorporated Kern County.',
  ordinance_url = 'https://kernplanning.com/dark-skies-ordinance-informational-guide/'
where slug = 'kern';

-- San Bernardino — Development Code Chapter 83.07, Light Trespass
update counties set
  status = 'passed',
  ordinance_title = 'Development Code Chapter 83.07 — Light Trespass',
  ordinance_summary =
    'Adopted by the Board of Supervisors on 7 December 2021. Full shielding on '
    || 'all fixtures, colour temperature capped at 3000K, and no blinking or '
    || 'flashing lights. Stricter limits in the Mountain and Desert regions '
    || '(0.1 foot-candles at residential property lines) than in the Valley '
    || 'region (0.5). Lights must be extinguished once no one is present '
    || 'outdoors, with motion-sensor exemptions. Compliance windows of 18 months '
    || 'for commercial and industrial, 24 months for other uses. '
    || 'Unincorporated county only.',
  ordinance_date_passed = '2021-12-07',
  ordinance_url = 'https://lus.sbcounty.gov/planning-home/outdoor-lighting-regulations/'
where slug = 'san-bernardino';

-- Los Angeles — Zoning Code Chapter 22.80, Rural Outdoor Lighting District
update counties set
  status = 'passed',
  ordinance_title = 'Zoning Code Chapter 22.80 — Rural Outdoor Lighting District (ROLD)',
  ordinance_summary =
    'Supplemental zoning district adopted in 2012 covering rural unincorporated '
    || 'areas of the county. Requires lights to be shielded and angled to limit '
    || 'light pollution and to stop illumination spilling onto adjacent '
    || 'properties. Applies within the mapped district, not countywide.',
  ordinance_date_passed = '2012-01-01',
  ordinance_url = 'https://planning.lacounty.gov/long-range-planning/rold/'
where slug = 'los-angeles';

-- Ventura — a set of overlay zones rather than one ordinance
update counties set
  status = 'passed',
  ordinance_title = 'Outdoor lighting overlay zones (Ojai Valley, Santa Monica Mountains, and others)',
  ordinance_summary =
    'Five overlay zones rather than a single countywide ordinance: Ojai Valley '
    || 'Dark Sky Overlay (2018, covering unincorporated Ojai Valley, Mira Monte, '
    || 'Casitas Springs, Meiners Oaks and Oak View), Santa Monica Mountains Dark '
    || 'Sky Overlay (2022), Coastal ESHA regulations (2022), Habitat Connectivity '
    || '& Wildlife Corridor Overlay (2019) and Scenic Resource Protection Overlay '
    || '(2008). Common requirements are fully shielded fixtures directing light '
    || 'below the horizontal, dark-hours curfews, and colour temperature limits. '
    || 'Unincorporated areas only — these do not affect the county''s cities.',
  ordinance_date_passed = '2018-01-01',
  ordinance_url = 'https://rma.venturacounty.gov/divisions/planning/ventura-county-outdoor-lighting-restrictions/'
where slug = 'ventura';

-- San Diego — Light Pollution Code
update counties set
  status = 'passed',
  ordinance_title = 'County Code of Regulatory Ordinances — Light Pollution Code',
  ordinance_summary =
    'Regulates outdoor lighting across unincorporated San Diego County with the '
    || 'stated intent of minimising light pollution and protecting astronomical '
    || 'research at the Palomar and Mount Laguna observatories. This is the code '
    || 'that protects Borrego Springs and Julian, California''s two DarkSky '
    || 'International certified communities, neither of which is an incorporated '
    || 'city.',
  ordinance_url = 'https://www.sandiegocounty.gov/pds/docs/LightPollutionCode.pdf'
where slug = 'san-diego';

-- ---------------------------------------------------------------------------
-- Certified dark sky places
-- ---------------------------------------------------------------------------

insert into dark_sky_places (county_id, name, slug, designation, designated_year, place_geoid, source_url)
values
  -- GEOIDs match the features in app/public/geo/ca-darksky-places.geojson,
  -- which is how the map knows which polygon to shade for each place.
  ((select id from counties where slug = 'san-diego'),
   'Borrego Springs', 'borrego-springs',
   'International Dark Sky Community', 2009,
   '0607596',
   'https://darksky.org/places/borrego-springs-dark-sky-community/'),

  ((select id from counties where slug = 'san-diego'),
   'Julian', 'julian',
   'International Dark Sky Community', 2021,
   '0637582',
   'https://darksky.org/news/julian-california-idsc-announcement/'),

  ((select id from counties where slug = 'san-diego'),
   'Anza-Borrego Desert State Park', 'anza-borrego-desert-state-park',
   'International Dark Sky Park', 2017,
   null,  -- a state park has no Census place boundary, so it is listed, not drawn
   'https://abdnha.org/darksky/')
on conflict (slug) do nothing;

commit;

select
  (select count(*) from counties where status <> 'not_started') as counties_with_ordinance,
  (select count(*) from dark_sky_places)                        as certified_places,
  (select count(*) from cities where status = 'passed')         as cities_passed;
