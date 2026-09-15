import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

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

Map<String, Object?> _data(Object? res) =>
    ((res as Map).map((k, v) => MapEntry(k.toString(), v as Object?)));

class CloudPartyService implements PartyService {
  FirebaseFunctions get _fn => FirebaseFunctions.instance;
  FirebaseFirestore? get _fs => Backend.instance.firestore;
  String? get _uid => Backend.instance.uid;

  void _needOnline() {
    if (!Backend.instance.isOnline || _uid == null) {
      throw StateError('Party indisponible hors ligne.');
    }
  }

  Never _friendly(FirebaseFunctionsException e) {
    throw StateError(switch (e.code) {
      'unauthenticated' => 'Connexion requise.',
      'not-found' => 'Room introuvable.',
      'failed-precondition' => e.message ?? 'Action impossible.',
      'invalid-argument' => e.message ?? 'Requête invalide.',
      'permission-denied' => e.message ?? 'Non autorisé.',
      _ => 'Erreur réseau, réessaie.',
    });
  }

  Future<Map<String, Object?>> _call(String name, Map<String, Object?> args) async {
    _needOnline();
    try {
      final res = await _fn
          .httpsCallable(name)
          .call(args)
          .timeout(const Duration(seconds: 35));
      return _data(res.data);
    } on FirebaseFunctionsException catch (e) {
      _friendly(e);
    }
  }

  @override
  Future<PartyRoomRef> createParty({
    String? theme,
    String? tunnelId,
    CustomTunnel? customTunnel,
    required String lang,
  }) async {
    final args = <String, Object?>{'lang': lang};
    if (theme != null) args['theme'] = theme;
    if (tunnelId != null) args['tunnelId'] = tunnelId;
    if (customTunnel != null) {
      args['customTunnel'] = {
        'theme': customTunnel.theme,
        'questions': customTunnel.questions
            .map((q) => {
                  'prompt': q.prompt,
                  'answer': q.answer,
                  'difficulty': q.difficulty.code,
                })
            .toList(),
      };
    }
    final m = await _call('createParty', args);
    return PartyRoomRef(
      roomId: m['roomId'] as String,
      code: m['code'] as String,
    );
  }

  @override
  Future<PartyRoomRef> joinParty({required String code}) async {
    final m = await _call('joinParty', {'code': code});
    return PartyRoomRef(roomId: m['roomId'] as String, code: code);
  }

  @override
  Future<void> leaveParty({required String roomId}) async {
    await _call('leaveParty', {'roomId': roomId});
  }

  @override
  Future<void> startParty({required String roomId}) async {
    await _call('startParty', {'roomId': roomId});
  }

  @override
  Future<PartyAnswerResult> submitAnswer({
    required String roomId,
    required String answer,
    required int elapsedMs,
    required String lang,
  }) async {
    final m = await _call('submitPartyAnswer', {
      'roomId': roomId,
      'answer': answer,
      'elapsedMs': elapsedMs,
      'lang': lang,
    });
    return PartyAnswerResult.fromMap(m);
  }

  @override
  Future<void> advanceParty({required String roomId}) async {
    await _call('advanceParty', {'roomId': roomId});
  }

  @override
  Future<void> endParty({required String roomId}) async {
    await _call('endParty', {'roomId': roomId});
  }

  @override
  Future<void> setPresence({
    required String roomId,
    required bool connected,
  }) async {
    final fs = _fs;
    final uid = _uid;
    if (fs == null || uid == null) return;
    try {
      await fs.doc('rooms/$roomId/players/$uid').update({
        'connected': connected,
        'lastSeen': DateTime.now().millisecondsSinceEpoch,
      }).timeout(const Duration(seconds: 8));
    } catch (_) {
      // Best-effort.
    }
  }

  @override
  Stream<PartyRoom> watchRoom(String roomId) {
    final fs = _fs;
    if (fs == null) {
      return Stream.error(StateError('Party indisponible hors ligne.'));
    }
    return fs.doc('rooms/$roomId').snapshots().map((snap) {
      final data = snap.data();
      if (!snap.exists || data == null) throw StateError('Room introuvable.');
      return PartyRoom.fromMap(
        snap.id,
        data.map((k, v) => MapEntry(k.toString(), v as Object?)),
      );
    });
  }

  @override
  Stream<List<PartyPlayer>> watchPlayers(String roomId) {
    final fs = _fs;
    if (fs == null) {
      return Stream.error(StateError('Party indisponible hors ligne.'));
    }
    return fs
        .collection('rooms/$roomId/players')
        .orderBy('score', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => PartyPlayer.fromMap(
                  d.id,
                  d.data().map((k, v) => MapEntry(k.toString(), v as Object?)),
                ))
            .toList());
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
