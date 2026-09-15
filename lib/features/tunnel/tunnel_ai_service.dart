import 'package:cloud_functions/cloud_functions.dart';

import '../../features/tunnel/custom_tunnel.dart';
import '../../core/data/backend.dart';

/// Appel client de la Cloud Function `generateTunnel`.
/// La clé API Claude reste dans Secret Manager : le client n'envoie
/// que { theme, lang } et reçoit 9 questions validées.
class TunnelAiService {
  /// Génère 9 questions (3 par difficulté) pour [theme].
  /// Lève [StateError] avec un message affichable en cas d'échec.
  Future<List<CustomQuestion>> generate({
    required String theme,
    String lang = 'fr',
  }) async {
    if (!Backend.instance.isOnline) {
      throw StateError('IA indisponible hors ligne.');
    }
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('generateTunnel');
      final res = await callable
          .call({'theme': theme.trim(), 'lang': lang}).timeout(
            const Duration(seconds: 100),
          );
      final data = res.data as Map;
      final raw = data['questions'] as List;
      final questions = raw.map((e) {
        final m = (e as Map).map((k, v) => MapEntry(k.toString(), v));
        return CustomQuestion.fromJson(
            m.map((k, v) => MapEntry(k, v as Object?)));
      }).toList();
      final tunnel = CustomTunnel(
        id: 'ai-preview',
        theme: theme,
        questions: questions,
      );
      if (!tunnel.isValid) {
        throw StateError('Réponse IA invalide, réessaie.');
      }
      return questions;
    } on FirebaseFunctionsException catch (e) {
      throw StateError(_friendly(e));
    } catch (_) {
      throw StateError('La génération IA a échoué, réessaie.');
    }
  }

  String _friendly(FirebaseFunctionsException e) => switch (e.code) {
        'unauthenticated' => 'Connexion requise pour l\u2019IA.',
        'invalid-argument' =>
          e.message ?? 'Thème invalide pour l\u2019IA.',
        'resource-exhausted' =>
          'Quota IA du jour atteint (5 générations).',
        _ => 'La génération IA a échoué, réessaie.',
      };
}
