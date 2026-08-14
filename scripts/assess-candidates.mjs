// ⚠ THIS APPROACH DOES NOT WORK. Kept as a record of a dead end so it is not
// tried again.
//
// It returned 65 "qualifying" out of 66 candidates, which is the tell: a test
// that passes almost everything is not testing anything. The reason is that
// the Municode search API is CLIENT-scoped, not CHAPTER-scoped — every probe
// below searches the entire municipal code rather than the lighting chapter.
//
// Control, run against two jurisdictions that are NOT candidates and have no
// lighting chapter at all:
//
//     Colusa   (1733)  -> 1 hit for "shielded"
//     Williams (17011) -> 1 hit for "shielded"
//
// "shielded" and "color temperature" appear in electrical, building and sign
// provisions all over a code. So a hit proves nothing about the lighting
// chapter, and data/municode-assessed.json should NOT be trusted or applied.
//
// THE FIX: fetch the actual content of the chapter NodeIds that
// scan-municode.mjs already captured, and test the provisions against that
// text instead of against a code-wide search. The NodeIds are in
// data/municode-candidates.json and are the right starting point.
//
// ---------------------------------------------------------------------------
//
// Original intent, which still stands once the scoping is fixed:
//
// Second pass over the Municode candidates: does the chapter actually DO
// anything, or is it just titled as though it does?
//
// The first scan (scan-municode.mjs) found 66 jurisdictions with a lighting
// phrase in a chapter heading. A heading is not a finding — Los Angeles taught
// us that directly. LAMC 93.0117 is titled "Outdoor Lighting Affecting
// Residential Property" and would sail through a heading scan, but it is a
// light-trespass rule with full-cutoff language for tennis courts and nothing
// else. Recorded as reviewed and NOT passed.
//
// So this pass searches each candidate for the provisions that decide the
// question, using the project's existing standard: a city counts when its code
// requires SHIELDING or caps COLOR TEMPERATURE. Everything else — curfews,
// lumen caps, trespass limits — is recorded as supporting detail because it
// changes whether the ask is a new ordinance or an amendment.
//
// Output is still a reviewed list for a human, not a database write. It just
// narrows 66 headings down to the ones with real provisions behind them.
//
// Usage: node scripts/assess-candidates.mjs

import { readFileSync, writeFileSync } from 'node:fs';

const UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/131.0 Safari/537.36';

// Grouped by what each phrase proves, not just by keyword.
const PROBES = [
  { key: 'shielded',  weight: 'qualifying', terms: ['fully shielded', 'full cutoff', 'full cut-off'] },
  { key: 'shielding', weight: 'qualifying', terms: ['shielded'] },
  { key: 'cct',       weight: 'qualifying', terms: ['color temperature', 'kelvin'] },
  { key: 'curfew',    weight: 'supporting', terms: ['curfew'] },
  { key: 'lumens',    weight: 'supporting', terms: ['lumens'] },
  { key: 'trespass',  weight: 'supporting', terms: ['light trespass'] },
];

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function hits(clientId, term) {
  const url =
    'https://api.municode.com/search' +
    `?stateId=5&clientId=${clientId}` +
    `&searchText=${encodeURIComponent(term)}` +
    '&searchMode=CLIENTMODE&contentTypeId=CODES';
  try {
    const res = await fetch(url, { headers: { 'User-Agent': UA, Accept: 'application/json' } });
    if (!res.ok) return 0;
    const d = await res.json();
    return d.NumberOfHits ?? 0;
  } catch {
    return 0;
  }
}

const main = async () => {
  const { candidates } = JSON.parse(
    readFileSync('data/municode-candidates.json', 'utf8')
  );
  console.log(`Assessing ${candidates.length} candidates…\n`);

  const out = [];

  for (const [i, c] of candidates.entries()) {
    const found = {};
    for (const probe of PROBES) {
      let n = 0;
      for (const t of probe.terms) {
        n += await hits(c.clientId, t);
        await sleep(120);
      }
      if (n) found[probe.key] = n;
    }

    const qualifying = PROBES
      .filter((p) => p.weight === 'qualifying' && found[p.key])
      .map((p) => p.key);

    const row = {
      name: c.name,
      clientId: c.clientId,
      chapter: c.strong[0]?.where ?? '',
      qualifies: qualifying.length > 0,
      qualifying,
      signals: found,
    };
    out.push(row);

    console.log(
      `[${String(i + 1).padStart(2)}/${candidates.length}] ` +
        `${row.qualifies ? '✔' : '·'} ${c.name.padEnd(26)} ` +
        `${qualifying.join(',') || '—'}`
    );
  }

  const qualifying = out.filter((r) => r.qualifies);
  writeFileSync(
    'data/municode-assessed.json',
    JSON.stringify({ assessed: out.length, qualifying }, null, 2)
  );

  console.log(`\n${'-'.repeat(60)}`);
  console.log(`Assessed:   ${out.length}`);
  console.log(`Qualifying: ${qualifying.length} (shielding and/or color temperature)`);
  console.log('Written to: data/municode-assessed.json');
};

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
