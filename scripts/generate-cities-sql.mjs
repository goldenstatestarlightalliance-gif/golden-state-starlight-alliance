// Generates supabase/all-cities.sql — every incorporated California city.
//
// WHY: the research seed only carries the 1-2 priority outreach cities per
// county (63 total). That is fine as a work list, but it is useless as a
// denominator: "cities with an ordinance" needs to be out of ALL of a county's
// cities, or Los Angeles reads as 0/1 instead of 0/88.
//
// Source is the same Census Places data the maps already render, so the city
// list and the map polygons cannot drift apart.
//
// Run: node scripts/generate-cities-sql.mjs

import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const geoDir = join(root, 'app/public/geo');

const q = (v) =>
  v === null || v === undefined || v === '' ? 'null' : `'${String(v).replace(/'/g, "''")}'`;

const slug = (s) =>
  s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

const rows = [];
let total = 0;

for (const file of readdirSync(join(geoDir, 'places'))) {
  const countyFips = file.replace('.geojson', '');
  const fc = JSON.parse(readFileSync(join(geoDir, 'places', file), 'utf8'));

  for (const f of fc.features) {
    const name = f.properties.BASENAME;
    // PLACE is the 5-digit Census place code — the stable identifier that ties
    // this row to the polygon the county page draws.
    const placeFips = f.properties.PLACE ?? null;
    if (!name) continue;
    total++;
    rows.push(
      `  ((select id from counties where fips = ${q(countyFips)}), ` +
      `${q(name)}, ${q(slug(name))}, ${q(placeFips)})`
    );
  }
}

const out = `-- GENERATED — regenerate with: node scripts/generate-cities-sql.mjs
-- Every incorporated California city (${total}), from Census Places.
--
-- Safe to run on the seeded database: cities already present (the 63 priority
-- outreach targets) keep their status and their is_priority flag. This only
-- backfills place_fips on those and adds the rest at not_started.
--
-- Idempotent — re-running changes nothing.

begin;

insert into cities (county_id, name, slug, place_fips) values
${rows.join(',\n')}
on conflict (county_id, name) do update
  set place_fips = coalesce(cities.place_fips, excluded.place_fips);

commit;

-- Expect ${total} cities across 55 counties.
-- Alpine, Mariposa and Trinity have no incorporated cities at all.
select
  (select count(*) from cities)                          as total_cities,
  (select count(*) from cities where is_priority)        as priority_cities,
  (select count(distinct county_id) from cities)         as counties_with_cities;
`;

writeFileSync(join(root, 'supabase/all-cities.sql'), out);
console.log(`Wrote supabase/all-cities.sql — ${total} cities`);
