import 'package:flutter/material.dart';

import 'brand_colors.dart';

abstract final class AppColors {
  static const primary = BrandColors.primary;
  static const headerStart = BrandColors.primary;
  static const headerEnd = BrandColors.primaryLight;
  static const background = Color(0xFFF6F8FB);
  static const heading = BrandColors.primary;
  static const body = Color(0xFF5E687A);
  static const success = BrandColors.success;
  static const warning = BrandColors.warning;
}

abstract final class AppTheme {
  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme.copyWith(primary: AppColors.primary),
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: 'Roboto',
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          color: AppColors.heading,
          fontSize: 24,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: TextStyle(
          color: AppColors.heading,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: TextStyle(
          color: AppColors.heading,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: TextStyle(color: AppColors.body, fontSize: 15),
        bodyMedium: TextStyle(color: AppColors.body, fontSize: 13),
      ),
    );
  }
}
