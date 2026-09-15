import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../features/tunnel/custom_tunnel.dart';
import '../../features/tunnel/custom_tunnel_store.dart';
import '../models/game_tunnel.dart';
import 'backend.dart';

/// Tunnels : CustomTunnelStore local en cache/édition,
/// Firestore (tunnels) en partage + catalogue public.
/// Hors ligne : publication impossible (erreur explicite),
/// lecture publique vide (les brouillons restent locaux).
class TunnelRepository {
  TunnelRepository({required this.local});

  final CustomTunnelStore local;

  FirebaseFirestore? get _fs => Backend.instance.firestore;
  FirebaseStorage? get _storage =>
      Backend.instance.isOnline ? FirebaseStorage.instance : null;
  String? get _uid => Backend.instance.uid;
  bool get isOnline => Backend.instance.isOnline;

  /// Publie un tunnel local : upload optionnel de l'image vers Storage,
  /// puis création du doc Firestore (rules : creatorId == uid).
  /// Retourne l'id du document. Le brouillon local est conservé.
  Future<String> publishTunnel(
    CustomTunnel tunnel, {
    Uint8List? imageBytes,
    bool isPublic = true,
    String langCode = 'fr',
  }) async {
    final fs = _fs;
    final storage = _storage;
    final uid = _uid;
    if (fs == null || uid == null) {
      throw StateError('Hors ligne : publication impossible.');
    }
    if (!GameTunnel.fromCustomTunnel(tunnel, creatorId: uid).isValid) {
      throw StateError('Tunnel incomplet (9 questions requises).');
    }
    String? imageUrl;
    if (imageBytes != null && storage != null) {
      final name = DateTime.now().millisecondsSinceEpoch;
      final ref = storage.ref('tunnel-images/$uid/$name.jpg');
      await ref
          .putData(imageBytes, SettableMetadata(contentType: 'image/jpeg'))
          .timeout(const Duration(seconds: 30));
      imageUrl = await ref.getDownloadURL().timeout(
            const Duration(seconds: 30),
          );
    }
    final game = GameTunnel.fromCustomTunnel(
      tunnel,
      creatorId: uid,
      isPublic: isPublic,
      imageUrl: imageUrl,
      langCode: langCode,
    );
    final doc = await fs
        .collection('tunnels')
        .add({...game.toMap(), 'createdAt': FieldValue.serverTimestamp()})
        .timeout(const Duration(seconds: 15));
    return doc.id;
  }

  Future<List<GameTunnel>> listPublicTunnels({int limit = 20}) async {
    final fs = _fs;
    if (fs == null) return const [];
    try {
      final snap = await fs
          .collection('tunnels')
          .where('isPublic', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 10));
      return snap.docs
          .map((d) => GameTunnel.fromMap(d.id, _stringKeyed(d.data())))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<GameTunnel>> myTunnels() async {
    final fs = _fs;
    final uid = _uid;
    if (fs == null || uid == null) return const [];
    try {
      final snap = await fs
          .collection('tunnels')
          .where('creatorId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 10));
      return snap.docs
          .map((d) => GameTunnel.fromMap(d.id, _stringKeyed(d.data())))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Map<String, Object?> _stringKeyed(Map<Object?, Object?> raw) =>
      raw.map((k, v) => MapEntry(k.toString(), v));
}
