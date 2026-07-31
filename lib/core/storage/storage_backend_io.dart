import 'package:flutter_riverpod/experimental/persist.dart';
import 'package:path/path.dart';
import 'package:riverpod_sqflite/riverpod_sqflite.dart';
import 'package:sqflite/sqflite.dart';

/// Opens Riverpod's official SQLite persistence adapter on native platforms.
Future<Storage<String, String>> openJsonStorage() async {
  return JsonSqFliteStorage.open(join(await getDatabasesPath(), 'riverpod.db'));
}
