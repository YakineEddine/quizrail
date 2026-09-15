import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../../features/shop/monetization_config.dart'
    show trainSkinPalettes;

/// Rails stylisés QuizRail : traverses bonbon + rails cyan à contour cartoon.
/// Remplace les traits gris par une voie de plateau de jeu.
class GameRailsPainter extends CustomPainter {
  const GameRailsPainter();

  static const _sleeperColors = [
    AppColors.sun,
    AppColors.pinkPop,
    AppColors.mintPop,
    AppColors.skyPop,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final y1 = size.height - 30;
    final y2 = size.height - 12;

    // Traverses bonbon
    var i = 0;
    for (var x = 6.0; x < size.width - 10; x += 30) {
      final color = _sleeperColors[i % _sleeperColors.length];
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y1 - 8, 20, (y2 - y1) + 16),
        const Radius.circular(6),
      );
      // Contour cartoon
      canvas.drawRRect(
        rect.outerRect.inflate(1.5).toRRect(7),
        Paint()..color = AppColors.ink,
      );
      canvas.drawRRect(rect, Paint()..color = color);
      // Reflet haut
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x + 3, y1 - 5, 14, 5),
          const Radius.circular(3),
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.55),
      );
      i++;
    }

    // Rails : contour encre + corps cyan + reflet blanc
    for (final y in [y1, y2]) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = AppColors.ink
          ..strokeWidth = 10
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = AppColors.skyPop
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        Offset(0, y - 1.5),
        Offset(size.width, y - 1.5),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.8)
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

extension on Rect {
  RRect toRRect(double radius) => RRect.fromRectAndRadius(this, Radius.circular(radius));
}

/// Ancien nom conservé pour compatibilité : délègue au nouveau painter.
typedef RailsPainter = GameRailsPainter;

/// Petit train sympathique et identifiable : loco avec visage + 2 wagons.
/// 100 % widgets (pas d'emoji, pas d'Icon.train gris).
/// [skin] reteinte la loco (classique gratuit, autres via la boutique).
class CuteTrain extends StatelessWidget {
  const CuteTrain({super.key, this.mirrored = false, this.skin = 'classic'});

  final bool mirrored;
  final String skin;

  @override
  Widget build(BuildContext context) {
    final palettes = trainSkinPalettes(
      classicCab: AppColors.skyPop,
      classicRoof: AppColors.sun,
      classicChimney: AppColors.sun,
      gold: AppColors.sun,
      pink: AppColors.pinkPop,
      mint: AppColors.mintPop,
      sky: AppColors.skyPop,
    );
    final pal = palettes[skin] ?? palettes['classic']!;
    final train = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _Locomotive(cab: pal.cab, roof: pal.roof, chimneyCap: pal.chimney),
        const _Connector(),
        const _Wagon(
          body: AppColors.mintPop,
          stripe: AppColors.ink,
          icon: Icons.quiz_rounded,
        ),
        const _Connector(),
        const _Wagon(
          body: AppColors.violetPop,
          stripe: AppColors.sun,
          icon: Icons.people_alt_rounded,
        ),
      ],
    );
    if (!mirrored) return train;
    return Transform.flip(flipX: true, child: train);
  }
}

class _Connector extends StatelessWidget {
  const _Connector();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 6,
      margin: const EdgeInsets.only(bottom: 14, left: 1, right: 1),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

class _Locomotive extends StatelessWidget {
  const _Locomotive({
    required this.cab,
    required this.roof,
    required this.chimneyCap,
  });

  final Color cab;
  final Color roof;
  final Color chimneyCap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      height: 62,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Cheminée
          Positioned(
            left: 58,
            top: 0,
            child: Container(
              width: 14,
              height: 16,
              decoration: BoxDecoration(
                color: AppColors.midnight,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.ink, width: 2),
              ),
            ),
          ),
          Positioned(
            left: 54,
            top: -2,
            child: Container(
              width: 22,
              height: 8,
              decoration: BoxDecoration(
                color: chimneyCap,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.ink, width: 2),
              ),
            ),
          ),
          // Cabine arrière
          Positioned(
            left: 2,
            top: 8,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: cab,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: AppColors.ink, width: 2.5),
              ),
              child: Center(
                child: Container(
                  width: 20,
                  height: 18,
                  decoration: BoxDecoration(
                    color: AppColors.cream,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.ink, width: 2),
                  ),
                ),
              ),
            ),
          ),
          // Toit
          Positioned(
            left: 0,
            top: 4,
            child: Container(
              width: 40,
              height: 9,
              decoration: BoxDecoration(
                color: roof,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: AppColors.ink, width: 2),
              ),
            ),
          ),
          // Corps principal
          Positioned(
            left: 12,
            top: 22,
            child: Container(
              width: 74,
              height: 30,
              decoration: BoxDecoration(
                gradient: AppColors.playGradient,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.ink, width: 2.5),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Eye(),
                  SizedBox(width: 5),
                  _Eye(pupilDx: 1.2),
                ],
              ),
            ),
          ),
          // Sourire sous les yeux
          const Positioned(
            left: 40,
            top: 40,
            child: _Smile(),
          ),
          // Phare
          Positioned(
            right: -3,
            top: 26,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.sun,
                border: Border.all(color: AppColors.ink, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Color(0xAAFFC93C),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
          // Pare-chocs
          Positioned(
            right: -4,
            top: 42,
            child: Container(
              width: 8,
              height: 12,
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          // Roues
          const Positioned(left: 16, bottom: 0, child: _Wheel(size: 18)),
          const Positioned(right: 10, bottom: 0, child: _Wheel(size: 22)),
        ],
      ),
    );
  }
}

class _Eye extends StatelessWidget {
  const _Eye({this.pupilDx = 0});

  final double pupilDx;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 13,
      height: 15,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppColors.ink, width: 1.8),
      ),
      child: Center(
        child: Transform.translate(
          offset: Offset(pupilDx, 1),
          child: Container(
            width: 5.5,
            height: 7,
            decoration: const BoxDecoration(
              color: AppColors.ink,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

class _Smile extends StatelessWidget {
  const _Smile();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: const Size(18, 9), painter: _SmilePainter());
  }
}

class _SmilePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawArc(
      Rect.fromLTWH(0, -6, size.width, 14),
      0.25 * math.pi,
      0.5 * math.pi,
      false,
      Paint()
        ..color = AppColors.ink
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Wagon extends StatelessWidget {
  const _Wagon({required this.body, required this.stripe, required this.icon});

  final Color body;
  final Color stripe;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 52,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 10,
            child: Container(
              width: 46,
              height: 28,
              decoration: BoxDecoration(
                color: body,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: AppColors.ink, width: 2.5),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 15, color: Colors.white),
                  const SizedBox(height: 2),
                  Container(
                    width: 30,
                    height: 4,
                    decoration: BoxDecoration(
                      color: stripe.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Positioned(left: 5, bottom: 0, child: _Wheel(size: 14)),
          const Positioned(right: 5, bottom: 0, child: _Wheel(size: 14)),
        ],
      ),
    );
  }
}

class _Wheel extends StatelessWidget {
  const _Wheel({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.ink,
        border: Border.all(color: AppColors.ink, width: 1),
      ),
      child: Center(
        child: Container(
          width: size * 0.42,
          height: size * 0.42,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.cream,
          ),
        ),
      ),
    );
  }
}

/// Train qui traverse tout l'écran en boucle, avec oscillation
/// verticale et fumée à 3 bouffées.
/// Zone >= 25 % de la hauteur d'écran (min 190, max 260).
/// Même API que le micro-test d'origine (controller + isRtl).
class TrainAnimation extends StatelessWidget {
  const TrainAnimation({
    super.key,
    required this.controller,
    required this.isRtl,
    this.heightFactor = 0.27,
  });

  final AnimationController controller;
  final bool isRtl;
  final double heightFactor;

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.sizeOf(context).height;
    final h = (screenH * heightFactor).clamp(190.0, 260.0);
    return SizedBox(
      height: h,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          return AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final progress = controller.value;
              const trainWidth = 210.0;
              const margin = 24.0;
              // Traversée complète : sort totalement d'un côté, rentre de l'autre.
              final dx = isRtl
                  ? maxWidth + margin -
                      progress * (maxWidth + trainWidth + margin * 2)
                  : -trainWidth -
                      margin +
                      progress * (maxWidth + trainWidth + margin * 2);
              // Oscillation verticale douce + léger tangage cartoon.
              final bob = math.sin(progress * math.pi * 2 * 4) * 5.0;
              final tilt = math.sin(progress * math.pi * 2 * 4) * 0.025;
              final trainTop = h / 2 - 44 + bob;
              // Cheminée : côté avant du train (miroir en RTL).
              final chimneyX = isRtl
                  ? dx + trainWidth - 78
                  : dx + 62;
              return Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: const GameRailsPainter()),
                  ),
                  Positioned(
                    left: dx,
                    top: trainTop,
                    child: Transform.rotate(
                      angle: isRtl ? -tilt : tilt,
                      child: Transform.scale(
                        scale: 1.18,
                        alignment: Alignment.bottomCenter,
                        child: CuteTrain(mirrored: isRtl),
                      ),
                    ),
                  ),
                  // Fumée : 3 bouffées décalées qui montent et s'estompent.
                  for (var k = 0; k < 3; k++)
                    Builder(
                      builder: (context) {
                        final phase = (progress * 2 + k / 3) % 1.0;
                        return Positioned(
                          left: chimneyX +
                              phase * (isRtl ? -18 : 18) +
                              math.sin((progress * 6 + k) * math.pi) * 3,
                          top: trainTop - 6 - phase * 34,
                          child: Opacity(
                            opacity: (1 - phase) * 0.75,
                            child: Container(
                              width: 9 + phase * 13,
                              height: 9 + phase * 13,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white
                                    .withValues(alpha: 0.9 - phase * 0.25),
                              ),
                            ),
                          ),
                        );
                      },
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
