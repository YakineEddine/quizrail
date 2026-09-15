import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/data/user_repository.dart';
import '../../core/i18n/app_lang.dart';
import '../../core/storage/app_prefs.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/cute_train.dart';
import '../../core/widgets/game_button.dart';
import '../../core/widgets/token_counter.dart';
import '../board/board_screen.dart';
import '../duel/duel_search_screen.dart';
import '../tunnel/tunnel_editor_screen.dart';

export '../../core/i18n/app_lang.dart';

/// Accueil QuizRail avec le design system jeu :
/// fond dégradé sombre, héros Baloo 2, train cartoon, boutons à relief.
/// Le portefeuille et la langue sont persistés via [AppPrefs].
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.prefs});

  final AppPrefs? prefs;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  AppLang _lang = AppLang.fr;
  int _tokens = 120;
  AppPrefs? _prefs;

  late final AnimationController _trainController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  )..repeat();

  @override
  void initState() {
    super.initState();
    _prefs = widget.prefs;
    if (_prefs != null) {
      _tokens = _prefs!.tokens;
      _lang = _prefs!.lang;
    } else {
      AppPrefs.load().then((p) {
        if (!mounted) return;
        setState(() {
          _prefs = p;
          _tokens = p.tokens;
          _lang = p.lang;
        });
      });
    }
  }

  @override
  void dispose() {
    _trainController.dispose();
    super.dispose();
  }

  String _t({required String fr, required String en, required String ar}) {
    switch (_lang) {
      case AppLang.fr:
        return fr;
      case AppLang.en:
        return en;
      case AppLang.ar:
        return ar;
    }
  }

  void _addTokens() {
    setState(() => _tokens += 10);
    final p = _prefs;
    if (p == null) return;
    p.setTokens(_tokens);
    // Miroir cloud best-effort (offline → ignoré, local fait foi).
    unawaited(UserRepository(prefs: p).pushTokens(_tokens));
  }

  void _setLang(AppLang lang) {
    setState(() => _lang = lang);
    final p = _prefs;
    if (p == null) return;
    p.setLang(lang);
    unawaited(UserRepository(prefs: p).pushLang(lang));
  }

  Future<void> _refreshTokens() async {
    final p = _prefs ?? await AppPrefs.load();
    _prefs ??= p;
    if (!mounted) return;
    setState(() => _tokens = p.tokens);
  }

  Future<void> _play() async {
    final prefs = _prefs ?? await AppPrefs.load();
    _prefs ??= prefs;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BoardScreen(prefs: prefs, lang: _lang),
      ),
    );
    await _refreshTokens();
  }

  Future<void> _openTunnelEditor() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TunnelEditorScreen(lang: _lang),
      ),
    );
  }

  Future<void> _openDuel() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DuelSearchScreen(prefs: _prefs, lang: _lang),
      ),
    );
    await _refreshTokens();
  }

  /// Titre avec marque isolée en bidi : "QuizRail" reste un bloc LTR
  /// (U+2066 LRI … U+2069 PDI) pour un ordre correct en AR.
  String _title() => switch (_lang) {
        AppLang.fr => 'QuizRail – Accueil',
        AppLang.en => 'QuizRail – Home',
        AppLang.ar => '\u2066QuizRail\u2069 – الرئيسية',
      };

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: _lang.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.deepSpace,
        body: Container(
          decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
          child: Stack(
            children: [
              // Halos énergiques (tons violet/rose du thème, pas de marron)
              const Positioned(
                top: -70,
                left: -50,
                child: _Glow(size: 230, color: AppColors.heroGlowPink),
              ),
              const Positioned(
                top: 60,
                right: -70,
                child: _Glow(size: 260, color: AppColors.heroGlowViolet),
              ),
              // Bas d'écran : duo violet + rose ancré dans la palette.
              // (L'ancien halo jaune large virait au marron sur fond nuit.)
              const Positioned(
                bottom: -70,
                left: -70,
                child: _Glow(size: 210, color: AppColors.heroGlowViolet),
              ),
              Positioned(
                bottom: -80,
                right: -60,
                child: _Glow(
                  size: 200,
                  color: AppColors.heroGlowPink.withValues(alpha: 0.75),
                ),
              ),
              SafeArea(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                  children: [
                    // Barre haute : logo + titre + langues
                    Row(
                      children: [
                        const _LogoBadge(),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _title(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(color: AppColors.cream),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _LangPills(lang: _lang, onSelect: _setLang),
                    const SizedBox(height: 22),
                    // Héros
                    _HeroBlock(
                      line1: _t(
                        fr: 'Monte à bord,',
                        en: 'All aboard,',
                        ar: 'اصعد على متن',
                      ),
                      line2: _t(
                        fr: 'le quiz est en route !',
                        en: 'the quiz is rolling!',
                        ar: 'الاختبار في الطريق!',
                      ),
                      sub: _t(
                        fr: 'Réponds vite, fais avancer ton train et empoche des jetons.',
                        en: 'Answer fast, move your train and stack up tokens.',
                        ar: 'أجب بسرعة، وحرّك قطارك واجمع الرموز.',
                      ),
                    ),
                    const SizedBox(height: 18),
                    // Compteur de jetons animé
                    TokenCounter(
                      tokens: _tokens,
                      label: _t(fr: 'Jetons', en: 'Tokens', ar: 'رموز'),
                      countKey: const Key('tokenCount'),
                      onAdd: _addTokens,
                    ),
                    const SizedBox(height: 16),
                    // Scène du train
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                      decoration: BoxDecoration(
                        color: AppColors.midnight.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: AppColors.midnightLight, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TrainAnimation(
                            key: const Key('trainAnimation'),
                            controller: _trainController,
                            isRtl: _lang.isRtl,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    GameButton(
                      label: _t(fr: 'Jouer', en: 'Play', ar: 'العب'),
                      icon: Icons.play_arrow_rounded,
                      onPressed: _play,
                    ),
                    const SizedBox(height: 10),
                    GameButton(
                      key: const Key('tunnelEditorButton'),
                      variant: GameButtonVariant.secondary,
                      label: _t(
                          fr: 'Tunnel custom',
                          en: 'Custom tunnel',
                          ar: 'نفق مخصص'),
                      icon: Icons.construction_rounded,
                      onPressed: _openTunnelEditor,
                    ),
                    const SizedBox(height: 10),
                    GameButton(
                      key: const Key('duelButton'),
                      variant: GameButtonVariant.gold,
                      label: _t(
                          fr: 'Duel en ligne',
                          en: 'Online duel',
                          ar: 'مبارزة online'),
                      icon: Icons.sports_kabaddi_rounded,
                      onPressed: _openDuel,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _t(
                        fr: 'Progression sauvegardée sur l\u2019appareil.',
                        en: 'Progress saved on this device.',
                        ar: 'يُحفظ تقدمك على هذا الجهاز.',
                      ),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
      ),
    );
  }
}

class _LogoBadge extends StatelessWidget {
  const _LogoBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        gradient: AppColors.playGradient,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.ink, width: 2.5),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowPlay,
            offset: Offset(0, 4),
            blurRadius: 0,
          ),
        ],
      ),
      child: const Icon(
        Icons.train_rounded,
        color: AppColors.cream,
        size: 26,
      ),
    );
  }
}

class _LangPills extends StatelessWidget {
  const _LangPills({required this.lang, required this.onSelect});

  final AppLang lang;
  final ValueChanged<AppLang> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: AppColors.midnight.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.midnightLight, width: 1.5),
      ),
      child: Row(
        children: AppLang.values.map((l) {
          final selected = l == lang;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelect(l),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  gradient: selected ? AppColors.goldGradient : null,
                  color: selected ? null : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: selected
                      ? Border.all(color: AppColors.ink, width: 2)
                      : Border.all(color: Colors.transparent, width: 2),
                  boxShadow: selected
                      ? const [
                          BoxShadow(
                            color: AppColors.shadowGold,
                            offset: Offset(0, 3),
                            blurRadius: 0,
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  l.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected ? AppColors.ink : AppColors.creamDim,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _HeroBlock extends StatelessWidget {
  const _HeroBlock({
    required this.line1,
    required this.line2,
    required this.sub,
  });

  final String line1;
  final String line2;
  final String sub;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Taille responsive : les lignes EN/FR longues ne débordent jamais.
        final longest =
            line1.length > line2.length ? line1.length : line2.length;
        final size =
            (constraints.maxWidth / (longest * 0.58)).clamp(24.0, 34.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Titre à caractère avec contour cartoon
            Stack(
              children: [
                Text(
                  '$line1\n$line2',
                  softWrap: true,
                  style: AppTypography.hero(size: size).copyWith(
                    foreground: Paint()
                      ..style = PaintingStyle.stroke
                      ..strokeWidth = 5
                      ..color = AppColors.ink,
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(line1,
                        softWrap: true,
                        style: AppTypography.hero(size: size)),
                    Text(line2,
                        softWrap: true,
                        style: AppTypography.heroAccent(size: size)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              sub,
              softWrap: true,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: AppColors.creamDim),
            ),
          ],
        );
      },
    );
  }
}
