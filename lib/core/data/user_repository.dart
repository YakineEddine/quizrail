import 'package:cloud_firestore/cloud_firestore.dart';

import '../i18n/app_lang.dart';
import '../models/app_user.dart';
import '../storage/app_prefs.dart';
import 'backend.dart';

/// Portefeuille + langue : SharedPreferences en source d'affichage,
/// Firestore (users/{uid}) en miroir cloud quand en ligne.
/// Chaque écriture est best-effort : le local ne bloque jamais.
class UserRepository {
  UserRepository({required this.prefs});

  final AppPrefs prefs;

  FirebaseFirestore? get _fs => Backend.instance.firestore;
  String? get _uid => Backend.instance.uid;

  /// Ramène le cloud vers le local si un profil existe (ex : réinstall).
  /// Sans perte : si le local a PLUS de jetons que le cloud (gains
  /// hors ligne), le max est conservé des deux côtés.
  Future<AppUser> pullToLocal() async {
    final fs = _fs;
    final uid = _uid;
    if (fs == null || uid == null) {
      return AppUser(
          uid: 'local', tokens: prefs.tokens, langCode: prefs.lang.code);
    }
    try {
      final snap = await fs
          .doc('users/$uid')
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 8));
      if (!snap.exists) return await _localUser();
      final cloud =
          AppUser.fromMap(uid, _stringKeyed(snap.data() ?? {}));
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
    final fs = _fs;
    final uid = _uid;
    if (fs == null || uid == null) return;
    try {
      await fs
          .doc('users/$uid')
          .set(data, SetOptions(merge: true))
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Offline / quota / rules : le local fait foi, synchro plus tard.
    }
  }

  Future<AppUser> _localUser() async => AppUser(
      uid: _uid ?? 'local',
      tokens: prefs.tokens,
      langCode: prefs.lang.code);

  static Map<String, Object?> _stringKeyed(Map<Object?, Object?> raw) =>
      raw.map((k, v) => MapEntry(k.toString(), v));
}
