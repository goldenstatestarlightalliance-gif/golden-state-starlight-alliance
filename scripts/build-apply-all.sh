#!/usr/bin/env bash
# Concatenates the migrations and the seed into supabase/apply-all.sql, a
# single file that can be pasted into the Supabase SQL editor in one pass.
#
# The core (schema + RLS + functions + seed) is wrapped in ONE transaction, so
# a failure anywhere rolls the whole thing back rather than leaving a
# half-built database that is awkward to clean up before retrying.
#
# 0004_cron.sql is deliberately left OUT — it depends on the pg_cron extension
# being enabled, and that failing must not take the schema down with it.
#
# Run from the repo root: bash scripts/build-apply-all.sh
set -euo pipefail

cd "$(dirname "$0")/.."

FILES=(
  supabase/migrations/0001_schema.sql
  supabase/migrations/0002_rls.sql
  supabase/migrations/0003_functions.sql
  supabase/seed.sql
)

OUT=supabase/apply-all.sql

{
  cat <<'HDR'
-- ===========================================================================
-- Golden State Starlight Alliance — full database setup
-- GENERATED: supabase/migrations/0001-0003 + supabase/seed.sql
-- Regenerate with: bash scripts/build-apply-all.sh
--
-- HOW TO RUN: paste this entire file into the Supabase SQL editor and Run.
--
-- Everything below is inside a single transaction. If any statement fails,
-- the whole apply rolls back and the database is left untouched — so a failed
-- run is safe to diagnose and retry without cleanup.
--
-- AFTERWARDS, run supabase/migrations/0004_cron.sql separately. It schedules
-- the 1-year chat retention job and needs the pg_cron extension enabled.
-- ===========================================================================

begin;

HDR

  for f in "${FILES[@]}"; do
    echo ""
    echo "-- ==========================================================================="
    echo "-- SOURCE: $f"
    echo "-- ==========================================================================="
    echo ""
    cat "$f"
    echo ""
  done

  cat <<'FTR'

commit;

-- Sanity check — expected: 58 counties, 63 cities, 59 channels, 58 templates.
select
  (select count(*) from counties)        as counties,
  (select count(*) from cities)          as cities,
  (select count(*) from organizations)   as organizations,
  (select count(*) from channels)        as channels,
  (select count(*) from email_templates) as email_templates,
  (select count(*) from county_outreach) as outreach_plans;
FTR
} > "$OUT"

echo "Wrote $OUT ($(wc -l < "$OUT") lines, $(du -h "$OUT" | cut -f1))"
echo "  tables:   $(grep -c '^create table' "$OUT")"
echo "  RLS on:   $(grep -c 'enable row level security' "$OUT")"
echo "  policies: $(grep -c '^create policy' "$OUT")"
