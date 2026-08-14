// Sweep every California city hosted on Municode for outdoor lighting law.
//
// WHY THIS EXISTS
//
// 476 of 483 California cities had never been checked for an existing
// ordinance, and the map therefore told visitors those cities had nothing.
// We had already been wrong about that four separate times — San Diego (1997),
// Yucca Valley (1998), Palm Desert, Big Bear Lake — every one missed because
// the chapter is titled "Lighting Standards" or "Outdoor Lighting
// Requirements" rather than "dark sky".
//
// Checking by hand was the blocker: Municode returns 403 to a plain fetch, so
// it looked like it needed a human per city. It does not — it needs a browser
// User-Agent. With that header its public search API answers normally.
//
// WHAT IT DOES NOT DO
//
// It does not decide whether a city has a qualifying ordinance. It produces a
// ranked candidate list for a human to read. The distinction matters: Colusa
// returns three hits for "outdoor lighting" and all three sit inside a
// CANNABIS DISPENSARIES chapter — a real keyword match and completely
// irrelevant. Marking that city "passed" automatically would put a false
// claim on a public advocacy site.
//
// Usage:  node scripts/scan-municode.mjs [--out candidates.json] [--delay 250]

import { writeFileSync } from 'node:fs';

const UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/131.0 Safari/537.36';

const args = process.argv.slice(2);
const argOf = (flag, fallback) => {
  const i = args.indexOf(flag);
  return i >= 0 && args[i + 1] ? args[i + 1] : fallback;
};

const OUT = argOf('--out', 'data/municode-candidates.json');
// Courtesy throttle. This is a free public API belonging to someone else and
// there is no rush — the whole sweep still finishes in a couple of minutes.
const DELAY = Number(argOf('--delay', 250));

const TERMS = ['outdoor lighting', 'light pollution', 'dark sky'];

// A hit is STRONG when a lighting phrase appears in the chapter or section
// title, and WEAK when it appears only in the body text. The cannabis case is
// exactly a weak hit, and separating the two is the whole value of the scan.
const TITLE_SIGNAL =
  /\b(outdoor light|exterior light|light pollution|dark sky|darksky|lighting standard|lighting regulation|lighting requirement|glare|illumination)/i;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function getJSON(url) {
  const res = await fetch(url, {
    headers: { 'User-Agent': UA, Accept: 'application/json' },
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.json();
}

async function searchCity(clientId, term) {
  const url =
    'https://api.municode.com/search' +
    `?stateId=5&clientId=${clientId}` +
    `&searchText=${encodeURIComponent(term)}` +
    '&searchMode=CLIENTMODE&contentTypeId=CODES';
  return getJSON(url);
}

const main = async () => {
  console.log('Fetching California client list…');
  const clients = await getJSON(
    'https://api.municode.com/Clients/stateAbbr?stateAbbr=CA'
  );
  console.log(`  ${clients.length} California jurisdictions on Municode\n`);

  const results = [];

  for (const [i, c] of clients.entries()) {
    const row = {
      clientId: c.ClientID,
      name: c.ClientName,
      strong: [],
      weak: 0,
      error: null,
    };

    for (const term of TERMS) {
      try {
        const data = await searchCity(c.ClientID, term);
        for (const hit of data.Hits ?? []) {
          const chapter = (hit.Ancestors ?? [])
            .map((a) => a.Title)
            .join(' › ');
          const where = `${chapter} › ${hit.Title ?? ''}`;

          if (TITLE_SIGNAL.test(where)) {
            // Deduplicate: the same section matches several search terms.
            if (!row.strong.some((s) => s.nodeId === hit.NodeId)) {
              row.strong.push({ nodeId: hit.NodeId, where: where.trim() });
            }
          } else {
            row.weak += 1;
          }
        }
      } catch (err) {
        row.error = err.message;
      }
      await sleep(DELAY);
    }

    results.push(row);

    const flag = row.strong.length ? `★ ${row.strong.length}` : row.error ? '!' : '·';
    console.log(
      `[${String(i + 1).padStart(3)}/${clients.length}] ${flag} ${c.ClientName}`
    );
  }

  const candidates = results
    .filter((r) => r.strong.length)
    .sort((a, b) => b.strong.length - a.strong.length);

  writeFileSync(OUT, JSON.stringify({ scanned: results.length, candidates }, null, 2));

  console.log(`\n${'-'.repeat(60)}`);
  console.log(`Scanned:    ${results.length} jurisdictions`);
  console.log(`Candidates: ${candidates.length} with a lighting phrase in a heading`);
  console.log(`Errors:     ${results.filter((r) => r.error).length}`);
  console.log(`Written to: ${OUT}`);
  console.log(
    '\nThese are CANDIDATES. Each still needs its chapter read before any\n' +
      'city is marked passed — a heading match is evidence, not a finding.'
  );
};

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
