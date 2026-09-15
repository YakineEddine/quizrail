import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/data/backend.dart';
import 'core/data/migration_service.dart';
import 'core/data/user_repository.dart';
import 'core/storage/app_prefs.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'features/home/home_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/tunnel/custom_tunnel_store.dart';

// Re-export pour compatibilité (tests / futurs écrans Phase 1).
export 'features/home/home_screen.dart';

void main() {
  runApp(const MyApp());
}

/// Racine QuizRail : ThemeData centralisé + portail de démarrage.
/// Le portail lit SharedPreferences (hasSeenOnboarding) puis aiguille
/// vers l'onboarding ou l'accueil. Tous les écrans héritent du thème jeu.
class MyApp extends StatelessWidget {
  const MyApp({super.key, this.prefsOverride});

  /// Prefs injectées (tests / previews). Sinon chargement réel.
  final AppPrefs? prefsOverride;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: MaterialApp(
        title: 'QuizRail',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: _BootGate(prefsOverride: prefsOverride),
      ),
    );
  }
}

class _BootGate extends StatefulWidget {
  const _BootGate({this.prefsOverride});

  final AppPrefs? prefsOverride;

  @override
  State<_BootGate> createState() => _BootGateState();
}

class _BootGateState extends State<_BootGate> {
  late final Future<AppPrefs> _future = _boot();

  /// Démarrage : prefs locales → backend (instant offline si Firebase
  /// non configuré) → migration one-shot → pull cloud vers local.
  /// Tout échec réseau est silencieux : l'app reste 100 % jouable.
  Future<AppPrefs> _boot() async {
    final prefs =
        widget.prefsOverride ?? await AppPrefs.load();
    if (widget.prefsOverride != null) return prefs;
    try {
      await Backend.instance
          .boot()
          .timeout(const Duration(seconds: 15));
      final customs = await CustomTunnelStore.load();
      await MigrationService.migrateIfNeeded(prefs: prefs, customs: customs)
          .timeout(const Duration(seconds: 30));
      await UserRepository(prefs: prefs)
          .pullToLocal()
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      // Repli local : progression SharedPreferences inchangée.
    }
    return prefs;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppPrefs>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Scaffold(
            backgroundColor: AppColors.deepSpace,
            body: Container(
              decoration: const BoxDecoration(
                  gradient: AppColors.backgroundGradient),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.train_rounded,
                        size: 64, color: AppColors.sun),
                    SizedBox(height: 12),
                    Text(
                      'QuizRail',
                      style: TextStyle(
                        color: AppColors.cream,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        final prefs = snapshot.data!;
        if (!prefs.hasSeenOnboarding) {
          return OnboardingScreen(prefs: prefs);
        }
        return HomeScreen(prefs: prefs);
      },
    );
  }
}
