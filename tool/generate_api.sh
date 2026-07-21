#!/usr/bin/env bash
#
# Regenerates the eigen_api Dart REST client from the OpenAPI spec.
#
# eigen_api is the dart-dio client for the Eigen server — a generated artifact
# that eigen_sdk consumes as a plain path dependency (declared in
# eigen_sdk/pubspec.yaml). This script regenerates only the GENERATED CODE
# (lib/, doc/). packages/eigen_api/pubspec.yaml is hand/CLI-owned and protected
# from the generator by .openapi-generator-ignore (a generator bug stamps too
# low an SDK constraint — see the pubspec header + #21815), so nothing here
# edits any pubspec or the workspace. eigen_api is intentionally NOT a workspace
# member.
#
# Toolchain: Java + the Dart-native openapi_generator_cli (no Node). Install once:
#   dart pub global activate openapi_generator_cli
#
# Models use json_serializable + copy_with_extension (the same codegen family as
# the app shell), not built_value. eigen_api's *.g.dart, pubspec.lock and
# .dart_tool are gitignored and rebuilt by build_runner (here and in CI),
# matching the repo convention.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPEC="$ROOT/openapi/openapi.json"
OUT="$ROOT/packages/eigen_api"
SERVER_SPEC="$ROOT/../eigen-server/packages/server/openapi.json"

export PATH="$PATH:$HOME/.pub-cache/bin"
command -v openapi-generator >/dev/null || {
  echo "error: 'openapi-generator' not found. Install it once with:" >&2
  echo "  dart pub global activate openapi_generator_cli" >&2
  exit 1
}

# 1) Refresh the vendored spec from the sibling server checkout when present, so
#    the committed snapshot never drifts. Without the sibling, use the snapshot.
if [ -f "$SERVER_SPEC" ]; then
  cp "$SERVER_SPEC" "$SPEC"
  echo "==> refreshed spec from ../eigen-server"
else
  echo "==> ../eigen-server not found; using committed snapshot openapi/openapi.json"
fi

# 2) Regenerate the generated code. The hand-owned pubspec.yaml and the
#    .openapi-generator-ignore that protects it are preserved; clearing lib/ and
#    doc/ guarantees no orphan files survive a schema removal.
echo "==> generating eigen_api (dart-dio + json_serializable)"
rm -rf "$OUT/lib" "$OUT/doc"
openapi-generator generate \
  -i "$SPEC" -g dart-dio -o "$OUT" \
  --additional-properties=pubName=eigen_api,pubLibrary=eigen_api,serializationLibrary=json_serializable \
  --global-property=modelTests=false,apiTests=false,modelDocs=true,apiDocs=true

# 3) Build eigen_api's built_value serializers (its own resolution supplies the
#    dev deps), then refresh the workspace that path-depends on it.
echo "==> build_runner (eigen_api) + workspace pub get"
( cd "$OUT" && dart pub get && dart run build_runner build --delete-conflicting-outputs )
( cd "$ROOT" && flutter pub get )

echo "==> done. Review packages/eigen_api and commit the refreshed sources."
echo "    (*.g.dart, pubspec.lock, .dart_tool are gitignored + rebuilt; not committed.)"
