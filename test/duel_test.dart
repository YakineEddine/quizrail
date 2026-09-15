import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quizrail/core/i18n/app_lang.dart';
import 'package:quizrail/core/models/game_duel.dart';
import 'package:quizrail/core/storage/app_prefs.dart';
import 'package:quizrail/features/duel/duel_board_screen.dart';
import 'package:quizrail/features/duel/duel_providers.dart';
import 'package:quizrail/features/duel/duel_results_screen.dart';
import 'package:quizrail/features/duel/duel_search_screen.dart';
import 'package:quizrail/features/duel/duel_service.dart';

GameDuel runningDuel() {
  final now = DateTime.now().millisecondsSinceEpoch;
  return GameDuel(
    id: 'duel1',
    playerIds: const ['me', 'opp'],
    status: 'running',
    questions: List.generate(
      8,
      (i) => DuelQuestion(
        prompt: {'fr': 'Q$i ?', 'en': 'Q$i?', 'ar': 'س$i؟'},
        difficulty: 'easy',
      ),
    ),
    players: {
      'me': const DuelPlayerState(langCode: 'fr'),
      'opp': DuelPlayerState(
        langCode: 'fr',
        score: 100,
        correct: 1,
        answered: 1,
        position: 1,
        lastSeenMs: now,
      ),
    },
  );
}

/// Adversaire silencieux depuis le début → bouton forfait visible.
GameDuel silentOppDuel() {
  final duel = runningDuel();
  return GameDuel(
    id: duel.id,
    playerIds: duel.playerIds,
    status: duel.status,
    questions: duel.questions,
    players: {
      'me': duel.me('me'),
      'opp': const DuelPlayerState(
        langCode: 'fr',
        score: 100,
        correct: 1,
        answered: 1,
        position: 1,
        lastSeenMs: 0,
      ),
    },
  );
}

GameDuel finishedDuel() => GameDuel(
      id: 'duel1',
      playerIds: const ['me', 'opp'],
      status: 'finished',
      questions: List.generate(
        8,
        (i) => DuelQuestion(
          prompt: {'fr': 'Q$i ?', 'en': 'Q$i?', 'ar': 'س$i؟'},
          difficulty: 'easy',
        ),
      ),
      players: const {
        'me': DuelPlayerState(
          langCode: 'fr',
          score: 300,
          correct: 3,
          answered: 8,
          position: 3,
          bestStreak: 2,
          totalElapsedMs: 45000,
          finished: true,
        ),
        'opp': DuelPlayerState(
          langCode: 'fr',
          score: 200,
          correct: 2,
          answered: 8,
          position: 2,
          bestStreak: 2,
          totalElapsedMs: 60000,
          finished: true,
        ),
      },
      winnerUid: 'me',
      finishReason: 'completed',
    );

void main() {
  test('decideWinnerUid : score puis temps puis nul', () {
    const a = DuelPlayerState(score: 200, totalElapsedMs: 50000);
    const b = DuelPlayerState(score: 100, totalElapsedMs: 10000);
    expect(decideWinnerUid('a', a, 'b', b), 'a');
    const c = DuelPlayerState(score: 100, totalElapsedMs: 90000);
    const d = DuelPlayerState(score: 100, totalElapsedMs: 10000);
    expect(decideWinnerUid('c', c, 'd', d), 'd');
    const e = DuelPlayerState(score: 100, totalElapsedMs: 10000);
    const f = DuelPlayerState(score: 100, totalElapsedMs: 10000);
    expect(decideWinnerUid('e', e, 'f', f), isNull);
  });

  test('canClaimForfeit : grâce 30 s', () {
    expect(
        canClaimForfeit(nowMs: 100000, oppLastSeenMs: 70001), isFalse);
    expect(canClaimForfeit(nowMs: 100000, oppLastSeenMs: 70000), isTrue);
    expect(canClaimForfeit(nowMs: 100000, oppLastSeenMs: 10000), isTrue);
  });

  test('DuelPower alignés serveur (coûts + noms API)', () {
    expect(DuelPower.freeze.cost, 15);
    expect(DuelPower.doubleGains.cost, 10);
    expect(DuelPower.steal.cost, 20);
    expect(DuelPower.freeze.apiName, 'freeze');
    expect(DuelPower.doubleGains.apiName, 'double');
    expect(DuelPower.steal.apiName, 'steal');
    expect(DuelRules.questionCount, 8);
    expect(DuelRules.forfeitGraceMs, 30000);
  });

  test('GameDuel.fromMap', () {
    final duel = GameDuel.fromMap('d1', {
      'playerIds': ['me', 'opp'],
      'status': 'running',
      'questions': [
        {
          'prompt': {'fr': 'Q ?', 'en': 'Q?', 'ar': 'س؟'},
          'difficulty': 'easy'
        }
      ],
      'players': {
        'me': {'score': 100, 'answered': 1},
        'opp': {'score': 0, 'connected': false},
      },
    });
    expect(duel.opponentOf('me'), 'opp');
    expect(duel.me('me').score, 100);
    expect(duel.opponent('me').connected, isFalse);
    expect(duel.questions.first.text(AppLangX.fromCode('fr')), 'Q ?');
    expect(duel.isFinished, isFalse);
  });

  testWidgets('Recherche : attente puis match vers le plateau',
      (tester) async {
    final fake = FakeDuelService(searchResults: const [
      DuelSearchResult(matched: false),
      DuelSearchResult(
          matched: true, duelId: 'duel1', opponentUid: 'opp'),
    ], duels: {'duel1': runningDuel()});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          duelServiceProvider.overrideWithValue(fake),
          duelStreamProvider('duel1')
              .overrideWithValue(AsyncValue.data(runningDuel())),
        ],
        child: MaterialApp(
          home: DuelSearchScreen(prefs: AppPrefs.inMemory()),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('duelSearchScreen')), findsOneWidget);
    // 1er essai immédiat (attente), 2e au bout de 3 s (match).
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('duelBoardScreen')), findsOneWidget);
    expect(find.byKey(const Key('duelMyTrain')), findsOneWidget);
    expect(find.byKey(const Key('duelOppTrain')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Recherche : annuler quitte la file', (tester) async {
    final fake = FakeDuelService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [duelServiceProvider.overrideWithValue(fake)],
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => Navigator.of(ctx).push(
                MaterialPageRoute(
                  builder: (_) => DuelSearchScreen(prefs: null),
                ),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('duelSearchScreen')), findsOneWidget);
    await tester.tap(find.byKey(const Key('duelSearchCancelButton')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(fake.leftQueue, isTrue);
    expect(find.byKey(const Key('duelSearchScreen')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Plateau duel : scores live + question + pouvoirs',
      (tester) async {
    final fake = FakeDuelService(duels: {'duel1': runningDuel()});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          duelServiceProvider.overrideWithValue(fake),
          duelStreamProvider('duel1')
              .overrideWithValue(AsyncValue.data(runningDuel())),
        ],
        child: MaterialApp(
          home: DuelBoardScreen(
            duelId: 'duel1',
            prefs: AppPrefs.inMemory(),
            uid: 'me',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('duelMyScore')), findsOneWidget);
    expect(find.byKey(const Key('duelOppScore')), findsOneWidget);
    // Question + pouvoirs sous la ligne de flottaison : drag progressif
    // (dragUntilVisible, pas scrollUntilVisible : le champ réponse embarque
    // son propre Scrollable interne qui rend la résolution ambiguë).
    final list = find.byType(ListView);
    Future<void> reveal(Finder f) async {
      await tester.dragUntilVisible(f, list, const Offset(0, -300));
      await tester.pump();
    }

    await reveal(find.byKey(const Key('duelAnswerField')));
    expect(find.text('Q0 ?'), findsOneWidget);
    expect(find.byKey(const Key('duelPowerfreeze')), findsOneWidget);
    expect(find.byKey(const Key('duelPowerdouble')), findsOneWidget);
    expect(find.byKey(const Key('duelPowersteal')), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('duelAnswerField')), 'paris');
    await reveal(find.byKey(const Key('duelSubmitButton')));
    await tester.tap(find.byKey(const Key('duelSubmitButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(fake.answers, 1);

    await reveal(find.byKey(const Key('duelPowerfreeze')));
    await tester.tap(find.byKey(const Key('duelPowerfreeze')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(fake.powers, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Forfait : bouton visible si adversaire silencieux',
      (tester) async {
    final fake = FakeDuelService(duels: {'duel1': silentOppDuel()});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          duelServiceProvider.overrideWithValue(fake),
          duelStreamProvider('duel1')
              .overrideWithValue(AsyncValue.data(silentOppDuel())),
        ],
        child: MaterialApp(
          home: DuelBoardScreen(
            duelId: 'duel1',
            prefs: AppPrefs.inMemory(),
            uid: 'me',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.dragUntilVisible(
      find.byKey(const Key('duelForfeitButton')),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.pump();
    expect(find.byKey(const Key('duelForfeitButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('duelForfeitButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(fake.forfeits, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Résultats : bannière + comparatif + revanche',
      (tester) async {
    final fake = FakeDuelService(duels: {'duel1': finishedDuel()});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          duelServiceProvider.overrideWithValue(fake),
          duelStreamProvider('duel1')
              .overrideWithValue(AsyncValue.data(finishedDuel())),
        ],
        child: MaterialApp(
          home: DuelResultsScreen(duelId: 'duel1', uid: 'me'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('duelWinnerBanner')), findsOneWidget);
    expect(find.text('Victoire !'), findsOneWidget);
    expect(find.text('300'), findsOneWidget);
    expect(find.text('200'), findsOneWidget);
    expect(find.byKey(const Key('duelRematchButton')), findsOneWidget);
    expect(find.byKey(const Key('duelNewSearchButton')), findsOneWidget);

    await tester.scrollUntilVisible(
        find.byKey(const Key('duelRematchButton')), 200);
    await tester.tap(find.byKey(const Key('duelRematchButton')));
    await tester.pump();
    expect(find.textContaining('En attente'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
