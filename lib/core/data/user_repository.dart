import '../i18n/app_lang.dart';
import '../models/app_user.dart';
import '../storage/app_prefs.dart';
import 'backend.dart';

/// Portefeuille + langue : SharedPreferences en source d'affichage,
/// Supabase (table `profiles`) en miroir cloud quand en ligne.
/// Chaque écriture est best-effort : le local ne bloque jamais.
class UserRepository {
  UserRepository({required this.prefs});

  final AppPrefs prefs;

  String? get _uid => Backend.instance.uid;

  /// Ramène le cloud vers le local si un profil existe (ex : réinstall).
  /// Sans perte : si le local a PLUS de jetons que le cloud (gains
  /// hors ligne), le max est conservé des deux côtés.
  Future<AppUser> pullToLocal() async {
    final db = Backend.instance.client;
    final uid = _uid;
    if (db == null || uid == null) {
      return AppUser(
          uid: 'local', tokens: prefs.tokens, langCode: prefs.lang.code);
    }
    try {
      final row = await db
          .from('profiles')
          .select()
          .eq('uid', uid)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));
      if (row == null) return await _localUser();
      final cloud = AppUser.fromMap(uid, _profileToUser(row));
      final mergedTokens =
          cloud.tokens > prefs.tokens ? cloud.tokens : prefs.tokens;
      if (mergedTokens != prefs.tokens) {
        await prefs.setTokens(mergedTokens);
      }
      final cloudLang = AppLangX.fromCode(cloud.langCode);
      if (cloudLang != prefs.lang) {
        await prefs.setLang(cloudLang);
      }
      if (mergedTokens != cloud.tokens) {
        await _push({'tokens': mergedTokens});
      }
      return AppUser(
          uid: uid, tokens: mergedTokens, langCode: prefs.lang.code);
    } catch (_) {
      return _localUser();
    }
  }

  Future<void> pushTokens(int value) async =>
      _push({'tokens': value});

  Future<void> pushLang(AppLang lang) async =>
      _push({'lang': lang.code});

  Future<void> _push(Map<String, Object?> data) async {
    final db = Backend.instance.client;
    final uid = _uid;
    if (db == null || uid == null) return;
    try {
      await db.from('profiles').upsert({
        'uid': uid,
        ...data,
      }).timeout(const Duration(seconds: 8));
    } catch (_) {
      // Offline / quota / RLS : le local fait foi, synchro plus tard.
    }
  }

  Future<AppUser> _localUser() async => AppUser(
      uid: _uid ?? 'local',
      tokens: prefs.tokens,
      langCode: prefs.lang.code);

  /// Ligne `profiles` (snake_case) → clés d'[AppUser.fromMap].
  static Map<String, Object?> _profileToUser(Map<String, dynamic> row) => {
        'tokens': row['tokens'],
        'lang': row['lang'],
        'createdAt': row['created_at'],
        'displayName': row['display_name'],
        'country': row['country'],
        'friendIds': row['friend_ids'],
      };
}
