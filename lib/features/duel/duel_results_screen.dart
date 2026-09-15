import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/backend.dart';
import '../../core/i18n/app_lang.dart';
import '../../core/models/game_duel.dart';
import '../../core/storage/app_prefs.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/game_button.dart';
import '../shop/ads_service.dart';
import '../shop/monetization_config.dart';
import 'duel_board_screen.dart';
import 'duel_providers.dart';
import 'duel_search_screen.dart';

/// Résultats du duel : gagnant, comparatif, revanche ou nouvel adversaire.
class DuelResultsScreen extends ConsumerStatefulWidget {
  const DuelResultsScreen({
    super.key,
    required this.duelId,
    this.lang = AppLang.fr,
    this.prefs,
    this.uid,
  });

  final String duelId;
  final AppLang lang;
  final AppPrefs? prefs;
  final String? uid;

  @override
  ConsumerState<DuelResultsScreen> createState() =>
      _DuelResultsScreenState();
}

class _DuelResultsScreenState extends ConsumerState<DuelResultsScreen> {
  Timer? _rematchTimer;
  bool _rematchAsked = false;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    // Interstitielle APRÈS les résultats (jamais en pleine question),
    // cappée et coupée par remove_ads — best-effort silencieux.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeShowResultsAd(context, AdPlacement.resultsDuel);
    });
  }

  String _t({required String fr, required String en, required String ar}) =>
      switch (widget.lang) {
        AppLang.fr => fr,
        AppLang.en => en,
        AppLang.ar => ar
      };

  @override
  void dispose() {
    _rematchTimer?.cancel();
    super.dispose();
  }

  Future<void> _rematch() async {
    if (_rematchAsked) return;
    setState(() => _rematchAsked = true);
    await _askOnce();
    if (!mounted || _navigated) return;
    // L'adversaire a ~60 s pour accepter (même rythme que le matchmaking).
    var tries = 0;
    _rematchTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      tries++;
      if (!mounted || _navigated || tries > 15) {
        _rematchTimer?.cancel();
        return;
      }
      await _askOnce();
    });
  }

  Future<void> _askOnce() async {
    try {
      final res = await ref
          .read(duelServiceProvider)
          .requestRematch(duelId: widget.duelId);
      if (res.matched && res.duelId != null && mounted && !_navigated) {
        _navigated = true;
        _rematchTimer?.cancel();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => DuelBoardScreen(
              duelId: res.duelId!,
              lang: widget.lang,
              prefs: widget.prefs,
              uid: _uid,
            ),
          ),
        );
      } else if (mounted) {
        setState(() {});
      }
    } catch (_) {
      // Réessayé au prochain tick.
    }
  }

  String get _uid => widget.uid ?? Backend.instance.uid ?? '';

  void _newSearch() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => DuelSearchScreen(
          prefs: widget.prefs,
          lang: widget.lang,
        ),
      ),
    );
  }

  String _ms(int v) {
    final s = (v / 1000).round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final asyncDuel = ref.watch(duelStreamProvider(widget.duelId));
    return Directionality(
      textDirection:
          widget.lang.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        key: const Key('duelResultsScreen'),
        backgroundColor: AppColors.deepSpace,
        body: Container(
          decoration:
              const BoxDecoration(gradient: AppColors.backgroundGradient),
          child: SafeArea(
            child: asyncDuel.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.sun),
              ),
              error: (e, _) => Center(
                child: Text(
                  e is StateError
                      ? e.message
                      : _t(
                          fr: 'Résultats indisponibles.',
                          en: 'Results unavailable.',
                          ar: 'النتائج غير متاحة.',
                        ),
                ),
              ),
              data: (duel) => _buildBody(context, duel),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, GameDuel duel) {
    final me = duel.me(_uid);
    final opp = duel.opponent(_uid);
    final won =
        duel.isFinished && !duel.isDraw && duel.winnerUid == _uid;
    final lost =
        duel.isFinished && !duel.isDraw && duel.winnerUid != _uid;

    final title = !duel.isFinished
        ? _t(
            fr: 'L\u2019adversaire termine…',
            en: 'Opponent is finishing…',
            ar: 'الخصم يُنهي…',
          )
        : duel.isDraw
            ? _t(fr: 'Match nul !', en: 'Draw!', ar: 'تعادل!')
            : won
                ? (duel.isForfeit
                    ? _t(
                        fr: 'Victoire par forfait !',
                        en: 'Win by forfeit!',
                        ar: 'فوز بالانسحاب!',
                      )
                    : _t(
                        fr: 'Victoire !',
                        en: 'Victory!',
                        ar: 'فوز!',
                      ))
                : _t(fr: 'Défaite…', en: 'Defeat…', ar: 'هزيمة…');

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
          decoration: BoxDecoration(
            gradient: won
                ? AppColors.goldGradient
                : AppColors.secondaryGradient,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.ink, width: 2.5),
          ),
          child: Column(
            children: [
              Icon(
                won
                    ? Icons.emoji_events_rounded
                    : (lost
                        ? Icons.sentiment_dissatisfied_rounded
                        : Icons.hourglass_bottom_rounded),
                size: 56,
                color: won ? AppColors.ink : AppColors.cream,
              ),
              const SizedBox(height: 8),
              Text(
                title,
                key: const Key('duelWinnerBanner'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: won ? AppColors.ink : AppColors.cream,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _VsRow(
          label: _t(fr: 'Score', en: 'Score', ar: 'النقاط'),
          mine: '${me.score}',
          theirs: '${opp.score}',
        ),
        _VsRow(
          label: _t(
              fr: 'Bonnes réponses',
              en: 'Correct answers',
              ar: 'إجابات صحيحة'),
          mine: '${me.correct}',
          theirs: '${opp.correct}',
        ),
        _VsRow(
          label: _t(
              fr: 'Meilleure série',
              en: 'Best streak',
              ar: 'أفضل سلسلة'),
          mine: '${me.bestStreak}',
          theirs: '${opp.bestStreak}',
        ),
        _VsRow(
          label: _t(fr: 'Temps', en: 'Time', ar: 'الوقت'),
          mine: _ms(me.totalElapsedMs),
          theirs: _ms(opp.totalElapsedMs),
        ),
        const SizedBox(height: 18),
        if (duel.isFinished) ...[
          GameButton(
            key: const Key('duelRematchButton'),
            label: _rematchAsked
                ? _t(
                    fr: 'En attente de l\u2019adversaire…',
                    en: 'Waiting for opponent…',
                    ar: 'بانتظار الخصم…',
                  )
                : _t(
                    fr: 'Revanche',
                    en: 'Rematch',
                    ar: 'مباراة ثأرية',
                  ),
            icon: Icons.sports_kabaddi_rounded,
            onPressed: _rematchAsked ? null : _rematch,
          ),
          const SizedBox(height: 10),
          GameButton(
            key: const Key('duelNewSearchButton'),
            variant: GameButtonVariant.secondary,
            label: _t(
              fr: 'Nouvel adversaire',
              en: 'New opponent',
              ar: 'خصم جديد',
            ),
            icon: Icons.search_rounded,
            onPressed: _newSearch,
          ),
        ],
      ],
    );
  }
}

class _VsRow extends StatelessWidget {
  const _VsRow({
    required this.label,
    required this.mine,
    required this.theirs,
  });

  final String label;
  final String mine;
  final String theirs;

  @override
  Widget build(BuildContext context) {
    TextStyle val(BuildContext c, bool hot) => TextStyle(
          color: hot ? AppColors.sun : AppColors.cream,
          fontSize: 20,
          fontWeight: FontWeight.w900,
        );
    final myWin =
        (int.tryParse(mine) ?? -1) >= (int.tryParse(theirs) ?? -1);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.midnight.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: AppColors.midnightLight, width: 1.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(mine,
                textAlign: TextAlign.center,
                style: val(context, myWin)),
          ),
          Expanded(
            flex: 2,
            child: Text(label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall),
          ),
          Expanded(
            child: Text(theirs,
                textAlign: TextAlign.center,
                style: val(context, !myWin)),
          ),
        ],
      ),
    );
  }
}
