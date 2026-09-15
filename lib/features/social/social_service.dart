import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../core/data/backend.dart';
import '../../core/models/game_tunnel.dart';
import '../../core/models/leaderboard_entry.dart';

enum MarketSort { popular, recent }

/// Façade sociale : classements, amis, notation, signalements, découverte.
abstract class SocialService {
  Stream<List<LeaderboardEntry>> watchGlobal({int limit});
  Stream<List<LeaderboardEntry>> watchCountry(String country, {int limit});
  Stream<List<LeaderboardEntry>> watchFriends(List<String> uids);
  Stream<Map<String, Object?>> watchMyProfile();
  Future<void> setCountry(String country);
  Future<void> setDisplayName(String displayName);
  Future<String> addFriend({required String friendUid});
  Future<void> rateTunnel({required String tunnelId, required int stars});
  Future<void> reportTunnel({required String tunnelId, required String reason});
  Stream<List<GameTunnel>> watchMarket({required MarketSort sort, String query});
}

List<LeaderboardEntry> _entries(QuerySnapshot<Map<String, dynamic>> snap) =>
    snap.docs.map((d) => LeaderboardEntry.fromMap(d.id, d.data())).toList();

class CloudSocialService implements SocialService {
  FirebaseFirestore? get _fs => Backend.instance.firestore;
  String? get _uid => Backend.instance.uid;

  void _needOnline() {
    if (!Backend.instance.isOnline || _uid == null) {
      throw StateError('Social indisponible hors ligne.');
    }
  }

  Never _friendly(FirebaseFunctionsException e) {
    throw StateError(switch (e.code) {
      'unauthenticated' => 'Connexion requise.',
      'not-found' => 'Introuvable.',
      'failed-precondition' => e.message ?? 'Action impossible.',
      'invalid-argument' => e.message ?? 'Requête invalide.',
      _ => 'Erreur réseau, réessaie.',
    });
  }

  @override
  Stream<List<LeaderboardEntry>> watchGlobal({int limit = 50}) {
    final fs = _fs;
    if (fs == null) {
      return Stream.error(StateError('Classements hors ligne indisponibles.'));
    }
    return fs
        .collection('leaderboard')
        .orderBy('bestScore', descending: true)
        .limit(limit)
        .snapshots()
        .map(_entries);
  }

  @override
  Stream<List<LeaderboardEntry>> watchCountry(String country,
      {int limit = 50}) {
    final fs = _fs;
    if (fs == null) {
      return Stream.error(StateError('Classements hors ligne indisponibles.'));
    }
    return fs
        .collection('leaderboard')
        .where('country', isEqualTo: country)
        .orderBy('bestScore', descending: true)
        .limit(limit)
        .snapshots()
        .map(_entries);
  }

  @override
  Stream<List<LeaderboardEntry>> watchFriends(List<String> uids) {
    final fs = _fs;
    if (fs == null) {
      return Stream.error(StateError('Classements hors ligne indisponibles.'));
    }
    final ids = uids.take(10).toList();
    if (ids.isEmpty) return Stream.value(const []);
    return fs
        .collection('leaderboard')
        .where(FieldPath.documentId, whereIn: ids)
        .snapshots()
        .map((snap) => sortBoard(_entries(snap)));
  }

  @override
  Stream<Map<String, Object?>> watchMyProfile() {
    final fs = _fs;
    final uid = _uid;
    if (fs == null || uid == null) {
      return Stream.error(StateError('Profil indisponible hors ligne.'));
    }
    return fs.doc('users/$uid').snapshots().map((snap) {
      final data = snap.data() ?? {};
      return {
        '_uid': uid,
        ...data.map((k, v) => MapEntry(k.toString(), v as Object?)),
      };
    });
  }

  @override
  Future<void> setCountry(String country) async {
    final fs = _fs;
    final uid = _uid;
    if (fs == null || uid == null) return;
    try {
      await fs.doc('users/$uid').set(
        {'country': country.trim().toUpperCase()},
        SetOptions(merge: true),
      ).timeout(const Duration(seconds: 8));
    } catch (_) {
      // Best-effort.
    }
  }

  @override
  Future<void> setDisplayName(String displayName) async {
    final fs = _fs;
    final uid = _uid;
    if (fs == null || uid == null) return;
    try {
      await fs.doc('users/$uid').set(
        {'displayName': displayName.trim()},
        SetOptions(merge: true),
      ).timeout(const Duration(seconds: 8));
    } catch (_) {
      // Best-effort.
    }
  }

  @override
  Future<String> addFriend({required String friendUid}) async {
    _needOnline();
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('addFriend')
          .call({'friendUid': friendUid}).timeout(
            const Duration(seconds: 20),
          );
      final m = (res.data as Map)
          .map((k, v) => MapEntry(k.toString(), v as Object?));
      return (m['displayName'] as String?) ?? friendUid;
    } on FirebaseFunctionsException catch (e) {
      _friendly(e);
    }
  }

  @override
  Future<void> rateTunnel(
      {required String tunnelId, required int stars}) async {
    _needOnline();
    try {
      await FirebaseFunctions.instance.httpsCallable('rateTunnel').call(
        {'tunnelId': tunnelId, 'stars': stars},
      ).timeout(const Duration(seconds: 20));
    } on FirebaseFunctionsException catch (e) {
      _friendly(e);
    }
  }

  @override
  Future<void> reportTunnel(
      {required String tunnelId, required String reason}) async {
    _needOnline();
    try {
      await FirebaseFunctions.instance.httpsCallable('reportTunnel').call(
        {'tunnelId': tunnelId, 'reason': reason},
      ).timeout(const Duration(seconds: 20));
    } on FirebaseFunctionsException catch (e) {
      _friendly(e);
    }
  }

  @override
  Stream<List<GameTunnel>> watchMarket(
      {required MarketSort sort, String query = ''}) {
    final fs = _fs;
    if (fs == null) {
      return Stream.error(StateError('Marché indisponible hors ligne.'));
    }
    final q = query.trim().toLowerCase();
    final base = sort == MarketSort.popular
        ? fs
            .collection('tunnels')
            .where('isPublic', isEqualTo: true)
            .orderBy('ratingAvg', descending: true)
            .limit(50)
        : fs
            .collection('tunnels')
            .where('isPublic', isEqualTo: true)
            .orderBy('createdAt', descending: true)
            .limit(50);
    return base.snapshots().map((snap) {
      var tunnels = snap.docs
          .map((d) => GameTunnel.fromMap(
                d.id,
                d.data().map((k, v) => MapEntry(k.toString(), v as Object?)),
              ))
          .toList();
      // Recherche thème côté client (pas d'index texte Firestore).
      if (q.isNotEmpty) {
        tunnels = tunnels
            .where((t) => t.theme.toLowerCase().contains(q))
            .toList();
      }
      if (sort == MarketSort.popular) {
        tunnels.sort((a, b) {
          final c = b.ratingAvg.compareTo(a.ratingAvg);
          return c != 0 ? c : b.ratingCount.compareTo(a.ratingCount);
        });
      }
      return tunnels;
    });
  }
}

/// Fake scriptable pour les tests.
class FakeSocialService implements SocialService {
  FakeSocialService({
    this.board = const [],
    this.profile = const {},
    this.market = const [],
  });

  final List<LeaderboardEntry> board;
  final Map<String, Object?> profile;
  final List<GameTunnel> market;

  int friendAdds = 0;
  int rates = 0;
  int reports = 0;
  MarketSort? lastSort;
  String? lastQuery;

  @override
  Stream<List<LeaderboardEntry>> watchGlobal({int limit = 50}) =>
      Stream.value(board.take(limit).toList());

  @override
  Stream<List<LeaderboardEntry>> watchCountry(String country,
          {int limit = 50}) =>
      Stream.value(
          board.where((e) => e.country == country).take(limit).toList());

  @override
  Stream<List<LeaderboardEntry>> watchFriends(List<String> uids) =>
      Stream.value(
          sortBoard(board.where((e) => uids.contains(e.uid)).toList()));

  @override
  Stream<Map<String, Object?>> watchMyProfile() =>
      Stream.value(profile);

  @override
  Future<void> setCountry(String country) async {}

  @override
  Future<void> setDisplayName(String displayName) async {}

  @override
  Future<String> addFriend({required String friendUid}) async {
    friendAdds++;
    return 'Ami $friendUid';
  }

  @override
  Future<void> rateTunnel(
      {required String tunnelId, required int stars}) async {
    rates++;
  }

  @override
  Future<void> reportTunnel(
      {required String tunnelId, required String reason}) async {
    reports++;
  }

  @override
  Stream<List<GameTunnel>> watchMarket(
      {required MarketSort sort, String query = ''}) {
    lastSort = sort;
    lastQuery = query;
    final q = query.trim().toLowerCase();
    final list = q.isEmpty
        ? market
        : market.where((t) => t.theme.toLowerCase().contains(q)).toList();
    return Stream.value(list);
  }
}
