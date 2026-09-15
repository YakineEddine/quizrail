import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Bouton jeu avec relief 3D cartoon : dégradé + ombre portée basse.
/// S'écrase légèrement au toucher (effet arcade).
enum GameButtonVariant { play, secondary, gold }

class GameButton extends StatefulWidget {
  const GameButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = GameButtonVariant.play,
    this.icon,
    this.height = 60,
    this.fontSize = 20,
    this.expanded = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final GameButtonVariant variant;
  final IconData? icon;
  final double height;
  final double fontSize;
  final bool expanded;

  @override
  State<GameButton> createState() => _GameButtonState();
}

class _GameButtonState extends State<GameButton> {
  bool _pressed = false;

  LinearGradient get _gradient => switch (widget.variant) {
        GameButtonVariant.play => AppColors.playGradient,
        GameButtonVariant.secondary => AppColors.secondaryGradient,
        GameButtonVariant.gold => AppColors.goldGradient,
      };

  Color get _shadow => switch (widget.variant) {
        GameButtonVariant.play => AppColors.shadowPlay,
        GameButtonVariant.secondary => AppColors.shadowSecondary,
        GameButtonVariant.gold => AppColors.shadowGold,
      };

  Color get _foreground => switch (widget.variant) {
        GameButtonVariant.gold => AppColors.ink,
        _ => AppColors.cream,
      };

  @override
  Widget build(BuildContext context) {
    final shadowH = _pressed ? 2.0 : 6.0;
    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      transform: Matrix4.translationValues(0, _pressed ? 4 : 0, 0),
      height: widget.height,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        gradient: _gradient,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.ink.withValues(alpha: 0.35), width: 2),
        boxShadow: [
          BoxShadow(
            color: _shadow,
            offset: Offset(0, shadowH),
            blurRadius: 0,
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.25),
            offset: const Offset(0, 2),
            blurRadius: 0,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: widget.expanded ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.icon != null) ...[
            Icon(widget.icon, color: _foreground, size: 24),
            const SizedBox(width: 10),
          ],
          Text(
            widget.label,
            style: TextStyle(
              color: _foreground,
              fontSize: widget.fontSize,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onPressed?.call();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: Semantics(
        button: true,
        label: widget.label,
        child: widget.expanded
            ? SizedBox(width: double.infinity, child: child)
            : child,
      ),
    );
  }
}
