import '../../features/tunnel/custom_tunnel_store.dart';
import '../i18n/app_lang.dart';
import '../models/game_tunnel.dart';
import '../storage/app_prefs.dart';
import 'backend.dart';

/// Migration one-shot SharedPreferences → table `profiles` (+ copies
/// privées des tunnels customs vers `tunnels`).
/// - Compte neuf (profil absent) : tout le local est poussé (zéro perte).
/// - Profil existant (réinstall / 2e appareil) : fusion sans perte —
///   jetons = max(local, cloud), tunnels customs locaux importés en privés.
/// - Échec réseau ou backend offline : false, réessayé au prochain lancement.
class MigrationService {
  /// Fusion jetons sans perte (testable sans backend).
  static int mergeTokens({required int local, required int? cloud}) {
    if (cloud == null) return local;
    return local > cloud ? local : cloud;
  }

  /// Pseudo repli déterministe (même convention que le serveur).
  static String _defaultDisplayName(String uid) =>
      'Joueur ${uid.length >= 4 ? uid.substring(0, 4).toUpperCase() : uid}';

  static Future<bool> migrateIfNeeded({
    required AppPrefs prefs,
    required CustomTunnelStore customs,
  }) async {
    if (prefs.cloudMigrated) return true;
    final backend = Backend.instance;
    final db = backend.client;
    final uid = backend.uid;
    if (db == null || uid == null) return false;
    try {
      final row = await db
          .from('profiles')
          .select()
          .eq('uid', uid)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));
      if (row == null) {
        await db.from('profiles').insert({
          'uid': uid,
          'tokens': prefs.tokens,
          'lang': prefs.lang.code,
          'display_name': _defaultDisplayName(uid),
          'country': '--',
        }).timeout(const Duration(seconds: 10));
      } else {
        final cloudTokens = (row['tokens'] as num?)?.toInt();
        final merged = mergeTokens(local: prefs.tokens, cloud: cloudTokens);
        final update = <String, Object?>{};
        if (merged != cloudTokens) update['tokens'] = merged;
        if (((row['display_name'] as String?) ?? '').isEmpty) {
          update['display_name'] = _defaultDisplayName(uid);
        }
        if (((row['country'] as String?) ?? '--') == '--') {
          update['country'] = '--';
        }
        if (update.isNotEmpty) {
          await db
              .from('profiles')
              .update(update)
              .eq('uid', uid)
              .timeout(const Duration(seconds: 10));
        }
        if (merged != prefs.tokens) {
          await prefs.setTokens(merged);
        }
      }
      // Tunnels customs locaux → copies privées cloud (brouillons gardés).
      for (final t in customs.tunnels) {
        final game = GameTunnel.fromCustomTunnel(
          t,
          creatorId: uid,
          isPublic: false,
        );
        if (!game.isValid) continue;
        await db.from('tunnels').insert({
          'theme': game.theme,
          'questions': game.questions.map((q) => q.toMap()).toList(),
          'creator_id': uid,
          'is_public': false,
          'lang': game.langCode,
        }).timeout(const Duration(seconds: 10));
      }
      await prefs.setCloudMigrated(true);
      return true;
    } catch (_) {
      return false;
    }
  }
}
