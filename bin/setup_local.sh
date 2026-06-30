#!/usr/bin/env bash
#
# One-time local setup so `supabase start` works after a fresh clone.
#
# Creates the two git-ignored files the local stack needs:
#   - supabase/signing_keys.json       JWT signing key(s) — required by
#                                      config.toml's [auth] signing_keys_path
#   - supabase/functions/.env.local    edge-function secrets (from the example)
#
# Idempotent: existing files are left untouched. Run from the engine repo root:
#   ./bin/setup_local.sh && supabase start
set -euo pipefail

cd "$(dirname "$0")/.."

key_file="supabase/signing_keys.json"
if [[ -f "$key_file" ]]; then
  echo "✓ $key_file already exists — leaving it"
else
  # `gen signing-key` prints one JWK to stdout; config.toml expects a JWK *array*,
  # so wrap it. --workdir <empty> sidesteps the chicken-and-egg where the CLI
  # reads config.toml's signing_keys_path before this file exists.
  printf '[%s]\n' \
    "$(supabase gen signing-key --algorithm ES256 --workdir "$(mktemp -d)")" \
    > "$key_file"
  echo "✓ created $key_file"
fi

env_file="supabase/functions/.env.local"
if [[ -f "$env_file" ]]; then
  echo "✓ $env_file already exists — leaving it"
else
  cp "supabase/functions/.env.local.example" "$env_file"
  echo "✓ created $env_file (fill in Firebase creds for local FCM)"
fi

echo "Done. Next: supabase start"
