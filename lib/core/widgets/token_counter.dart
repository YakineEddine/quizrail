import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Pièce dorée QuizRail : dégradé or + étoile + reflet.
class GoldCoin extends StatelessWidget {
  const GoldCoin({super.key, this.size = 46});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.goldGradient,
        border: Border.all(color: AppColors.ink, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.sun.withValues(alpha: 0.55),
            blurRadius: 14,
            spreadRadius: 1,
          ),
          const BoxShadow(
            color: AppColors.shadowGold,
            offset: Offset(0, 3),
            blurRadius: 0,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.star_rounded, size: size * 0.62, color: AppColors.ink.withValues(alpha: 0.85)),
          // Reflet
          Positioned(
            top: size * 0.12,
            left: size * 0.18,
            child: Container(
              width: size * 0.26,
              height: size * 0.14,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compteur de jetons animé : pop + glisse à chaque gain.
/// Garde la sémantique texte pour les tests (key transmise au compteur).
class TokenCounter extends StatelessWidget {
  const TokenCounter({
    super.key,
    required this.tokens,
    required this.label,
    this.countKey,
    this.onAdd,
    this.addLabel = '+10',
  });

  final int tokens;
  final String label;
  final Key? countKey;
  final VoidCallback? onAdd;
  final String addLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Row(
        children: [
          const GoldCoin(size: 52),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        letterSpacing: 1.4,
                        color: AppColors.sun,
                      ),
                ),
                const SizedBox(height: 2),
                // AnimatedSwitcher = pop animé à chaque changement de valeur.
                // La clé de test est sur le switcher (stable), le texte animé
                // garde un ValueKey pour déclencher la transition.
                AnimatedSwitcher(
                  key: countKey,
                  duration: const Duration(milliseconds: 350),
                  transitionBuilder: (child, animation) {
                    final scale = Tween<double>(begin: 0.6, end: 1.0)
                        .animate(CurvedAnimation(parent: animation, curve: Curves.elasticOut));
                    final slide = Tween<Offset>(
                      begin: const Offset(0, 0.45),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutBack));
                    return ScaleTransition(
                      scale: scale,
                      child: SlideTransition(position: slide, child: child),
                    );
                  },
                  child: Text(
                    '$tokens',
                    key: ValueKey<int>(tokens),
                    style: AppTypography.tokenCount(),
                  ),
                ),
              ],
            ),
          ),
          _GainButton(
            key: const Key('addTokensButton'),
            onAdd: onAdd,
            addLabel: addLabel,
          ),
        ],
      ),
    );
  }
}

class _GainButton extends StatefulWidget {
  const _GainButton({super.key, required this.onAdd, required this.addLabel});

  final VoidCallback? onAdd;
  final String addLabel;

  @override
  State<_GainButton> createState() => _GainButtonState();
}

class _GainButtonState extends State<_GainButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onAdd?.call();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        transform: Matrix4.translationValues(0, _pressed ? 3 : 0, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: AppColors.goldGradient,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.ink, width: 2),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadowGold,
              offset: Offset(0, _pressed ? 1 : 4),
              blurRadius: 0,
            ),
          ],
        ),
        // Toujours LTR : en AR le "+" doit rester à gauche du nombre.
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add, color: AppColors.ink, size: 20),
              Text(
                widget.addLabel.replaceFirst('+', ''),
                style: const TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
