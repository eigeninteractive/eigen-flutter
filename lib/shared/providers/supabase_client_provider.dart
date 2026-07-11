import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'supabase_client_provider.g.dart';

/// The app-wide Supabase client — the data layer's single backend handle.
///
/// Only repositories and data services may watch this; everything above them
/// consumes domain types. Enforced by
/// `test/core/architecture/supabase_isolation_test.dart`.
@Riverpod(keepAlive: true)
SupabaseClient supabaseClient(Ref ref) {
  return Supabase.instance.client;
}
