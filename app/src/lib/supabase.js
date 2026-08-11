import { createClient } from '@supabase/supabase-js';

const url = import.meta.env.VITE_SUPABASE_URL;
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;

// Whether the app has credentials at all. Exported so the UI can show a clear
// "not configured yet" banner instead of a blank screen — and so the public map
// still renders county geography before the database is wired up.
export const configured = Boolean(url && key);

if (!configured) {
  console.warn(
    'Supabase is not configured. Copy .env.example to .env and set ' +
      'VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY. ' +
      'Status colors and org credits will be empty until then.'
  );
}

// This key is public by design and ships inside the browser bundle. Every table
// it can reach is gated by Row Level Security (supabase/migrations/0002_rls.sql).
export const supabase = configured ? createClient(url, key) : null;
