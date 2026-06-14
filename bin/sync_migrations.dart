/// Assembles an Eigen Engine app's Supabase migrations from its packages.
///
/// Supabase's CLI expects one flat, timestamp-ordered `migrations/` directory,
/// but the canonical SQL is split across packages: the framework/infra
/// migrations ship with `eigen_engine`, and each game's hook migration ships
/// with its game package. This tool copies them into the app's (git-ignored)
/// `supabase/migrations/` so `supabase db reset`/`db push` work unchanged.
///
/// Run from an app package's directory:
/// ```sh
/// dart run eigen_engine:sync_migrations --game tic_tac_toe
/// ```
///
/// Package locations are resolved via `package:` URIs (not relative paths), so
/// this keeps working if the engine is later consumed as a hosted/git
/// dependency rather than a path dependency. Supabase applies the result in
/// lexicographic (timestamp) order; Postgres does not resolve plpgsql function
/// references at `CREATE` time, so a game's hooks may sort before or after the
/// infra functions. The tool's only structural guard is against filename
/// collisions between packages.
library;

import 'dart:io';
import 'dart:isolate';

const _enginePackage = 'eigen_engine';

Future<void> main(List<String> args) async {
  final games = <String>[];
  var out = 'supabase/migrations';

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    switch (arg) {
      case '--game':
        if (i + 1 >= args.length) _fail('--game requires a package name');
        games.add(args[++i]);
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

  if (games.isEmpty) {
    _fail('at least one --game <package_name> is required');
  }

  // Engine infra migrations first, then each game's hook migrations.
  final sources = <String, Uri>{
    _enginePackage: await _migrationsDir(_enginePackage),
  };
  for (final game in games) {
    sources[game] = await _migrationsDir(game);
  }

  final outDir = Directory(out);
  if (outDir.existsSync()) outDir.deleteSync(recursive: true);
  outDir.createSync(recursive: true);

  final origin = <String, String>{}; // filename -> source package
  var copied = 0;
  for (final entry in sources.entries) {
    final dir = Directory.fromUri(entry.value);
    if (!dir.existsSync()) {
      stderr.writeln(
        "sync_migrations: warning: '${entry.key}' has no "
        'supabase/migrations directory — skipping.',
      );
      continue;
    }
    for (final file in dir.listSync().whereType<File>()) {
      if (!file.path.endsWith('.sql')) continue;
      final name = file.uri.pathSegments.last;
      final clash = origin[name];
      if (clash != null) {
        _fail(
          "duplicate migration filename '$name' in both '$clash' and "
          "'${entry.key}'. Re-timestamp one of them.",
        );
      }
      origin[name] = entry.key;
      file.copySync('${outDir.path}/$name');
      copied++;
    }
  }

  stdout.writeln(
    'Synced $copied migration(s) into $out '
    '(Supabase applies them in timestamp order).',
  );
}

/// Resolves `<package>/supabase/migrations/` via the running app's package
/// config. Returns a `file:` directory URI.
Future<Uri> _migrationsDir(String package) async {
  final libUri = await Isolate.resolvePackageUri(
    Uri.parse('package:$package/'),
  );
  if (libUri == null) {
    _fail(
      "could not resolve package '$package'. "
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
  sink.writeln(
    'Usage: dart run eigen_engine:sync_migrations '
    '--game <package> [--game <package> ...] [--out <dir>]',
  );
}
