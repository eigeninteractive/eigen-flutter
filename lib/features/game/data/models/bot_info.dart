import 'package:freezed_annotation/freezed_annotation.dart';

part 'bot_info.freezed.dart';
part 'bot_info.g.dart';

/// A bot in this game's catalog, as returned by the `get_bots` RPC.
///
/// The bot **capability** layer (the "bot sense"), distinct from the identity
/// layer ([PlayerInfo], via `get_players`): display-safe identity columns plus the
/// operational facts only a bot has. [isLocal] true means the bot is driven
/// client-side (a matching [LocalBot] whose [LocalBot.username] equals this
/// [username] must ship in this build); false means a server bot, driven by its
/// webhook. The local-bot driver reads [config] from this catalog (cached) to pass
/// to `LocalBot.chooseAction`. [config] is null for server bots (their config never
/// leaves the server) and `{}` for a local bot with none set.
@freezed
abstract class BotInfo with _$BotInfo {
  const factory BotInfo({
    required String id,
    required String username,
    required String displayName,
    String? avatarUrl,
    required int schemaVersion,
    required bool isLocal,
    required bool ratedEligible,
    Map<String, dynamic>? config,
  }) = _BotInfo;

  factory BotInfo.fromJson(Map<String, dynamic> json) =>
      _$BotInfoFromJson(json);
}
