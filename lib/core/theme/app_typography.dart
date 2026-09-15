import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Typographie QuizRail.
/// - Titres : Baloo 2 (arrondi, ludique, très lisible en FR/EN/AR fallback).
/// - Texte courant : Nunito (ronde, douce).
/// Tous les écrans héritent via ThemeData, pas de style en dur.
abstract final class AppTypography {
  static TextTheme textTheme(TextTheme base) {
    final display = GoogleFonts.baloo2TextTheme(base);
    final body = GoogleFonts.nunitoTextTheme(base);
    return base.copyWith(
      displayLarge: display.displayLarge?.copyWith(
        fontWeight: FontWeight.w800,
        color: AppColors.cream,
        letterSpacing: -0.5,
      ),
      displayMedium: display.displayMedium?.copyWith(
        fontWeight: FontWeight.w800,
        color: AppColors.cream,
      ),
      displaySmall: display.displaySmall?.copyWith(
        fontWeight: FontWeight.w800,
        color: AppColors.cream,
      ),
      headlineMedium: display.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
        color: AppColors.cream,
      ),
      headlineSmall: display.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        color: AppColors.cream,
      ),
      titleLarge: display.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: AppColors.cream,
      ),
      titleMedium: body.titleMedium?.copyWith(
        fontWeight: FontWeight.w800,
        color: AppColors.cream,
      ),
      titleSmall: body.titleSmall?.copyWith(
        fontWeight: FontWeight.w800,
        color: AppColors.creamDim,
        letterSpacing: 0.6,
      ),
      bodyLarge: body.bodyLarge?.copyWith(
        color: AppColors.cream,
        fontWeight: FontWeight.w600,
      ),
      bodyMedium: body.bodyMedium?.copyWith(color: AppColors.creamDim),
      bodySmall: body.bodySmall?.copyWith(color: AppColors.creamDim),
      labelLarge: body.labelLarge?.copyWith(fontWeight: FontWeight.w800),
    );
  }

  /// Titre hero avec contour cartoon (stroke peint dans les widgets).
  static TextStyle hero({double size = 40}) => GoogleFonts.baloo2(
        fontSize: size,
        fontWeight: FontWeight.w800,
        color: AppColors.cream,
        height: 1.0,
        letterSpacing: -0.5,
      );

  static TextStyle heroAccent({double size = 40}) => GoogleFonts.baloo2(
        fontSize: size,
        fontWeight: FontWeight.w800,
        color: AppColors.sun,
        height: 1.0,
      );

  static TextStyle tokenCount({double size = 34}) => GoogleFonts.baloo2(
        fontSize: size,
        fontWeight: FontWeight.w800,
        color: AppColors.cream,
        height: 1.0,
      );
}
