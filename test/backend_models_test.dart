import 'package:flutter_test/flutter_test.dart';
import 'package:quizrail/core/data/migration_service.dart';
import 'package:quizrail/core/models/app_user.dart';
import 'package:quizrail/core/models/game_session.dart';
import 'package:quizrail/core/models/game_tunnel.dart';
import 'package:quizrail/features/tunnel/custom_tunnel.dart';

CustomTunnel validTunnel({String theme = 'Espace'}) => CustomTunnel(
      id: 't1',
      theme: theme,
      questions: [
        for (var i = 0; i < 3; i++)
          CustomQuestion(
              prompt: 'Q$i', answer: 'A$i', difficulty: TunnelDifficulty.easy),
        for (var i = 3; i < 6; i++)
          CustomQuestion(
              prompt: 'Q$i', answer: 'A$i', difficulty: TunnelDifficulty.medium),
        for (var i = 6; i < 9; i++)
          CustomQuestion(
              prompt: 'Q$i', answer: 'A$i', difficulty: TunnelDifficulty.hard),
      ],
    );

void main() {
  test('AppUser roundtrip', () {
    const u = AppUser(uid: 'u1', tokens: 250, langCode: 'ar');
    final back = AppUser.fromMap('u1', u.toMap());
    expect(back.tokens, 250);
    expect(back.langCode, 'ar');
  });

  test('AppUser valeurs par défaut', () {
    final u = AppUser.fromMap('u2', {});
    expect(u.tokens, 120);
    expect(u.langCode, 'fr');
    expect(u.displayName, '');
    expect(u.country, '--');
    expect(u.friendIds, isEmpty);
    expect(u.label, 'Joueur u2');
    expect(const AppUser(uid: 'abcdef').label, 'Joueur ABCD');
  });

  test('AppUser social roundtrip', () {
    const u = AppUser(
      uid: 'abcdef',
      tokens: 300,
      langCode: 'fr',
      displayName: 'Zoe',
      country: 'FR',
      friendIds: ['u2', 'u3'],
    );
    final back = AppUser.fromMap('abcdef', u.toMap());
    expect(back.displayName, 'Zoe');
    expect(back.label, 'Zoe');
    expect(back.country, 'FR');
    expect(back.friendIds, ['u2', 'u3']);
  });

  test('GameTunnel pont local <-> cloud', () {
    final local = validTunnel();
    final game = GameTunnel.fromCustomTunnel(
      local,
      creatorId: 'uid-1',
      isPublic: true,
      imageUrl: 'https://x/y.jpg',
    );
    expect(game.isValid, isTrue);
    expect(game.creatorId, 'uid-1');
    expect(game.questions.length, 9);

    final back =
        GameTunnel.fromMap('doc1', game.toMap());
    expect(back.id, 'doc1');
    expect(back.theme, 'Espace');
    expect(back.isPublic, isTrue);
    expect(back.isValid, isTrue);

    final relocal = back.toCustomTunnel();
    expect(relocal.isValid, isTrue);
    expect(relocal.questions.length, 9);
  });

  test('GameTunnel invalide si contrat 9 questions rompu', () {
    final game = GameTunnel(
      theme: 'X',
      creatorId: 'u',
      questions: const [
        GameQuestion(
            prompt: 'Q', answer: 'A', difficulty: TunnelDifficulty.easy),
      ],
    );
    expect(game.isValid, isFalse);
  });

  test('GameSession newRun + roundtrip', () {
    final s = GameSession.newRun(tunnelId: 't1', uid: 'u1');
    expect(s.participantIds, ['u1']);
    expect(s.finished, isFalse);
    final full = s.copyWith(score: 300, finished: true, position: 6);
    final back = GameSession.fromMap('s1', full.toMap());
    expect(back.score, 300);
    expect(back.finished, isTrue);
    expect(back.participantIds, contains('u1'));
  });

  test('mergeTokens sans perte', () {
    // Compte neuf : le local est poussé tel quel.
    expect(
        MigrationService.mergeTokens(local: 120, cloud: null), 120);
    // Gains hors ligne : le max gagne.
    expect(MigrationService.mergeTokens(local: 300, cloud: 120), 300);
    // Cloud plus riche (2e appareil) : le cloud gagne.
    expect(MigrationService.mergeTokens(local: 120, cloud: 500), 500);
  });
}
