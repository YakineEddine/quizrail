import '../models/game_session.dart';
import 'backend.dart';

/// Sessions de partie : Supabase (table `sessions`) uniquement quand
/// en ligne (pas de cache local Phase 1 — la partie en cours reste
/// en mémoire).
class SessionRepository {
  String? get _uid => Backend.instance.uid;
  bool get isOnline => Backend.instance.isOnline;

  /// Crée ou met à jour une session. Retourne null hors ligne.
  Future<String?> save(GameSession session) async {
    final db = Backend.instance.client;
    final uid = _uid;
    if (db == null || uid == null) return null;
    try {
      final parts = {...session.participantIds, uid}.toList();
      final data = {
        'tunnel_id': session.tunnelId,
        'participant_ids': parts,
        'score': session.score,
        'best_streak': session.bestStreak,
        'tokens_earned': session.tokensEarned,
        'position': session.position,
        'total_tiles': session.totalTiles,
        'finished': session.finished,
      };
      if (session.id.isEmpty) {
        final row = await db
            .from('sessions')
            .insert(data)
            .select('id')
            .single()
            .timeout(const Duration(seconds: 10));
        return (row['id'] as Object?).toString();
      }
      await db
          .from('sessions')
          .upsert({...data, 'id': session.id}).timeout(
            const Duration(seconds: 10),
          );
      return session.id;
    } catch (_) {
      return null;
    }
  }

  Future<List<GameSession>> mySessions({int limit = 20}) async {
    final db = Backend.instance.client;
    final uid = _uid;
    if (db == null || uid == null) return const [];
    try {
      final rows = await db
          .from('sessions')
          .select()
          .contains('participant_ids', [uid])
          .order('created_at', ascending: false)
          .limit(limit)
          .timeout(const Duration(seconds: 10));
      return (rows as List)
          .whereType<Map>()
          .map((r) => GameSession.fromMap(
                (r['id'] as Object?).toString(),
                _sessionToMap(r),
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Ligne `sessions` (snake_case) → clés de [GameSession.fromMap].
  static Map<String, Object?> _sessionToMap(Map row) => {
        'tunnelId': row['tunnel_id'],
        'participantIds': row['participant_ids'],
        'score': row['score'],
        'bestStreak': row['best_streak'],
        'tokensEarned': row['tokens_earned'],
        'position': row['position'],
        'totalTiles': row['total_tiles'],
        'finished': row['finished'],
        'createdAt': row['created_at'],
      };
}
