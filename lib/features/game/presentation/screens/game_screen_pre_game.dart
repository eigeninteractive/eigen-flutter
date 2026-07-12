part of 'game_screen.dart';

/// Waiting room shown for [GameStatus.waiting] and [GameStatus.ready].
///
/// Does not require an observation — game_states and observations are only
/// created at [GameStatus.active] transition.
class _PreGameContent extends ConsumerWidget {
  const _PreGameContent({
    required this.game,
    required this.isStartingGame,
    required this.isCancelling,
    required this.isLeaving,
    required this.onStartGame,
    required this.onCancelGame,
    required this.onLeaveGame,
  });

  final Game game;
  final bool isStartingGame;
  final bool isCancelling;
  final bool isLeaving;
  final VoidCallback onStartGame;
  final VoidCallback onCancelGame;
  final VoidCallback onLeaveGame;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gamePlayersAsync = ref.watch(gamePlayersProvider(gameId: game.id));
    final currentUser = ref.watch(currentUserProvider);
    final appHost = ref.watch(appConfigProvider).engine.appHost;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isCreator = game.createdBy == currentUser?.id;
    final isReady = game.status == GameStatus.ready;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isReady ? Icons.people : Icons.hourglass_empty,
              size: 52,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            isReady ? 'All players ready!' : 'Waiting for players...',
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Game #${game.id.substring(0, 8)}',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (game.shortCode != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.key, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    game.shortCode!,
                    style: textTheme.titleLarge?.copyWith(
                      letterSpacing: 2,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            if (gameInviteLink(game.shortCode!, appHost: appHost)
                case final link?) ...[
              const SizedBox(height: 16),
              // QR modules must be dark-on-light for scanner compatibility,
              // so the inner background is always white regardless of theme.
              // The card wrapper integrates it visually with the surface.
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: QrImageView(
                    data: link.toString(),
                    version: QrVersions.auto,
                    size: 160,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: game.shortCode!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Code copied')),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy code'),
                ),
                if (gameInviteLink(game.shortCode!, appHost: appHost)
                    case final link?) ...[
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => SharePlus.instance.share(
                      ShareParams(text: link.toString()),
                    ),
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text('Share link'),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 36),
          if (gamePlayersAsync.value case final gamePlayers?)
            _ParticipantList(
              playersContext: gamePlayers,
              currentUserId: currentUser?.id,
            ),
          const SizedBox(height: 36),
          // Host can fill an open seat with a server bot (multiplayer fill).
          if (isCreator &&
              (gamePlayersAsync.value?.players.length ?? 0) <
                  game.maxPlayers) ...[
            OutlinedButton.icon(
              onPressed: () => showDialog<void>(
                context: context,
                useSafeArea: true,
                builder: (_) => _AddBotDialog(
                  gameId: game.id,
                  rated: game.rated,
                  config: game.config,
                  schemaVersion: game.schemaVersion,
                ),
              ),
              icon: const Icon(Icons.smart_toy_outlined),
              label: const Text('Add bot'),
            ),
            const SizedBox(height: 12),
          ],
          if (isReady && isCreator)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: isStartingGame ? null : onStartGame,
                  icon: isStartingGame
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: const Text('Start Game'),
                ),
                const SizedBox(width: 12),
                _CancelButton(
                  isCancelling: isCancelling,
                  onCancel: onCancelGame,
                  label: 'Cancel',
                ),
              ],
            ),
          if (!isReady && isCreator)
            _CancelButton(
              isCancelling: isCancelling,
              onCancel: onCancelGame,
              label: 'Cancel Game',
            ),
          if (!isCreator)
            OutlinedButton.icon(
              onPressed: isLeaving ? null : onLeaveGame,
              icon: isLeaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.exit_to_app),
              label: const Text('Leave Game'),
            ),
        ],
      ),
    );
  }
}

/// Host picker for adding a server bot to a multiplayer waiting game.
///
/// Lists only **server** bots (local bots are seated only via the solo picker),
/// schema-compatible, and rated-eligible when the game is rated. On success it
/// invalidates the players list so the new seat appears immediately.
class _AddBotDialog extends ConsumerStatefulWidget {
  const _AddBotDialog({
    required this.gameId,
    required this.rated,
    required this.config,
    required this.schemaVersion,
  });

  final String gameId;
  final bool rated;
  final Map<String, dynamic> config;

  /// The game's `schema_version` — seating gates run against *this* game's
  /// rules unit, not the latest.
  final int schemaVersion;

  @override
  ConsumerState<_AddBotDialog> createState() => _AddBotDialogState();
}

class _AddBotDialogState extends ConsumerState<_AddBotDialog> {
  String? _selectedBotId;
  bool _adding = false;

  @override
  Widget build(BuildContext context) {
    final botsAsync = ref.watch(availableBotsProvider);

    return AlertDialog(
      title: const Text('Add a bot'),
      content: switch (botsAsync) {
        AsyncError(:final error) => Text(humanize(error)),
        AsyncData(value: final bots) => _picker(bots),
        _ => const SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator()),
        ),
      },
      actions: [
        TextButton(
          onPressed: _adding ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_adding || _selectedBotId == null) ? null : _add,
          child: _adding
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Add'),
        ),
      ],
    );
  }

  /// Server bots seatable into this game: server-only, schema-compatible
  /// (the bot's declared max schema covers this game's version), rated guard,
  /// and accepted by *this game's version* of the botSeatable rule (the Dart
  /// twin of the server's GameRules.botSeatable, which enforces it at
  /// seating). [_selectedBotId] defaults to the first available.
  Widget _picker(List<BotInfo> bots) {
    final rules = ref
        .read(currentGameModuleProvider)
        .versions[widget.schemaVersion];
    final usable = rules == null
        ? const <BotInfo>[]
        : bots
              .where(
                (b) =>
                    !b.isLocal &&
                    widget.schemaVersion <= b.schemaVersion &&
                    (!widget.rated || b.ratedEligible) &&
                    rules.botSeatable(
                      BotSeatableArgs(
                        gameConfig: widget.config,
                        botConfig: b.config,
                      ),
                    ),
              )
              .toList();
    if (usable.isEmpty) {
      return Text(
        widget.rated
            ? 'No rated-eligible server bots are available.'
            : 'No server bots are available.',
      );
    }
    _selectedBotId ??= usable.first.id;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: usable.map((b) {
        return ChoiceChip(
          label: Text(b.displayName),
          selected: _selectedBotId == b.id,
          onSelected: _adding
              ? null
              : (_) => setState(() => _selectedBotId = b.id),
        );
      }).toList(),
    );
  }

  Future<void> _add() async {
    setState(() => _adding = true);
    try {
      await ref
          .read(gameRepositoryProvider)
          .addBotToGame(gameId: widget.gameId, botId: _selectedBotId!);
      if (!mounted) return;
      ref.invalidate(gamePlayersProvider(gameId: widget.gameId));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _adding = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(humanize(e))));
    }
  }
}

/// Participant slots shown in the pre-game waiting room.
class _ParticipantList extends StatelessWidget {
  const _ParticipantList({
    required this.playersContext,
    required this.currentUserId,
  });

  final PlayersContext playersContext;
  final String? currentUserId;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final players = playersContext.players.values.toList();

    return Column(
      children: players.map((gp) {
        final isMe = gp.playerIndex == playersContext.mySeat.indexOrNull;
        final isBot = gp.type == ParticipantType.bot;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PlayerAvatar(
                playerInfo: gp.info,
                radius: 20,
                isBot: isBot,
                // A deleted seat's info is a synthetic placeholder whose id
                // resolves to no player — never open the profile sheet on it.
                onTap: gp.isDeleted
                    ? null
                    : () => PlayerProfileSheet.show(
                        context,
                        playerId: gp.info.id,
                        type: gp.type,
                      ),
              ),
              const SizedBox(width: 12),
              Text(
                isMe ? 'You' : '@${gp.info.username}',
                style: textTheme.bodyMedium,
              ),
              if (isBot) ...[const SizedBox(width: 8), const BotTag()],
            ],
          ),
        );
      }).toList(),
    );
  }
}
