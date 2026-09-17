import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/backend.dart';
import '../../core/i18n/app_lang.dart';
import '../../core/storage/app_prefs.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/game_button.dart';
import 'duel_board_screen.dart';
import 'duel_offline_screen.dart';
import 'duel_providers.dart';

/// File d'attente duel : animation de recherche, annulation, timeout 60 s.
/// À l'appariement → plateau duel temps réel.
class DuelSearchScreen extends ConsumerStatefulWidget {
  const DuelSearchScreen({super.key, this.prefs, this.lang = AppLang.fr});

  final AppPrefs? prefs;
  final AppLang lang;

  @override
  ConsumerState<DuelSearchScreen> createState() => _DuelSearchScreenState();
}

class _DuelSearchScreenState extends ConsumerState<DuelSearchScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref
        .read(duelSearchProvider.notifier)
        .search(lang: widget.lang.code));
  }

  String _t({required String fr, required String en, required String ar}) =>
      switch (widget.lang) {
        AppLang.fr => fr,
        AppLang.en => en,
        AppLang.ar => ar
      };

  void _retry() {
    _retryAsync();
  }

  bool _retrying = false;

  Future<void> _retryAsync() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      // Le boot initial a pu échouer (Avion, Supabase non configuré…).
      // Sans ce retry, "Réessayer" re-tentait findDuel en restant offline.
      await Backend.instance.retry();
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
    if (!mounted) return;
    ref.read(duelSearchProvider.notifier).search(lang: widget.lang.code);
  }

  void _playOffline() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DuelOfflineScreen(
          prefs: widget.prefs,
          lang: widget.lang,
        ),
      ),
    );
  }

  bool _isOfflineError(String? error) =>
      error != null && error.toLowerCase().contains('hors ligne');

  Future<void> _cancel() async {
    await ref.read(duelSearchProvider.notifier).cancel();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(duelSearchProvider);
    ref.listen(duelSearchProvider, (prev, next) {
      if (next.phase == DuelSearchPhase.matched && next.duelId != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => DuelBoardScreen(
              duelId: next.duelId!,
              lang: widget.lang,
              prefs: widget.prefs,
            ),
          ),
        );
      }
    });

    return Directionality(
      textDirection:
          widget.lang.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        key: const Key('duelSearchScreen'),
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
                        onPressed: _cancel,
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: AppColors.cream),
                      ),
                      Expanded(
                        child: Text(
                          _t(
                              fr: 'Duel en ligne',
                              en: 'Online duel',
                              ar: 'مبارزة online'),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ],
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (search.phase == DuelSearchPhase.searching) ...[
                          const SizedBox(
                            width: 72,
                            height: 72,
                            child: CircularProgressIndicator(
                              strokeWidth: 6,
                              color: AppColors.sun,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            _t(
                              fr: 'Recherche d\u2019adversaire…',
                              en: 'Finding an opponent…',
                              ar: 'جارٍ البحث عن خصم…',
                            ),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _t(
                              fr: 'Appariement par ordre d\u2019arrivée.',
                              en: 'First-come, first-served pairing.',
                              ar: 'الإقران حسب ترتيب الوصول.',
                            ),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ] else if (search.phase ==
                            DuelSearchPhase.timeout) ...[
                          const Icon(Icons.timer_off_rounded,
                              size: 64, color: AppColors.sun),
                          const SizedBox(height: 16),
                          Text(
                            _t(
                              fr: 'Personne en file pour l\u2019instant.',
                              en: 'Nobody in queue right now.',
                              ar: 'لا أحد في الانتظار حاليًا.',
                            ),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 16),
                          GameButton(
                            key: const Key('duelRetryButton'),
                            label: _t(
                                fr: 'Réessayer',
                                en: 'Retry',
                                ar: 'إعادة المحاولة'),
                            icon: Icons.refresh_rounded,
                            onPressed: _retry,
                          ),
                        ] else if (search.phase == DuelSearchPhase.error) ...[
                          const Icon(Icons.cloud_off_rounded,
                              size: 64, color: AppColors.pinkPop),
                          const SizedBox(height: 16),
                          Text(
                            _isOfflineError(search.error)
                                ? _t(
                                    fr: 'Serveur duel injoignable. Vérifie ta connexion ou joue contre le Train fantôme en attendant.',
                                    en: 'Duel server unreachable. Check your connection or play the Ghost train meanwhile.',
                                    ar: 'تعذر الوصول لخادم المبارزة. تحقق من الاتصال أو العب ضد قطار الشبح مؤقتًا.',
                                  )
                                : (search.error ??
                                    _t(
                                      fr: 'Erreur réseau.',
                                      en: 'Network error.',
                                      ar: 'خطأ في الشبكة.',
                                    )),
                            key: const Key('duelSearchError'),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 16),
                          GameButton(
                            key: const Key('duelRetryButton'),
                            label: _retrying
                                ? _t(
                                    fr: 'Connexion…',
                                    en: 'Connecting…',
                                    ar: 'جارٍ الاتصال…')
                                : _t(
                                    fr: 'Réessayer',
                                    en: 'Retry',
                                    ar: 'إعادة المحاولة'),
                            icon: Icons.refresh_rounded,
                            onPressed: _retrying ? null : _retry,
                          ),
                          if (_isOfflineError(search.error)) ...[
                            const SizedBox(height: 10),
                            GameButton(
                              key: const Key('duelOfflineButton'),
                              variant: GameButtonVariant.gold,
                              label: _t(
                                  fr: 'Jouer hors ligne (bot)',
                                  en: 'Play offline (bot)',
                                  ar: 'العب دون اتصال (روبوت)'),
                              icon: Icons.smart_toy_rounded,
                              onPressed: _playOffline,
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                  GameButton(
                    key: const Key('duelSearchCancelButton'),
                    variant: GameButtonVariant.secondary,
                    label: _t(
                        fr: 'Annuler', en: 'Cancel', ar: 'إلغاء'),
                    icon: Icons.close_rounded,
                    onPressed: _cancel,
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
