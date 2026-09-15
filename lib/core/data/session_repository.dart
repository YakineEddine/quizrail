import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/game_session.dart';
import 'backend.dart';

/// Sessions de partie : Firestore uniquement quand en ligne
/// (pas de cache local Phase 1 — la partie en cours reste en mémoire).
class SessionRepository {
  FirebaseFirestore? get _fs => Backend.instance.firestore;
  String? get _uid => Backend.instance.uid;
  bool get isOnline => Backend.instance.isOnline;

  /// Crée ou met à jour une session. Retourne null hors ligne.
  Future<String?> save(GameSession session) async {
    final fs = _fs;
    final uid = _uid;
    if (fs == null || uid == null) return null;
    try {
      final parts = {...session.participantIds, uid}.toList();
      final data = {
        ...session.toMap(),
        'participantIds': parts,
        'updatedAt': FieldValue.serverTimestamp(),
        if (session.createdAtMillis == null)
          'createdAt': FieldValue.serverTimestamp(),
      };
      if (session.id.isEmpty) {
        final doc = await fs
            .collection('sessions')
            .add(data)
            .timeout(const Duration(seconds: 10));
        return doc.id;
      }
      await fs
          .collection('sessions')
          .doc(session.id)
          .set(data, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));
      return session.id;
    } catch (_) {
      return null;
    }
  }

  Future<List<GameSession>> mySessions({int limit = 20}) async {
    final fs = _fs;
    final uid = _uid;
    if (fs == null || uid == null) return const [];
    try {
      final snap = await fs
          .collection('sessions')
          .where('participantIds', arrayContains: uid)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 10));
      return snap.docs
          .map((d) => GameSession.fromMap(
              d.id,
              d.data().map((k, v) => MapEntry(k.toString(), v as Object?))))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
