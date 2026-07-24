/// Widget tests for the board.
///
/// Testing a game screen means building a [GameContentContext] by hand — there
/// is no server, no socket and no auth involved, because `buildContent`
/// receives a plain value object. [_context] below is the whole harness, and
/// it is the piece worth copying into your own game.
///
/// The one piece of framework wiring a test does need is a [ProviderScope] with
/// an [AppConfig]: shared widgets like [PlayerAvatar] resolve avatar URLs
/// against the API host, so they read the config the app injected.
library;

import 'package:eigen_flutter/eigen_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rps_example/rps.dart';

void main() {
  const rules = RpsRulesV1();

  testWidgets('offers a throw when the seat is pending', (tester) async {
    await tester.pumpWidget(
      _harness(
        rules.buildContent(
          _context(observation: _fresh, pendingPlayers: const [0]),
        ),
      ),
    );

    expect(find.text('Your throw.'), findsOneWidget);
    expect(_enabledMoves(tester), 3);
  });

  testWidgets('locks the board the moment a throw is tapped', (tester) async {
    var submitted = <String, dynamic>{};
    await tester.pumpWidget(
      _harness(
        rules.buildContent(
          _context(
            observation: _fresh,
            pendingPlayers: const [0],
            onAction: (json) async {
              submitted = json;
              return ActionSubmitResult.committed;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('paper'));
    await tester.pump();

    // The tap is reflected before any frame comes back — the optimism this
    // game has, standing in for a `previewAction` it cannot implement.
    expect(submitted, {'move': 'paper'});
    expect(find.text('Waiting for your opponent…'), findsOneWidget);
    expect(_enabledMoves(tester), 0);
  });

  testWidgets('re-enables the board when a throw does not commit', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        rules.buildContent(
          _context(
            observation: _fresh,
            pendingPlayers: const [0],
            onAction: (_) async => ActionSubmitResult.rejected,
          ),
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('rock'));
    await tester.pump();

    // No frame is coming for a rejected submit, so the guess has to be undone
    // here or the player would be locked out for the rest of the round.
    expect(_enabledMoves(tester), 3);
  });

  testWidgets('will not offer a second throw in the same round', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        rules.buildContent(
          _context(
            observation: RpsObservation.fromJson(const {
              'round': 1,
              'wins': [0, 0],
              'lastRound': null,
              'yourMove': 'rock',
            }),
            pendingPlayers: const [0],
          ),
        ),
      ),
    );

    expect(_enabledMoves(tester), 0);
    expect(find.text('Waiting for your opponent…'), findsOneWidget);
  });

  testWidgets('renders the reveal and the score after a round', (tester) async {
    await tester.pumpWidget(
      _harness(
        rules.buildContent(
          _context(
            observation: RpsObservation.fromJson(const {
              'round': 2,
              'wins': [1, 0],
              'lastRound': {
                'moves': ['rock', 'scissors'],
                'winner': 0,
              },
              'yourMove': null,
            }),
            pendingPlayers: const [0],
          ),
        ),
      ),
    );

    expect(find.text('Round 2 · first to 3'), findsOneWidget);
    expect(find.text('You won the round'), findsOneWidget);
  });

  testWidgets('reports the match result once it is finished', (tester) async {
    await tester.pumpWidget(
      _harness(
        rules.buildContent(
          _context(
            observation: _fresh,
            pendingPlayers: const [],
            gameStatus: GameStatus.finished,
            outcomes: [
              Outcome(
                playerIndex: 0,
                result: OutcomeResultEnum.loss,
                placement: 2,
                teamIndex: 0,
                score: null,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('You lost the match.'), findsOneWidget);
    expect(_enabledMoves(tester), 0);
  });
}

final _fresh = RpsObservation.fromJson(const {
  'round': 1,
  'wins': [0, 0],
  'lastRound': null,
  'yourMove': null,
});

/// A [GameContentContext] for seat 0 of a two-player match.
GameContentContext _context({
  required RpsObservation observation,
  required List<int> pendingPlayers,
  GameStatus gameStatus = GameStatus.active,
  List<Outcome> outcomes = const [],
  Future<ActionSubmitResult> Function(Map<String, dynamic>)? onAction,
}) {
  return GameContentContext(
    config: const RpsConfig(targetWins: 3),
    frame: GameFrame(
      observation: observation,
      pendingPlayers: pendingPlayers,
      version: 1,
      timing: TimingContext(clock: ServerClock()),
    ),
    gameStatus: gameStatus,
    outcomes: outcomes,
    actionPending: false,
    onAction: onAction ?? (_) async => ActionSubmitResult.committed,
    onInvalidAction: () {},
    playersContext: PlayersContext(
      mySeat: const Seated(0),
      players: {0: _player(0, 'You'), 1: _player(1, 'Opponent')},
    ),
  );
}

GamePlayer _player(int index, String name) => GamePlayer(
  playerIndex: index,
  type: SeatTypeEnum.human,
  info: Player(
    id: 'player-$index',
    username: name.toLowerCase(),
    displayName: name,
    avatarUrl: null,
    isAnonymous: false,
  ),
);

Widget _harness(Widget content) => ProviderScope(
  overrides: [
    appConfigProvider.overrideWithValue(
      const AppConfig(
        branding: Branding(appName: 'RPS', seedColor: Colors.teal),
        engine: EngineConfig(
          apiBaseUrl: 'https://example.invalid',
          googleWebClientId: 'test',
        ),
      ),
    ),
  ],
  child: MaterialApp(home: Scaffold(body: content)),
);

/// How many of the three move buttons are currently tappable.
int _enabledMoves(WidgetTester tester) => tester
    .widgetList<IconButton>(find.byType(IconButton))
    .where((button) => button.onPressed != null)
    .length;
