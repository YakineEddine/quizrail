import 'package:flutter/material.dart';

/// Tokens de couleur QuizRail — palette jeu, énergique, fond sombre.
/// Utilisés par [AppTheme] et tous les widgets custom.
/// Ne pas utiliser de blanc/gris Material par défaut dans les écrans :
/// passer systématiquement par ces tokens.
abstract final class AppColors {
  // Fonds
  static const deepSpace = Color(0xFF14102E); // fond principal nuit violette
  static const midnight = Color(0xFF241B4D); // surface / carte sombre
  static const midnightLight = Color(0xFF322665); // carte hover / bordure
  static const ink = Color(0xFF0D0A26); // ombres, contours cartoon

  // Accents vifs
  static const violetPop = Color(0xFF7C4DFF);
  static const pinkPop = Color(0xFFFF4D8D);
  static const orangePop = Color(0xFFFF6B35);
  static const skyPop = Color(0xFF40C4FF);
  static const mintPop = Color(0xFF2EE6A8);

  // Doré jetons
  static const sun = Color(0xFFFFC93C);
  static const sunDeep = Color(0xFFE8A100);
  static const sunSoft = Color(0xFFFFE29A);

  // Textes
  static const cream = Color(0xFFFFF6E9);
  static const creamDim = Color(0xFFCFC3EC);

  // Dégradés centralisés
  static const backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF1B1440),
      deepSpace,
      Color(0xFF2A1656),
    ],
    stops: [0.0, 0.55, 1.0],
  );

  static const heroGlowPink = Color(0x66FF4D8D);
  static const heroGlowViolet = Color(0x667C4DFF);
  static const heroGlowSun = Color(0x55FFC93C);

  static const playGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [pinkPop, orangePop],
  );

  static const secondaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [violetPop, skyPop],
  );

  static const goldGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [sunSoft, sun, sunDeep],
  );

  static const railGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF7CD4FF), skyPop, Color(0xFF1D86C9)],
  );

  // Ombres / reliefs cartoon
  static const shadowPlay = Color(0xFF9E2148); // sous le bouton Jouer
  static const shadowSecondary = Color(0xFF3A2396); // sous bouton secondaire
  static const shadowGold = Color(0xFF8A5B00);

  static List<BoxShadow> glow(Color color, {double blur = 24}) => [
        BoxShadow(
          color: color.withValues(alpha: 0.45),
          blurRadius: blur,
          spreadRadius: 1,
        ),
      ];
}
