import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

/// Langues supportées par le micro-test.
/// FR/EN en LTR, AR en RTL pour valider le layout bidirectionnel.
enum AppLang { fr, en, ar }

extension AppLangX on AppLang {
  String get label {
    switch (this) {
      case AppLang.fr:
        return 'FR';
      case AppLang.en:
        return 'EN';
      case AppLang.ar:
        return 'AR';
    }
  }

  bool get isRtl => this == AppLang.ar;
}

/// Micro-test écran d'accueil QuizRail :
/// - train animé (AnimationController + CustomPainter pour les rails)
/// - compteur de jetons (état éphémère type streak/timer/position)
/// - sélecteur FR/EN/AR (dont RTL)
/// Zéro dépendance externe : Flutter SDK seul.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QuizRail',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: .fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  AppLang _lang = AppLang.fr;
  int _tokens = 120;

  late final AnimationController _trainController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

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
  }

  void _setLang(AppLang lang) {
    setState(() => _lang = lang);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: _lang.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_t(fr: 'QuizRail – Accueil', en: 'QuizRail – Home', ar: 'QuizRail – الرئيسية')),
          centerTitle: true,
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Sélecteur de langue
            SegmentedButton<AppLang>(
              segments: const [
                ButtonSegment(value: AppLang.fr, label: Text('FR')),
                ButtonSegment(value: AppLang.en, label: Text('EN')),
                ButtonSegment(value: AppLang.ar, label: Text('AR')),
              ],
              selected: {_lang},
              onSelectionChanged: (selection) => _setLang(selection.first),
            ),
            const SizedBox(height: 24),
            // Compteur de jetons
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.confirmation_num, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _t(fr: 'Jetons', en: 'Tokens', ar: 'رموز'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            '$_tokens',
                            key: const Key('tokenCount'),
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      key: const Key('addTokensButton'),
                      onPressed: _addTokens,
                      icon: const Icon(Icons.add),
                      label: const Text('+10'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Train animé
            Card(
              clipBehavior: Clip.hardEdge,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  children: [
                    Text(
                      _t(
                        fr: 'Micro-test animation',
                        en: 'Animation micro-test',
                        ar: 'اختبار الرسوم المتحركة',
                      ),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 12),
                    TrainAnimation(
                      key: const Key('trainAnimation'),
                      controller: _trainController,
                      isRtl: _lang.isRtl,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _addTokens,
              child: Text(_t(fr: 'Jouer', en: 'Play', ar: 'العب')),
            ),
            const SizedBox(height: 8),
            Text(
              _t(
                fr: 'Riverpod prévu en Phase 1, aucun package externe ici.',
                en: 'Riverpod planned for Phase 1, no external package here.',
                ar: 'Riverpod مخطط له في المرحلة 1، لا حزم خارجية هنا.',
              ),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Train qui traverse l'écran en boucle.
/// Le sens s'inverse en AR pour rester cohérent avec le RTL.
class TrainAnimation extends StatelessWidget {
  const TrainAnimation({
    super.key,
    required this.controller,
    required this.isRtl,
  });

  final AnimationController controller;
  final bool isRtl;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          return AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              // 0.0 -> 1.0 en boucle, avec marge pour sortie d'écran.
              final progress = controller.value;
              final trainWidth = 140.0;
              final dx = isRtl
                  ? maxWidth - progress * (maxWidth + trainWidth * 2) + trainWidth
                  : -trainWidth + progress * (maxWidth + trainWidth * 2);
              return Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: RailsPainter()),
                  ),
                  Positioned(
                    left: dx,
                    top: 8,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.train, size: 44),
                        const SizedBox(width: 4),
                        Container(
                          width: 36,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.teal.shade300,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Icon(Icons.people, size: 20),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          width: 36,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.orange.shade300,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Icon(Icons.quiz, size: 20),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// Rails dessinés en CustomPainter (préfigure les rails du plateau).
/// C'est ce rendu qu'il faudra tester sur appareil réel en Phase 1.
class RailsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final railPaint = Paint()
      ..color = Colors.grey.shade600
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final sleeperPaint = Paint()
      ..color = Colors.brown.shade300
      ..strokeWidth = 4;

    final y1 = size.height - 28;
    final y2 = size.height - 12;
    canvas.drawLine(Offset(0, y1), Offset(size.width, y1), railPaint);
    canvas.drawLine(Offset(0, y2), Offset(size.width, y2), railPaint);

    for (var x = 8.0; x < size.width; x += 24) {
      canvas.drawLine(Offset(x, y1 - 2), Offset(x, y2 + 2), sleeperPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
