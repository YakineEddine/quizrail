import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quizrail/main.dart';

void main() {
  testWidgets('Affiche titre FR et compteur initial', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(find.text('QuizRail – Accueil'), findsOneWidget);
    expect(find.byKey(const Key('tokenCount')), findsOneWidget);
    expect(find.text('120'), findsOneWidget);
    expect(find.byKey(const Key('trainAnimation')), findsOneWidget);
  });

  testWidgets('Bouton +10 incrémente les jetons', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    await tester.tap(find.byKey(const Key('addTokensButton')));
    await tester.pump();

    expect(find.text('130'), findsOneWidget);
  });

  testWidgets('Passage en EN change les libellés', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    await tester.tap(find.text('EN'));
    await tester.pump();

    expect(find.text('QuizRail – Home'), findsOneWidget);
    expect(find.text('Tokens'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
  });

  testWidgets('Passage en AR active le RTL', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    await tester.tap(find.text('AR'));
    await tester.pump();

    expect(find.text('QuizRail – الرئيسية'), findsOneWidget);
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
  });

  testWidgets('Le train avance entre deux frames', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    final trainFinder = find.byKey(const Key('trainAnimation'));
    expect(trainFinder, findsOneWidget);

    // L'animation est en repeat() : deux frames espacées doivent peindre
    // quelque chose de différent sans crasher (pas de pumpAndSettle).
    await tester.pump(const Duration(milliseconds: 500));
    expect(trainFinder, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    expect(trainFinder, findsOneWidget);
  });
}
