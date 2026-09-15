import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quizrail/core/i18n/app_lang.dart';
import 'package:quizrail/core/models/party.dart';
import 'package:quizrail/core/storage/app_prefs.dart';
import 'package:quizrail/features/party/party_host_screen.dart';
import 'package:quizrail/features/party/party_join_screen.dart';
import 'package:quizrail/features/party/party_play_screen.dart';
import 'package:quizrail/features/party/party_providers.dart';
import 'package:quizrail/features/party/party_results_screen.dart';
import 'package:quizrail/features/party/party_service.dart';

PartyRoom lobbyRoom() => PartyRoom(
      id: 'room1',
      code: 'ABC234',
      hostId: 'me',
      status: 'lobby',
      theme: 'Animaux',
      questions: List.generate(
        8,
        (i) => PartyQuestion(
          prompt: {'fr': 'Q$i ?', 'en': 'Q$i?', 'ar': 'س$i؟'},
          difficulty: 'easy',
        ),
      ),
      questionIndex: 0,
      playerIds: const ['me', 'p2'],
    );

PartyRoom playingRoom() => PartyRoom(
      id: 'room1',
      code: 'ABC234',
      hostId: 'me',
      status: 'playing',
      theme: 'Animaux',
      questions: List.generate(
        8,
        (i) => PartyQuestion(
          prompt: {'fr': 'Q$i ?', 'en': 'Q$i?', 'ar': 'س$i؟'},
          difficulty: 'easy',
        ),
      ),
      questionIndex: 2,
      playerIds: const ['me', 'p2'],
    );

PartyRoom finishedRoom() => PartyRoom(
      id: 'room1',
      code: 'ABC234',
      hostId: 'me',
      status: 'finished',
      theme: 'Animaux',
      questions: List.generate(
        8,
        (i) => PartyQuestion(
          prompt: {'fr': 'Q$i ?', 'en': 'Q$i?', 'ar': 'س$i؟'},
          difficulty: 'easy',
        ),
      ),
      questionIndex: 8,
      playerIds: const ['me', 'p2'],
      winnerUid: 'me',
    );

List<PartyPlayer> twoPlayers() => const [
      PartyPlayer(
          uid: 'me', displayName: 'Moi', score: 300, correct: 3, answered: 8),
      PartyPlayer(
          uid: 'p2', displayName: 'Zoe', score: 200, correct: 2, answered: 8),
    ];

/// Charge : 10 joueurs dans la même room (heartbeat 10 s chacun,
/// écritures réparties sur 10 docs players/{uid}, room écrite par le host).
List<PartyPlayer> tenPlayers() => List.generate(
      10,
      (i) => PartyPlayer(
        uid: 'p$i',
        displayName: 'Joueur $i',
        score: 100 * (10 - i),
        correct: 10 - i,
        answered: 8,
        finishedAtMs: 1000 * (i + 1),
      ),
    );

PartyRoom tenPlayerRoom() => PartyRoom(
      id: 'room1',
      code: 'ABC234',
      hostId: 'p0',
      status: 'playing',
      theme: 'Animaux',
      questions: List.generate(
        8,
        (i) => PartyQuestion(
          prompt: {'fr': 'Q$i ?', 'en': 'Q$i?', 'ar': 'س$i؟'},
          difficulty: 'easy',
        ),
      ),
      questionIndex: 2,
      playerIds: List.generate(10, (i) => 'p$i'),
    );

void main() {
  test('validRoomCode : 6 caractères non ambigus', () {
    expect(validRoomCode('ABC234'), isTrue);
    expect(validRoomCode('abc234'), isTrue);
    expect(validRoomCode('ABC12'), isFalse);
    expect(validRoomCode('ABC1234'), isFalse);
    expect(validRoomCode('ABC12!'), isFalse);
    // Caractères ambigus exclus (génération côté serveur).
    expect(validRoomCode('ABC12I'), isFalse);
    expect(validRoomCode('ABC120'), isFalse);
    expect(validRoomCode('ABC123'), isFalse);
    expect(validRoomCode(''), isFalse);
  });

  test('partyWinner : score, puis premier à finir, sinon nul', () {
    const a =
        PartyPlayer(uid: 'a', score: 300, finishedAtMs: 5000);
    const b =
        PartyPlayer(uid: 'b', score: 200, finishedAtMs: 1000);
    expect(partyWinner([a, b]).winnerUid, 'a');
    const c =
        PartyPlayer(uid: 'c', score: 200, finishedAtMs: 9000);
    const d =
        PartyPlayer(uid: 'd', score: 200, finishedAtMs: 1000);
    expect(partyWinner([c, d]).winnerUid, 'd');
    const e = PartyPlayer(uid: 'e', score: 200);
    const f = PartyPlayer(uid: 'f', score: 200);
    final draw = partyWinner([e, f]);
    expect(draw.winnerUid, isNull);
    expect(draw.isDraw, isTrue);
    expect(partyWinner([]).isDraw, isTrue);
  });

  test('PartyRoom/PartyPlayer fromMap', () {
    final room = PartyRoom.fromMap('r1', {
      'code': 'ABC123',
      'hostId': 'h',
      'status': 'playing',
      'theme': 'T',
      'questions': [
        {
          'prompt': {'fr': 'Q ?', 'en': 'Q?', 'ar': 'س؟'},
          'difficulty': 'easy'
        }
      ],
      'questionIndex': 3,
      'playerIds': ['h', 'p'],
    });
    expect(room.isPlaying, isTrue);
    expect(room.isHost('h'), isTrue);
    expect(room.questions.first.text(AppLangX.fromCode('fr')), 'Q ?');
    final p = PartyPlayer.fromMap('p', {'score': 150});
    expect(p.score, 150);
    expect(p.connected, isTrue);
  });

  testWidgets('Host : création puis salon (code + QR + joueurs)',
      (tester) async {
    final fake = FakePartyService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          partyServiceProvider.overrideWithValue(fake),
          partyRoomProvider('room1')
              .overrideWithValue(AsyncValue.data(lobbyRoom())),
          partyPlayersProvider('room1')
              .overrideWithValue(AsyncValue.data(twoPlayers())),
        ],
        child: MaterialApp(
          home: PartyHostScreen(prefs: AppPrefs.inMemory(), uid: 'me'),
        ),
      ),
    );
    await tester.pump();
    await tester.enterText(
        find.byKey(const Key('partyThemeField')), 'Animaux');
    await tester.tap(find.byKey(const Key('partyCreateButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(fake.creates, 1);
    expect(find.byKey(const Key('partyCodeText')), findsOneWidget);
    expect(find.text('ABC234'), findsOneWidget);
    expect(find.byKey(const Key('partyQr')), findsOneWidget);
    expect(find.byKey(const Key('partyLobbyList')), findsOneWidget);
    expect(find.byKey(const Key('partyStartButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('partyStartButton')));
    await tester.pump();
    expect(fake.starts, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Host : animation (suivante / terminer)', (tester) async {
    final fake = FakePartyService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          partyServiceProvider.overrideWithValue(fake),
          partyRoomProvider('room1')
              .overrideWithValue(AsyncValue.data(playingRoom())),
          partyPlayersProvider('room1')
              .overrideWithValue(AsyncValue.data(twoPlayers())),
        ],
        child: MaterialApp(
          home: PartyHostScreen(
              prefs: AppPrefs.inMemory(), uid: 'me', roomId: 'room1'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('partyNextButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('partyNextButton')));
    await tester.pump();
    expect(fake.advances, 1);
    await tester.tap(find.byKey(const Key('partyEndButton')));
    await tester.pump();
    expect(fake.ends, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Join : code puis salon d\u2019attente', (tester) async {
    final fake = FakePartyService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          partyServiceProvider.overrideWithValue(fake),
          partyRoomProvider('room1')
              .overrideWithValue(AsyncValue.data(lobbyRoom())),
          partyPlayersProvider('room1')
              .overrideWithValue(AsyncValue.data(twoPlayers())),
        ],
        child: MaterialApp(
          home: PartyJoinScreen(prefs: AppPrefs.inMemory(), uid: 'p2'),
        ),
      ),
    );
    await tester.pump();
    await tester.enterText(
        find.byKey(const Key('partyCodeField')), 'ABC234');
    await tester.tap(find.byKey(const Key('partyJoinButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(fake.joins, 1);
    expect(find.byKey(const Key('partyLobbyList')), findsOneWidget);
    expect(find.textContaining('host'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Play : question + réponse + classement', (tester) async {
    final fake = FakePartyService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          partyServiceProvider.overrideWithValue(fake),
          partyRoomProvider('room1')
              .overrideWithValue(AsyncValue.data(playingRoom())),
          partyPlayersProvider('room1')
              .overrideWithValue(AsyncValue.data(twoPlayers())),
        ],
        child: MaterialApp(
          home: PartyPlayScreen(
            roomId: 'room1',
            prefs: AppPrefs.inMemory(),
            uid: 'me',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // Question courante = index 2.
    expect(find.text('Q2 ?'), findsOneWidget);
    expect(find.byKey(const Key('partyStandings')), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('partyAnswerField')), 'chat');
    await tester.tap(find.byKey(const Key('partySubmitButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(fake.answers, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Résultats : bannière gagnant + tableau', (tester) async {    final fake = FakePartyService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          partyServiceProvider.overrideWithValue(fake),
          partyPlayersProvider('room1')
              .overrideWithValue(AsyncValue.data(twoPlayers())),
        ],
        child: MaterialApp(
          home: PartyResultsScreen(roomId: 'room1', uid: 'me'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('partyWinnerBanner')), findsOneWidget);
    expect(find.text('Tu gagnes la Party !'), findsOneWidget);
    expect(find.text('300'), findsOneWidget);
    expect(find.byKey(const Key('partyLeaveButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('partyLeaveButton')));
    await tester.pump();
    expect(fake.leaves, 1);
    await tester.pumpWidget(const SizedBox());
  });

  test('Charge : gagnant correct parmi 10 joueurs + ex æquo départagé', () {
    final players = tenPlayers();
    expect(players.length, 10);
    // p0 a le meilleur score (1000).
    expect(partyWinner(players).winnerUid, 'p0');
    // Ex æquo en tête : le premier à avoir fini gagne.
    final tied = List.generate(
      10,
      (i) {
        if (i == 0) {
          return const PartyPlayer(
              uid: 'x', displayName: 'X', score: 500,
              answered: 8, finishedAtMs: 9000);
        }
        if (i == 1) {
          return const PartyPlayer(
              uid: 'y', displayName: 'Y', score: 500,
              answered: 8, finishedAtMs: 1000);
        }
        return PartyPlayer(
            uid: 'p$i', displayName: 'Joueur $i', score: 100, answered: 8);
      },
    );
    expect(partyWinner(tied).winnerUid, 'y');
  });

  testWidgets('Charge : 10 joueurs — jeu + classement live fluides',
      (tester) async {
    final fake = FakePartyService();
    final sw = Stopwatch()..start();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          partyServiceProvider.overrideWithValue(fake),
          partyRoomProvider('room1')
              .overrideWithValue(AsyncValue.data(tenPlayerRoom())),
          partyPlayersProvider('room1')
              .overrideWithValue(AsyncValue.data(tenPlayers())),
        ],
        child: MaterialApp(
          home: PartyPlayScreen(
            roomId: 'room1',
            prefs: AppPrefs.inMemory(),
            uid: 'p3',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // Question courante + les 10 lignes de classement rendues.
    expect(find.text('Q2 ?'), findsOneWidget);
    expect(find.byKey(const Key('partyStandings')), findsOneWidget);
    for (var i = 0; i < 10; i++) {
      expect(find.text('Joueur $i'), findsOneWidget);
    }
    // Réponse sous charge : un seul appel serveur, pas de contention.
    await tester.enterText(
        find.byKey(const Key('partyAnswerField')), 'chat');
    await tester.tap(find.byKey(const Key('partySubmitButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(fake.answers, 1);
    sw.stop();
    // Budget : rendu + interaction de 10 joueurs bien sous 30 s
    // (en pratique < 5 s sur émulateur CI).
    expect(sw.elapsed.inSeconds, lessThan(30));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Charge : 10 joueurs — résultats + bannière', (tester) async {
    final fake = FakePartyService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          partyServiceProvider.overrideWithValue(fake),
          partyPlayersProvider('room1')
              .overrideWithValue(AsyncValue.data(tenPlayers())),
        ],
        child: MaterialApp(
          home: const PartyResultsScreen(roomId: 'room1', uid: 'p0'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('partyWinnerBanner')), findsOneWidget);
    // ListView paresseuse : les dernières lignes sont hors écran.
    for (var i = 0; i < 10; i++) {
      expect(find.text('Joueur $i', skipOffstage: false), findsOneWidget);
    }
    expect(find.text('1000', skipOffstage: false), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
