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
