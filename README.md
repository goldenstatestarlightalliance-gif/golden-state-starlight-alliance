# Golden State Starlight Alliance

A California coalition working to get **dark sky policy** — outdoor lighting
ordinances that cut unnecessary night-time light pollution through shielded
fixtures, warmer colour temperatures, and lighting curfews — adopted by at
least one city or county government in **all 58 California counties**.

This repository holds the coalition's website: a public progress tracker and a
private coordination platform for the volunteer network.

## What it does

**Public** (no login required)

- Interactive map of all 58 counties, neutral by default, coloured by progress
- A page per county: city-level sub-map, ordinance summaries with links to the
  actual legal text, credited partner organizations, and a running timeline
- A fixed six-stage pipeline: Not Started → Contacted → Meeting Scheduled →
  Ordinance Drafted → Passed → Enforced

**Private** (accounts, planned)

- Organization-based roles, statewide + per-county chat, full audit log

## Stack

| Layer | Choice |
|---|---|
| Frontend | React + Vite, React Router |
| Maps | Leaflet, GeoJSON from US Census TIGER/Line |
| Backend | Supabase (Postgres, Auth, Realtime) |
| Hosting | Netlify |

## Repository layout

```
app/                   React application (Vite root)
  public/geo/          Census boundary GeoJSON, committed
supabase/
  migrations/          Schema, RLS policies, functions, cron
  seed.sql             Generated — do not edit by hand
  apply-all.sql        Generated — the whole database in one file
scripts/               Data generation and boundary fetching
data/                  Source research JSON
docs/                  Build spec and handoff brief
```

## Setup

```bash
npm install --prefix app
cp .env.example .env    # then fill in your Supabase values
npm run dev --prefix app
```

The app degrades gracefully without `.env` — the map still renders county
geography, just with no status colours or org credits.

### Database

Paste `supabase/apply-all.sql` into the Supabase SQL editor and run it. It is
wrapped in a single transaction, so a failure rolls back cleanly. Then run
`supabase/migrations/0004_cron.sql` separately; it schedules the chat retention
job and needs the `pg_cron` extension enabled.

### Regenerating derived files

```bash
node scripts/generate-seed-sql.mjs   # data/*.json  -> supabase/seed.sql
bash scripts/build-apply-all.sh      # migrations   -> supabase/apply-all.sql
node scripts/fetch-boundaries.mjs    # Census       -> app/public/geo/
```

## A note on keys

The Supabase **publishable** key is exposed in the browser bundle by design.
Row Level Security is what protects the data — every table has RLS enabled and
policies matching the role ladder. A `service_role` / `sb_secret_` key must
never appear in this repository or in any client-side code; it bypasses every
policy here.

## Data sources

County and incorporated-place boundaries come from the US Census Bureau
TIGER/Line service (public domain). Outreach research in `data/` was compiled
and fact-checked by the coalition; it includes publicly-sourced records of
local officials who have acted on lighting policy, with citations.
