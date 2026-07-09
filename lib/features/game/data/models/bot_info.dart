import 'package:freezed_annotation/freezed_annotation.dart';

part 'bot_info.freezed.dart';
part 'bot_info.g.dart';

/// A bot in this game's catalog, as returned by the `app_bots` RPC.
///
/// The bot **capability** layer (the "bot sense"), distinct from the identity
/// layer ([PlayerInfo], via `app_players`): display-safe identity columns plus the
/// operational facts only a bot has. [isLocal] true means the bot is driven
/// client-side (a matching [LocalBot] whose [LocalBot.username] equals this
/// [username] must ship in this build); false means a server bot, driven by its
/// webhook. [config] is exposed for **both** local and server bots (persona tuning
/// plus capability declaration — what game configs the bot supports, read
/// by [GameRules.botSeatable] — the pickers filter on it locally, and the server
/// enforces the same rule at seating). The local-bot driver also reads it (cached) to pass
/// to `LocalBot.chooseAction`. `{}` when none is set; the engine imposes no schema on
/// it, and it never holds secrets.
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
    // Always supplied by app_bots (bots.config is NOT NULL); empty when unset.
    required Map<String, dynamic> config,
  }) = _BotInfo;

  factory BotInfo.fromJson(Map<String, dynamic> json) =>
      _$BotInfoFromJson(json);
}
