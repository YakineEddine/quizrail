import '../i18n/app_lang.dart';

/// Duel temps réel — miroir de duels/{id} (lecture seule côté client,
/// sauf présence). Toute écriture de score passe par les Cloud Functions.
///
/// Les constantes ci-dessous DOIVENT rester synchronisées avec
/// functions/src/duel.ts (coûts, durées, règles de score).
abstract final class DuelRules {
  static const int questionCount = 8;
  static const int minElapsedMs = 700;
  static const int forfeitGraceMs = 30000;
  static const int freezeMs = 5000;
  static const int doubleMs = 20000;
  static const int stealAmount = 10;
  static const int scoreCorrect = 100;
  static const int scoreStreakBonus = 25; // à partir de 3 de suite
}

enum DuelPower { freeze, doubleGains, steal }

extension DuelPowerX on DuelPower {
  /// Nom attendu par la callable usePower.
  String get apiName => switch (this) {
        DuelPower.freeze => 'freeze',
        DuelPower.doubleGains => 'double',
        DuelPower.steal => 'steal',
      };

  int get cost => switch (this) {
        DuelPower.freeze => 15,
        DuelPower.doubleGains => 10,
        DuelPower.steal => 20,
      };
}

/// État d'un joueur dans le duel.
class DuelPlayerState {
  const DuelPlayerState({
    this.langCode = 'fr',
    this.score = 0,
    this.correct = 0,
    this.wrong = 0,
    this.streak = 0,
    this.bestStreak = 0,
    this.answered = 0,
    this.position = 0,
    this.totalElapsedMs = 0,
    this.finished = false,
    this.connected = true,
    this.lastSeenMs = 0,
    this.frozenUntilMs = 0,
    this.doubleUntilMs = 0,
  });

  final String langCode;
  final int score;
  final int correct;
  final int wrong;
  final int streak;
  final int bestStreak;
  final int answered;
  final int position;
  final int totalElapsedMs;
  final bool finished;
  final bool connected;
  final int lastSeenMs;
  final int frozenUntilMs;
  final int doubleUntilMs;

  bool isFrozen(int nowMs) => nowMs < frozenUntilMs;
  bool hasDouble(int nowMs) => nowMs < doubleUntilMs;

  factory DuelPlayerState.fromMap(Map<String, Object?> map) {
    int n(String k) => (map[k] as num?)?.toInt() ?? 0;
    return DuelPlayerState(
      langCode: (map['lang'] as String?) ?? 'fr',
      score: n('score'),
      correct: n('correct'),
      wrong: n('wrong'),
      streak: n('streak'),
      bestStreak: n('bestStreak'),
      answered: n('answered'),
      position: n('position'),
      totalElapsedMs: n('totalElapsedMs'),
      finished: (map['finished'] as bool?) ?? false,
      connected: (map['connected'] as bool?) ?? true,
      lastSeenMs: n('lastSeen'),
      frozenUntilMs: n('frozenUntil'),
      doubleUntilMs: n('doubleUntil'),
    );
  }
}

class DuelQuestion {
  const DuelQuestion({required this.prompt, required this.difficulty});

  final Map<String, String> prompt;
  final String difficulty;

  String text(AppLang lang) =>
      prompt[lang.code] ?? prompt['fr'] ?? '';

  factory DuelQuestion.fromMap(Map<String, Object?> map) {
    final raw = (map['prompt'] as Map? ?? {}).map(
      (k, v) => MapEntry(k.toString(), v.toString()),
    );
    return DuelQuestion(
      prompt: Map<String, String>.from(raw),
      difficulty: (map['difficulty'] as String?) ?? 'medium',
    );
  }
}

/// Doc duel complet (affichage uniquement — le serveur arbitre).
class GameDuel {
  const GameDuel({
    required this.id,
    required this.playerIds,
    required this.status,
    required this.questions,
    required this.players,
    this.winnerUid,
    this.finishReason,
    this.isDraw = false,
    this.rematchRequests = const [],
  });

  final String id;
  final List<String> playerIds;
  final String status;
  final List<DuelQuestion> questions;
  final Map<String, DuelPlayerState> players;
  final String? winnerUid;
  final String? finishReason;
  final bool isDraw;
  final List<String> rematchRequests;

  bool get isFinished => status == 'finished';
  bool get isForfeit => finishReason == 'forfeit';

  String opponentOf(String uid) =>
      playerIds.firstWhere((id) => id != uid, orElse: () => '');

  DuelPlayerState me(String uid) =>
      players[uid] ?? const DuelPlayerState();
  DuelPlayerState opponent(String uid) =>
      players[opponentOf(uid)] ?? const DuelPlayerState();

  factory GameDuel.fromMap(String id, Map<String, Object?> map) {
    final rawPlayers = (map['players'] as Map? ?? {}).map(
      (k, v) => MapEntry(
        k.toString(),
        DuelPlayerState.fromMap(
          (v as Map).map((kk, vv) => MapEntry(kk.toString(), vv as Object?)),
        ),
      ),
    );
    final rawQuestions = (map['questions'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => DuelQuestion.fromMap(
            e.map((k, v) => MapEntry(k.toString(), v as Object?))))
        .toList();
    return GameDuel(
      id: id,
      playerIds: ((map['playerIds'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      status: (map['status'] as String?) ?? 'running',
      questions: rawQuestions,
      players: Map<String, DuelPlayerState>.from(rawPlayers),
      winnerUid: map['winnerUid'] as String?,
      finishReason: map['finishReason'] as String?,
      isDraw: (map['isDraw'] as bool?) ?? false,
      rematchRequests: ((map['rematchRequests'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

/// Départage affichage (le serveur est l'arbitre officiel) :
/// score, puis temps total le plus court, puis nul.
String? decideWinnerUid(
  String aUid,
  DuelPlayerState a,
  String bUid,
  DuelPlayerState b,
) {
  if (a.score != b.score) return a.score > b.score ? aUid : bUid;
  if (a.totalElapsedMs != b.totalElapsedMs) {
    return a.totalElapsedMs < b.totalElapsedMs ? aUid : bUid;
  }
  return null; // match nul
}

/// Forfait réclamable si l'adversaire est silencieux depuis 30 s.
bool canClaimForfeit({required int nowMs, required int oppLastSeenMs}) =>
    nowMs - oppLastSeenMs >= DuelRules.forfeitGraceMs;
