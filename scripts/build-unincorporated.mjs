// Builds app/public/geo/unincorporated/<countyFips>.geojson — the named
// unincorporated regions of each California county.
//
// WHY THIS EXISTS
// San Diego County publishes a map of Community Planning Areas: the county
// divided into named regions (Fallbrook, Ramona, Julian, Borrego Springs,
// Mountain Empire…) covering everything OUTSIDE the incorporated cities. That
// is the right way to show a California county, because cities are a minority
// of the land — 15% of San Diego — and the rest is real communities with no
// city government.
//
// Those planning areas are San Diego's own dataset and have no statewide
// equivalent. Census County Subdivisions do tile every county and carry nearly
// the same names, but they cover the WHOLE county including the cities — which
// is why an earlier attempt to use them raw looked like a second, wrong set of
// city boundaries ("San Diego" the subdivision vs "San Diego" the city).
//
// So: subtract the cities from the subdivisions. What is left is exactly the
// unincorporated land, split into named regions, for all 58 counties.
//
// Run: node scripts/build-unincorporated.mjs   (after fetch-boundaries + fetch-subdivisions)

import { readFileSync, writeFileSync, mkdirSync, readdirSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import difference from '@turf/difference';
import union from '@turf/union';
import { featureCollection } from '@turf/helpers';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const geoDir = join(root, 'app/public/geo');
const outDir = join(geoDir, 'unincorporated');
mkdirSync(outDir, { recursive: true });

const counties = JSON.parse(readFileSync(join(geoDir, 'ca-counties.geojson'), 'utf8'));

// turf 7 takes a FeatureCollection rather than two positional arguments.
// Wrapping them keeps the call sites readable and the version detail in one
// place. Failures are counted, not swallowed — an earlier version caught them
// silently and produced output that looked plausible but had subtracted
// nothing at all.
let unionFailures = 0, differenceFailures = 0;

const unionOf = (a, b) => {
  try {
    return union(featureCollection([a, b])) ?? a;
  } catch {
    unionFailures++;
    return a;
  }
};

const differenceOf = (subject, clip) => {
  try {
    // Returns null when the subject is entirely covered by the clip.
    return difference(featureCollection([subject, clip]));
  } catch {
    differenceFailures++;
    return subject;
  }
};

let totalRegions = 0, totalBytes = 0, skipped = [], noCities = [];

for (const county of counties.features) {
  const fips = county.properties.COUNTY;
  const name = county.properties.BASENAME;

  const subPath = join(geoDir, 'subdivisions', `${fips}.geojson`);
  if (!existsSync(subPath)) { skipped.push(`${name} (no subdivisions)`); continue; }

  const subs = JSON.parse(readFileSync(subPath, 'utf8'));
  const placePath = join(geoDir, 'places', `${fips}.geojson`);

  // Counties with no incorporated cities (Alpine, Mariposa, Trinity) need no
  // subtraction — every subdivision is already entirely unincorporated.
  let cityUnion = null;
  if (existsSync(placePath)) {
    const places = JSON.parse(readFileSync(placePath, 'utf8'));
    for (const p of places.features) {
      cityUnion = cityUnion ? unionOf(cityUnion, p) : p;
    }
  } else {
    noCities.push(name);
  }

  const regions = [];
  for (const sub of subs.features) {
    let geom = sub;
    if (cityUnion) geom = differenceOf(sub, cityUnion);
    // A subdivision entirely covered by cities disappears, which is correct —
    // it has no unincorporated land left. San Francisco is the clean example.
    if (!geom) continue;

    geom.properties = {
      GEOID: sub.properties.GEOID,
      NAME: sub.properties.BASENAME,
      COUNTY: fips,
    };
    regions.push(geom);
  }

  const fc = featureCollection(regions);
  const body = JSON.stringify(fc);
  writeFileSync(join(outDir, `${fips}.geojson`), body);

  totalRegions += regions.length;
  totalBytes += body.length;
  process.stdout.write(`${name} ${regions.length}  `);
}

console.log('\n');
console.log(`Wrote ${counties.features.length - skipped.length} files to app/public/geo/unincorporated/`);
console.log(`  regions:    ${totalRegions}`);
console.log(`  total size: ${(totalBytes / 1e6).toFixed(2)} MB`);
if (noCities.length) console.log(`  no incorporated cities: ${noCities.join(', ')}`);
if (skipped.length) console.log(`  SKIPPED: ${skipped.join('; ')}`);
if (unionFailures || differenceFailures) {
  console.log(`  ! geometry failures — union ${unionFailures}, difference ${differenceFailures}`);
}
