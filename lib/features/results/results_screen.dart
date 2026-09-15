import 'package:flutter/material.dart';

import '../../core/storage/app_prefs.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/game_button.dart';
import '../../core/widgets/token_counter.dart';
import '../board/board_screen.dart';
import '../home/home_screen.dart';
import '../shop/ads_service.dart';
import '../shop/monetization_config.dart';

/// Résultats de partie : score, meilleure série, jetons, wagon + Rejouer/Accueil.
class ResultsScreen extends StatefulWidget {
  const ResultsScreen({
    super.key,
    this.prefs,
    this.lang = AppLang.fr,
    this.score = 0,
    this.bestStreak = 0,
    this.tokensEarned = 0,
    this.walletTokens = 0,
    this.position = 0,
    this.totalTiles = 12,
  });

  final AppPrefs? prefs;
  final AppLang lang;
  final int score;
  final int bestStreak;
  final int tokensEarned;
  final int walletTokens;
  final int position;
  final int totalTiles;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  @override
  void initState() {
    super.initState();
    // Interstitielle APRÈS les résultats (jamais en pleine question),
    // cappée et coupée par remove_ads — best-effort silencieux.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeShowResultsAd(context, AdPlacement.resultsSolo);
    });
  }

  String _t({required String fr, required String en, required String ar}) =>
      switch (widget.lang) {
        AppLang.fr => fr,
        AppLang.en => en,
        AppLang.ar => ar
      };

  @override
  Widget build(BuildContext context) {
    final progress = widget.totalTiles <= 1
        ? 0.0
        : (widget.position / (widget.totalTiles - 1))
            .clamp(0.0, 1.0);
    final pct = (progress * 100).round();
    return Directionality(
      textDirection:
          widget.lang.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        key: const Key('resultsScreen'),
        backgroundColor: AppColors.deepSpace,
        body: Container(
          decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                // Trophée.
                Container(
                  height: 190,
                  decoration: BoxDecoration(
                    gradient: AppColors.goldGradient,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.ink, width: 2.5),
                    boxShadow: const [
                      BoxShadow(
                          color: AppColors.shadowGold,
                          offset: Offset(0, 6),
                          blurRadius: 0),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.emoji_events_rounded,
                          size: 64, color: AppColors.ink),
                      const SizedBox(height: 6),
                      Text(
                        _t(
                            fr: 'Partie terminée !',
                            en: 'Run complete!',
                            ar: 'انتهت الجولة!'),
                        softWrap: true,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Stats 2x2 (lignes simples : pas de scroll imbriqué).
                Row(
                  children: [
                    Expanded(
                      child: _ResultStat(
                          label: _t(
                              fr: 'Score', en: 'Score', ar: 'النقاط'),
                          value: '${widget.score}',
                          color: AppColors.pinkPop),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ResultStat(
                          label: _t(
                              fr: 'Meilleure série',
                              en: 'Best streak',
                              ar: 'أفضل سلسلة'),
                          value: '${widget.bestStreak}',
                          color: AppColors.skyPop),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _ResultStat(
                          label: _t(
                              fr: 'Jetons gagnés',
                              en: 'Tokens earned',
                              ar: 'رموز مكتسبة'),
                          value: '+${widget.tokensEarned}',
                          color: AppColors.sun),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ResultStat(
                          label: _t(
                              fr: 'Wagon', en: 'Wagon', ar: 'العربة'),
                          value: '$pct %',
                          color: AppColors.mintPop),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Progression du wagon.
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.midnight.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                        color: AppColors.midnightLight, width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.train_rounded,
                              color: AppColors.sun, size: 22),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _t(
                               fr: 'Progression : case ${widget.position + 1}/${widget.totalTiles}',
                                   en: 'Progress: tile ${widget.position + 1}/${widget.totalTiles}',
                                   ar: 'التقدم: خانة ${widget.position + 1}/${widget.totalTiles}'),
                              softWrap: true,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 14,
                        decoration: BoxDecoration(
                          color: AppColors.deepSpace,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppColors.ink, width: 2),
                        ),
                        child: FractionallySizedBox(
                          widthFactor: progress.clamp(0.05, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: AppColors.secondaryGradient,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Portefeuille.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const GoldCoin(size: 26),
                    const SizedBox(width: 8),
                    Text(
                      _t(
                           fr: 'Portefeuille : ${widget.walletTokens} jetons',
                           en: 'Wallet: ${widget.walletTokens} tokens',
                           ar: 'المحفظة: ${widget.walletTokens} رموز'),
                      style: AppTypography.tokenCount(size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                GameButton(
                  key: const Key('replayButton'),
                  label: _t(
                      fr: 'Rejouer', en: 'Play again', ar: 'العب مجددًا'),
                  icon: Icons.replay_rounded,
                  onPressed: () =>
                      Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) =>
                          BoardScreen(prefs: widget.prefs, lang: widget.lang),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                GameButton(
                  key: const Key('homeButton'),
                  variant: GameButtonVariant.secondary,
                  label: _t(
                      fr: 'Accueil', en: 'Home', ar: 'الرئيسية'),
                  icon: Icons.home_rounded,
                  onPressed: () =>
                      Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (_) => HomeScreen(prefs: widget.prefs),
                    ),
                    (_) => false,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultStat extends StatelessWidget {
  const _ResultStat(
      {required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 108,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.midnight.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(18),
        border:
            Border.all(color: AppColors.midnightLight, width: 1.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration:
                BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(height: 6),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall),
          Text(value, style: AppTypography.tokenCount(size: 26)),
        ],
      ),
    );
  }
}
