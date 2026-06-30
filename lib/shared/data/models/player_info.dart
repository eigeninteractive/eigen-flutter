import 'package:freezed_annotation/freezed_annotation.dart';

part 'player_info.freezed.dart';
part 'player_info.g.dart';

/// Public identity of a player (human or bot), sourced from the
/// `app_players` RPC.
///
/// Contains only publicly-safe fields (no email, no payment tier).
/// Used across the app wherever a player's identity needs to be displayed —
/// game screen, lobby cards, home screen, etc.
@freezed
abstract class PlayerInfo with _$PlayerInfo {
  const factory PlayerInfo({
    required String id,
    required String username,
    required String displayName,
    String? avatarUrl,
  }) = _PlayerInfo;

  factory PlayerInfo.fromJson(Map<String, dynamic> json) =>
      _$PlayerInfoFromJson(json);
}
