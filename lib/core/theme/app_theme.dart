import 'package:flutter/material.dart';

abstract final class AppColors {
  static const primary = Color(0xFF5064D8);
  static const headerStart = Color(0xFF4F63D7);
  static const headerEnd = Color(0xFF58B5CD);
  static const background = Color(0xFFF6F8FB);
  static const heading = Color(0xFF13213A);
  static const body = Color(0xFF5E687A);
  static const success = Color(0xFF2FA36B);
  static const warning = Color(0xFFE56B6F);
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
