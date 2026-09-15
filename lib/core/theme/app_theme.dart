import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';

/// ThemeData centralisé QuizRail.
/// Tous les écrans Phase 1+ héritent automatiquement via MaterialApp.theme.
/// Palette sombre énergique, jamais de blanc/gris par défaut.
abstract final class AppTheme {
  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    final texts = AppTypography.textTheme(base.textTheme);

    final scheme = const ColorScheme.dark(
      brightness: Brightness.dark,
      primary: AppColors.pinkPop,
      onPrimary: AppColors.cream,
      secondary: AppColors.violetPop,
      onSecondary: AppColors.cream,
      tertiary: AppColors.sun,
      onTertiary: AppColors.ink,
      surface: AppColors.midnight,
      onSurface: AppColors.cream,
      surfaceContainerHighest: AppColors.midnightLight,
      error: AppColors.orangePop,
      onError: AppColors.cream,
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.deepSpace,
      canvasColor: AppColors.deepSpace,
      textTheme: texts,
      primaryTextTheme: texts,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        foregroundColor: AppColors.cream,
      ),
      cardTheme: CardThemeData(
        color: AppColors.midnight.withValues(alpha: 0.85),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: AppColors.midnightLight, width: 1.5),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.sun;
            }
            return AppColors.midnightLight.withValues(alpha: 0.6);
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.ink;
            }
            return AppColors.cream;
          }),
          side: const WidgetStatePropertyAll(
            BorderSide(color: AppColors.midnightLight, width: 1.5),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.pinkPop,
          foregroundColor: AppColors.cream,
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.midnightLight,
        contentTextStyle: texts.bodyMedium?.copyWith(color: AppColors.cream),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
