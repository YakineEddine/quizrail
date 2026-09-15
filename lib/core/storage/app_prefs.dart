import 'package:shared_preferences/shared_preferences.dart';

import '../i18n/app_lang.dart';

/// Clés de persistance Phase 1 (ne pas renommer : déjà potentiellement
/// stockées sur appareils de test).
abstract final class PrefKeys {
  static const walletTokens = 'wallet_tokens';
  static const settingsLang = 'settings_lang';
  static const hasSeenOnboarding = 'hasSeenOnboarding';
}

/// Façade SharedPreferences branchée avant que l'état ne se complexifie.
/// - wallet_tokens : portefeuille de jetons partagé (accueil / plateau).
/// - settings_lang : 'fr' | 'en' | 'ar'.
/// - hasSeenOnboarding : flag d'onboarding vu.
/// Repli mémoire si le plugin est indisponible (tests widget sans mock).
class AppPrefs {
  AppPrefs._(this._prefs, this._mem);

  final SharedPreferences? _prefs;
  final Map<String, Object> _mem;

  static const _defaultTokens = 120;

  static Future<AppPrefs> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.containsKey(PrefKeys.walletTokens)) {
        await prefs.setInt(PrefKeys.walletTokens, _defaultTokens);
      }
      if (!prefs.containsKey(PrefKeys.settingsLang)) {
        await prefs.setString(PrefKeys.settingsLang, AppLang.fr.code);
      }
      if (!prefs.containsKey(PrefKeys.hasSeenOnboarding)) {
        await prefs.setBool(PrefKeys.hasSeenOnboarding, false);
      }
      return AppPrefs._(prefs, const {});
    } catch (_) {
      // Fallback mémoire (tests) : onboarding déjà vu pour rester sur l'accueil.
      return AppPrefs._(null, {
        PrefKeys.walletTokens: _defaultTokens,
        PrefKeys.settingsLang: AppLang.fr.code,
        PrefKeys.hasSeenOnboarding: true,
      });
    }
  }

  /// Fabrique mémoire pour les tests / previews.
  factory AppPrefs.inMemory({
    int tokens = _defaultTokens,
    AppLang lang = AppLang.fr,
    bool seenOnboarding = true,
  }) {
    return AppPrefs._(null, {
      PrefKeys.walletTokens: tokens,
      PrefKeys.settingsLang: lang.code,
      PrefKeys.hasSeenOnboarding: seenOnboarding,
    });
  }

  int get tokens {
    final p = _prefs;
    if (p != null) return p.getInt(PrefKeys.walletTokens) ?? _defaultTokens;
    return _mem[PrefKeys.walletTokens] as int? ?? _defaultTokens;
  }

  Future<void> setTokens(int value) async {
    final p = _prefs;
    if (p != null) {
      await p.setInt(PrefKeys.walletTokens, value);
    } else {
      _mem[PrefKeys.walletTokens] = value;
    }
  }

  AppLang get lang {
    final raw = _prefs?.getString(PrefKeys.settingsLang) ??
        _mem[PrefKeys.settingsLang] as String?;
    return AppLangX.fromCode(raw);
  }

  Future<void> setLang(AppLang lang) async {
    final p = _prefs;
    if (p != null) {
      await p.setString(PrefKeys.settingsLang, lang.code);
    } else {
      _mem[PrefKeys.settingsLang] = lang.code;
    }
  }

  bool get hasSeenOnboarding {
    final p = _prefs;
    if (p != null) {
      return p.getBool(PrefKeys.hasSeenOnboarding) ?? false;
    }
    return _mem[PrefKeys.hasSeenOnboarding] as bool? ?? true;
  }

  Future<void> setHasSeenOnboarding(bool value) async {
    final p = _prefs;
    if (p != null) {
      await p.setBool(PrefKeys.hasSeenOnboarding, value);
    } else {
      _mem[PrefKeys.hasSeenOnboarding] = value;
    }
  }
}
