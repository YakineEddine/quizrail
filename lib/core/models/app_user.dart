/// Profil cloud QuizRail — miroir de users/{uid} dans Firestore.
/// Pur Dart (aucun plugin) : testable sans Firebase.
/// Les champs sociaux (pseudo, pays, amis) sont lus/écrits par les
/// écrans de classements et les fonctions (jamais de score côté client).
class AppUser {
  const AppUser({
    required this.uid,
    this.tokens = 120,
    this.langCode = 'fr',
    this.createdAtMillis,
    this.displayName = '',
    this.country = '--',
    this.friendIds = const [],
  });

  final String uid;
  final int tokens;
  final String langCode;
  final int? createdAtMillis;
  final String displayName;
  final String country;
  final List<String> friendIds;

  /// Nom affiché avec repli déterministe (même convention que le serveur).
  String get label => displayName.isNotEmpty
      ? displayName
      : 'Joueur ${uid.length >= 4 ? uid.substring(0, 4).toUpperCase() : uid}';

  Map<String, Object?> toMap() => {
        'tokens': tokens,
        'lang': langCode,
        if (createdAtMillis != null) 'createdAt': createdAtMillis,
        if (displayName.isNotEmpty) 'displayName': displayName,
        if (country != '--') 'country': country,
        if (friendIds.isNotEmpty) 'friendIds': friendIds,
      };

  factory AppUser.fromMap(String uid, Map<String, Object?> map) {
    return AppUser(
      uid: uid,
      tokens: (map['tokens'] as num?)?.toInt() ?? 120,
      langCode: (map['lang'] as String?) ?? 'fr',
      createdAtMillis: _readMillis(map['createdAt']),
      displayName: (map['displayName'] as String?) ?? '',
      country: (map['country'] as String?) ?? '--',
      friendIds: ((map['friendIds'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  /// Millis : int en tests/cache, Timestamp Firestore en prod
  /// (sans dépendre du plugin pour garder le modèle en pur Dart).
  static int? _readMillis(Object? value) {
    if (value is num) return value.toInt();
    if (value == null) return null;
    try {
      final ms = (value as dynamic).millisecondsSinceEpoch as Object?;
      if (ms is num) return ms.toInt();
    } catch (_) {
      // Format inconnu : pas de date.
    }
    return null;
  }
}
