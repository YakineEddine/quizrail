import 'package:cloud_firestore/cloud_firestore.dart';

import '../../features/tunnel/custom_tunnel_store.dart';
import '../i18n/app_lang.dart';
import '../models/game_tunnel.dart';
import '../storage/app_prefs.dart';
import 'backend.dart';

/// Migration one-shot SharedPreferences → users/{uid}.
/// - Compte neuf (doc absent) : tout le local est poussé (zéro perte).
/// - Doc existant (réinstall / 2e appareil) : fusion sans perte —
///   jetons = max(local, cloud), langue locale conservée uniquement si
///   le cloud n'en a pas, tunnels customs locaux importés en privés.
/// - Échec réseau ou backend offline : false, réessayé au prochain lancement.
class MigrationService {
  /// Fusion jetons sans perte (testable sans Firebase).
  static int mergeTokens({required int local, required int? cloud}) {
    if (cloud == null) return local;
    return local > cloud ? local : cloud;
  }

  /// Pseudo repli déterministe (même convention que les fonctions).
  static String _defaultDisplayName(String uid) =>
      'Joueur ${uid.length >= 4 ? uid.substring(0, 4).toUpperCase() : uid}';

  static Future<bool> migrateIfNeeded({
    required AppPrefs prefs,
    required CustomTunnelStore customs,
  }) async {
    if (prefs.cloudMigrated) return true;
    final backend = Backend.instance;
    final fs = backend.firestore;
    final uid = backend.uid;
    if (fs == null || uid == null) return false;
    try {
      final userRef = fs.doc('users/$uid');
      final snap = await userRef
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));
      if (!snap.exists) {
        await userRef.set({
          'tokens': prefs.tokens,
          'lang': prefs.lang.code,
          'displayName': _defaultDisplayName(uid),
          'country': '--',
          'friendIds': const [],
          'createdAt': FieldValue.serverTimestamp(),
          'migratedAt': FieldValue.serverTimestamp(),
        }).timeout(const Duration(seconds: 10));
      } else {
        final data = snap.data() ?? {};
        final cloudTokens = (data['tokens'] as num?)?.toInt();
        final merged = mergeTokens(local: prefs.tokens, cloud: cloudTokens);
        final update = <String, Object?>{
          'migratedAt': FieldValue.serverTimestamp(),
        };
        if (merged != cloudTokens) update['tokens'] = merged;
        if ((data['lang'] as String?) == null) {
          update['lang'] = prefs.lang.code;
        }
        // Backfill social : n'écrase jamais un pseudo/pays déjà choisi.
        if ((data['displayName'] as String?) == null) {
          update['displayName'] = _defaultDisplayName(uid);
        }
        if ((data['country'] as String?) == null) {
          update['country'] = '--';
        }
        if (data['friendIds'] == null) {
          update['friendIds'] = const [];
        }
        await userRef
            .set(update, SetOptions(merge: true))
            .timeout(const Duration(seconds: 10));
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
        await fs.collection('tunnels').add({
          ...game.toMap(),
          'createdAt': FieldValue.serverTimestamp(),
          'migratedFromLocal': true,
        }).timeout(const Duration(seconds: 10));
      }
      await prefs.setCloudMigrated(true);
      return true;
    } catch (_) {
      return false;
    }
  }
}
