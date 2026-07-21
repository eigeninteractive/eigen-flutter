import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:eigen_flutter/core/errors/error_messages.dart';
import 'package:eigen_flutter/core/game/game_creation_spec.dart';
import 'package:eigen_flutter/core/game/game_module.dart';
import 'package:eigen_flutter/features/auth/providers/auth_providers.dart';
import 'package:eigen_api/eigen_api.dart';
import 'package:eigen_flutter/features/game/presentation/widgets/timing_selector.dart';
import 'package:eigen_flutter/features/game/providers/game_providers.dart';

/// Solo-game picker (the "New Solo Game" FAB): choose an opponent for each bot
/// seat and start a solo game (you + bots) immediately — no waiting room.
///
/// Fully generic — nothing branches on the game's identity. The opponent-seat
/// count is `playersForConfig(config) - 1`: the game's own `buildCreationConfig`
/// carries the player count for variable-count games, and a generic count
/// selector appears only when the game exposes a true range (`min < max`).
///
/// Every seat defaults to the first available bot; the user overrides only the
/// seats they care about. **Timing selects the bot class**: an *untimed* game
/// offers **local** bots (driven by the present human's client — no deadline
/// backstop needed); a *timed* game offers **server** bots (their endpoint may be
/// unreachable, so a deadline is required) and never to guests. The server
/// enforces this partition; switching timing re-derives the usable list, and any
/// seat whose bot is no longer usable falls back to the default, so no invalid
/// combination can be submitted.
class PlayVsBotDialog extends ConsumerStatefulWidget {
  const PlayVsBotDialog({super.key});

  @override
  ConsumerState<PlayVsBotDialog> createState() => _PlayVsBotDialogState();
}

class _PlayVsBotDialogState extends ConsumerState<PlayVsBotDialog> {
  late Map<String, dynamic> _config;
  late Widget? _creationConfigWidget;
  late int _minPlayers;
  late int _maxPlayers;
  // Total players (you + opponents), within [_minPlayers, _maxPlayers]. For a
  // fixed-count game min == max, so this never changes.
  late int _totalPlayers;
  // Resolved timing from the shared TimingSelector; seeded with its default.
  late ResolvedTiming _timing;
  // The mode the picker opens in — computed from the (warm) bot catalog so it has
  // opponents. Held to pass the same key to TimingSelector and its seed.
  late final String? _initialTimingKey;
  // Sparse per-seat overrides: only seats the user explicitly changed. Every
  // other seat derives the default (first available bot) at build time, so there
  // is no list to keep sized and no state mutation during build.
  final Map<int, String> _seatOverrides = {};
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    final module = ref.read(currentGameModuleProvider);
    _config = Map.of(module.creationSpec.defaultConfig);
    final (min, max) = module.playersForConfig(_config);
    _minPlayers = min;
    _maxPlayers = max;
    _totalPlayers = min;
    // Open in a mode that actually has opponents. The bot catalog is already warm
    // (prewarmed at auth + keepAlive), so we can decide here rather than guess.
    _initialTimingKey = _bestTimingKey(module);
    _timing = TimingSelector.initial(
      module.creationSpec.timingConfigs,
      initialKey: _initialTimingKey,
    );
    _creationConfigWidget = module.buildCreationConfig(
      onChanged: (config) {
        setState(() {
          _config = config;
          final (newMin, newMax) = module.playersForConfig(config);
          _minPlayers = newMin;
          _maxPlayers = newMax;
          _totalPlayers = _totalPlayers.clamp(newMin, newMax);
        });
      },
    );
  }

  /// The timing mode to open the picker in, chosen from the (warm) bot catalog so
  /// the picker never opens in a mode with no opponents: the first untimed mode
  /// when a local bot is usable, else the first timed mode when a server bot is,
  /// else `null` (TimingSelector falls back to the first declared mode).
  String? _bestTimingKey(GameModule module) {
    final configs = module.creationSpec.timingConfigs;
    String? untimedKey;
    String? timedKey;
    for (final entry in configs.entries) {
      if (entry.value is UntimedConfig) {
        untimedKey ??= entry.key;
      } else {
        timedKey ??= entry.key;
      }
    }
    // Catalog not loaded yet (it normally is, via prewarm): best-effort untimed.
    final bots = ref.read(availableBotsProvider).value;
    if (bots == null) return untimedKey;

    final isGuest = ref.read(isAnonymousProvider);
    if (_usableBots(bots, module, timed: false, isGuest: isGuest).isNotEmpty) {
      return untimedKey;
    }
    if (_usableBots(bots, module, timed: true, isGuest: isGuest).isNotEmpty) {
      return timedKey;
    }
    return null;
  }

  /// Usable bots for the current timing/guest state: schema-compatible local
  /// bots that ship in this build, plus server bots only when the game is timed
  /// and the caller is registered (the server rejects an untimed server-bot
  /// game, and guests are local-only).
  List<Bot> _usableBots(
    List<Bot> bots,
    GameModule module, {
    required bool timed,
    required bool isGuest,
  }) => bots.where((b) {
    // Solo creation always targets the latest version, so bots are gated
    // against the latest rules unit.
    final rules = module.latestRules;
    if (b.schemaVersion > module.latestSchemaVersion) return false;
    // Config gate: the game's own botSeatable rule decides which bots support the
    // chosen config (the Dart twin of the server's GameRules.botSeatable, which
    // enforces it at seating). Local UX only — no network round-trip per config.
    if (!rules.botSeatable(
      BotSeatableArgs(
        gameConfig: _config,
        botConfig: b.config as Map<String, dynamic>,
      ),
    )) {
      return false;
    }
    // A server-seated bot requires a timed game: dispatch is single-attempt, so
    // the turn deadline is the only thing that resolves a bot which never
    // moves. The server enforces this, so offering an untimed option here would
    // only produce a rejected create. (The untimed case returns when
    // client-driven bots do, for offline play - those need no backstop.)
    return timed && !isGuest;
  }).toList();

  /// The bot id for opponent [seat]: the user's override if it is still usable,
  /// otherwise the default (first available bot).
  String _seatBot(int seat, List<Bot> usable) {
    final override = _seatOverrides[seat];
    if (override != null && usable.any((b) => b.id == override)) {
      return override;
    }
    return usable.first.id;
  }

  @override
  Widget build(BuildContext context) {
    final module = ref.watch(currentGameModuleProvider);
    final botsAsync = ref.watch(availableBotsProvider);
    final isGuest = ref.watch(isAnonymousProvider);
    final timed = _timing.mode != 'untimed';
    final usable = switch (botsAsync) {
      AsyncData(:final value) => _usableBots(
        value,
        module,
        timed: timed,
        isGuest: isGuest,
      ),
      _ => const <Bot>[],
    };
    final opponents = _totalPlayers - 1;
    final canPlay = !_creating && usable.isNotEmpty && opponents >= 1;

    return AlertDialog(
      title: const Text('New Solo Game'),
      content: switch (botsAsync) {
        AsyncError(:final error) => Text(humanize(error)),
        AsyncData() => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_creationConfigWidget != null) ...[
                _creationConfigWidget!,
                const SizedBox(height: 16),
              ],
              if (_minPlayers < _maxPlayers) ...[
                _PlayersSelector(
                  min: _minPlayers,
                  max: _maxPlayers,
                  value: _totalPlayers,
                  enabled: !_creating,
                  onChanged: (n) => setState(() => _totalPlayers = n),
                ),
                const SizedBox(height: 16),
              ],
              TimingSelector(
                configs: module.creationSpec.timingConfigs,
                enabled: !_creating,
                initialKey: _initialTimingKey,
                onChanged: (timing) => setState(() => _timing = timing),
              ),
              const SizedBox(height: 16),
              // Opponent selectors — filtered locally by module.botSeatable, so
              // they update instantly as the config changes (no refetch).
              if (usable.isEmpty)
                const Text('No AI opponents are available for this game yet.')
              else
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < opponents; i++)
                      _OpponentRow(
                        label: opponents == 1
                            ? 'Opponent'
                            : 'Opponent ${i + 1}',
                        value: _seatBot(i, usable),
                        bots: usable,
                        enabled: !_creating,
                        onChanged: (id) =>
                            setState(() => _seatOverrides[i] = id),
                      ),
                  ],
                ),
            ],
          ),
        ),
        _ => const SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator()),
        ),
      },
      actions: [
        TextButton(
          onPressed: _creating ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: canPlay ? _start : null,
          child: _creating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Play'),
        ),
      ],
    );
  }

  Future<void> _start() async {
    final module = ref.read(currentGameModuleProvider);
    final usable = _usableBots(
      ref.read(availableBotsProvider).value ?? const [],
      module,
      timed: _timing.mode != 'untimed',
      isGuest: ref.read(isAnonymousProvider),
    );
    if (usable.isEmpty) return;
    final opponents = _totalPlayers - 1;
    final botIds = [for (var i = 0; i < opponents; i++) _seatBot(i, usable)];

    setState(() => _creating = true);
    try {
      final started = await ref
          .read(gameRepositoryProvider)
          .createSoloGame(
            botIds: botIds,
            schemaVersion: module.latestSchemaVersion,
            minPlayers: _totalPlayers,
            maxPlayers: _totalPlayers,
            turnSeconds: _timing.turnSeconds,
            budgetSeconds: _timing.budgetSeconds,
            incrementSeconds: _timing.incrementSeconds,
            config: _config,
          );
      if (!mounted) return;
      Navigator.pop(context);
      context.pushNamed('game', pathParameters: {'gameId': started.gameId});
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(humanize(e))));
    }
  }
}

/// Total-players selector, shown only when the game exposes a count range
/// (`min < max`); the opponent-seat count is the chosen value minus one.
class _PlayersSelector extends StatelessWidget {
  const _PlayersSelector({
    required this.min,
    required this.max,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final int min;
  final int max;
  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Players', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          segments: [
            for (var n = min; n <= max; n++)
              ButtonSegment(value: n, label: Text('$n')),
          ],
          selected: {value},
          onSelectionChanged: enabled
              ? (selection) => onChanged(selection.first)
              : null,
        ),
      ],
    );
  }
}

/// One opponent seat's bot selector, defaulting to the first available bot.
class _OpponentRow extends StatelessWidget {
  const _OpponentRow({
    required this.label,
    required this.value,
    required this.bots,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<Bot> bots;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          DropdownButton<String>(
            value: value,
            items: [
              for (final b in bots)
                DropdownMenuItem(value: b.id, child: Text(b.displayName)),
            ],
            onChanged: enabled
                ? (id) {
                    if (id != null) onChanged(id);
                  }
                : null,
          ),
        ],
      ),
    );
  }
}
