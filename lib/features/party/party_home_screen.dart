import 'package:flutter/material.dart';

import '../../core/data/backend.dart';
import '../../core/i18n/app_lang.dart';
import '../../core/storage/app_prefs.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/game_button.dart';
import 'party_host_screen.dart';
import 'party_join_screen.dart';
import 'party_local_screen.dart';

/// Aiguillage Party : créer une room (host) ou rejoindre avec un code.
class PartyHomeScreen extends StatelessWidget {
  const PartyHomeScreen({super.key, this.prefs, this.lang = AppLang.fr});

  final AppPrefs? prefs;
  final AppLang lang;

  String _t({required String fr, required String en, required String ar}) =>
      switch (lang) {
        AppLang.fr => fr,
        AppLang.en => en,
        AppLang.ar => ar
      };

  @override
  Widget build(BuildContext context) {
    final uid = Backend.instance.uid ?? '';
    return Directionality(
      textDirection: lang.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        key: const Key('partyHomeScreen'),
        backgroundColor: AppColors.deepSpace,
        body: Container(
          decoration:
              const BoxDecoration(gradient: AppColors.backgroundGradient),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: AppColors.cream),
                      ),
                      Expanded(
                        child: Text(
                          _t(
                              fr: 'Party',
                              en: 'Party',
                              ar: 'حفلة'),
                          style:
                              Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ],
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.groups_rounded,
                            size: 72, color: AppColors.sun),
                        const SizedBox(height: 16),
                        Text(
                          _t(
                            fr: 'Un écran anime, tous les téléphones jouent.',
                            en: 'One screen hosts, every phone plays.',
                            ar: 'شاشة تستضيف، وكل الهواتف تلعب.',
                          ),
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 24),
                        GameButton(
                          key: const Key('partyGoHostButton'),
                          label: _t(
                              fr: 'Créer une room',
                              en: 'Create a room',
                              ar: 'إنشاء غرفة'),
                          icon: Icons.add_home_rounded,
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PartyHostScreen(
                                lang: lang,
                                prefs: prefs,
                                uid: uid,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        GameButton(
                          key: const Key('partyGoJoinButton'),
                          variant: GameButtonVariant.secondary,
                          label: _t(
                              fr: 'Rejoindre avec un code',
                              en: 'Join with a code',
                              ar: 'الانضمام برمز'),
                          icon: Icons.login_rounded,
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PartyJoinScreen(
                                lang: lang,
                                prefs: prefs,
                                uid: uid,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        GameButton(
                          key: const Key('partyGoLocalButton'),
                          variant: GameButtonVariant.gold,
                          label: _t(
                              fr: 'Party locale (même écran)',
                              en: 'Local party (same screen)',
                              ar: 'حفلة محلية (نفس الشاشة)'),
                          icon: Icons.smartphone_rounded,
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PartyLocalScreen(
                                lang: lang,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _t(
                            fr: 'Sans réseau : joue en local. En ligne : crée une room.',
                            en: 'No network? Play locally. Online: create a room.',
                            ar: 'بدون شبكة؟ العب محليًا. متصل؟ أنشئ غرفة.',
                          ),
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
