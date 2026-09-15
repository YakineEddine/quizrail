/// Modèle Tunnel custom Phase 1 — 100 % local, zéro coût.
/// - 1 thème + 9 questions (3 par difficulté) + réponse exacte.
/// - image optionnelle : simple chemin local (image_picker), jamais uploadé.
enum TunnelDifficulty { easy, medium, hard }

extension TunnelDifficultyX on TunnelDifficulty {
  String label({String lang = 'fr'}) {
    switch (this) {
      case TunnelDifficulty.easy:
        return switch (lang) { 'en' => 'Easy', 'ar' => 'سهل', _ => 'Facile' };
      case TunnelDifficulty.medium:
        return switch (lang) { 'en' => 'Medium', 'ar' => 'متوسط', _ => 'Moyen' };
      case TunnelDifficulty.hard:
        return switch (lang) { 'en' => 'Hard', 'ar' => 'صعب', _ => 'Difficile' };
    }
  }

  String get code => name;
  static TunnelDifficulty fromCode(String? code) => switch (code) {
        'medium' => TunnelDifficulty.medium,
        'hard' => TunnelDifficulty.hard,
        _ => TunnelDifficulty.easy,
      };
}

/// Une question custom : énoncé + réponse exacte + difficulté.
class CustomQuestion {
  const CustomQuestion({
    required this.prompt,
    required this.answer,
    required this.difficulty,
  });

  final String prompt;
  final String answer;
  final TunnelDifficulty difficulty;

  bool get isValid =>
      prompt.trim().isNotEmpty && answer.trim().isNotEmpty;

  Map<String, Object?> toJson() => {
        'prompt': prompt,
        'answer': answer,
        'difficulty': difficulty.code,
      };

  factory CustomQuestion.fromJson(Map<String, Object?> json) {
    return CustomQuestion(
      prompt: (json['prompt'] as String?) ?? '',
      answer: (json['answer'] as String?) ?? '',
      difficulty:
          TunnelDifficultyX.fromCode(json['difficulty'] as String?),
    );
  }
}

/// Un tunnel custom complet : thème + image optionnelle + 9 questions.
class CustomTunnel {
  const CustomTunnel({
    required this.id,
    required this.theme,
    this.imagePath,
    required this.questions,
  });

  final String id;
  final String theme;
  final String? imagePath;
  final List<CustomQuestion> questions;

  /// Règles Phase 1 : thème non vide + 9 questions valides,
  /// exactement 3 par difficulté.
  bool get isValid {
    if (theme.trim().isEmpty) return false;
    if (questions.length != 9) return false;
    if (questions.any((q) => !q.isValid)) return false;
    for (final d in TunnelDifficulty.values) {
      if (questions.where((q) => q.difficulty == d).length != 3) {
        return false;
      }
    }
    return true;
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'theme': theme,
        'imagePath': imagePath,
        'questions': questions.map((q) => q.toJson()).toList(),
      };

  factory CustomTunnel.fromJson(Map<String, Object?> json) {
    final raw = json['questions'] as List? ?? const [];
    return CustomTunnel(
      id: (json['id'] as String?) ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      theme: (json['theme'] as String?) ?? '',
      imagePath: json['imagePath'] as String?,
      questions: raw
          .whereType<Map>()
          .map((e) => CustomQuestion.fromJson(
              e.map((k, v) => MapEntry(k.toString(), v))))
          .toList(),
    );
  }
}
