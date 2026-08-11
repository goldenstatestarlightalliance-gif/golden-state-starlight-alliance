// Downloads California county and incorporated-place boundaries from the US
// Census Bureau and writes them to app/public/geo/ as GeoJSON.
//
// Source: Census TIGERweb ArcGIS REST services. Same underlying TIGER/Line data
// the spec calls for (§4), but served as GeoJSON directly, which avoids a
// shapefile conversion step. Public domain, no API key.
//
// Run: node scripts/fetch-boundaries.mjs
//
// The output lands in app/public/geo/ and IS committed — the files are small
// once simplified, and committing them means the site builds on Netlify without
// depending on census.gov being reachable at deploy time.

import { writeFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const outDir = join(root, 'app/public/geo');
mkdirSync(outDir, { recursive: true });

const CA = '06';
const TIGERWEB = 'https://tigerweb.geo.census.gov/arcgis/rest/services/TIGERweb';

async function fetchLayer(label, service, layerId, where, outFields) {
  const params = new URLSearchParams({
    where,
    outFields,
    f: 'geojson',
    outSR: '4326',
    returnGeometry: 'true',
  });
  const url = `${TIGERWEB}/${service}/MapServer/${layerId}/query?${params}`;

  process.stdout.write(`Fetching ${label}... `);
  const res = await fetch(url);
  if (!res.ok) throw new Error(`${label}: HTTP ${res.status} ${res.statusText}`);

  const json = await res.json();
  if (json.error) throw new Error(`${label}: ${JSON.stringify(json.error)}`);
  if (!json.features?.length) throw new Error(`${label}: no features returned`);

  console.log(`${json.features.length} features`);
  return json;
}

// TIGER geometry is survey-grade — vastly more detail than a web map can draw.
// Raw, the two layers are ~14 MB, which is a slow first paint on the flagship
// public page. Two passes bring that down by roughly 10x:
//
//   1. Douglas-Peucker to drop vertices that don't change the visible outline.
//   2. Coordinate rounding to cut the digits each surviving vertex costs.
//
// Rounding alone is not enough — it shortens numbers but keeps every vertex.

// Perpendicular distance from p to the line ab, in degrees.
function perpDistance(p, a, b) {
  const [px, py] = p, [ax, ay] = a, [bx, by] = b;
  const dx = bx - ax, dy = by - ay;
  if (dx === 0 && dy === 0) return Math.hypot(px - ax, py - ay);
  const t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy);
  const clamped = Math.max(0, Math.min(1, t));
  return Math.hypot(px - (ax + clamped * dx), py - (ay + clamped * dy));
}

function douglasPeucker(points, tolerance) {
  if (points.length <= 2) return points;

  let maxDist = 0, index = 0;
  for (let i = 1; i < points.length - 1; i++) {
    const d = perpDistance(points[i], points[0], points[points.length - 1]);
    if (d > maxDist) { maxDist = d; index = i; }
  }

  if (maxDist <= tolerance) return [points[0], points[points.length - 1]];

  return [
    ...douglasPeucker(points.slice(0, index + 1), tolerance).slice(0, -1),
    ...douglasPeucker(points.slice(index), tolerance),
  ];
}

// A ring must keep at least 4 points (3 distinct + closing point) to stay a
// valid polygon, so heavy simplification never destroys a small city outline.
function simplifyRing(ring, tolerance) {
  if (ring.length <= 4) return ring;
  let out = douglasPeucker(ring, tolerance);
  if (out.length < 4) {
    const step = Math.max(1, Math.floor(ring.length / 4));
    out = [ring[0], ring[step], ring[step * 2], ring[0]];
  }
  // Re-close the ring if simplification moved the endpoint.
  const [f, l] = [out[0], out[out.length - 1]];
  if (f[0] !== l[0] || f[1] !== l[1]) out.push([f[0], f[1]]);
  return out;
}

function simplify(geojson, { tolerance = 0.002, decimals = 4 } = {}) {
  const round = (n) => Number(n.toFixed(decimals));

  // Walk down to ring level (arrays of [x,y]) whatever the geometry nesting.
  const walk = (coords, depth = 0) => {
    if (typeof coords[0][0] === 'number') {
      const simplified = simplifyRing(coords, tolerance);
      // Rounding can create consecutive duplicates; drop them.
      const rounded = simplified.map(([x, y]) => [round(x), round(y)]);
      const deduped = rounded.filter(
        (p, i) => i === 0 || p[0] !== rounded[i - 1][0] || p[1] !== rounded[i - 1][1]
      );
      return deduped.length >= 4 ? deduped : rounded;
    }
    return coords.map((c) => walk(c, depth + 1));
  };

  for (const f of geojson.features) {
    if (f.geometry?.coordinates) f.geometry.coordinates = walk(f.geometry.coordinates);
  }
  return geojson;
}

const countVertices = (geojson) => {
  let n = 0;
  const walk = (c) => {
    if (typeof c[0] === 'number') n++;
    else c.forEach(walk);
  };
  for (const f of geojson.features) if (f.geometry?.coordinates) walk(f.geometry.coordinates);
  return n;
};

const write = (name, data) => {
  const path = join(outDir, name);
  writeFileSync(path, JSON.stringify(data));
  const mb = (JSON.stringify(data).length / 1e6).toFixed(2);
  console.log(`  -> app/public/geo/${name} (${mb} MB)`);
};

// Counties: layer 1 of the State_County service.
const counties = await fetchLayer(
  'CA counties',
  'State_County',
  1,
  `STATE='${CA}'`,
  'GEOID,NAME,BASENAME,STATE,COUNTY'
);
const countyVerts = countVertices(counties);
// Same tolerance and precision as the places layer below.
//
// These two layers are drawn on top of each other on every county page, and
// they share real edges — a coastal city's seaward boundary IS the county's.
// Simplifying counties 4x more coarsely (0.002 vs 0.0005) made those shared
// edges disagree by a few hundred metres, so cities visibly failed to meet the
// county outline along the coast. Matching tolerances keeps shared edges
// identical.
write('ca-counties.geojson', simplify(counties, { tolerance: 0.0005, decimals: 5 }));
console.log(`     vertices ${countyVerts} -> ${countVertices(counties)}`);

// Incorporated places: layer 4 of the Places service. This is where the full
// ~482-city list actually comes from — the research JSON only carries the 63
// priority outreach targets.
const places = await fetchLayer(
  'CA incorporated places',
  'Places_CouSub_ConCity_SubMCD',
  4,
  `STATE='${CA}'`,
  'GEOID,NAME,BASENAME,STATE,PLACE'
);
const placeVerts = countVertices(places);
// Tighter tolerance (~50m): county pages zoom in far enough to see city shape.
simplify(places, { tolerance: 0.0005, decimals: 5 });
console.log(`     vertices ${placeVerts} -> ${countVertices(places)}`);

// Split places into one file per county so a county page downloads only its own
// cities instead of all 483. TIGERweb place records carry no county field
// (places can straddle county lines), so assign each to the county whose
// polygon contains its centroid.
const centroid = (geom) => {
  let sx = 0, sy = 0, n = 0;
  const walk = (c) => {
    if (typeof c[0] === 'number') { sx += c[0]; sy += c[1]; n++; }
    else c.forEach(walk);
  };
  walk(geom.coordinates);
  return [sx / n, sy / n];
};

// Ray casting against every ring of a (Multi)Polygon.
const contains = (geom, [x, y]) => {
  const polys = geom.type === 'MultiPolygon' ? geom.coordinates : [geom.coordinates];
  for (const poly of polys) {
    let inside = false;
    for (const ring of poly) {
      for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
        const [xi, yi] = ring[i], [xj, yj] = ring[j];
        if ((yi > y) !== (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) {
          inside = !inside;
        }
      }
    }
    if (inside) return true;
  }
  return false;
};

// Evenly sample up to `n` vertices from a geometry.
const sampleVertices = (geom, n = 40) => {
  const all = [];
  const walk = (c) => {
    if (typeof c[0] === 'number') all.push(c);
    else c.forEach(walk);
  };
  walk(geom.coordinates);
  if (all.length <= n) return all;
  const step = all.length / n;
  return Array.from({ length: n }, (_, i) => all[Math.floor(i * step)]);
};

const byCounty = new Map();
const unassigned = [];
for (const place of places.features) {
  // Centroid alone is wrong for places whose polygon spans open water: San
  // Francisco's includes the Farallon Islands ~30mi offshore, which drags its
  // centroid into the Pacific. A single fallback vertex is worse still — it can
  // be one of the islands and land in a neighbouring county's water.
  //
  // So: vote. Sample vertices around the outline and take the county that
  // contains the most of them. The mainland bulk of a place always outvotes an
  // offshore appendage.
  const votes = new Map();
  for (const v of sampleVertices(place.geometry)) {
    const county = counties.features.find((f) => contains(f.geometry, v));
    if (county) {
      const fips = county.properties.COUNTY;
      votes.set(fips, (votes.get(fips) ?? 0) + 1);
    }
  }

  if (!votes.size) { unassigned.push(place.properties.BASENAME); continue; }
  const [fips] = [...votes.entries()].sort((a, b) => b[1] - a[1])[0];
  if (!byCounty.has(fips)) byCounty.set(fips, []);
  byCounty.get(fips).push(place);
}

mkdirSync(join(outDir, 'places'), { recursive: true });
for (const [fips, features] of byCounty) {
  writeFileSync(
    join(outDir, 'places', `${fips}.geojson`),
    JSON.stringify({ type: 'FeatureCollection', features })
  );
}

const totalPlaceBytes = [...byCounty.values()].reduce(
  (n, f) => n + JSON.stringify(f).length, 0);

console.log(`  -> app/public/geo/places/*.geojson (${byCounty.size} files, ` +
  `${(totalPlaceBytes / 1e6).toFixed(2)} MB total, ` +
  `largest ${(Math.max(...[...byCounty.values()].map(f => JSON.stringify(f).length)) / 1e3).toFixed(0)} KB)`);
if (unassigned.length) {
  console.log(`  ! ${unassigned.length} place(s) unassigned: ${unassigned.join(', ')}`);
}

console.log(`\nDone. ${counties.features.length} counties, ${places.features.length} places.`);
