import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/data/backend.dart';
import '../../core/models/game_duel.dart';

/// Résultats des RPC duel (contrats miroirs de supabase/schema.sql).
class DuelSearchResult {
  const DuelSearchResult(
      {required this.matched, this.duelId, this.opponentUid});

  final bool matched;
  final String? duelId;
  final String? opponentUid;

  factory DuelSearchResult.fromMap(Map<String, Object?> map) {
    return DuelSearchResult(
      matched: map['status'] == 'matched',
      duelId: map['duelId'] as String?,
      opponentUid: map['opponentUid'] as String?,
    );
  }
}

class DuelAnswerResult {
  const DuelAnswerResult({
    required this.correct,
    required this.gained,
    required this.score,
    required this.position,
    required this.answered,
    required this.finished,
    required this.duelFinished,
    this.winnerUid,
    this.isDraw = false,
  });

  final bool correct;
  final int gained;
  final int score;
  final int position;
  final int answered;
  final bool finished;
  final bool duelFinished;
  final String? winnerUid;
  final bool isDraw;

  factory DuelAnswerResult.fromMap(Map<String, Object?> map) {
    int n(String k) => (map[k] as num?)?.toInt() ?? 0;
    return DuelAnswerResult(
      correct: (map['correct'] as bool?) ?? false,
      gained: n('gained'),
      score: n('score'),
      position: n('position'),
      answered: n('answered'),
      finished: (map['finished'] as bool?) ?? false,
      duelFinished: (map['duelFinished'] as bool?) ?? false,
      winnerUid: map['winnerUid'] as String?,
      isDraw: (map['isDraw'] as bool?) ?? false,
    );
  }
}

class DuelPowerResult {
  const DuelPowerResult({required this.wallet, this.effectMs = 0});

  final int wallet;
  final int effectMs;
}

/// Façade duel : matchmaking, réponses, pouvoirs, forfait, revanche, présence.
/// Implémentation Supabase (RPC + Realtime) ou fake (tests).
abstract class DuelService {
  Future<DuelSearchResult> findDuel({required String lang});
  Future<void> leaveQueue();
  Future<DuelAnswerResult> submitAnswer({
    required String duelId,
    required int questionIndex,
    required String answer,
    required int elapsedMs,
    required String lang,
  });
  Future<DuelPowerResult> usePower({
    required String duelId,
    required DuelPower power,
  });
  Future<void> claimForfeit({required String duelId});
  Future<DuelSearchResult> requestRematch({required String duelId});
  Future<void> setPresence({required String duelId, required bool connected});
  Stream<GameDuel> watchDuel(String duelId);
}

Map<String, Object?> _stringKeyed(Map raw) =>
    raw.map((k, v) => MapEntry(k.toString(), v as Object?));

/// Ligne `duels` (snake_case) → clés attendues par [GameDuel.fromMap].
GameDuel _duelFromRow(Map<String, dynamic> row) {
  return GameDuel.fromMap(row['id'].toString(), {
    'playerIds': ((row['player_ids'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList(),
    'status': row['status'],
    'questions': row['questions'],
    'players': row['players'],
    'winnerUid': row['winner_uid'],
    'finishReason': row['finish_reason'],
    'isDraw': row['is_draw'],
    'rematchRequests': row['rematch_requests'],
  });
}

/// Implémentation réelle : RPC Supabase (arbitrage serveur) + Realtime.
class SupabaseDuelService implements DuelService {
  SupabaseClient? get _db => Backend.instance.client;
  String? get _uid => Backend.instance.uid;

  SupabaseClient _needOnline() {
    final db = _db;
    if (!Backend.instance.isOnline || db == null || _uid == null) {
      throw StateError('Duel indisponible hors ligne.');
    }
    return db;
  }

  @override
  Future<DuelSearchResult> findDuel({required String lang}) async {
    final db = _needOnline();
    try {
      final res = await db
          .rpc('find_duel', params: {'p_lang': lang}).timeout(
            const Duration(seconds: 35),
          );
      return DuelSearchResult.fromMap(_stringKeyed(res as Map));
    } catch (e) {
      throw Backend.friendly(e);
    }
  }

  @override
  Future<void> leaveQueue() async {
    final db = _db;
    final uid = _uid;
    if (db == null || uid == null) return;
    try {
      await db.rpc('leave_queue').timeout(const Duration(seconds: 8));
    } catch (_) {
      // Best-effort : la file expire d'elle-même au prochain appariement.
    }
  }

  @override
  Future<DuelAnswerResult> submitAnswer({
    required String duelId,
    required int questionIndex,
    required String answer,
    required int elapsedMs,
    required String lang,
  }) async {
    final db = _needOnline();
    try {
      final res = await db.rpc('submit_duel_answer', params: {
        'p_duel_id': duelId,
        'p_answer': answer,
        'p_elapsed_ms': elapsedMs,
        'p_lang': lang,
      }).timeout(const Duration(seconds: 35));
      return DuelAnswerResult.fromMap(_stringKeyed(res as Map));
    } catch (e) {
      throw Backend.friendly(e);
    }
  }

  @override
  Future<DuelPowerResult> usePower({
    required String duelId,
    required DuelPower power,
  }) async {
    final db = _needOnline();
    try {
      final res = await db.rpc('use_power', params: {
        'p_duel_id': duelId,
        'p_power': power.apiName,
      }).timeout(const Duration(seconds: 35));
      final m = _stringKeyed(res as Map);
      return DuelPowerResult(
        wallet: (m['wallet'] as num?)?.toInt() ?? 0,
        effectMs: (m['frozenUntil'] as num?)?.toInt() ??
            (m['doubleUntil'] as num?)?.toInt() ??
            0,
      );
    } catch (e) {
      throw Backend.friendly(e);
    }
  }

  @override
  Future<void> claimForfeit({required String duelId}) async {
    final db = _needOnline();
    try {
      await db.rpc('claim_forfeit', params: {
        'p_duel_id': duelId,
      }).timeout(const Duration(seconds: 35));
    } catch (e) {
      throw Backend.friendly(e);
    }
  }

  @override
  Future<DuelSearchResult> requestRematch({required String duelId}) async {
    final db = _needOnline();
    try {
      final res = await db.rpc('request_rematch', params: {
        'p_duel_id': duelId,
      }).timeout(const Duration(seconds: 35));
      return DuelSearchResult.fromMap(_stringKeyed(res as Map));
    } catch (e) {
      throw Backend.friendly(e);
    }
  }

  @override
  Future<void> setPresence({
    required String duelId,
    required bool connected,
  }) async {
    final db = _db;
    final uid = _uid;
    if (db == null || uid == null) return;
    try {
      await db.rpc('touch_duel_presence', params: {
        'p_duel_id': duelId,
        'p_connected': connected,
      }).timeout(const Duration(seconds: 8));
    } catch (_) {
      // Best-effort : le forfait se base sur lastSeen, pas sur cet appel.
    }
  }

  @override
  Stream<GameDuel> watchDuel(String duelId) {
    final db = _db;
    if (db == null) {
      return Stream.error(StateError('Duel indisponible hors ligne.'));
    }
    return db
        .from('duels')
        .stream(primaryKey: ['id'])
        .eq('id', duelId)
        .map((rows) {
          if (rows.isEmpty) throw StateError('Duel introuvable.');
          return _duelFromRow(rows.first);
        });
  }
}

/// Fake scriptable pour les tests widget (aucun réseau).
class FakeDuelService implements DuelService {
  FakeDuelService({
    this.searchResults = const [],
    this.answer,
    this.powerWallet = 100,
    this.duels = const {},
  });

  final List<DuelSearchResult> searchResults;
  final DuelAnswerResult? answer;
  final int powerWallet;
  final Map<String, GameDuel> duels;
  int searches = 0;
  int answers = 0;
  int powers = 0;
  int forfeits = 0;
  bool leftQueue = false;
  bool presenceOff = false;

  @override
  Future<DuelSearchResult> findDuel({required String lang}) async {
    searches++;
    if (searches <= searchResults.length) return searchResults[searches - 1];
    return const DuelSearchResult(matched: false);
  }

  @override
  Future<void> leaveQueue() async => leftQueue = true;

  @override
  Future<DuelAnswerResult> submitAnswer({
    required String duelId,
    required int questionIndex,
    required String answer,
    required int elapsedMs,
    required String lang,
  }) async {
    answers++;
    return this.answer ??
        const DuelAnswerResult(
          correct: true,
          gained: 100,
          score: 100,
          position: 1,
          answered: 1,
          finished: false,
          duelFinished: false,
        );
  }

  @override
  Future<DuelPowerResult> usePower({
    required String duelId,
    required DuelPower power,
  }) async {
    powers++;
    return DuelPowerResult(wallet: powerWallet);
  }

  @override
  Future<void> claimForfeit({required String duelId}) async {
    forfeits++;
  }

  @override
  Future<DuelSearchResult> requestRematch({required String duelId}) async =>
      const DuelSearchResult(matched: false);

  @override
  Future<void> setPresence({
    required String duelId,
    required bool connected,
  }) async {
    if (!connected) presenceOff = true;
  }

  @override
  Stream<GameDuel> watchDuel(String duelId) {
    final duel = duels[duelId];
    if (duel == null) return Stream.error(StateError('Duel introuvable.'));
    return Stream.value(duel);
  }
}
