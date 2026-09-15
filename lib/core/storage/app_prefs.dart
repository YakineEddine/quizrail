import 'package:shared_preferences/shared_preferences.dart';

import '../i18n/app_lang.dart';

/// Clés de persistance Phase 1 (ne pas renommer : déjà potentiellement
/// stockées sur appareils de test).
abstract final class PrefKeys {
  static const walletTokens = 'wallet_tokens';
  static const settingsLang = 'settings_lang';
  static const hasSeenOnboarding = 'hasSeenOnboarding';
  static const migratedToCloud = 'migrated_to_cloud_v1';
  static const removeAds = 'monet_remove_ads';
  static const battlePass = 'monet_battle_pass';
  static const ownedSkins = 'monet_owned_skins';
  static const selectedSkin = 'monet_selected_skin';
  static const lastInterstitialMs = 'monet_last_interstitial_ms';
}

/// Façade SharedPreferences branchée avant que l'état ne se complexifie.
/// - wallet_tokens : portefeuille de jetons partagé (accueil / plateau).
/// - settings_lang : 'fr' | 'en' | 'ar'.
/// - hasSeenOnboarding : flag d'onboarding vu.
/// - migrated_to_cloud_v1 : migration one-shot vers users/{uid} effectuée.
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

  /// Migration cloud effectuée (one-shot, voir MigrationService).
  bool get cloudMigrated {
    final p = _prefs;
    if (p != null) {
      return p.getBool(PrefKeys.migratedToCloud) ?? false;
    }
    return _mem[PrefKeys.migratedToCloud] as bool? ?? false;
  }

  Future<void> setCloudMigrated(bool value) async {
    final p = _prefs;
    if (p != null) {
      await p.setBool(PrefKeys.migratedToCloud, value);
    } else {
      _mem[PrefKeys.migratedToCloud] = value;
    }
  }

  // -- Monétisation (miroir local des droits serveurs) ----------------------
  // Écrits uniquement après validation serveur (boutique) ou lecture des
  // droits (entitlements). Jamais de crédit local direct hors gains de jeu.

  bool get removeAds {
    final p = _prefs;
    if (p != null) return p.getBool(PrefKeys.removeAds) ?? false;
    return _mem[PrefKeys.removeAds] as bool? ?? false;
  }

  Future<void> setRemoveAds(bool value) async {
    final p = _prefs;
    if (p != null) {
      await p.setBool(PrefKeys.removeAds, value);
    } else {
      _mem[PrefKeys.removeAds] = value;
    }
  }

  bool get battlePassActive {
    final p = _prefs;
    if (p != null) return p.getBool(PrefKeys.battlePass) ?? false;
    return _mem[PrefKeys.battlePass] as bool? ?? false;
  }

  Future<void> setBattlePass(bool value) async {
    final p = _prefs;
    if (p != null) {
      await p.setBool(PrefKeys.battlePass, value);
    } else {
      _mem[PrefKeys.battlePass] = value;
    }
  }

  List<String> get ownedSkins {
    final p = _prefs;
    if (p != null) return p.getStringList(PrefKeys.ownedSkins) ?? const [];
    final raw = _mem[PrefKeys.ownedSkins];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return const [];
  }

  Future<void> setOwnedSkins(List<String> value) async {
    final p = _prefs;
    if (p != null) {
      await p.setStringList(PrefKeys.ownedSkins, value);
    } else {
      _mem[PrefKeys.ownedSkins] = value;
    }
  }

  String get selectedSkin {
    final p = _prefs;
    if (p != null) return p.getString(PrefKeys.selectedSkin) ?? 'classic';
    return _mem[PrefKeys.selectedSkin] as String? ?? 'classic';
  }

  Future<void> setSelectedSkin(String value) async {
    final p = _prefs;
    if (p != null) {
      await p.setString(PrefKeys.selectedSkin, value);
    } else {
      _mem[PrefKeys.selectedSkin] = value;
    }
  }

  int? get lastInterstitialMs {
    final p = _prefs;
    if (p != null) return p.getInt(PrefKeys.lastInterstitialMs);
    return _mem[PrefKeys.lastInterstitialMs] as int?;
  }

  Future<void> setLastInterstitialMs(int value) async {
    final p = _prefs;
    if (p != null) {
      await p.setInt(PrefKeys.lastInterstitialMs, value);
    } else {
      _mem[PrefKeys.lastInterstitialMs] = value;
    }
  }
}
