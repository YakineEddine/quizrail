import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/tunnel/custom_tunnel.dart';
import '../../features/tunnel/custom_tunnel_store.dart';
import '../models/game_tunnel.dart';
import 'backend.dart';

/// Ligne `tunnels` (snake_case) → [GameTunnel.fromMap].
GameTunnel gameTunnelFromRow(Map<String, dynamic> row) {
  return GameTunnel.fromMap((row['id'] as Object?).toString(), {
    'theme': row['theme'],
    'imageUrl': row['image_url'],
    'creatorId': row['creator_id'],
    'isPublic': row['is_public'],
    'lang': row['lang'],
    'questions': row['questions'],
    'createdAt': row['created_at'],
    'ratingAvg': row['rating_avg'],
    'ratingCount': row['rating_count'],
  });
}

/// Tunnels : CustomTunnelStore local en cache/édition,
/// Supabase (table `tunnels` + bucket `tunnel-images`) en partage.
/// Hors ligne : publication impossible (erreur explicite),
/// lecture publique vide (les brouillons restent locaux).
class TunnelRepository {
  TunnelRepository({required this.local});

  final CustomTunnelStore local;

  String? get _uid => Backend.instance.uid;
  bool get isOnline => Backend.instance.isOnline;

  /// Publie un tunnel local : upload optionnel de l'image vers le Storage,
  /// puis insertion (RLS : creator_id == uid).
  /// Retourne l'id. Le brouillon local est conservé.
  Future<String> publishTunnel(
    CustomTunnel tunnel, {
    Uint8List? imageBytes,
    bool isPublic = true,
    String langCode = 'fr',
  }) async {
    final db = Backend.instance.client;
    final uid = _uid;
    if (db == null || uid == null) {
      throw StateError('Hors ligne : publication impossible.');
    }
    if (!GameTunnel.fromCustomTunnel(tunnel, creatorId: uid).isValid) {
      throw StateError('Tunnel incomplet (9 questions requises).');
    }
    String? imageUrl;
    if (imageBytes != null) {
      final name = DateTime.now().millisecondsSinceEpoch;
      final path = '$uid/$name.jpg';
      try {
        await db.storage
            .from('tunnel-images')
            .uploadBinary(
              path,
              imageBytes,
              fileOptions:
                  const FileOptions(contentType: 'image/jpeg'),
            )
            .timeout(const Duration(seconds: 30));
        imageUrl = db.storage.from('tunnel-images').getPublicUrl(path);
      } catch (e) {
        throw Backend.friendly(e,
            fallback: 'Envoi de l’image impossible, réessaie.');
      }
    }
    final game = GameTunnel.fromCustomTunnel(
      tunnel,
      creatorId: uid,
      isPublic: isPublic,
      imageUrl: imageUrl,
      langCode: langCode,
    );
    try {
      final row = await db
          .from('tunnels')
          .insert({
            'theme': game.theme,
            'questions':
                game.questions.map((q) => q.toMap()).toList(),
            'creator_id': uid,
            'is_public': isPublic,
            'lang': langCode,
            'image_url': ?imageUrl,
          })
          .select('id')
          .single()
          .timeout(const Duration(seconds: 15));
      return (row['id'] as Object?).toString();
    } catch (e) {
      throw Backend.friendly(e, fallback: 'Publication impossible.');
    }
  }

  Future<List<GameTunnel>> listPublicTunnels({int limit = 20}) async {
    final db = Backend.instance.client;
    if (db == null) return const [];
    try {
      final rows = await db
          .from('tunnels')
          .select()
          .eq('is_public', true)
          .order('created_at', ascending: false)
          .limit(limit)
          .timeout(const Duration(seconds: 10));
      return (rows as List)
          .whereType<Map<String, dynamic>>()
          .map(gameTunnelFromRow)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<GameTunnel>> myTunnels() async {
    final db = Backend.instance.client;
    final uid = _uid;
    if (db == null || uid == null) return const [];
    try {
      final rows = await db
          .from('tunnels')
          .select()
          .eq('creator_id', uid)
          .order('created_at', ascending: false)
          .limit(50)
          .timeout(const Duration(seconds: 10));
      return (rows as List)
          .whereType<Map<String, dynamic>>()
          .map(gameTunnelFromRow)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
