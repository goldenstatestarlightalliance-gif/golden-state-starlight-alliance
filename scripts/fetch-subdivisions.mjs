// Fetches Census County Subdivisions for California and writes one file per
// county to app/public/geo/subdivisions/.
//
// WHY: incorporated cities cover only a fraction of most counties, so a map
// drawn from cities alone reads as mostly empty — which is not what a county
// looks like. San Diego County's own published maps divide the whole county
// into named subregional areas (Camp Pendleton, Ramona, Palomar-Julian,
// Mountain Empire…), so every part of the county is accounted for.
//
// Census County Subdivisions are the equivalent that exists statewide: they
// tile each county completely, with no gaps, and for San Diego they carry
// almost exactly the same names as the county's own SRA map.
//
// IMPORTANT: these are STATISTICAL areas, not governments. They cannot pass an
// ordinance, so they are drawn as neutral background only — the status colours
// stay on incorporated cities, which are the bodies that actually legislate.
//
// Run: node scripts/fetch-subdivisions.mjs

import { writeFileSync, mkdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const geoDir = join(root, 'app/public/geo');
const outDir = join(geoDir, 'subdivisions');
mkdirSync(outDir, { recursive: true });

const TIGERWEB = 'https://tigerweb.geo.census.gov/arcgis/rest/services/TIGERweb';
const COUSUB_LAYER = 1;

const counties = JSON.parse(readFileSync(join(geoDir, 'ca-counties.geojson'), 'utf8'));

// Same simplification approach as the county boundaries — survey-grade detail
// is wasted on a background layer.
function perpDistance(p, a, b) {
  const [px, py] = p, [ax, ay] = a, [bx, by] = b;
  const dx = bx - ax, dy = by - ay;
  if (dx === 0 && dy === 0) return Math.hypot(px - ax, py - ay);
  const t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy);
  const c = Math.max(0, Math.min(1, t));
  return Math.hypot(px - (ax + c * dx), py - (ay + c * dy));
}

function douglasPeucker(points, tol) {
  if (points.length <= 2) return points;
  let max = 0, idx = 0;
  for (let i = 1; i < points.length - 1; i++) {
    const d = perpDistance(points[i], points[0], points[points.length - 1]);
    if (d > max) { max = d; idx = i; }
  }
  if (max <= tol) return [points[0], points[points.length - 1]];
  return [
    ...douglasPeucker(points.slice(0, idx + 1), tol).slice(0, -1),
    ...douglasPeucker(points.slice(idx), tol),
  ];
}

function simplifyRing(ring, tol) {
  if (ring.length <= 4) return ring;
  let out = douglasPeucker(ring, tol);
  if (out.length < 4) {
    const step = Math.max(1, Math.floor(ring.length / 4));
    out = [ring[0], ring[step], ring[step * 2], ring[0]];
  }
  const [f, l] = [out[0], out[out.length - 1]];
  if (f[0] !== l[0] || f[1] !== l[1]) out.push([f[0], f[1]]);
  return out;
}

const round = (n) => Number(n.toFixed(4));

function simplify(geojson, tol = 0.0008) {
  const walk = (c) => {
    if (typeof c[0][0] === 'number') {
      const s = simplifyRing(c, tol).map(([x, y]) => [round(x), round(y)]);
      const dedup = s.filter((p, i) => i === 0 || p[0] !== s[i - 1][0] || p[1] !== s[i - 1][1]);
      return dedup.length >= 4 ? dedup : s;
    }
    return c.map(walk);
  };
  for (const f of geojson.features) {
    if (f.geometry?.coordinates) f.geometry.coordinates = walk(f.geometry.coordinates);
  }
  return geojson;
}

let totalSubs = 0;
let totalBytes = 0;
let failed = [];

for (const county of counties.features) {
  const fips = county.properties.COUNTY;
  const name = county.properties.BASENAME;

  const params = new URLSearchParams({
    where: `STATE='06' AND COUNTY='${fips}'`,
    outFields: 'GEOID,BASENAME,NAME,COUNTY,COUSUB',
    f: 'geojson',
    outSR: '4326',
    returnGeometry: 'true',
  });

  try {
    const res = await fetch(
      `${TIGERWEB}/Places_CouSub_ConCity_SubMCD/MapServer/${COUSUB_LAYER}/query?${params}`
    );
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const json = await res.json();
    if (!json.features?.length) throw new Error('no features');

    simplify(json);
    const body = JSON.stringify(json);
    writeFileSync(join(outDir, `${fips}.geojson`), body);

    totalSubs += json.features.length;
    totalBytes += body.length;
    process.stdout.write(`${name} ${json.features.length}  `);
  } catch (e) {
    failed.push(`${name}: ${e.message}`);
  }
}

console.log('\n');
console.log(`Wrote ${counties.features.length - failed.length} files to app/public/geo/subdivisions/`);
console.log(`  subdivisions: ${totalSubs}`);
console.log(`  total size:   ${(totalBytes / 1e6).toFixed(2)} MB`);
if (failed.length) console.log(`  FAILED: ${failed.join('; ')}`);
