// The fixed six-stage advocacy pipeline (spec §4).
//
// Order here is authoritative: it drives sorting, progress bars, and the map
// color ramp. It must stay in sync with the progress_stage enum in
// supabase/migrations/0001_schema.sql.

// Matches the warm ramp in lib/coverage.js rather than running its own
// rainbow. The four working stages are quiet tints so that the two stages
// that represent an actual result — Passed and Enforced — are the only things
// that carry weight on a county map.
export const STAGES = [
  {
    key: 'not_started',
    label: 'Not Started',
    // Counties default to neutral and only take on color as they progress,
    // per the founder's instruction that color is applied by status, not
    // baked into the base map.
    color: '#f3f1ed',
    text: '#5b6478',
  },
  { key: 'contacted',          label: 'Contacted',          color: '#ece5d8', text: '#6b5f45' },
  { key: 'meeting_scheduled',  label: 'Meeting Scheduled',  color: '#e2d7c2', text: '#635639' },
  { key: 'ordinance_drafted',  label: 'Ordinance Drafted',  color: '#d6c7a9', text: '#584a2f' },
  // Brand Gold — the first stage that means the work landed, and the first
  // that is allowed to shout.
  { key: 'passed',             label: 'Passed',             color: '#E9B44C', text: '#3d2f10' },
  // A distinct "done and verified" tier beyond Passed. Ink rather than a
  // deeper gold: Enforced is rare and should be unmistakable, and the brand's
  // own ground is the strongest mark available without inventing a colour.
  { key: 'enforced',           label: 'Enforced',           color: '#0B1226', text: '#ffffff' },
];

const BY_KEY = Object.fromEntries(STAGES.map((s) => [s.key, s]));

export const stage = (key) => BY_KEY[key] ?? STAGES[0];
export const stageIndex = (key) => STAGES.findIndex((s) => s.key === key);
export const stageColor = (key) => stage(key).color;
export const stageLabel = (key) => stage(key).label;

// How far through the pipeline, 0..1. Used for the county progress bars.
export const stageProgress = (key) =>
  Math.max(0, stageIndex(key)) / (STAGES.length - 1);
