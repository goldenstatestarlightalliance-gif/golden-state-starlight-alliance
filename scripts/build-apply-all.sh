#!/usr/bin/env bash
# Concatenates the migrations and the seed into supabase/apply-all.sql, a
# single file that can be pasted into the Supabase SQL editor in one pass.
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
-- GENERATED: concatenation of supabase/migrations/*.sql + supabase/seed.sql
-- Regenerate with: bash scripts/build-apply-all.sh
--
-- Paste this whole file into the Supabase SQL editor and Run.
-- Order matters: schema -> RLS -> functions -> seed.
-- ===========================================================================

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
} > "$OUT"

echo "Wrote $OUT ($(wc -l < "$OUT") lines)"
echo "  tables:   $(grep -c '^create table' "$OUT")"
echo "  RLS on:   $(grep -c 'enable row level security' "$OUT")"
echo "  policies: $(grep -c '^create policy' "$OUT")"
