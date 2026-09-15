import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../core/data/user_repository.dart';

import '../../core/i18n/app_lang.dart';
import '../../core/storage/app_prefs.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/cute_train.dart';
import '../../core/widgets/game_button.dart';
import '../../core/widgets/token_counter.dart';
import '../results/results_screen.dart';
import 'questions.dart';

enum TileType { start, normal, bonus, trap, shortcut, finish }

class BoardTile {
  const BoardTile(this.pos, this.type);
  final Offset pos; // coordonnées normalisées 0..1
  final TileType type;
}

/// Tracé en S avec embranchement (raccourci 6 → 8 en pointillés).
const kTiles = [
  BoardTile(Offset(0.12, 0.86), TileType.start),
  BoardTile(Offset(0.31, 0.86), TileType.normal),
  BoardTile(Offset(0.50, 0.86), TileType.normal),
  BoardTile(Offset(0.69, 0.86), TileType.bonus),
  BoardTile(Offset(0.86, 0.72), TileType.normal),
  BoardTile(Offset(0.69, 0.58), TileType.trap),
  BoardTile(Offset(0.50, 0.58), TileType.shortcut),
  BoardTile(Offset(0.31, 0.58), TileType.normal),
  BoardTile(Offset(0.14, 0.43), TileType.bonus),
  BoardTile(Offset(0.32, 0.29), TileType.normal),
  BoardTile(Offset(0.55, 0.29), TileType.trap),
  BoardTile(Offset(0.80, 0.14), TileType.finish),
];

Color _tileFill(TileType t) => switch (t) {
      TileType.start => AppColors.skyPop,
      TileType.normal => AppColors.midnightLight,
      TileType.bonus => AppColors.sun,
      TileType.trap => AppColors.pinkPop,
      TileType.shortcut => AppColors.mintPop,
      TileType.finish => AppColors.cream,
    };

String _tileGlyph(TileType t) => switch (t) {
      TileType.start => '▶',
      TileType.normal => '',
      TileType.bonus => '★',
      TileType.trap => '⚠',
      TileType.shortcut => '≫',
      TileType.finish => '⚑',
    };

/// Plateau Solo : rails, cases bonus/piège/raccourci + embranchement.
class BoardPainter extends CustomPainter {
  const BoardPainter();

  static const _sleeperColors = [
    AppColors.sun,
    AppColors.pinkPop,
    AppColors.mintPop,
    AppColors.skyPop,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    Offset px(Offset n) => Offset(n.dx * size.width, n.dy * size.height);

    // Vrais rails stylisés, cohérents avec l'accueil (GameRailsPainter) :
    // deux lignes parallèles (contour encre + corps couleur + reflet)
    // + traverses bonbon perpendiculaires.
    void rail(Offset a, Offset b,
        {required Color railColor, int seed = 0}) {
      final vec = b - a;
      final len = vec.distance;
      if (len < 2) return;
      final dir = vec / len;
      final n = Offset(-dir.dy, dir.dx);
      const gauge = 13.0;

      // Traverses sous les rails.
      var idx = seed;
      for (var d = 12.0; d < len - 8; d += 20) {
        final c = a + dir * d;
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.rotate(math.atan2(dir.dy, dir.dx));
        final r = RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset.zero, width: 9, height: gauge + 14),
          const Radius.circular(3.5),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            r.outerRect.inflate(1.2),
            const Radius.circular(4.5),
          ),
          Paint()..color = AppColors.ink,
        );
        canvas.drawRRect(
            r, Paint()..color = _sleeperColors[idx % _sleeperColors.length]);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: const Offset(0, -3), width: 5, height: gauge + 4),
            const Radius.circular(2.5),
          ),
          Paint()..color = Colors.white.withValues(alpha: 0.35),
        );
        canvas.restore();
        idx++;
      }

      // Deux rails parallèles.
      for (final s in [-gauge / 2, gauge / 2]) {
        final ra = a + n * s;
        final rb = b + n * s;
        canvas.drawLine(
            ra,
            rb,
            Paint()
              ..color = AppColors.ink
              ..strokeWidth = 8
              ..strokeCap = StrokeCap.round);
        canvas.drawLine(
            ra,
            rb,
            Paint()
              ..color = railColor
              ..strokeWidth = 5
              ..strokeCap = StrokeCap.round);
        canvas.drawLine(
            ra + const Offset(0, -1.2),
            rb + const Offset(0, -1.2),
            Paint()
              ..color = Colors.white.withValues(alpha: 0.65)
              ..strokeWidth = 1.4
              ..strokeCap = StrokeCap.round);
      }
    }

    // Embranchement raccourci 6 → 8 : mêmes rails, teinte menthe distinctive.
    rail(px(kTiles[6].pos), px(kTiles[8].pos),
        railColor: AppColors.mintPop, seed: 2);
    // Voie principale.
    for (var i = 0; i < kTiles.length - 1; i++) {
      rail(px(kTiles[i].pos), px(kTiles[i + 1].pos),
          railColor: AppColors.skyPop, seed: i);
    }

    // Cases.
    for (var i = 0; i < kTiles.length; i++) {
      final c = px(kTiles[i].pos);
      final t = kTiles[i].type;
      final r = (t == TileType.start || t == TileType.finish) ? 21.0 : 17.0;
      canvas.drawCircle(c, r + 2.5, Paint()..color = AppColors.ink);
      canvas.drawCircle(c, r, Paint()..color = _tileFill(t));
      canvas.drawCircle(
          c + const Offset(-4, -5), 5, Paint()..color = Colors.white.withValues(alpha: 0.5));
      final glyph = _tileGlyph(t);
      if (glyph.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
            text: glyph,
            style: TextStyle(
              color: (t == TileType.bonus || t == TileType.finish)
                  ? AppColors.ink
                  : Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
      }
      // Numéro de case.
      final num = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: const TextStyle(
              color: AppColors.creamDim,
              fontSize: 10,
              fontWeight: FontWeight.w800),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      num.paint(canvas, c + Offset(-num.width / 2, r + 5));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Écran Plateau Solo : le train avance case par case à chaque bonne réponse.
class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key, this.prefs, this.lang = AppLang.fr});

  final AppPrefs? prefs;
  final AppLang lang;

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen>
    with SingleTickerProviderStateMixin {
  late final AppLang _lang = widget.lang;
  late int _tokens = widget.prefs?.tokens ?? 120;
  int _pos = 0;
  // Position normalisée du train (0..1) : suit exactement les rails.
  Offset _trainNorm = kTiles[0].pos;
  // Chemin courant (waypoints normalisés) + sens pour orienter le train.
  List<Offset> _railPath = [kTiles[0].pos];
  double _trainAngle = 0;
  bool _trainMirrored = false;
  int _score = 0;
  int _streak = 0;
  int _best = 0;
  int _earned = 0;
  int _qIndex = 0;
  int _answered = 0;
  bool _moving = false;

  late final AnimationController _move =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 750));
  Animation<double>? _anim;

  static const int _maxQuestions = 8;

  @override
  void dispose() {
    _move.dispose();
    super.dispose();
  }

  String _t({required String fr, required String en, required String ar}) =>
      switch (_lang) { AppLang.fr => fr, AppLang.en => en, AppLang.ar => ar };

  int get _last => kTiles.length - 1;
  bool get _finished => _pos >= _last || _answered >= _maxQuestions;

  Future<void> _persist() async {
    final p = widget.prefs;
    if (p == null) return;
    await p.setTokens(_tokens);
    // Miroir cloud best-effort (offline → ignoré).
    unawaited(UserRepository(prefs: p).pushTokens(_tokens));
  }

  /// Échantillonne [path] (waypoints normalisés) à [t] 0..1 en suivant
  /// la longueur des segments — le train reste sur les rails, sans couper.
  static Offset _samplePath(List<Offset> path, double t) {
    if (path.length < 2) return path.first;
    final lens = <double>[];
    var total = 0.0;
    for (var i = 0; i < path.length - 1; i++) {
      final l = (path[i + 1] - path[i]).distance;
      lens.add(l);
      total += l;
    }
    if (total <= 0) return path.last;
    var dist = (t.clamp(0.0, 1.0)) * total;
    for (var i = 0; i < lens.length; i++) {
      if (dist <= lens[i] || i == lens.length - 1) {
        final f = lens[i] <= 0 ? 1.0 : (dist / lens[i]).clamp(0.0, 1.0);
        return Offset(
          path[i].dx + (path[i + 1].dx - path[i].dx) * f,
          path[i].dy + (path[i + 1].dy - path[i].dy) * f,
        );
      }
      dist -= lens[i];
    }
    return path.last;
  }

  static double _pathAngle(List<Offset> path, double t) {
    if (path.length < 2) return 0;
    const e = 0.02;
    final a = _samplePath(path, (t - e).clamp(0.0, 1.0));
    final b = _samplePath(path, (t + e).clamp(0.0, 1.0));
    final d = b - a;
    if (d.distance < 1e-6) return 0;
    return math.atan2(d.dy, d.dx);
  }

  void _flyTo(int target) {
    target = target.clamp(0, _last);
    final start = _pos;
    if (target == start) return;
    final base = math.min(start + 1, _last);
    final isShortcut =
        kTiles[base].type == TileType.shortcut && target > base;
    final List<Offset> path;
    if (isShortcut) {
      // Passe par la case raccourci puis suit la voie menthe directe.
      path = [kTiles[start].pos, kTiles[base].pos, kTiles[target].pos];
      _move.duration = const Duration(milliseconds: 1100);
    } else {
      // Suit chaque case intermédiaire de la voie principale.
      path = [];
      final step = target > start ? 1 : -1;
      for (var i = start; ; i += step) {
        path.add(kTiles[i].pos);
        if (i == target) break;
      }
      _move.duration = Duration(
          milliseconds: 650 * (target - start).abs().clamp(1, 4));
    }
    setState(() => _moving = true);
    _railPath = path;
    _anim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _move, curve: Curves.easeInOut),
    )..addListener(() {
        final t = _anim!.value;
        final p = _samplePath(_railPath, t);
        final ang = _pathAngle(_railPath, t);
        setState(() {
          _trainNorm = p;
          _trainAngle = ang;
          // Oriente le train dans le sens de marche (miroir si vers gauche).
          final dx = math.cos(ang);
          if (dx.abs() > 0.25) _trainMirrored = dx < 0;
        });
      });
    _move.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      setState(() {
        _pos = target;
        _trainNorm = kTiles[target].pos;
        _moving = false;
      });
      if (_finished) _goResults();
    });
  }

  void _openQuestion() {
    if (_moving || _finished) return;
    final q = kQuestions[_qIndex % kQuestions.length];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => QuestionSheet(
        question: q,
        lang: _lang,
        tokens: _tokens,
        onSpend: (cost) {
          if (_tokens < cost) return false;
          setState(() => _tokens -= cost);
          _persist();
          return true;
        },
        onCorrect: () => _onCorrect(),
        onWrong: (answer) => _onWrong(answer),
      ),
    );
  }

  void _onCorrect() {
    final base = math.min(_pos + 1, _last);
    final tile = kTiles[base].type;
    final target =
        (tile == TileType.shortcut ? base + 2 : base).clamp(0, _last);
    var gain = 10;
    if (tile == TileType.bonus) gain += 10;
    if (tile == TileType.trap) gain -= 5;
    setState(() {
      _score += 100;
      _streak += 1;
      _best = math.max(_best, _streak);
      _tokens = math.max(0, _tokens + gain);
      _earned += gain > 0 ? gain : 0;
      _qIndex += 1;
      _answered += 1;
    });
    _persist();
    final msg = switch (tile) {
      TileType.bonus =>
        _t(fr: 'Bonus ! +10 jetons', en: 'Bonus! +10 tokens', ar: 'مكافأة! +10 رموز'),
      TileType.trap =>
        _t(fr: 'Piège… −5 jetons', en: 'Trap… −5 tokens', ar: 'فخ… −5 رموز'),
      TileType.shortcut =>
        _t(fr: 'Raccourci ! +2 cases', en: 'Shortcut! +2 tiles', ar: 'اختصار! +2 خانات'),
      _ => _t(fr: 'Bonne réponse !', en: 'Correct!', ar: 'إجابة صحيحة!'),
    };
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
    _flyTo(target);
    if (target >= _last || _answered >= _maxQuestions) return;
  }

  void _onWrong(String answer) {
    setState(() {
      _streak = 0;
      _qIndex += 1;
      _answered += 1;
    });
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(_t(
          fr: 'Raté ! Réponse : $answer',
          en: 'Missed! Answer: $answer',
          ar: 'خطأ! الإجابة: $answer',
        )),
      ));
    if (_finished) _goResults();
  }

  void _goResults() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ResultsScreen(
          prefs: widget.prefs,
          lang: _lang,
          score: _score,
          bestStreak: _best,
          tokensEarned: _earned,
          walletTokens: _tokens,
          position: _pos,
          totalTiles: kTiles.length,
        ),
      ),
    );
  }

  void _showLegend() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        key: const Key('boardLegendDialog'),
        backgroundColor: AppColors.midnight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.midnightLight, width: 1.5),
        ),
        title: Text(
          _t(fr: 'Légende', en: 'Legend', ar: 'دليل الخانات'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LegendRow(
              fill: AppColors.sun,
              glyph: '★',
              glyphColor: AppColors.ink,
              title: _t(fr: 'Bonus', en: 'Bonus', ar: 'مكافأة'),
              subtitle: _t(
                  fr: '+10 jetons',
                  en: '+10 tokens',
                  ar: '+10 رموز'),
            ),
            const SizedBox(height: 8),
            _LegendRow(
              fill: AppColors.pinkPop,
              glyph: '⚠',
              glyphColor: Colors.white,
              title: _t(fr: 'Piège', en: 'Trap', ar: 'فخ'),
              subtitle: _t(
                  fr: '−5 jetons',
                  en: '−5 tokens',
                  ar: '−5 رموز'),
            ),
            const SizedBox(height: 8),
            _LegendRow(
              fill: AppColors.mintPop,
              glyph: '≫',
              glyphColor: Colors.white,
              title: _t(fr: 'Raccourci', en: 'Shortcut', ar: 'اختصار'),
              subtitle: _t(
                  fr: 'Voie menthe : +2 cases',
                  en: 'Mint track: +2 tiles',
                  ar: 'مسار نعناعي: +2 خانات'),
            ),
            const SizedBox(height: 8),
            _LegendRow(
              fill: AppColors.skyPop,
              glyph: '●',
              glyphColor: Colors.white,
              title: _t(fr: 'Voie normale', en: 'Normal track', ar: 'مسار عادي'),
              subtitle: _t(
                  fr: 'Rails bleus : +1 case',
                  en: 'Blue rails: +1 tile',
                  ar: 'مسارات زرقاء: +1 خانة'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              _t(fr: 'Compris !', en: 'Got it!', ar: 'فهمت!'),
              style: const TextStyle(
                  color: AppColors.sun, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = _last == 0 ? 0.0 : _pos / _last;
    // Utilise toute la hauteur dispo : le plateau grandit sur grands écrans
    // (plus d'espace mort sous les boutons), min 340 pour petits écrans.
    final screenH = MediaQuery.sizeOf(context).height;
    final boardH = (screenH - 380).clamp(340.0, 640.0);
    return Directionality(
      textDirection: _lang.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        key: const Key('boardScreen'),
        backgroundColor: AppColors.deepSpace,
        body: Container(
          decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                // En-tête : retour + titre + légende + portefeuille.
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
                            fr: 'Plateau Solo',
                            en: 'Solo Board',
                            ar: 'لوحة الفردي'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      key: const Key('boardLegendButton'),
                      tooltip: _t(
                          fr: 'Légende', en: 'Legend', ar: 'دليل الخانات'),
                      onPressed: _showLegend,
                      icon: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.midnight,
                          border: Border.all(
                              color: AppColors.sun, width: 1.8),
                        ),
                        child: const Center(
                          child: Text(
                            '?',
                            style: TextStyle(
                              color: AppColors.sun,
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.midnight.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppColors.midnightLight, width: 1.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const GoldCoin(size: 22),
                          const SizedBox(width: 6),
                          Text('$_tokens',
                              style: const TextStyle(
                                  color: AppColors.sun,
                                  fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Progression du wagon.
                _ProgressBar(
                  progress: progress,
                  label: _t(
                      fr: 'Question ${_answered + 1}/$_maxQuestions',
                      en: 'Question ${_answered + 1}/$_maxQuestions',
                      ar: 'سؤال ${_answered + 1}/$_maxQuestions'),
                ),
                const SizedBox(height: 12),
                // Plateau.
                Container(
                  height: boardH,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.midnight.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                        color: AppColors.midnightLight, width: 1.5),
                  ),
                  child: LayoutBuilder(
                    builder: (context, c) {
                      Offset px(Offset n) =>
                          Offset(n.dx * c.maxWidth, n.dy * c.maxHeight);
                      // Le train roule SUR les rails : position échantillonnée
                      // le long du tracé, roues posées sur la voie.
                      final p = px(_trainNorm);
                      // Léger tangage cartoon selon la pente, sans cabrer.
                      final lean =
                          (_trainAngle == 0.0) ? 0.0 :
                          (math.sin(_trainAngle) * 0.08).clamp(-0.1, 0.1);
                      return Stack(
                        children: [
                          const Positioned.fill(
                            child: CustomPaint(
                              key: Key('boardPaint'),
                              painter: BoardPainter(),
                            ),
                          ),
                          Positioned(
                            left: (p.dx - 34).clamp(0.0, c.maxWidth - 68),
                            top: (p.dy - 50).clamp(0.0, c.maxHeight - 60),
                            child: _BoardTrain(
                              mirrored: _trainMirrored,
                              angle: lean,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                // Stats.
                Row(
                  children: [
                    Expanded(
                        child: _Stat(
                            label: _t(fr: 'Score', en: 'Score', ar: 'النقاط'),
                            value: '$_score')),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _Stat(
                            label:
                                _t(fr: 'Série', en: 'Streak', ar: 'السلسلة'),
                            value: '$_streak')),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _Stat(
                            label: _t(
                                fr: 'Jetons +',
                                en: 'Tokens +',
                                ar: '+ رموز'),
                            value: '+$_earned')),
                  ],
                ),
                const SizedBox(height: 14),
                GameButton(
                  key: const Key('nextQuestionButton'),
                  label: _moving
                      ? _t(
                          fr: 'Train en route…',
                          en: 'Train moving…',
                          ar: 'القطار يتحرك…')
                      : _t(
                          fr: 'Question suivante',
                          en: 'Next question',
                          ar: 'السؤال التالي'),
                  icon: Icons.quiz_rounded,
                  onPressed: _moving ? null : _openQuestion,
                ),
                TextButton(
                  key: const Key('finishBoardButton'),
                  onPressed: _moving ? null : _goResults,
                  child: Text(
                    _t(
                        fr: 'Terminer la partie',
                        en: 'Finish run',
                        ar: 'إنهاء الجولة'),
                    style: const TextStyle(
                        color: AppColors.creamDim,
                        fontWeight: FontWeight.w800),
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

class _BoardTrain extends StatelessWidget {
  const _BoardTrain({this.mirrored = false, this.angle = 0});

  final bool mirrored;
  final double angle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 68,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.sun.withValues(alpha: 0.5),
            blurRadius: 12,
          ),
        ],
      ),
      child: Transform.rotate(
        angle: angle,
        child: FittedBox(
          fit: BoxFit.contain,
          // 212 = largeur naturelle du CuteTrain (204) + marge anti-overflow.
          child: SizedBox(
              width: 212, height: 90, child: CuteTrain(mirrored: mirrored)),
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.fill,
    required this.glyph,
    required this.glyphColor,
    required this.title,
    required this.subtitle,
  });

  final Color fill;
  final String glyph;
  final Color glyphColor;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: fill,
            border: Border.all(color: AppColors.ink, width: 2),
          ),
          child: Center(
            child: Text(
              glyph,
              style: TextStyle(
                color: glyphColor,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                    color: AppColors.cream, fontWeight: FontWeight.w900),
              ),
              Text(
                subtitle,
                style: const TextStyle(color: AppColors.creamDim, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.progress, required this.label});

  final double progress;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: AppColors.sun)),
        const SizedBox(height: 6),
        Container(
          height: 16,
          decoration: BoxDecoration(
            color: AppColors.midnight,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.ink, width: 2),
          ),
          child: Stack(
            children: [
              FractionallySizedBox(
                widthFactor: progress.clamp(0.04, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: AppColors.playGradient,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.midnight.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: AppColors.midnightLight, width: 1.5),
      ),
      child: Column(
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 2),
          Text(value,
              style: AppTypography.tokenCount(size: 22)),
        ],
      ),
    );
  }
}

/// Carte question en bottom-sheet : champ de réponse + indices payants.
class QuestionSheet extends StatefulWidget {
  const QuestionSheet({
    super.key,
    required this.question,
    required this.lang,
    required this.tokens,
    required this.onSpend,
    required this.onCorrect,
    required this.onWrong,
  });

  final QuizQuestion question;
  final AppLang lang;
  final int tokens;
  final bool Function(int cost) onSpend;
  final VoidCallback onCorrect;
  final ValueChanged<String> onWrong;

  @override
  State<QuestionSheet> createState() => _QuestionSheetState();
}

class _QuestionSheetState extends State<QuestionSheet> {
  final _controller = TextEditingController();
  bool _letter = false;
  bool _revealed = false;
  String? _error;
  // Vrai uniquement après une tentative de validation : le message
  // d'erreur ne doit jamais apparaître à l'ouverture de la question.
  bool _attempted = false;

  static const letterCost = 5;
  static const revealCost = 15;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _t({required String fr, required String en, required String ar}) =>
      switch (widget.lang) {
        AppLang.fr => fr,
        AppLang.en => en,
        AppLang.ar => ar
      };

  void _submit() {
    setState(() => _attempted = true);
    final ok = widget.question.check(_controller.text, widget.lang);
    if (ok) {
      Navigator.of(context).pop();
      widget.onCorrect();
    } else {
      setState(() => _error = _t(
          fr: 'Pas tout à fait, réessaie ou prends un indice.',
          en: 'Not quite — retry or grab a hint.',
          ar: 'ليس تمامًا، حاول مجددًا أو خذ تلميحًا.'));
    }
  }

  void _giveUp() {
    Navigator.of(context).pop();
    widget.onWrong(widget.question.answers(widget.lang).first);
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      key: const Key('questionSheet'),
      margin: EdgeInsets.only(bottom: insets),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
      decoration: const BoxDecoration(
        color: AppColors.midnight,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        border: Border(
          top: BorderSide(color: AppColors.midnightLight, width: 1.5),
          left: BorderSide(color: AppColors.midnightLight, width: 1.5),
          right: BorderSide(color: AppColors.midnightLight, width: 1.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.midnightLight,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.question.prompt(widget.lang),
              softWrap: true,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('answerField'),
              controller: _controller,
              onSubmitted: (_) => _submit(),
              textInputAction: TextInputAction.done,
              style: const TextStyle(
                  color: AppColors.cream, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                hintText: _t(
                    fr: 'Ta réponse…',
                    en: 'Your answer…',
                    ar: 'إجابتك…'),
                hintStyle:
                    const TextStyle(color: AppColors.creamDim),
                filled: true,
                fillColor: AppColors.deepSpace,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                      color: AppColors.midnightLight, width: 1.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      const BorderSide(color: AppColors.sun, width: 2),
                ),
              ),
            ),
            if (_letter)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _t(
                      fr: 'Commence par « ${widget.question.firstLetter(widget.lang)} »',
                      en: 'Starts with “${widget.question.firstLetter(widget.lang)}”',
                      ar: 'يبدأ بـ«${widget.question.firstLetter(widget.lang)}»'),
                  style: const TextStyle(
                      color: AppColors.sun, fontWeight: FontWeight.w800),
                ),
              ),
            if (_revealed)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _t(
                      fr: 'Réponse : ${widget.question.answers(widget.lang).first}',
                      en: 'Answer: ${widget.question.answers(widget.lang).first}',
                      ar: 'الإجابة: ${widget.question.answers(widget.lang).first}'),
                  style: const TextStyle(
                      color: AppColors.mintPop,
                      fontWeight: FontWeight.w800),
                ),
              ),
            if (_attempted && _error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    key: const Key('answerErrorText'),
                    softWrap: true,
                    style: const TextStyle(
                        color: AppColors.pinkPop,
                        fontWeight: FontWeight.w700)),
              ),
            const SizedBox(height: 12),
            // Indices payants (prix toujours LTR).
            Row(
              children: [
                Expanded(
                  child: _HintButton(
                    key: const Key('hintLetterButton'),
                    icon: Icons.text_fields_rounded,
                    title: _t(
                        fr: '1re lettre',
                        en: '1st letter',
                        ar: 'الحرف الأول'),
                    price: letterCost,
                    used: _letter,
                    affordable: widget.tokens >= letterCost,
                    onTap: () {
                      if (_letter) return;
                      if (widget.onSpend(letterCost)) {
                        setState(() {
                          _letter = true;
                          _error = null;
                        });
                      } else {
                        setState(() => _error = _t(
                            fr: 'Pas assez de jetons.',
                            en: 'Not enough tokens.',
                            ar: 'رموز غير كافية.'));
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _HintButton(
                    key: const Key('hintRevealButton'),
                    icon: Icons.visibility_rounded,
                    title: _t(
                        fr: 'Révéler', en: 'Reveal', ar: 'كشف'),
                    price: revealCost,
                    used: _revealed,
                    affordable: widget.tokens >= revealCost,
                    onTap: () {
                      if (_revealed) return;
                      if (widget.onSpend(revealCost)) {
                        setState(() {
                          _revealed = true;
                          _error = null;
                        });
                      } else {
                        setState(() => _error = _t(
                            fr: 'Pas assez de jetons.',
                            en: 'Not enough tokens.',
                            ar: 'رموز غير كافية.'));
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GameButton(
              key: const Key('submitAnswerButton'),
              label: _t(
                  fr: 'Valider', en: 'Submit', ar: 'تأكيد'),
              icon: Icons.check_rounded,
              height: 54,
              fontSize: 18,
              onPressed: _submit,
            ),
            TextButton(
              onPressed: _giveUp,
              child: Text(
                _t(
                    fr: 'Abandonner cette question',
                    en: 'Skip question',
                    ar: 'تخطي السؤال'),
                style: const TextStyle(
                    color: AppColors.creamDim,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HintButton extends StatelessWidget {
  const _HintButton({
    super.key,
    required this.icon,
    required this.title,
    required this.price,
    required this.used,
    required this.affordable,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final int price;
  final bool used;
  final bool affordable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dim = used || !affordable;
    return GestureDetector(
      onTap: used ? null : onTap,
      child: Opacity(
        opacity: dim ? 0.55 : 1.0,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: used
                ? AppColors.mintPop.withValues(alpha: 0.25)
                : AppColors.midnightLight.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: used ? AppColors.mintPop : AppColors.sun,
                width: 1.5),
          ),
          child: Column(
            children: [
              Icon(icon,
                  size: 20,
                  color:
                      used ? AppColors.mintPop : AppColors.sun),
              const SizedBox(height: 4),
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.cream,
                      fontWeight: FontWeight.w800,
                      fontSize: 13)),
              // Prix isolé en LTR pour un ordre stable en AR.
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text('−$price 🪙',
                    style: const TextStyle(
                        color: AppColors.sun,
                        fontWeight: FontWeight.w900,
                        fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
