import '../../features/tunnel/custom_tunnel.dart';
import '../../core/data/backend.dart';
import 'tunnel_local_generator.dart';

/// Appel de l'Edge Function Supabase `generate-tunnel` (gratuite).
/// Les clés API (Gemini, OpenAI) restent dans les secrets du projet :
/// le client n'envoie que { theme, lang } et reçoit 9 questions validées.
/// Hors ligne : repli local immédiat ([TunnelLocalGenerator]).
class TunnelAiService {
  /// Vrai quand la dernière génération a utilisé le repli local.
  bool lastWasLocalFallback = false;

  /// Génère 9 questions (3 par difficulté) pour [theme].
  /// Lève [StateError] avec un message affichable en cas d'échec.
  Future<List<CustomQuestion>> generate({
    required String theme,
    String lang = 'fr',
  }) async {
    final db = Backend.instance.client;
    if (!Backend.instance.isOnline || db == null) {
      lastWasLocalFallback = true;
      return TunnelLocalGenerator.generate(theme: theme, lang: lang);
    }
    lastWasLocalFallback = false;
    try {
      final res = await db.functions
          .invoke('generate-tunnel', body: {
            'theme': theme.trim(),
            'lang': lang,
          })
          .timeout(const Duration(seconds: 100));
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
        throw StateError('Réponse IA invalide.');
      }
      return questions;
    } catch (_) {
      // Serveur IA injoignable / non déployé / quota : repli local,
      // le bouton reste toujours utile (9 questions valides).
      lastWasLocalFallback = true;
      return TunnelLocalGenerator.generate(theme: theme, lang: lang);
    }
  }
}
