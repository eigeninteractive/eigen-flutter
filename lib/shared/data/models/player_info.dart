import 'package:freezed_annotation/freezed_annotation.dart';

part 'player_info.freezed.dart';
part 'player_info.g.dart';

/// Public identity of a player (human or bot), sourced from the
/// `app_players` RPC.
///
/// Contains only publicly-safe fields (no email, no payment tier).
/// Used across the app wherever a player's identity needs to be displayed —
/// game screen, lobby cards, home screen, etc.
///
/// [isGuest] is true for anonymous (guest) accounts, always false for bots.
/// Guests cannot be friended, so UI hides social affordances for them.
/// Required, not defaulted: the RPC always returns it, and a default would
/// silently map a decode gap to "not a guest" — the fail-open direction.
/// Breaking JSON-shape changes are handled by the persisted cache's
/// `destroyKey`, not by per-field defaults.
@freezed
abstract class PlayerInfo with _$PlayerInfo {
  const factory PlayerInfo({
    required String id,
    required String username,
    required String displayName,
    String? avatarUrl,
    required bool isGuest,
  }) = _PlayerInfo;

  factory PlayerInfo.fromJson(Map<String, dynamic> json) =>
      _$PlayerInfoFromJson(json);
}
