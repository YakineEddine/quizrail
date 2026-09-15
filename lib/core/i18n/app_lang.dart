/// Langue d'interface partagée par tous les écrans Phase 1.
/// FR/EN en LTR, AR en RTL.
enum AppLang { fr, en, ar }

extension AppLangX on AppLang {
  String get label => switch (this) {
        AppLang.fr => 'FR',
        AppLang.en => 'EN',
        AppLang.ar => 'AR',
      };

  /// Code persisté dans SharedPreferences (settings_lang).
  String get code => switch (this) {
        AppLang.fr => 'fr',
        AppLang.en => 'en',
        AppLang.ar => 'ar',
      };

  bool get isRtl => this == AppLang.ar;

  static AppLang fromCode(String? code) => switch (code) {
        'en' => AppLang.en,
        'ar' => AppLang.ar,
        _ => AppLang.fr,
      };
}
