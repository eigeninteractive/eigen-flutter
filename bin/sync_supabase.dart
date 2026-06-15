/// Vendors the Eigen Engine's Supabase backend into the current app.
///
/// Supabase has no native "depend on another project's backend" mechanism, so
/// the engine's backend pieces are **vendored** (copied, committed) into the
/// app's `supabase/`. This covers everything that is engine-owned:
///   - `migrations/*.sql`  — framework/infra schema + RPCs
///   - `functions/<name>/`  — engine edge functions (update-ratings, refresh-fcm-token)
///   - `seed.sql`           — engine app_config + serverless-secret vault seed
///
/// NOT copied (per-project / secret, set up once per app): `config.toml` (base it
/// on the engine's and set `project_id`), `signing_keys.json`, `functions/.env.local`.
///
/// Run from the app directory (the app must depend on `eigen_engine`):
/// ```sh
/// dart run eigen_engine:sync_supabase [--out supabase]
/// ```
///
/// Idempotent: overwrites the engine-owned files and leaves everything else
/// (your game hook migration, any app-specific edge functions). Commit the
/// result. Re-run when you bump the engine version. The engine is resolved via
/// its `package:` URI, so this works for path, git, or hosted dependencies.
library;

import 'dart:io';
import 'dart:isolate';

const _enginePackage = 'eigen_engine';

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

  // functions/<name>/  (each engine function dir, copied whole)
  final srcFunctions = Directory('${engine.path}/functions');
  if (srcFunctions.existsSync()) {
    for (final dir in srcFunctions.listSync().whereType<Directory>()) {
      final name = dir.uri.pathSegments[dir.uri.pathSegments.length - 2];
      _copyDir(dir, Directory('$out/functions/$name'));
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

/// Recursively copies [src] into [dst] (overwriting files; creating dirs).
void _copyDir(Directory src, Directory dst) {
  dst.createSync(recursive: true);
  for (final entity in src.listSync()) {
    final name = entity.uri.pathSegments.last;
    if (entity is Directory) {
      _copyDir(entity, Directory('${dst.path}/$name'));
    } else if (entity is File) {
      entity.copySync('${dst.path}/$name');
    }
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
