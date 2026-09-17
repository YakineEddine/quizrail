import '../../core/data/backend.dart';
import '../../core/data/tunnel_repository.dart'
    show gameTunnelFromRow;
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

/// Ligne `leaderboard` → [LeaderboardEntry.fromMap].
LeaderboardEntry _entryFromRow(Map<String, dynamic> row) {
  return LeaderboardEntry.fromMap((row['uid'] as Object?).toString(), {
    'displayName': row['display_name'],
    'country': row['country'],
    'bestScore': row['best_score'],
    'wins': row['wins'],
    'games': row['games'],
  });
}

class SupabaseSocialService implements SocialService {
  String? get _uid => Backend.instance.uid;

  void _needOnline() {
    if (!Backend.instance.isOnline ||
        Backend.instance.client == null ||
        _uid == null) {
      throw StateError('Social indisponible hors ligne.');
    }
  }

  @override
  Stream<List<LeaderboardEntry>> watchGlobal({int limit = 50}) {
    final db = Backend.instance.client;
    if (db == null) {
      return Stream.error(StateError('Classements hors ligne indisponibles.'));
    }
    return db
        .from('leaderboard')
        .stream(primaryKey: ['uid']).map((rows) {
      final entries = rows
          .whereType<Map<String, dynamic>>()
          .map(_entryFromRow)
          .toList();
      return sortBoard(entries).take(limit).toList();
    });
  }

  @override
  Stream<List<LeaderboardEntry>> watchCountry(String country,
      {int limit = 50}) {
    final db = Backend.instance.client;
    if (db == null) {
      return Stream.error(StateError('Classements hors ligne indisponibles.'));
    }
    return db
        .from('leaderboard')
        .stream(primaryKey: ['uid']).map((rows) {
      final entries = rows
          .whereType<Map<String, dynamic>>()
          .map(_entryFromRow)
          .where((e) => e.country == country)
          .toList();
      return sortBoard(entries).take(limit).toList();
    });
  }

  @override
  Stream<List<LeaderboardEntry>> watchFriends(List<String> uids) {
    final db = Backend.instance.client;
    if (db == null) {
      return Stream.error(StateError('Classements hors ligne indisponibles.'));
    }
    final ids = uids.take(10).toList();
    if (ids.isEmpty) return Stream.value(const []);
    return db
        .from('leaderboard')
        .stream(primaryKey: ['uid']).map((rows) {
      final entries = rows
          .whereType<Map<String, dynamic>>()
          .map(_entryFromRow)
          .where((e) => ids.contains(e.uid))
          .toList();
      return sortBoard(entries);
    });
  }

  @override
  Stream<Map<String, Object?>> watchMyProfile() {
    final db = Backend.instance.client;
    final uid = _uid;
    if (db == null || uid == null) {
      return Stream.error(StateError('Profil indisponible hors ligne.'));
    }
    return db
        .from('profiles')
        .stream(primaryKey: ['uid'])
        .eq('uid', uid)
        .map((rows) {
          if (rows.isEmpty) return <String, Object?>{'_uid': uid};
          final r = rows.first;
          return <String, Object?>{
            '_uid': uid,
            'displayName': r['display_name'],
            'country': r['country'],
            'tokens': r['tokens'],
            'lang': r['lang'],
            'friendIds': r['friend_ids'],
          };
        });
  }

  @override
  Future<void> setCountry(String country) async {
    final db = Backend.instance.client;
    final uid = _uid;
    if (db == null || uid == null) return;
    try {
      await db
          .from('profiles')
          .update({'country': country.trim().toUpperCase()})
          .eq('uid', uid)
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Best-effort.
    }
  }

  @override
  Future<void> setDisplayName(String displayName) async {
    final db = Backend.instance.client;
    final uid = _uid;
    if (db == null || uid == null) return;
    try {
      await db
          .from('profiles')
          .update({'display_name': displayName.trim()})
          .eq('uid', uid)
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Best-effort.
    }
  }

  @override
  Future<String> addFriend({required String friendUid}) async {
    _needOnline();
    final db = Backend.instance.client!;
    try {
      final res = await db.rpc('add_friend', params: {
        'p_friend_uid': friendUid,
      }).timeout(const Duration(seconds: 20));
      final m = (res as Map)
          .map((k, v) => MapEntry(k.toString(), v as Object?));
      return (m['displayName'] as String?) ?? friendUid;
    } catch (e) {
      throw Backend.friendly(e);
    }
  }

  @override
  Future<void> rateTunnel(
      {required String tunnelId, required int stars}) async {
    _needOnline();
    final db = Backend.instance.client!;
    try {
      await db.rpc('rate_tunnel', params: {
        'p_tunnel_id': tunnelId,
        'p_stars': stars,
      }).timeout(const Duration(seconds: 20));
    } catch (e) {
      throw Backend.friendly(e);
    }
  }

  @override
  Future<void> reportTunnel(
      {required String tunnelId, required String reason}) async {
    _needOnline();
    final db = Backend.instance.client!;
    try {
      await db.rpc('report_tunnel', params: {
        'p_tunnel_id': tunnelId,
        'p_reason': reason,
      }).timeout(const Duration(seconds: 20));
    } catch (e) {
      throw Backend.friendly(e);
    }
  }

  @override
  Stream<List<GameTunnel>> watchMarket(
      {required MarketSort sort, String query = ''}) {
    final db = Backend.instance.client;
    if (db == null) {
      return Stream.error(StateError('Marché indisponible hors ligne.'));
    }
    final q = query.trim().toLowerCase();
    return db
        .from('tunnels')
        .stream(primaryKey: ['id'])
        .eq('is_public', true)
        .map((rows) {
          var tunnels = rows
              .whereType<Map<String, dynamic>>()
              .map(gameTunnelFromRow)
              .toList();
          // Recherche thème côté client (pas d'index texte).
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
          } else {
            tunnels.sort((a, b) => (b.createdAtMillis ?? 0)
                .compareTo(a.createdAtMillis ?? 0));
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
