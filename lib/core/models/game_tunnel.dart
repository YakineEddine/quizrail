import '../../features/tunnel/custom_tunnel.dart';

/// Question version cloud — même contrat que [CustomQuestion].
class GameQuestion {
  const GameQuestion({
    required this.prompt,
    required this.answer,
    required this.difficulty,
  });

  final String prompt;
  final String answer;
  final TunnelDifficulty difficulty;

  bool get isValid =>
      prompt.trim().isNotEmpty && answer.trim().isNotEmpty;

  factory GameQuestion.fromCustom(CustomQuestion q) => GameQuestion(
        prompt: q.prompt,
        answer: q.answer,
        difficulty: q.difficulty,
      );

  CustomQuestion toCustom() =>
      CustomQuestion(prompt: prompt, answer: answer, difficulty: difficulty);

  Map<String, Object?> toMap() => {
        'prompt': prompt,
        'answer': answer,
        'difficulty': difficulty.code,
      };

  factory GameQuestion.fromMap(Map<String, Object?> map) {
    return GameQuestion(
      prompt: (map['prompt'] as String?) ?? '',
      answer: (map['answer'] as String?) ?? '',
      difficulty:
          TunnelDifficultyX.fromCode(map['difficulty'] as String?),
    );
  }
}

/// Tunnel version cloud — miroir de tunnels/{id} dans Firestore.
/// Pont bidirectionnel avec [CustomTunnel] (stockage local).
class GameTunnel {
  const GameTunnel({
    this.id = '',
    required this.theme,
    this.imageUrl,
    required this.creatorId,
    this.isPublic = false,
    this.langCode = 'fr',
    required this.questions,
    this.createdAtMillis,
  });

  final String id;
  final String theme;
  final String? imageUrl;
  final String creatorId;
  final bool isPublic;
  final String langCode;
  final List<GameQuestion> questions;
  final int? createdAtMillis;

  /// Même contrat que [CustomTunnel.isValid] : 9 questions, 3 par difficulté.
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

  factory GameTunnel.fromCustomTunnel(
    CustomTunnel t, {
    required String creatorId,
    bool isPublic = false,
    String? imageUrl,
    String langCode = 'fr',
  }) {
    return GameTunnel(
      theme: t.theme,
      imageUrl: imageUrl ?? t.imagePath,
      creatorId: creatorId,
      isPublic: isPublic,
      langCode: langCode,
      questions: t.questions.map(GameQuestion.fromCustom).toList(),
    );
  }

  CustomTunnel toCustomTunnel() => CustomTunnel(
        id: id.isEmpty
            ? DateTime.now().millisecondsSinceEpoch.toString()
            : id,
        theme: theme,
        imagePath: imageUrl,
        questions: questions.map((q) => q.toCustom()).toList(),
      );

  Map<String, Object?> toMap() => {
        'theme': theme,
        if (imageUrl != null) 'imageUrl': imageUrl,
        'creatorId': creatorId,
        'isPublic': isPublic,
        'lang': langCode,
        'questions': questions.map((q) => q.toMap()).toList(),
        if (createdAtMillis != null) 'createdAt': createdAtMillis,
      };

  factory GameTunnel.fromMap(String id, Map<String, Object?> map) {
    final raw = map['questions'] as List? ?? const [];
    return GameTunnel(
      id: id,
      theme: (map['theme'] as String?) ?? '',
      imageUrl: map['imageUrl'] as String?,
      creatorId: (map['creatorId'] as String?) ?? '',
      isPublic: (map['isPublic'] as bool?) ?? false,
      langCode: (map['lang'] as String?) ?? 'fr',
      questions: raw
          .whereType<Map>()
          .map((e) => GameQuestion.fromMap(
              e.map((k, v) => MapEntry(k.toString(), v))))
          .toList(),
      createdAtMillis: (map['createdAt'] as num?)?.toInt(),
    );
  }
}
