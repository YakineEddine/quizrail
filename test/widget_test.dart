import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:quizrail/core/storage/app_prefs.dart';
import 'package:quizrail/features/board/board_screen.dart';
import 'package:quizrail/features/results/results_screen.dart';
import 'package:quizrail/main.dart';

// Marque isolée en bidi (U+2066 LRI … U+2069 PDI), cf. HomeScreen._title().
const _arTitle = '\u2066QuizRail\u2069 – الرئيسية';

/// Pompe MyApp avec prefs mémoire (pas de pumpAndSettle : le train est en
/// repeat() infini). Retourne les prefs pour assertions.
Future<AppPrefs> _pumpApp(WidgetTester tester,
    {bool seenOnboarding = true, String lang = 'fr', int tokens = 120}) async {
  final prefs = AppPrefs.inMemory(
    tokens: tokens,
    lang: AppLangX.fromCode(lang),
    seenOnboarding: seenOnboarding,
  );
  await tester.pumpWidget(MyApp(prefsOverride: prefs));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  return prefs;
}

void main() {
  test('Clés de persistance Phase 1', () {
    expect(PrefKeys.walletTokens, 'wallet_tokens');
    expect(PrefKeys.settingsLang, 'settings_lang');
    expect(PrefKeys.hasSeenOnboarding, 'hasSeenOnboarding');
  });

  test('AppPrefs mémoire : roundtrip jetons/langue/flag', () async {
    final prefs = AppPrefs.inMemory();
    expect(prefs.tokens, 120);
    await prefs.setTokens(200);
    expect(prefs.tokens, 200);
    await prefs.setLang(AppLangX.fromCode('ar'));
    expect(prefs.lang.isRtl, isTrue);
    await prefs.setHasSeenOnboarding(true);
    expect(prefs.hasSeenOnboarding, isTrue);
  });

  test('AppPrefs.load initialise les défauts via SharedPreferences',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await AppPrefs.load();
    expect(prefs.tokens, 120);
    expect(prefs.lang, AppLang.fr);
    expect(prefs.hasSeenOnboarding, isFalse);
  });

  testWidgets('Affiche titre FR et compteur initial', (tester) async {
    await _pumpApp(tester);

    expect(find.text('QuizRail – Accueil'), findsOneWidget);
    expect(find.byKey(const Key('tokenCount')), findsOneWidget);
    expect(find.text('120'), findsOneWidget);
    expect(find.byKey(const Key('trainAnimation')), findsOneWidget);
  });

  testWidgets('Bouton +10 incrémente les jetons', (tester) async {
    final prefs = await _pumpApp(tester);

    await tester.tap(find.byKey(const Key('addTokensButton')));
    await tester.pump();

    expect(find.text('130'), findsOneWidget);
    expect(prefs.tokens, 130);
  });

  testWidgets('Passage en EN change les libellés', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.text('EN'));
    await tester.pump();

    expect(find.text('QuizRail – Home'), findsOneWidget);
    expect(find.text('Tokens'), findsOneWidget);
    // CTA sous la ligne de flottaison (zone train agrandie) : scroller.
    await tester.scrollUntilVisible(find.text('Play'), 200);
    expect(find.text('Play'), findsOneWidget);
  });

  testWidgets('Passage en AR : titre isolé + RTL + bouton +10 en LTR',
      (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.text('AR'));
    await tester.pump();

    // Titre avec marque isolée, pas de forme bancale.
    expect(find.text(_arTitle), findsOneWidget);
    // Le Directionality racine du HomeScreen doit être en RTL.
    final directionality = tester.widget<Directionality>(
      find
          .ancestor(
            of: find.byType(Scaffold),
            matching: find.byType(Directionality),
          )
          .first,
    );
    expect(directionality.textDirection, TextDirection.rtl);
    // Le bouton +10 reste LTR (signe à gauche du nombre).
    final wrappers = tester.widgetList<Directionality>(
      find.ancestor(
        of: find.byKey(const Key('addTokensButton')),
        matching: find.byType(Directionality),
      ),
    );
    expect(
      wrappers.any((d) => d.textDirection == TextDirection.ltr),
      isTrue,
    );
  });

  testWidgets('Le train avance entre deux frames', (tester) async {
    await _pumpApp(tester);

    final trainFinder = find.byKey(const Key('trainAnimation'));
    expect(trainFinder, findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));
    expect(trainFinder, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    expect(trainFinder, findsOneWidget);
  });

  testWidgets('Zone du train >= 25 % de la hauteur écran', (tester) async {
    await _pumpApp(tester);

    final h = tester.getSize(find.byKey(const Key('trainAnimation'))).height;
    expect(h, greaterThanOrEqualTo(600 * 0.25));
  });

  testWidgets('FR + EN sur petit écran : aucun débordement', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final prefs = AppPrefs.inMemory();
    await tester.pumpWidget(MyApp(prefsOverride: prefs));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('QuizRail – Accueil'), findsOneWidget);

    await tester.tap(find.text('EN'));
    await tester.pump();
    expect(find.text('QuizRail – Home'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('Onboarding skippable pose le flag et va à l\u2019accueil',
      (tester) async {
    final prefs = await _pumpApp(tester, seenOnboarding: false);

    expect(find.byKey(const Key('onboardingSkipButton')), findsOneWidget);
    expect(find.byKey(const Key('onboardingPage0')), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboardingSkipButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(prefs.hasSeenOnboarding, isTrue);
    expect(find.text('QuizRail – Accueil'), findsOneWidget);
  });

  testWidgets('Plateau : rend le board et ouvre la carte question',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: BoardScreen(prefs: AppPrefs.inMemory())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const Key('boardScreen')), findsOneWidget);
    expect(find.byKey(const Key('boardPaint')), findsOneWidget);

    await tester.scrollUntilVisible(
        find.byKey(const Key('nextQuestionButton')), 250);
    await tester.tap(find.byKey(const Key('nextQuestionButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('questionSheet')), findsOneWidget);
    expect(find.byKey(const Key('answerField')), findsOneWidget);
    expect(find.byKey(const Key('hintLetterButton')), findsOneWidget);
    expect(find.byKey(const Key('hintRevealButton')), findsOneWidget);
    expect(find.byKey(const Key('submitAnswerButton')), findsOneWidget);
  });

  testWidgets('Plateau : bonne réponse fait scorer et avancer', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: BoardScreen(prefs: AppPrefs.inMemory())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.scrollUntilVisible(
        find.byKey(const Key('nextQuestionButton')), 250);
    await tester.tap(find.byKey(const Key('nextQuestionButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 1re question FR : « Capitale de la France ? » → paris.
    await tester.enterText(find.byKey(const Key('answerField')), 'paris');
    await tester.tap(find.byKey(const Key('submitAnswerButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    await tester.scrollUntilVisible(find.text('100'), -250);
    expect(find.text('100'), findsOneWidget);
  });

  testWidgets('Résultats : stats + CTA Rejouer / Accueil', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ResultsScreen(
          score: 300,
          bestStreak: 3,
          tokensEarned: 40,
          walletTokens: 160,
          position: 6,
          totalTiles: 12,
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('resultsScreen')), findsOneWidget);
    expect(find.text('300'), findsOneWidget);
    expect(find.text('+40'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.byKey(const Key('homeButton')), 300);
    expect(find.byKey(const Key('replayButton')), findsOneWidget);
    expect(find.byKey(const Key('homeButton')), findsOneWidget);

    await tester.tap(find.byKey(const Key('replayButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('boardScreen')), findsOneWidget);
  });
}
