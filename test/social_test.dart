import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quizrail/core/models/game_tunnel.dart';
import 'package:quizrail/core/models/leaderboard_entry.dart';
import 'package:quizrail/features/social/leaderboard_screen.dart';
import 'package:quizrail/features/social/marketplace_screen.dart';
import 'package:quizrail/features/social/social_providers.dart';
import 'package:quizrail/features/social/social_service.dart';
import 'package:quizrail/features/tunnel/custom_tunnel.dart';

GameTunnel marketTunnel({
  required String id,
  required String theme,
  double avg = 0,
  int count = 0,
}) =>
    GameTunnel(
      id: id,
      theme: theme,
      creatorId: 'c1',
      questions: const [
        GameQuestion(
            prompt: 'Q', answer: 'A', difficulty: TunnelDifficulty.easy),
      ],
      ratingAvg: avg,
      ratingCount: count,
    );

void main() {
  test('LeaderboardEntry label + défauts', () {
    const e = LeaderboardEntry(
        uid: 'abcdef', bestScore: 300, wins: 2, games: 5, country: 'FR');
    expect(e.label, 'Joueur ABCD');
    const named =
        LeaderboardEntry(uid: 'x', displayName: 'Zoe', bestScore: 10);
    expect(named.label, 'Zoe');
    final d = LeaderboardEntry.fromMap('u', {});
    expect(d.bestScore, 0);
    expect(d.country, '--');
  });

  test('sortBoard décroissant', () {
    const a = LeaderboardEntry(uid: 'a', bestScore: 100);
    const b = LeaderboardEntry(uid: 'b', bestScore: 300);
    const c = LeaderboardEntry(uid: 'c', bestScore: 200);
    final sorted = sortBoard([a, b, c]);
    expect(sorted.map((e) => e.uid).toList(), ['b', 'c', 'a']);
  });

  test('GameTunnel notation roundtrip', () {
    final t = marketTunnel(id: 't1', theme: 'Espace', avg: 4.5, count: 10);
    final back = GameTunnel.fromMap('t1', t.toMap());
    expect(back.ratingAvg, 4.5);
    expect(back.ratingCount, 10);
    // Sans avis : champs absents, défauts à 0.
    final plain = marketTunnel(id: 't2', theme: 'Mer');
    expect(plain.toMap().containsKey('ratingAvg'), isFalse);
    expect(GameTunnel.fromMap('t2', plain.toMap()).ratingCount, 0);
  });

  testWidgets('Classements : onglets + ajout ami', (tester) async {
    final fake = FakeSocialService(
      board: const [
        LeaderboardEntry(
            uid: 'me', displayName: 'Moi', country: 'FR', bestScore: 300),
        LeaderboardEntry(
            uid: 'u2', displayName: 'Zoe', country: 'FR', bestScore: 200),
        LeaderboardEntry(
            uid: 'u3', displayName: 'Max', country: 'US', bestScore: 500),
      ],
      profile: const {
        '_uid': 'me',
        'country': 'FR',
        'friendIds': ['u2'],
      },
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [socialServiceProvider.overrideWithValue(fake)],
        child: const MaterialApp(home: LeaderboardScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // Mondial : les 3.
    expect(find.text('Moi'), findsOneWidget);
    expect(find.text('Max'), findsOneWidget);
    // Amis : moi + u2, pas Max.
    await tester.tap(find.byKey(const Key('lbTabfriends')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Zoe'), findsOneWidget);
    expect(find.text('Max'), findsNothing);
    // Pays : FR uniquement.
    await tester.tap(find.byKey(const Key('lbTabcountry')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('FR', skipOffstage: false), findsWidgets);
    expect(find.text('Max'), findsNothing);
    // Ajout ami.
    await tester.enterText(
        find.byKey(const Key('lbFriendField')), 'u9');
    await tester.tap(find.byKey(const Key('lbAddFriendButton')));
    await tester.pump();
    expect(fake.friendAdds, 1);
    expect(find.byKey(const Key('lbFriendMsg')), findsOneWidget);
  });

  testWidgets('Marché : tri + recherche + note + signalement',
      (tester) async {
    final fake = FakeSocialService(market: [
      marketTunnel(id: 't1', theme: 'Espace', avg: 4.5, count: 10),
      marketTunnel(id: 't2', theme: 'Animaux'),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [socialServiceProvider.overrideWithValue(fake)],
        child: const MaterialApp(home: MarketplaceScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('mkTunnelCard_t1')), findsOneWidget);
    expect(find.byKey(const Key('mkTunnelCard_t2')), findsOneWidget);
    // Tri récents.
    await tester.tap(find.byKey(const Key('mkSortrecent')));
    await tester.pump();
    expect(fake.lastSort, MarketSort.recent);
    // Recherche filtre côté service (2 pumps : rebuild + émission).
    await tester.enterText(
        find.byKey(const Key('mkSearchField')), 'espace');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(fake.lastQuery, 'espace');
    expect(find.byKey(const Key('mkTunnelCard_t1')), findsOneWidget);
    expect(find.byKey(const Key('mkTunnelCard_t2')), findsNothing);
    await tester.enterText(find.byKey(const Key('mkSearchField')), '');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // Notation (drag : le champ recherche a son Scrollable interne).
    final list = find.byKey(const Key('mkList'));
    await tester.dragUntilVisible(
      find.byKey(const Key('mkRateButton_t1')),
      list,
      const Offset(0, -300),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('mkRateButton_t1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('mkRateDialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('mkStar_4')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(fake.rates, 1);
    // Signalement.
    await tester.dragUntilVisible(
      find.byKey(const Key('mkReportButton_t2')),
      list,
      const Offset(0, -300),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('mkReportButton_t2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('mkReportDialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('mkReason_spam')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(fake.reports, 1);
  });
}
