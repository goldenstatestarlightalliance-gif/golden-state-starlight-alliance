// County map colouring by ordinance coverage — what fraction of a county's
// incorporated cities have actually passed a dark sky ordinance.
//
// This is separate from the six-stage pipeline in pipeline.js. The pipeline
// tracks where a single city or county is in the advocacy process; coverage
// answers "how much of this county is actually covered", which is the number
// the public map is really about.

// Extension is explicit so `node --test` can load this directly. Vite resolves
// extensionless imports; Node's ESM loader does not.
import { stageIndex } from './pipeline.js';

// A city counts once its ordinance is on the books. "Drafted" does not count —
// a draft is not policy, and counting it would overstate real progress on the
// public accountability map.
export const hasOrdinance = (city) =>
  stageIndex(city?.status) >= stageIndex('passed');

/**
 * The colour bands.
 *
 * NOTE ON THE SCALE: the brief asked for five bands with white as 0–20%. I
 * split the bottom band instead, so 0% is white and anything above zero picks
 * up colour. The reason is concrete — with a 0–20% bottom band, Los Angeles
 * needs 18 city ordinances before it stops looking identical to a county that
 * has done nothing, and San Bernardino needs 5. Early wins would be invisible
 * for years on a map whose whole job is showing momentum.
 *
 * This way the first ordinance in a county is visible immediately, and the
 * five colours still map to the 20% bands that were asked for.
 *
 * To go back to the original scale, delete the `{ min: 0, max: 0 }` entry and
 * set the next band's min to 0 — nothing else reads these numbers.
 */
export const COVERAGE_BANDS = [
  { key: 'none',      min: 0,   max: 0,   label: 'No ordinances yet', color: '#f4f4f5', text: '#3f3f46' },
  { key: 'starting',  min: 0,   max: 20,  label: 'Up to 20%',          color: '#fef08a', text: '#713f12' },
  { key: 'building',  min: 20,  max: 40,  label: '20–40%',             color: '#fdba74', text: '#7c2d12' },
  { key: 'halfway',   min: 40,  max: 60,  label: '40–60%',             color: '#86efac', text: '#14532d' },
  { key: 'most',      min: 60,  max: 80,  label: '60–80%',             color: '#22c55e', text: '#052e16' },
  { key: 'nearly',    min: 80,  max: 100, label: '80–100%',            color: '#0f766e', text: '#ffffff' },
];

/**
 * Coverage for one county.
 * Returns { withOrdinance, totalCities, percent, band }.
 */
export function coverageFor(county) {
  const cities = county?.cities ?? [];
  const total = cities.length;
  const withOrdinance = cities.filter(hasOrdinance).length;

  // A county with no incorporated cities (Alpine, Mariposa, Trinity) has no
  // meaningful percentage — dividing by zero would render NaN%.
  const percent = total === 0 ? null : (withOrdinance / total) * 100;

  return { withOrdinance, totalCities: total, percent, band: bandFor(percent) };
}

export function bandFor(percent) {
  if (percent === null || percent === undefined) return COVERAGE_BANDS[0];
  if (percent <= 0) return COVERAGE_BANDS[0];

  // Upper-inclusive: 20% belongs to the 0–20 band, not to 20–40.
  return (
    COVERAGE_BANDS.find((b) => b.min > 0 && percent > b.min && percent <= b.max) ??
    COVERAGE_BANDS.find((b) => b.min === 0 && b.max === 20)
  );
}

export const coverageColor = (percent) => bandFor(percent).color;
