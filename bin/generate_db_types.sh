#!/usr/bin/env bash
#
# Regenerates the engine-owned DB types from the LOCAL Supabase schema, so the
# edge-function TS derives DB enums (and any non-jsonb shapes) straight from the
# migrations. The committed file must equal this script's output — the db-types
# CI workflow runs the same script and fails on any diff.
#
# `gen types` output isn't deno-formatted, so we pipe it through `deno fmt`; the
# result is a normal source file (no ignore directives) that `deno fmt --check`
# and `deno lint` cover like any other.
#
# Requires `supabase start` running first (migrations applied) and `deno` on PATH.
#   ./bin/setup_local.sh && supabase start && ./bin/generate_db_types.sh
set -euo pipefail

cd "$(dirname "$0")/.."

out="supabase/functions/_types/database.types.ts"
supabase gen types typescript --local --schema public > "$out"
deno fmt "$out" >/dev/null

echo "Wrote $out"
