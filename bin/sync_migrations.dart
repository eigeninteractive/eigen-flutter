/// Vendors the Eigen Engine's Supabase migrations into the current app.
///
/// Supabase has no native "depend on another project's migrations" mechanism,
/// so the engine's infra migrations are **vendored** (copied, committed) into
/// the app's `supabase/migrations/`, sitting alongside the app's own
/// (hand-authored) game hook migration. `supabase db reset`/`db push` then work
/// unchanged, and the app's migration history lives in its own repo.
///
/// Run from the app directory (the app must depend on `eigen_engine`):
/// ```sh
/// dart run eigen_engine:sync_migrations [--out supabase/migrations]
/// ```
///
/// Idempotent: copies the engine's `*.sql` into `--out`, overwriting previously
/// vendored copies and leaving every other file (your game migrations)
/// untouched. Commit the result. Re-run when you bump the engine version.
///
/// The engine is resolved via its `package:` URI (not a relative path), so this
/// keeps working whether the engine is a path, git, or hosted dependency.
/// Engine migration filenames are timestamped and reserved — don't author app
/// migrations with the same names.
library;

import 'dart:io';
import 'dart:isolate';

const _enginePackage = 'eigen_engine';

Future<void> main(List<String> args) async {
  var out = 'supabase/migrations';

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

  final srcDir = Directory.fromUri(await _engineMigrationsDir());
  if (!srcDir.existsSync()) {
    _fail('engine has no supabase/migrations directory at ${srcDir.path}');
  }

  final outDir = Directory(out)..createSync(recursive: true);

  var copied = 0;
  for (final file in srcDir.listSync().whereType<File>()) {
    if (!file.path.endsWith('.sql')) continue;
    final name = file.uri.pathSegments.last;
    file.copySync('${outDir.path}/$name');
    copied++;
  }

  stdout.writeln(
    'Vendored $copied engine migration(s) into $out. '
    'Commit them alongside your game migrations.',
  );
}

/// Resolves `eigen_engine/supabase/migrations/` via the engine's `package:`
/// URI. Returns a `file:` directory URI.
Future<Uri> _engineMigrationsDir() async {
  final libUri = await Isolate.resolvePackageUri(
    Uri.parse('package:$_enginePackage/'),
  );
  if (libUri == null) {
    _fail(
      "could not resolve package '$_enginePackage'. "
      'Run this from an app that depends on it.',
    );
  }
  // libUri points at the package's lib/; migrations live a level up.
  return libUri.resolve('../supabase/migrations/');
}

Never _fail(String message) {
  stderr.writeln('sync_migrations: $message');
  _printUsage(stderr);
  exit(64); // EX_USAGE
}

void _printUsage(IOSink sink) {
  sink.writeln('Usage: dart run eigen_engine:sync_migrations [--out <dir>]');
}
