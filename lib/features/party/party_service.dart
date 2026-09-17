import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/tunnel/custom_tunnel.dart';
import '../../core/data/backend.dart';
import '../../core/models/party.dart';

class PartyRoomRef {
  const PartyRoomRef({required this.roomId, required this.code});
  final String roomId;
  final String code;
}

class PartyAnswerResult {
  const PartyAnswerResult({
    required this.correct,
    required this.gained,
    required this.score,
    required this.finished,
  });
  final bool correct;
  final int gained;
  final int score;
  final bool finished;

  factory PartyAnswerResult.fromMap(Map<String, Object?> map) {
    return PartyAnswerResult(
      correct: (map['correct'] as bool?) ?? false,
      gained: (map['gained'] as num?)?.toInt() ?? 0,
      score: (map['score'] as num?)?.toInt() ?? 0,
      finished: (map['finished'] as bool?) ?? false,
    );
  }
}

/// Façade Party : rooms, réponses validées serveur, animation host.
abstract class PartyService {
  Future<PartyRoomRef> createParty({
    String? theme,
    String? tunnelId,
    CustomTunnel? customTunnel,
    required String lang,
  });
  Future<PartyRoomRef> joinParty({required String code});
  Future<void> leaveParty({required String roomId});
  Future<void> startParty({required String roomId});
  Future<PartyAnswerResult> submitAnswer({
    required String roomId,
    required String answer,
    required int elapsedMs,
    required String lang,
  });
  Future<void> advanceParty({required String roomId});
  Future<void> endParty({required String roomId});
  Future<void> setPresence({required String roomId, required bool connected});
  Stream<PartyRoom> watchRoom(String roomId);
  Stream<List<PartyPlayer>> watchPlayers(String roomId);
}

Map<String, Object?> _stringKeyed(Map raw) =>
    raw.map((k, v) => MapEntry(k.toString(), v as Object?));

/// Ligne `rooms` (snake_case) → clés attendues par [PartyRoom.fromMap].
PartyRoom _roomFromRow(Map<String, dynamic> row) {
  return PartyRoom.fromMap(row['id'].toString(), {
    'code': row['code'],
    'hostId': row['host_id'],
    'status': row['status'],
    'theme': row['theme'],
    'questions': row['questions'],
    'questionIndex': row['question_index'],
    'playerIds': row['player_ids'],
    'winnerUid': row['winner_uid'],
    'isDraw': row['is_draw'],
  });
}

/// Ligne `room_players` → clés attendues par [PartyPlayer.fromMap].
PartyPlayer _playerFromRow(Map<String, dynamic> row) {
  return PartyPlayer.fromMap(row['uid'].toString(), {
    'displayName': row['display_name'],
    'score': row['score'],
    'correct': row['correct'],
    'answered': row['answered'],
    'streak': row['streak'],
    'bestStreak': row['best_streak'],
    'lastQuestionIndex': row['last_question_index'],
    'finished': row['finished'],
    'finishedAt': row['finished_at'],
    'connected': row['connected'],
    'lastSeen': row['last_seen'],
  });
}

class SupabasePartyService implements PartyService {
  SupabaseClient? get _db => Backend.instance.client;
  String? get _uid => Backend.instance.uid;

  SupabaseClient _needOnline() {
    final db = _db;
    if (!Backend.instance.isOnline || db == null || _uid == null) {
      throw StateError('Party indisponible hors ligne.');
    }
    return db;
  }

  /// Construit le set {prompts, answers} comme l'ancien serveur :
  /// tunnel du marché, tunnel custom, sinon banque standard (nulls).
  Future<({List<Object?>? prompts, List<Object?>? answers, String theme})>
      _questionSet({
    String? theme,
    String? tunnelId,
    CustomTunnel? customTunnel,
  }) async {
    List<Map<String, Object?>>? prompts;
    List<Map<String, Object?>>? answers;
    var resolvedTheme = (theme ?? '').trim();
    if (customTunnel != null) {
      prompts = customTunnel.questions
          .map((q) => {
                'prompt': {'fr': q.prompt, 'en': q.prompt, 'ar': q.prompt},
                'difficulty': q.difficulty.code,
              })
          .toList();
      answers = customTunnel.questions
          .map((q) => {
                'fr': [q.answer],
                'en': [q.answer],
                'ar': [q.answer],
              })
          .toList();
      if (resolvedTheme.isEmpty) resolvedTheme = customTunnel.theme;
    } else if (tunnelId != null) {
      final db = _needOnline();
      try {
        final row = await db
            .from('tunnels')
            .select('theme, questions')
            .eq('id', tunnelId)
            .maybeSingle()
            .timeout(const Duration(seconds: 15));
        if (row == null) throw StateError('Tunnel introuvable.');
        final raw = (row['questions'] as List? ?? const []);
        prompts = raw
            .whereType<Map>()
            .map((q) => {
                  'prompt': {
                    'fr': '${q['prompt'] ?? ''}',
                    'en': '${q['prompt'] ?? ''}',
                    'ar': '${q['prompt'] ?? ''}'
                  },
                  'difficulty': '${q['difficulty'] ?? 'medium'}',
                })
            .toList();
        answers = raw
            .whereType<Map>()
            .map((q) => {
                  'fr': ['${q['answer'] ?? ''}'],
                  'en': ['${q['answer'] ?? ''}'],
                  'ar': ['${q['answer'] ?? ''}'],
                })
            .toList();
        if (resolvedTheme.isEmpty) {
          resolvedTheme = (row['theme'] as String?) ?? 'Party';
        }
      } catch (e) {
        throw Backend.friendly(e, fallback: 'Tunnel introuvable.');
      }
    } else if (resolvedTheme.isEmpty) {
      resolvedTheme = 'QuizRail Party';
    }
    return (prompts: prompts, answers: answers, theme: resolvedTheme);
  }

  @override
  Future<PartyRoomRef> createParty({
    String? theme,
    String? tunnelId,
    CustomTunnel? customTunnel,
    required String lang,
  }) async {
    final db = _needOnline();
    try {
      final set = await _questionSet(
          theme: theme, tunnelId: tunnelId, customTunnel: customTunnel);
      final res = await db.rpc('create_party', params: {
        'p_theme': set.theme,
        'p_prompts': set.prompts,
        'p_answers': set.answers,
      }).timeout(const Duration(seconds: 35));
      final m = _stringKeyed(res as Map);
      return PartyRoomRef(
        roomId: m['roomId'] as String,
        code: m['code'] as String,
      );
    } catch (e) {
      throw Backend.friendly(e);
    }
  }

  @override
  Future<PartyRoomRef> joinParty({required String code}) async {
    final db = _needOnline();
    try {
      final res = await db.rpc('join_party', params: {
        'p_code': code,
      }).timeout(const Duration(seconds: 35));
      final m = _stringKeyed(res as Map);
      return PartyRoomRef(
        roomId: m['roomId'] as String,
        code: code.trim().toUpperCase(),
      );
    } catch (e) {
      throw Backend.friendly(e);
    }
  }

  @override
  Future<void> leaveParty({required String roomId}) async {
    final db = _needOnline();
    try {
      await db.rpc('leave_party', params: {
        'p_room_id': roomId,
      }).timeout(const Duration(seconds: 35));
    } catch (e) {
      throw Backend.friendly(e);
    }
  }

  @override
  Future<void> startParty({required String roomId}) async {
    final db = _needOnline();
    try {
      await db.rpc('start_party', params: {
        'p_room_id': roomId,
      }).timeout(const Duration(seconds: 35));
    } catch (e) {
      throw Backend.friendly(e);
    }
  }

  @override
  Future<PartyAnswerResult> submitAnswer({
    required String roomId,
    required String answer,
    required int elapsedMs,
    required String lang,
  }) async {
    final db = _needOnline();
    try {
      final res = await db.rpc('submit_party_answer', params: {
        'p_room_id': roomId,
        'p_answer': answer,
        'p_elapsed_ms': elapsedMs,
        'p_lang': lang,
      }).timeout(const Duration(seconds: 35));
      return PartyAnswerResult.fromMap(_stringKeyed(res as Map));
    } catch (e) {
      throw Backend.friendly(e);
    }
  }

  @override
  Future<void> advanceParty({required String roomId}) async {
    final db = _needOnline();
    try {
      await db.rpc('advance_party', params: {
        'p_room_id': roomId,
      }).timeout(const Duration(seconds: 35));
    } catch (e) {
      throw Backend.friendly(e);
    }
  }

  @override
  Future<void> endParty({required String roomId}) async {
    final db = _needOnline();
    try {
      await db.rpc('end_party', params: {
        'p_room_id': roomId,
      }).timeout(const Duration(seconds: 35));
    } catch (e) {
      throw Backend.friendly(e);
    }
  }

  @override
  Future<void> setPresence({
    required String roomId,
    required bool connected,
  }) async {
    final db = _db;
    final uid = _uid;
    if (db == null || uid == null) return;
    try {
      await db.rpc('touch_room_presence', params: {
        'p_room_id': roomId,
        'p_connected': connected,
      }).timeout(const Duration(seconds: 8));
    } catch (_) {
      // Best-effort.
    }
  }

  @override
  Stream<PartyRoom> watchRoom(String roomId) {
    final db = _db;
    if (db == null) {
      return Stream.error(StateError('Party indisponible hors ligne.'));
    }
    return db
        .from('rooms')
        .stream(primaryKey: ['id'])
        .eq('id', roomId)
        .map((rows) {
          if (rows.isEmpty) throw StateError('Room introuvable.');
          return _roomFromRow(rows.first);
        });
  }

  @override
  Stream<List<PartyPlayer>> watchPlayers(String roomId) {
    final db = _db;
    if (db == null) {
      return Stream.error(StateError('Party indisponible hors ligne.'));
    }
    return db
        .from('room_players')
        .stream(primaryKey: ['room_id', 'uid'])
        .eq('room_id', roomId)
        .map((rows) {
          final players = rows.map(_playerFromRow).toList()
            ..sort((a, b) => b.score.compareTo(a.score));
          return players;
        });
  }
}

/// Fake scriptable pour les tests (aucun réseau).
class FakePartyService implements PartyService {
  FakePartyService({
    this.roomRef = const PartyRoomRef(roomId: 'room1', code: 'ABC234'),
    this.answer,
    this.rooms = const {},
    this.players = const {},
  });

  final PartyRoomRef roomRef;
  final PartyAnswerResult? answer;
  final Map<String, PartyRoom> rooms;
  final Map<String, List<PartyPlayer>> players;

  int creates = 0;
  int joins = 0;
  int leaves = 0;
  int starts = 0;
  int answers = 0;
  int advances = 0;
  int ends = 0;

  @override
  Future<PartyRoomRef> createParty({
    String? theme,
    String? tunnelId,
    CustomTunnel? customTunnel,
    required String lang,
  }) async {
    creates++;
    return roomRef;
  }

  @override
  Future<PartyRoomRef> joinParty({required String code}) async {
    joins++;
    return roomRef;
  }

  @override
  Future<void> leaveParty({required String roomId}) async => leaves++;

  @override
  Future<void> startParty({required String roomId}) async => starts++;

  @override
  Future<PartyAnswerResult> submitAnswer({
    required String roomId,
    required String answer,
    required int elapsedMs,
    required String lang,
  }) async {
    answers++;
    return this.answer ??
        const PartyAnswerResult(
            correct: true, gained: 100, score: 100, finished: false);
  }

  @override
  Future<void> advanceParty({required String roomId}) async => advances++;

  @override
  Future<void> endParty({required String roomId}) async => ends++;

  @override
  Future<void> setPresence({
    required String roomId,
    required bool connected,
  }) async {}

  @override
  Stream<PartyRoom> watchRoom(String roomId) {
    final room = rooms[roomId];
    if (room == null) return Stream.error(StateError('Room introuvable.'));
    return Stream.value(room);
  }

  @override
  Stream<List<PartyPlayer>> watchPlayers(String roomId) =>
      Stream.value(players[roomId] ?? const []);
}
