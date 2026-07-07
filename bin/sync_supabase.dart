/// Vendors the Eigen Engine's Supabase backend into the current app.
///
/// Supabase has no native "depend on another project's backend" mechanism, so
/// the engine's backend pieces are **vendored** (copied, committed) into the
/// app's `supabase/`. The engine owns and ships:
///   - `migrations/*.sql`              framework/infra schema + RPCs
///   - `functions/_engine/`            the edge-function framework (Hono app,
///                                     GameEngine contract, rpc/runtime, FCM,
///                                     ratings, notify, bot auth, PRNG)
///   - `functions/_types/`             generated `database.types.ts` +
///                                     hand-authored `engine.types.ts`
///   - `functions/engine/`             the single deployable function harness
///                                     (`index.ts` + `deno.json` + `.npmrc`)
///   - `functions/deno.json`           shared import map
///   - `seed.sql`                      engine app_config seed
///
/// The app owns exactly one thing under `functions/`: `_lib/`, where it
/// implements its `GameEngine` (in `game.ts` and any files it adds). That dir is
/// **scaffolded once** from the engine's example and then never touched, so an
/// app's game is safe across re-syncs. Everything else — including the
/// `engine/` harness — is engine-owned and re-vendored (mirror + prune) each
/// sync.
/// Also NOT copied (per-project / secret): `config.toml` (the app adds its own
/// `[functions.engine]` block — base it on the engine's reference config),
/// `signing_keys.json`, `functions/.env.local`.
///
/// Run from the app directory (the app must depend on `eigen_engine`):
/// ```sh
/// dart run eigen_engine:sync_supabase [--out supabase]
/// ```
///
/// Idempotent and a true **mirror within each engine dir**: files removed
/// upstream are pruned, so re-running tracks the engine exactly. The app's
/// `_lib/`, any app-added function dirs, and the app's own migrations are left
/// alone (the engine never deletes whole dirs an app might own). The engine is
/// resolved via its `package:` URI (path, git, or hosted deps).
library;

import 'dart:io';
import 'dart:isolate';

const _enginePackage = 'eigen_engine';

/// The app-owned game dir inside `functions/`. The engine ships an example
/// `_lib/game.ts`; on first sync it is scaffolded into the app, then the app
/// owns `_lib/` entirely — the engine never mirrors or prunes it again, so the
/// app's `GameEngine` (and any files it adds) survive re-syncs.
const _appLibDir = '_lib';

/// The seam file the engine scaffolds into [_appLibDir]. Its presence in the app
/// marks `_lib/` as already owned, so a re-sync leaves the whole dir untouched.
const _appSeamFile = 'game.ts';

/// Engine-owned dirs under `functions/`, mirrored (+ pruned) on every sync.
/// Deliberately an explicit allowlist — only the shared framework, the types,
/// and the single `engine` function harness are vendored, so nothing else in
/// the engine's `functions/` can ever leak into an app.
const _engineOwnedDirs = ['_engine', '_types', 'engine'];

Future<void> main(List<String> args) async {
  var out = 'supabase';

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    switch (arg) {
      case '--out':
        if (i + 1 >= args.length) _fail('--out requires a directory');
        out = args[++i];
      case '-h' || '--help':
        _printUsage(stdout);
        return;
      default:
        _fail('unknown argument: $arg');
    }
  }

  final engine = Directory.fromUri(await _engineSupabaseDir());
  if (!engine.existsSync()) {
    _fail('engine supabase directory not found at ${engine.path}');
  }

  var migrations = 0;
  var functions = 0;
  var seeds = 0;
  var scaffoldedLib = false;

  // migrations/*.sql
  final srcMigrations = Directory('${engine.path}/migrations');
  if (srcMigrations.existsSync()) {
    final dst = Directory('$out/migrations')..createSync(recursive: true);
    for (final f in srcMigrations.listSync().whereType<File>()) {
      if (!f.path.endsWith('.sql')) continue;
      f.copySync('${dst.path}/${f.uri.pathSegments.last}');
      migrations++;
    }
  }

  // functions/ — exactly the allowlisted engine dirs, mirrored. `_lib` is the
  // exception: it's the app's game, scaffolded once and then left alone. Any
  // other dir — app-added functions, engine-side strays — is never touched.
  final srcFunctions = Directory('${engine.path}/functions');
  if (srcFunctions.existsSync()) {
    final dstFunctions = Directory('$out/functions')
      ..createSync(recursive: true);
    // Engine-owned root file: the shared import map. The real `.env.local`
    // (a secret) is never copied.
    final importMap = File('${srcFunctions.path}/deno.json');
    if (importMap.existsSync()) {
      importMap.copySync('${dstFunctions.path}/deno.json');
    }
    final srcLib = Directory('${srcFunctions.path}/$_appLibDir');
    if (srcLib.existsSync()) {
      scaffoldedLib = _scaffoldAppLib(
        srcLib,
        Directory('${dstFunctions.path}/$_appLibDir'),
      );
    }
    for (final name in _engineOwnedDirs) {
      final src = Directory('${srcFunctions.path}/$name');
      if (!src.existsSync()) {
        _fail('engine package is missing functions/$name — broken checkout?');
      }
      final dst = Directory('${dstFunctions.path}/$name');
      _copyDir(src, dst);
      _pruneDir(src, dst);
      functions++;
    }
  }

  // seed.sql
  final srcSeed = File('${engine.path}/seed.sql');
  if (srcSeed.existsSync()) {
    Directory(out).createSync(recursive: true);
    srcSeed.copySync('$out/seed.sql');
    seeds++;
  }

  stdout.writeln(
    'Vendored into $out: $migrations migration(s), $functions function(s), '
    '$seeds seed file(s). Commit them alongside your app-owned files.',
  );

  // Nudge: on first vendor, point the app at its one seam + the config block it
  // must add by hand (config.toml is per-app, never vendored).
  if (scaffoldedLib) {
    stdout.writeln(
      'Scaffolded $out/functions/$_appLibDir/ from the engine example — '
      'implement your GameEngine in $_appSeamFile there (the rest, including '
      'the engine/ harness, is engine-owned and re-vendored each sync).',
    );
    stdout.writeln(
      'Then add a [functions.engine] block (verify_jwt=false; '
      'import_map/entrypoint under ./functions/engine/) to config.toml — it is '
      'per-app, not vendored. See the engine config for the reference block.',
    );
  }
}

/// Scaffolds the app-owned [_appLibDir] from the engine's example, but only when
/// the app doesn't already have one (detected via [_appSeamFile]). After the
/// first sync the app owns `_lib/` entirely — its `GameEngine` implementation
/// plus any files it adds — so the engine never copies into it or prunes it
/// again, and re-syncs leave the app's game untouched. Returns `true` if the dir
/// was freshly scaffolded.
bool _scaffoldAppLib(Directory src, Directory dst) {
  final seam = File('${dst.path}/$_appSeamFile');
  if (seam.existsSync()) return false;
  _copyDir(src, dst);
  return true;
}

/// Resolves `eigen_engine/supabase/` via the engine's `package:` URI.
Future<Uri> _engineSupabaseDir() async {
  final libUri = await Isolate.resolvePackageUri(
    Uri.parse('package:$_enginePackage/'),
  );
  if (libUri == null) {
    _fail(
      "could not resolve package '$_enginePackage'. "
      'Run this from an app that depends on it.',
    );
  }
  // libUri points at the package's lib/; supabase/ lives a level up.
  return libUri.resolve('../supabase/');
}

/// Recursively copies [src] into [dst] (creating dirs), overwriting files.
///
/// Generated `deno.lock` files are never copied — they are git-ignored and
/// regenerated per project, so the engine's lock must not be pushed onto apps.
void _copyDir(Directory src, Directory dst) {
  dst.createSync(recursive: true);
  for (final entity in src.listSync(recursive: true).whereType<File>()) {
    final rel = entity.path.substring(src.path.length + 1);
    if (rel.endsWith('deno.lock')) continue;
    final target = File('${dst.path}/$rel')..parent.createSync(recursive: true);
    entity.copySync(target.path);
  }
}

/// Deletes files under [dstRoot] absent from [srcRoot], then removes any emptied
/// dirs — making the copy a true mirror, so engine files removed upstream don't
/// linger in the app. Generated `deno.lock` files are never pruned (so the app's
/// own lockfile is preserved).
void _pruneDir(Directory srcRoot, Directory dstRoot) {
  if (!dstRoot.existsSync()) return;
  for (final entity in dstRoot.listSync(recursive: true)) {
    if (entity is! File) continue;
    final rel = entity.path.substring(dstRoot.path.length + 1);
    if (rel.endsWith('deno.lock')) continue;
    if (!File('${srcRoot.path}/$rel').existsSync()) entity.deleteSync();
  }
  // Remove directories left empty by the prune (deepest first).
  final dirs = dstRoot.listSync(recursive: true).whereType<Directory>().toList()
    ..sort((a, b) => b.path.length.compareTo(a.path.length));
  for (final dir in dirs) {
    if (dir.listSync().isEmpty) dir.deleteSync();
  }
}

Never _fail(String message) {
  stderr.writeln('sync_supabase: $message');
  _printUsage(stderr);
  exit(64); // EX_USAGE
}

void _printUsage(IOSink sink) {
  sink.writeln(
    'Usage: dart run eigen_engine:sync_supabase [--out <supabase-dir>]',
  );
}
