import '../i18n/app_lang.dart';

/// Room Party — miroir de rooms/{id} (état global écrit par les fonctions,
/// jamais directement par les clients).
class PartyQuestion {
  const PartyQuestion({required this.prompt, required this.difficulty});

  final Map<String, String> prompt;
  final String difficulty;

  String text(AppLang lang) => prompt[lang.code] ?? prompt['fr'] ?? '';

  factory PartyQuestion.fromMap(Map<String, Object?> map) {
    final raw = (map['prompt'] as Map? ?? {})
        .map((k, v) => MapEntry(k.toString(), v.toString()));
    return PartyQuestion(
      prompt: Map<String, String>.from(raw),
      difficulty: (map['difficulty'] as String?) ?? 'medium',
    );
  }
}

class PartyPlayer {
  const PartyPlayer({
    required this.uid,
    this.displayName = '',
    this.score = 0,
    this.correct = 0,
    this.answered = 0,
    this.streak = 0,
    this.bestStreak = 0,
    this.lastQuestionIndex = -1,
    this.finished = false,
    this.finishedAtMs = 0,
    this.connected = true,
    this.lastSeenMs = 0,
  });

  final String uid;
  final String displayName;
  final int score;
  final int correct;
  final int answered;
  final int streak;
  final int bestStreak;
  final int lastQuestionIndex;
  final bool finished;
  final int finishedAtMs;
  final bool connected;
  final int lastSeenMs;

  bool isSilent(int nowMs) => nowMs - lastSeenMs >= 30000;

  factory PartyPlayer.fromMap(String uid, Map<String, Object?> map) {
    int n(String k) => (map[k] as num?)?.toInt() ?? 0;
    return PartyPlayer(
      uid: uid,
      displayName: (map['displayName'] as String?) ?? '',
      score: n('score'),
      correct: n('correct'),
      answered: n('answered'),
      streak: n('streak'),
      bestStreak: n('bestStreak'),
      lastQuestionIndex: (map['lastQuestionIndex'] as num?)?.toInt() ?? -1,
      finished: (map['finished'] as bool?) ?? false,
      finishedAtMs: n('finishedAt'),
      connected: (map['connected'] as bool?) ?? true,
      lastSeenMs: n('lastSeen'),
    );
  }
}

class PartyRoom {
  const PartyRoom({
    required this.id,
    required this.code,
    required this.hostId,
    required this.status,
    required this.theme,
    required this.questions,
    required this.questionIndex,
    required this.playerIds,
    this.winnerUid,
    this.isDraw = false,
  });

  final String id;
  final String code;
  final String hostId;
  final String status;
  final String theme;
  final List<PartyQuestion> questions;
  final int questionIndex;
  final List<String> playerIds;
  final String? winnerUid;
  final bool isDraw;

  bool get isLobby => status == 'lobby';
  bool get isPlaying => status == 'playing';
  bool get isFinished => status == 'finished';
  bool isHost(String uid) => hostId == uid;

  factory PartyRoom.fromMap(String id, Map<String, Object?> map) {
    final rawQuestions = (map['questions'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => PartyQuestion.fromMap(
            e.map((k, v) => MapEntry(k.toString(), v as Object?))))
        .toList();
    return PartyRoom(
      id: id,
      code: (map['code'] as String?) ?? '',
      hostId: (map['hostId'] as String?) ?? '',
      status: (map['status'] as String?) ?? 'lobby',
      theme: (map['theme'] as String?) ?? '',
      questions: rawQuestions,
      questionIndex: (map['questionIndex'] as num?)?.toInt() ?? 0,
      playerIds: ((map['playerIds'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      winnerUid: map['winnerUid'] as String?,
      isDraw: (map['isDraw'] as bool?) ?? false,
    );
  }
}

/// Code room : 6 caractères non ambigus (pas de 0/O/1/I).
bool validRoomCode(String code) =>
    RegExp(r'^[A-Z0-9]{6}$').hasMatch(code.trim().toUpperCase()) &&
    !RegExp(r'[01IO]').hasMatch(code.trim().toUpperCase());

/// Gagnant party (miroir affichage, le serveur arbitre) : meilleur score,
/// départage au premier à avoir fini, sinon nul.
({String? winnerUid, bool isDraw}) partyWinner(List<PartyPlayer> players) {
  if (players.isEmpty) return (winnerUid: null, isDraw: true);
  final top = players.map((p) => p.score).reduce((a, b) => a > b ? a : b);
  final first = players.where((p) => p.score == top).toList();
  if (first.length == 1) return (winnerUid: first.first.uid, isDraw: false);
  final done =
      first.where((p) => p.finishedAtMs > 0).toList()
        ..sort((a, b) => a.finishedAtMs.compareTo(b.finishedAtMs));
  if (done.isNotEmpty) return (winnerUid: done.first.uid, isDraw: false);
  return (winnerUid: null, isDraw: true);
}
