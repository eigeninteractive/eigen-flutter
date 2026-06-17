import 'package:checks/checks.dart';
import 'package:eigen_engine/features/game/data/models/game.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Game round-trips a per-turn rated game', () {
    final json = <String, Object?>{
      'id': 'g1',
      'created_by': 'u1',
      'status': 'active',
      'access': 'friends',
      'turn_seconds': 60,
      'budget_seconds': null,
      'increment_seconds': null,
      'min_players': 2,
      'max_players': 2,
      'config': {'board': 3},
      'schema_version': 1,
      'short_code': 'AB12',
      'rated': true,
      'rating_pool': 'rapid',
      'created_at': '2026-06-15T10:30:00.000Z',
      'finished_at': null,
      'updated_at': '2026-06-15T10:31:00.000Z',
    };
    check(Game.fromJson(json).toJson()).deepEquals(json);
  });

  test('Game round-trips a budget-mode unrated game', () {
    final json = <String, Object?>{
      'id': 'g2',
      'created_by': null,
      'status': 'waiting',
      'access': 'public',
      'turn_seconds': null,
      'budget_seconds': 600,
      'increment_seconds': 2,
      'min_players': 2,
      'max_players': 4,
      'config': <String, Object?>{},
      'schema_version': 2,
      'short_code': null,
      'rated': false,
      'rating_pool': null,
      'created_at': '2026-06-15T10:30:00.000Z',
      'finished_at': null,
      'updated_at': '2026-06-15T10:30:00.000Z',
    };
    check(Game.fromJson(json).toJson()).deepEquals(json);
  });
}
