// Fetches boundaries for California's DarkSky International certified
// communities and writes app/public/geo/ca-darksky-places.geojson.
//
// These are NOT incorporated cities — Borrego Springs and Julian are Census
// Designated Places, unincorporated communities protected by San Diego
// County's Light Pollution Code rather than by a city ordinance. That is
// exactly why they need their own layer: they represent real dark sky
// protection that the city-coverage percentage can never show.
//
// CDPs live in layer 5 of the Places service (layer 4 is incorporated places).
//
// Run: node scripts/fetch-darksky-places.mjs

import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const TIGERWEB = 'https://tigerweb.geo.census.gov/arcgis/rest/services/TIGERweb';
const CDP_LAYER = 5;

// Certified communities with a Census CDP boundary we can draw.
// Anza-Borrego Desert State Park is also certified (International Dark Sky
// Park, 2017) but is a state park, not a Census place, so it has no boundary
// here — it is recorded in the database without geometry.
const PLACES = [
  { match: 'Borrego Springs', slug: 'borrego-springs', designation: 'International Dark Sky Community', year: 2009 },
  { match: 'Julian',          slug: 'julian',          designation: 'International Dark Sky Community', year: 2021 },
];

const round = (n) => Number(n.toFixed(5));
const roundCoords = (c) =>
  typeof c[0] === 'number' ? [round(c[0]), round(c[1])] : c.map(roundCoords);

const features = [];

for (const p of PLACES) {
  const params = new URLSearchParams({
    where: `STATE='06' AND BASENAME='${p.match}'`,
    outFields: 'GEOID,BASENAME,NAME,STATE,PLACE',
    f: 'geojson',
    outSR: '4326',
    returnGeometry: 'true',
  });

  const url = `${TIGERWEB}/Places_CouSub_ConCity_SubMCD/MapServer/${CDP_LAYER}/query?${params}`;
  process.stdout.write(`Fetching ${p.match} CDP... `);

  const res = await fetch(url);
  if (!res.ok) throw new Error(`${p.match}: HTTP ${res.status}`);
  const json = await res.json();

  // Filter to the CDP proper — a LIKE-free exact match can still return e.g.
  // both "Julian CDP" and a similarly named place.
  const match = json.features?.find((f) => /CDP$/.test(f.properties.NAME));
  if (!match) {
    console.log(`NOT FOUND (got: ${json.features?.map((f) => f.properties.NAME).join(', ') || 'nothing'})`);
    continue;
  }

  match.geometry.coordinates = roundCoords(match.geometry.coordinates);
  match.properties = {
    ...match.properties,
    slug: p.slug,
    designation: p.designation,
    designated_year: p.year,
  };
  features.push(match);
  console.log(`ok — ${match.properties.NAME}`);
}

const fc = { type: 'FeatureCollection', features };
const out = join(root, 'app/public/geo/ca-darksky-places.geojson');
writeFileSync(out, JSON.stringify(fc));

console.log(
  `\nWrote app/public/geo/ca-darksky-places.geojson — ${features.length} places, ` +
  `${(JSON.stringify(fc).length / 1024).toFixed(0)} KB`
);
