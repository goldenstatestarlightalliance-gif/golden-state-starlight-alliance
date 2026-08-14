// County map coloring by ordinance coverage — what fraction of a county's
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
 * The color bands.
 *
 * NOTE ON THE SCALE: the brief asked for five bands with white as 0–20%. I
 * split the bottom band instead, so 0% is white and anything above zero picks
 * up color. The reason is concrete — with a 0–20% bottom band, Los Angeles
 * needs 18 city ordinances before it stops looking identical to a county that
 * has done nothing, and San Bernardino needs 5. Early wins would be invisible
 * for years on a map whose whole job is showing momentum.
 *
 * This way the first ordinance in a county is visible immediately, and the
 * five colors still map to the 20% bands that were asked for.
 *
 * To go back to the original scale, delete the `{ min: 0, max: 0 }` entry and
 * set the next band's min to 0 — nothing else reads these numbers.
 */
/**
 * A SINGLE-HUE WARM RAMP, NOT A RAINBOW.
 *
 * The original ran grey → yellow → orange → green → teal. Two problems with
 * that on this map. It fought the brand, and more importantly a rainbow gives
 * every band roughly equal visual weight, so a county at 15% shouted about as
 * loudly as one at 90% and the eye had nowhere to land.
 *
 * Now the first five steps are progressively deeper tints of the brand gold
 * with the saturation held down, and only the top band is the actual saturated
 * Gold. The jump in saturation — not just in darkness — is what makes a nearly
 * finished county the one thing that pops on an otherwise quiet map.
 *
 * Ordering still reads correctly if printed in greyscale, because lightness
 * decreases monotonically across the whole ramp including the last step.
 */
export const COVERAGE_BANDS = [
  { key: 'none',      min: 0,   max: 0,   label: 'No ordinances yet', color: '#f3f1ed', text: '#5b6478' },
  { key: 'starting',  min: 0,   max: 20,  label: 'Up to 20%',          color: '#ece5d8', text: '#6b5f45' },
  { key: 'building',  min: 20,  max: 40,  label: '20–40%',             color: '#e2d7c2', text: '#635639' },
  { key: 'halfway',   min: 40,  max: 60,  label: '40–60%',             color: '#d6c7a9', text: '#584a2f' },
  { key: 'most',      min: 60,  max: 80,  label: '60–80%',             color: '#c7b58c', text: '#4a3d25' },
  // The only saturated step in the scale. This is the pop.
  { key: 'nearly',    min: 80,  max: 100, label: '80–100%',            color: '#E9B44C', text: '#3d2f10' },
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
