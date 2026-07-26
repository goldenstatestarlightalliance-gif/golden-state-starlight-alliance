// Turns data/GoldenStateStarlight_seed_data.json into supabase/seed.sql.
//
// Emitting SQL (rather than driving the Supabase JS client) means seeding never
// needs the service_role / sb_secret_ key — you paste the output into the SQL
// editor, which is already authenticated.
//
// Run: node scripts/generate-seed-sql.mjs

import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const seed = JSON.parse(
  readFileSync(join(root, 'data/GoldenStateStarlight_seed_data.json'), 'utf8')
);

// 3-digit county FIPS for all 58 CA counties. These are the join key to the
// Census TIGER/Line boundary features the map renders, so they have to be exact.
const FIPS = {
  Alameda: '001', Alpine: '003', Amador: '005', Butte: '007', Calaveras: '009',
  Colusa: '011', 'Contra Costa': '013', 'Del Norte': '015', 'El Dorado': '017',
  Fresno: '019', Glenn: '021', Humboldt: '023', Imperial: '025', Inyo: '027',
  Kern: '029', Kings: '031', Lake: '033', Lassen: '035', 'Los Angeles': '037',
  Madera: '039', Marin: '041', Mariposa: '043', Mendocino: '045', Merced: '047',
  Modoc: '049', Mono: '051', Monterey: '053', Napa: '055', Nevada: '057',
  Orange: '059', Placer: '061', Plumas: '063', Riverside: '065',
  Sacramento: '067', 'San Benito': '069', 'San Bernardino': '071',
  'San Diego': '073', 'San Francisco': '075', 'San Joaquin': '077',
  'San Luis Obispo': '079', 'San Mateo': '081', 'Santa Barbara': '083',
  'Santa Clara': '085', 'Santa Cruz': '087', Shasta: '089', Sierra: '091',
  Siskiyou: '093', Solano: '095', Sonoma: '097', Stanislaus: '099',
  Sutter: '101', Tehama: '103', Trinity: '105', Tulare: '107', Tuolumne: '109',
  Ventura: '111', Yolo: '113', Yuba: '115',
};

const q = (v) =>
  v === null || v === undefined || v === '' ? 'null' : `'${String(v).replace(/'/g, "''")}'`;

const slug = (s) =>
  s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

const out = [];
const w = (s = '') => out.push(s);

w('-- GENERATED FILE — do not edit by hand.');
w('-- Regenerate with: node scripts/generate-seed-sql.mjs');
w('-- Source: data/GoldenStateStarlight_seed_data.json');
w('--');
w('-- Idempotent: safe to re-run. Counties/cities upsert on their natural keys,');
w('-- and every county starts at not_started (spec §4) — real progress is');
w('-- recorded through the app so it lands in the audit log.');
w('--');
w('-- No begin/commit here: apply-all.sql wraps schema + RLS + functions + seed');
w('-- in one outer transaction, and a nested begin would silently commit it.');
w();

// --- Priority tiers, keyed by county ---------------------------------------
// priority_master_list rows are "County County -- City" strings; we only need
// the county half to attach the tier and its rationale.
const priorityByCounty = new Map();
for (const row of seed.priority_master_list ?? []) {
  const countyPart = String(row.county_city).split('--')[0].trim();
  const name = countyPart.replace(/\s+County$/i, '').trim();
  if (!priorityByCounty.has(name)) priorityByCounty.set(name, row);
}

// --- Counties ---------------------------------------------------------------
w('-- 58 California counties');
w('insert into counties (fips, name, slug, region, priority, priority_reason, rationale, hook, confidence, geo_level) values');

const countyNames = Object.keys(seed.counties_and_cities);
const missingFips = countyNames.filter((n) => !FIPS[n]);
if (missingFips.length) {
  throw new Error(`No FIPS mapping for: ${missingFips.join(', ')}`);
}
if (countyNames.length !== 58) {
  console.warn(`! Expected 58 counties in seed data, found ${countyNames.length}`);
}

const countyRows = countyNames.map((name) => {
  const c = seed.counties_and_cities[name];
  const p = priorityByCounty.get(name);
  return `  (${q(FIPS[name])}, ${q(name)}, ${q(slug(name))}, ${q(c.region)}, ` +
    `${p?.priority ?? 'null'}, ${q(p?.priority_reason)}, ${q(c.rationale)}, ` +
    `${q(c.hook)}, ${q(c.confidence)}, ${q(c.geo_level)})`;
});
w(countyRows.join(',\n') + ';');
w();

// --- Priority cities --------------------------------------------------------
// NOTE: this is the 1-2 outreach target cities per county from the research,
// NOT the full ~482 incorporated CA cities. The rest are loaded separately from
// the Census Places file by scripts/fetch-boundaries.mjs.
w('-- Priority outreach cities (from research; ~63 rows, not the full 482)');
w('insert into cities (county_id, name, slug, is_priority) values');
const cityRows = [];
for (const [countyName, c] of Object.entries(seed.counties_and_cities)) {
  for (const city of c.cities ?? []) {
    cityRows.push(
      `  ((select id from counties where fips = ${q(FIPS[countyName])}), ` +
      `${q(city)}, ${q(slug(city))}, true)`
    );
  }
}
w(cityRows.join(',\n'));
w('on conflict (county_id, name) do update set is_priority = true;');
w();

// --- Per-county outreach plan -----------------------------------------------
w('-- Researched outreach plan per county (prof + student org, method, deadline).');
w('-- Contact strings preserve the fact-check corrections from the research.');
w('insert into county_outreach (county_id, method, deadline, prof_org, prof_contact, student_org, student_contact) values');
const outreachRows = [];
for (const [name, row] of priorityByCounty) {
  if (!FIPS[name]) continue;
  outreachRows.push(
    `  ((select id from counties where fips = ${q(FIPS[name])}), ${q(row.method)}, ` +
    `${q(row.deadline)}, ${q(row.prof_org)}, ${q(row.prof_contact)}, ` +
    `${q(row.student_org)}, ${q(row.student_contact)})`
  );
}
w(outreachRows.join(',\n'));
w('on conflict (county_id) do update set');
w('  method = excluded.method, deadline = excluded.deadline,');
w('  prof_org = excluded.prof_org, prof_contact = excluded.prof_contact,');
w('  student_org = excluded.student_org, student_contact = excluded.student_contact,');
w('  updated_at = now();');
w();

// --- Council contacts -------------------------------------------------------
const councilRows = [];
for (const [countyName, c] of Object.entries(seed.counties_and_cities)) {
  for (const p of c.council ?? []) {
    councilRows.push(
      `  ((select id from counties where fips = ${q(FIPS[countyName])}), ` +
      `${q(p.name)}, ${q(p.title)}, ${q(p.evidence)}, ${q(p.source)})`
    );
  }
}
if (councilRows.length) {
  w('-- Researched council members / local champions');
  w('insert into council_contacts (county_id, name, title, evidence, source_url) values');
  w(councilRows.join(',\n') + ';');
  w();
}

// --- Organizations ----------------------------------------------------------
// region_orgs lists partner orgs per region. Flatten to a unique org list, then
// link each org to every county in its region via county_org_participation.
const KIND = { sierra: 'sierra_club', darksky: 'darksky', audubon: 'audubon', astro: 'astronomy', student: 'student' };
const orgs = new Map(); // name -> { kind, regions:Set }

for (const [region, set] of Object.entries(seed.region_orgs ?? {})) {
  for (const [key, val] of Object.entries(set)) {
    const names = Array.isArray(val) ? val : [val];
    for (const name of names) {
      if (!name) continue;
      if (!orgs.has(name)) orgs.set(name, { kind: KIND[key] ?? 'other', regions: new Set() });
      orgs.get(name).regions.add(region);
    }
  }
}

w('-- Partner organizations, plus the "general public" umbrella org.');
w('-- The umbrella org is a normal row with no special casing (spec §3).');
w('insert into organizations (name, slug, kind, region, is_umbrella, approved) values');
const orgRows = [
  `  ('California Starlight Volunteers', 'california-starlight-volunteers', 'general_public', null, true, true)`,
];
for (const [name, meta] of orgs) {
  const region = meta.regions.size === 1 ? [...meta.regions][0] : null;
  orgRows.push(`  (${q(name)}, ${q(slug(name))}, ${q(meta.kind)}::org_kind, ${q(region)}, false, true)`);
}
w(orgRows.join(',\n'));
w('on conflict (name) do nothing;');
w();

// Link orgs to the counties in their region.
const countyRegion = Object.fromEntries(
  Object.entries(seed.counties_and_cities).map(([n, c]) => [n, c.region])
);
const participationRows = [];
for (const [name, meta] of orgs) {
  for (const region of meta.regions) {
    for (const [countyName, r] of Object.entries(countyRegion)) {
      if (r !== region) continue;
      participationRows.push(
        `  ((select id from counties where fips = ${q(FIPS[countyName])}), ` +
        `(select id from organizations where name = ${q(name)}))`
      );
    }
  }
}
w('-- Which orgs cover which counties (drives map popups + county credit lists)');
w('insert into county_org_participation (county_id, org_id) values');
w(participationRows.join(',\n'));
w('on conflict (county_id, org_id) do nothing;');
w();

// --- Email templates --------------------------------------------------------
w('-- Per-county outreach email drafts (members-only under RLS)');
w('insert into email_templates (county_id, body) values');
const tmplRows = Object.entries(seed.email_templates_by_county ?? {})
  .filter(([name]) => FIPS[name])
  .map(([name, body]) =>
    `  ((select id from counties where fips = ${q(FIPS[name])}), ${q(body)})`);
w(tmplRows.join(',\n'));
w('on conflict (county_id) do update set body = excluded.body, updated_at = now();');
w();

// --- Chat channels ----------------------------------------------------------
w('-- 1 statewide channel + 1 per county = 59 total (spec §5)');
w(`insert into channels (kind, county_id, name, slug)`);
w(`values ('statewide', null, 'California Statewide', 'statewide')`);
w('on conflict (slug) do nothing;');
w();
w('insert into channels (kind, county_id, name, slug)');
w("select 'county', id, name || ' County', slug from counties");
w('on conflict (slug) do nothing;');
w();


const sql = out.join('\n');
writeFileSync(join(root, 'supabase/seed.sql'), sql);

console.log('Wrote supabase/seed.sql');
console.log(`  counties:      ${countyRows.length}`);
console.log(`  cities:        ${cityRows.length}  (priority targets only)`);
console.log(`  outreach plans:${outreachRows.length}`);
console.log(`  council:       ${councilRows.length}  (only 2 counties have named champions in the research)`);
console.log(`  organizations: ${orgRows.length}`);
console.log(`  participation: ${participationRows.length}`);
console.log(`  email drafts:  ${tmplRows.length}`);
