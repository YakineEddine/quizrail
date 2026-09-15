/// Partie persistée — miroir de sessions/{id} dans Firestore.
/// Seuls les uids de [participantIds] peuvent la lire/écrire (rules).
class GameSession {
  const GameSession({
    this.id = '',
    required this.tunnelId,
    required this.participantIds,
    this.score = 0,
    this.bestStreak = 0,
    this.tokensEarned = 0,
    this.position = 0,
    this.totalTiles = 12,
    this.finished = false,
    this.createdAtMillis,
  });

  final String id;
  final String tunnelId;
  final List<String> participantIds;
  final int score;
  final int bestStreak;
  final int tokensEarned;
  final int position;
  final int totalTiles;
  final bool finished;
  final int? createdAtMillis;

  factory GameSession.newRun({
    required String tunnelId,
    required String uid,
    int totalTiles = 12,
  }) {
    return GameSession(
      tunnelId: tunnelId,
      participantIds: [uid],
      totalTiles: totalTiles,
    );
  }

  GameSession copyWith({
    int? score,
    int? bestStreak,
    int? tokensEarned,
    int? position,
    bool? finished,
  }) {
    return GameSession(
      id: id,
      tunnelId: tunnelId,
      participantIds: participantIds,
      score: score ?? this.score,
      bestStreak: bestStreak ?? this.bestStreak,
      tokensEarned: tokensEarned ?? this.tokensEarned,
      position: position ?? this.position,
      totalTiles: totalTiles,
      finished: finished ?? this.finished,
      createdAtMillis: createdAtMillis,
    );
  }

  Map<String, Object?> toMap() => {
        'tunnelId': tunnelId,
        'participantIds': participantIds,
        'score': score,
        'bestStreak': bestStreak,
        'tokensEarned': tokensEarned,
        'position': position,
        'totalTiles': totalTiles,
        'finished': finished,
        if (createdAtMillis != null) 'createdAt': createdAtMillis,
      };

  factory GameSession.fromMap(String id, Map<String, Object?> map) {
    final rawParts = map['participantIds'] as List? ?? const [];
    return GameSession(
      id: id,
      tunnelId: (map['tunnelId'] as String?) ?? '',
      participantIds: rawParts.map((e) => e.toString()).toList(),
      score: (map['score'] as num?)?.toInt() ?? 0,
      bestStreak: (map['bestStreak'] as num?)?.toInt() ?? 0,
      tokensEarned: (map['tokensEarned'] as num?)?.toInt() ?? 0,
      position: (map['position'] as num?)?.toInt() ?? 0,
      totalTiles: (map['totalTiles'] as num?)?.toInt() ?? 12,
      finished: (map['finished'] as bool?) ?? false,
      createdAtMillis: (map['createdAt'] as num?)?.toInt(),
    );
  }
}
