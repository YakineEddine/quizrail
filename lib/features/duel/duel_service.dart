import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../core/data/backend.dart';
import '../../core/models/game_duel.dart';

/// Résultats des callables duel (contrats miroirs de functions/src/duel.ts).
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
/// Implémentation cloud (callables + Firestore) ou fake (tests).
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

Map<String, Object?> _data(Object? res) =>
    ((res as Map).map((k, v) => MapEntry(k.toString(), v as Object?)));

/// Implémentation réelle : Cloud Functions + Firestore temps réel.
class CloudDuelService implements DuelService {
  FirebaseFunctions get _fn => FirebaseFunctions.instance;
  FirebaseFirestore? get _fs => Backend.instance.firestore;
  String? get _uid => Backend.instance.uid;

  void _needOnline() {
    if (!Backend.instance.isOnline || _uid == null) {
      throw StateError('Duel indisponible hors ligne.');
    }
  }

  Never _friendly(FirebaseFunctionsException e) {
    throw StateError(switch (e.code) {
      'unauthenticated' => 'Connexion requise.',
      'not-found' => 'Duel introuvable.',
      'failed-precondition' => e.message ?? 'Action impossible.',
      'invalid-argument' => e.message ?? 'Requête invalide.',
      'resource-exhausted' => e.message ?? 'Quota atteint.',
      _ => 'Erreur réseau, réessaie.',
    });
  }

  @override
  Future<DuelSearchResult> findDuel({required String lang}) async {
    _needOnline();
    try {
      final res = await _fn
          .httpsCallable('findDuel')
          .call({'lang': lang}).timeout(const Duration(seconds: 35));
      return DuelSearchResult.fromMap(_data(res.data));
    } on FirebaseFunctionsException catch (e) {
      _friendly(e);
    }
  }

  @override
  Future<void> leaveQueue() async {
    final fs = _fs;
    final uid = _uid;
    if (fs == null || uid == null) return;
    try {
      await fs.doc('duelQueue/$uid').delete().timeout(
            const Duration(seconds: 8),
          );
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
    _needOnline();
    try {
      final res = await _fn.httpsCallable('submitDuelAnswer').call({
        'duelId': duelId,
        'questionIndex': questionIndex,
        'answer': answer,
        'elapsedMs': elapsedMs,
        'lang': lang,
      }).timeout(const Duration(seconds: 35));
      return DuelAnswerResult.fromMap(_data(res.data));
    } on FirebaseFunctionsException catch (e) {
      _friendly(e);
    }
  }

  @override
  Future<DuelPowerResult> usePower({
    required String duelId,
    required DuelPower power,
  }) async {
    _needOnline();
    try {
      final res = await _fn.httpsCallable('usePower').call({
        'duelId': duelId,
        'power': power.apiName,
      }).timeout(const Duration(seconds: 35));
      final m = _data(res.data);
      return DuelPowerResult(
        wallet: (m['wallet'] as num?)?.toInt() ?? 0,
        effectMs: (m['frozenUntil'] as num?)?.toInt() ??
            (m['doubleUntil'] as num?)?.toInt() ??
            0,
      );
    } on FirebaseFunctionsException catch (e) {
      _friendly(e);
    }
  }

  @override
  Future<void> claimForfeit({required String duelId}) async {
    _needOnline();
    try {
      await _fn.httpsCallable('claimForfeit').call({'duelId': duelId}).timeout(
            const Duration(seconds: 35),
          );
    } on FirebaseFunctionsException catch (e) {
      _friendly(e);
    }
  }

  @override
  Future<DuelSearchResult> requestRematch({required String duelId}) async {
    _needOnline();
    try {
      final res = await _fn
          .httpsCallable('rematchDuel')
          .call({'duelId': duelId}).timeout(const Duration(seconds: 35));
      return DuelSearchResult.fromMap(_data(res.data));
    } on FirebaseFunctionsException catch (e) {
      _friendly(e);
    }
  }

  @override
  Future<void> setPresence({
    required String duelId,
    required bool connected,
  }) async {
    final fs = _fs;
    final uid = _uid;
    if (fs == null || uid == null) return;
    try {
      await fs.doc('duels/$duelId').update({
        'players.$uid.connected': connected,
        'players.$uid.lastSeen': DateTime.now().millisecondsSinceEpoch,
      }).timeout(const Duration(seconds: 8));
    } catch (_) {
      // Best-effort : le forfait se base sur lastSeen, pas sur cet appel.
    }
  }

  @override
  Stream<GameDuel> watchDuel(String duelId) {
    final fs = _fs;
    if (fs == null) {
      return Stream.error(StateError('Duel indisponible hors ligne.'));
    }
    return fs.doc('duels/$duelId').snapshots().map((snap) {
      final data = snap.data();
      if (!snap.exists || data == null) {
        throw StateError('Duel introuvable.');
      }
      return GameDuel.fromMap(
        snap.id,
        data.map((k, v) => MapEntry(k.toString(), v as Object?)),
      );
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
