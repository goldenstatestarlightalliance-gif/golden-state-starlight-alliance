// The fixed six-stage advocacy pipeline (spec §4).
//
// Order here is authoritative: it drives sorting, progress bars, and the map
// color ramp. It must stay in sync with the progress_stage enum in
// supabase/migrations/0001_schema.sql.

export const STAGES = [
  {
    key: 'not_started',
    label: 'Not Started',
    // Counties default to neutral and only take on color as they progress,
    // per the founder's instruction that color is applied by status, not
    // baked into the base map.
    color: '#f4f4f5',
    text: '#3f3f46',
  },
  { key: 'contacted',          label: 'Contacted',          color: '#fef3c7', text: '#78350f' },
  { key: 'meeting_scheduled',  label: 'Meeting Scheduled',  color: '#fdba74', text: '#7c2d12' },
  { key: 'ordinance_drafted',  label: 'Ordinance Drafted',  color: '#bbf7d0', text: '#14532d' },
  { key: 'passed',             label: 'Passed',             color: '#22c55e', text: '#052e16' },
  // A distinct "done and verified" tier beyond Passed.
  { key: 'enforced',           label: 'Enforced',           color: '#0f766e', text: '#ffffff' },
];

const BY_KEY = Object.fromEntries(STAGES.map((s) => [s.key, s]));

export const stage = (key) => BY_KEY[key] ?? STAGES[0];
export const stageIndex = (key) => STAGES.findIndex((s) => s.key === key);
export const stageColor = (key) => stage(key).color;
export const stageLabel = (key) => stage(key).label;

// How far through the pipeline, 0..1. Used for the county progress bars.
export const stageProgress = (key) =>
  Math.max(0, stageIndex(key)) / (STAGES.length - 1);
