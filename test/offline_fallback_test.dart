import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quizrail/core/storage/app_prefs.dart';
import 'package:quizrail/features/duel/duel_offline_screen.dart';
import 'package:quizrail/features/party/party_local_screen.dart';
import 'package:quizrail/features/tunnel/tunnel_local_generator.dart';
import 'package:quizrail/features/tunnel/custom_tunnel.dart';

void main() {
  test('generateur local : 9 questions valides 3/3/3', () {
    for (final lang in ['fr', 'en', 'ar']) {
      final qs = TunnelLocalGenerator.generate(theme: 'Animaux', lang: lang);
      final tunnel =
          CustomTunnel(id: 't', theme: 'Animaux', questions: qs);
      expect(tunnel.isValid, isTrue, reason: 'lang=$lang');
    }
  });

  testWidgets('duel offline : ecran + reponse', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: DuelOfflineScreen(prefs: AppPrefs.inMemory())),
    );
    await tester.pump();
    expect(find.byKey(const Key('duelOfflineScreen')), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('duelOfflineAnswerField')), 'paris');
    await tester.tap(find.byKey(const Key('duelOfflineSubmitButton')));
    await tester.pump();
    expect(find.byKey(const Key('duelOfflineScore')), findsOneWidget);
  });

  testWidgets('party locale : setup puis jeu', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PartyLocalScreen()));
    await tester.pump();
    expect(find.byKey(const Key('partyLocalScreen')), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('partyLocalNameField_0')), 'Moi');
    await tester.enterText(
        find.byKey(const Key('partyLocalNameField_1')), 'Zoe');
    await tester.tap(find.byKey(const Key('partyLocalStartButton')));
    await tester.pump();
    expect(find.byKey(const Key('partyLocalAnswerField')), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('partyLocalAnswerField')), 'paris');
    await tester.tap(find.byKey(const Key('partyLocalSubmitButton')));
    await tester.pump();
    expect(find.byKey(const Key('partyLocalAnswerField')), findsOneWidget);
  });
}
