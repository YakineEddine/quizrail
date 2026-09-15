/// Entrée de classement — miroir de leaderboard/{uid}.
/// Écrite uniquement côté serveur (fin de duel / fin de party).
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.uid,
    this.displayName = '',
    this.country = '--',
    this.bestScore = 0,
    this.wins = 0,
    this.games = 0,
  });

  final String uid;
  final String displayName;
  final String country;
  final int bestScore;
  final int wins;
  final int games;

  String get label =>
      displayName.isNotEmpty ? displayName : 'Joueur ${uid.length >= 4 ? uid.substring(0, 4).toUpperCase() : uid}';

  factory LeaderboardEntry.fromMap(String uid, Map<String, Object?> map) {
    return LeaderboardEntry(
      uid: uid,
      displayName: (map['displayName'] as String?) ?? '',
      country: (map['country'] as String?) ?? '--',
      bestScore: (map['bestScore'] as num?)?.toInt() ?? 0,
      wins: (map['wins'] as num?)?.toInt() ?? 0,
      games: (map['games'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Tri affichage : meilleur score décroissant.
List<LeaderboardEntry> sortBoard(List<LeaderboardEntry> entries) {
  final sorted = [...entries];
  sorted.sort((a, b) => b.bestScore.compareTo(a.bestScore));
  return sorted;
}
