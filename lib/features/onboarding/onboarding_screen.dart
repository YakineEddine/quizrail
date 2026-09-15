import 'package:flutter/material.dart';

import '../../core/storage/app_prefs.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/cute_train.dart';
import '../../core/widgets/game_button.dart';
import '../../core/widgets/token_counter.dart';
import '../home/home_screen.dart';

class _OnboardData {
  const _OnboardData({
    required this.frTitle,
    required this.enTitle,
    required this.arTitle,
    required this.frDesc,
    required this.enDesc,
    required this.arDesc,
    required this.gradient,
    required this.shadow,
  });

  final String frTitle;
  final String enTitle;
  final String arTitle;
  final String frDesc;
  final String enDesc;
  final String arDesc;
  final Gradient gradient;
  final Color shadow;

  String title(AppLang l) => switch (l) {
        AppLang.fr => frTitle,
        AppLang.en => enTitle,
        AppLang.ar => arTitle,
      };

  String desc(AppLang l) => switch (l) {
        AppLang.fr => frDesc,
        AppLang.en => enDesc,
        AppLang.ar => arDesc,
      };
}

/// Onboarding 4 écrans max, skippable. Pose le flag hasSeenOnboarding.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.prefs, this.initialLang = AppLang.fr});

  final AppPrefs? prefs;
  final AppLang initialLang;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final PageController _pages = PageController();
  late AppLang _lang = widget.prefs?.lang ?? widget.initialLang;
  int _index = 0;

  static const _data = [
    _OnboardData(
      frTitle: 'Ton train file sur les rails',
      enTitle: 'Your train runs the rails',
      arTitle: 'قطارك يسير على القضبان',
      frDesc: 'Chaque bonne réponse fait avancer ton convoi case par case. Cap sur le terminus !',
      enDesc: 'Every correct answer moves your train tile by tile. Full steam to the terminus!',
      arDesc: 'كل إجابة صحيحة تحرك قطارك خانة بخانة. إلى المحطة الأخيرة!',
      gradient: AppColors.secondaryGradient,
      shadow: AppColors.shadowSecondary,
    ),
    _OnboardData(
      frTitle: 'Séries et jetons dorés',
      enTitle: 'Streaks and golden tokens',
      arTitle: 'السلاسل والرموز الذهبية',
      frDesc: 'Enchaîne les bonnes réponses : ta série grimpe et les jetons pleuvent.',
      enDesc: 'Chain correct answers: your streak grows and tokens rain down.',
      arDesc: 'سلسل الإجابات الصحيحة: سلسلتك تكبر والرموز تتساقط.',
      gradient: AppColors.goldGradient,
      shadow: AppColors.shadowGold,
    ),
    _OnboardData(
      frTitle: 'Des indices quand tu cales',
      enTitle: 'Hints when you stall',
      arTitle: 'تلميحات عندما تتعثر',
      frDesc: 'Première lettre −5 jetons, révélation −15. À dégainer au bon moment.',
      enDesc: 'First letter −5 tokens, reveal −15. Play them at the right moment.',
      arDesc: 'الحرف الأول −5 رموز، والكشف −15. استخدمها في الوقت المناسب.',
      gradient: AppColors.playGradient,
      shadow: AppColors.shadowPlay,
    ),
    _OnboardData(
      frTitle: 'Quiz IA et parcours custom',
      enTitle: 'AI quizzes and custom tracks',
      arTitle: 'اختبارات ذكية ومسارات مخصصة',
      frDesc: 'Génère des questions par thème ou construis ton propre parcours.',
      enDesc: 'Generate themed questions or build your own track.',
      arDesc: 'ولّد أسئلة حسب الموضوع أو ابنِ مسارك الخاص.',
      gradient: AppColors.secondaryGradient,
      shadow: AppColors.shadowSecondary,
    ),
  ];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  String _t({required String fr, required String en, required String ar}) =>
      switch (_lang) { AppLang.fr => fr, AppLang.en => en, AppLang.ar => ar };

  Future<void> _finish() async {
    await widget.prefs?.setHasSeenOnboarding(true);
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => HomeScreen(prefs: widget.prefs)),
    );
  }

  void _next() {
    if (_index >= _data.length - 1) {
      _finish();
    } else {
      _pages.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _index >= _data.length - 1;
    return Directionality(
      textDirection: _lang.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.deepSpace,
        body: Container(
          decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
          child: SafeArea(
            child: Column(
              children: [
                // Barre haute : skip + langues
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: AppLang.values.map((l) {
                            final sel = l == _lang;
                            return Padding(
                              padding: const EdgeInsetsDirectional.only(end: 6),
                              child: GestureDetector(
                                onTap: () => setState(() => _lang = l),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 7),
                                  decoration: BoxDecoration(
                                    gradient:
                                        sel ? AppColors.goldGradient : null,
                                    color: sel
                                        ? null
                                        : AppColors.midnightLight
                                            .withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: sel
                                          ? AppColors.ink
                                          : AppColors.midnightLight,
                                      width: sel ? 2 : 1.5,
                                    ),
                                  ),
                                  child: Text(
                                    l.label,
                                    style: TextStyle(
                                      color: sel
                                          ? AppColors.ink
                                          : AppColors.creamDim,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      TextButton(
                        key: const Key('onboardingSkipButton'),
                        onPressed: _finish,
                        child: Text(
                          _t(fr: 'Passer', en: 'Skip', ar: 'تخطي'),
                          style: const TextStyle(
                            color: AppColors.creamDim,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: _data.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) =>
                        _Page(data: _data[i], lang: _lang, index: i),
                  ),
                ),
                // Dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _data.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _index ? 26 : 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: i == _index
                            ? AppColors.sun
                            : AppColors.midnightLight,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.ink, width: 1.5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: GameButton(
                    key: const Key('onboardingNextButton'),
                    label: last
                        ? _t(
                            fr: 'En route !',
                            en: "Let's roll!",
                            ar: 'هيا بنا!')
                        : _t(fr: 'Suivant', en: 'Next', ar: 'التالي'),
                    icon: last
                        ? Icons.train_rounded
                        : Icons.arrow_forward_rounded,
                    onPressed: _next,
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

class _Page extends StatelessWidget {
  const _Page({required this.data, required this.lang, required this.index});

  final _OnboardData data;
  final AppLang lang;
  final int index;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: Key('onboardingPage$index'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      children: [
        Container(
          height: 210,
          decoration: BoxDecoration(
            gradient: data.gradient,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.ink, width: 2.5),
            boxShadow: [
              BoxShadow(
                  color: data.shadow,
                  offset: const Offset(0, 6),
                  blurRadius: 0),
            ],
          ),
          child: Center(child: _Art(index: index)),
        ),
        const SizedBox(height: 22),
        Text(
          data.title(lang),
          softWrap: true,
          style: AppTypography.hero(size: 30),
        ),
        const SizedBox(height: 10),
        Text(
          data.desc(lang),
          softWrap: true,
          style: Theme.of(context)
              .textTheme
              .bodyLarge
              ?.copyWith(color: AppColors.creamDim),
        ),
      ],
    );
  }
}

class _Art extends StatelessWidget {
  const _Art({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    switch (index) {
      case 0:
        return const SizedBox(
          width: 230,
          child: CuteTrain(),
        );
      case 1:
        return const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GoldCoin(size: 64),
            SizedBox(width: 12),
            GoldCoin(size: 84),
            SizedBox(width: 12),
            GoldCoin(size: 64),
          ],
        );
      case 2:
        return const Icon(
          Icons.lightbulb_rounded,
          size: 92,
          color: AppColors.ink,
        );
      default:
        return const Icon(
          Icons.auto_awesome_rounded,
          size: 92,
          color: AppColors.cream,
        );
    }
  }
}
