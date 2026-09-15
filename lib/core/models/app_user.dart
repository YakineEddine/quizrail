/// Profil cloud QuizRail — miroir de users/{uid} dans Firestore.
/// Pur Dart (aucun plugin) : testable sans Firebase.
class AppUser {
  const AppUser({
    required this.uid,
    this.tokens = 120,
    this.langCode = 'fr',
    this.createdAtMillis,
  });

  final String uid;
  final int tokens;
  final String langCode;
  final int? createdAtMillis;

  Map<String, Object?> toMap() => {
        'tokens': tokens,
        'lang': langCode,
        if (createdAtMillis != null) 'createdAt': createdAtMillis,
      };

  factory AppUser.fromMap(String uid, Map<String, Object?> map) {
    return AppUser(
      uid: uid,
      tokens: (map['tokens'] as num?)?.toInt() ?? 120,
      langCode: (map['lang'] as String?) ?? 'fr',
      createdAtMillis: (map['createdAt'] as num?)?.toInt(),
    );
  }
}
