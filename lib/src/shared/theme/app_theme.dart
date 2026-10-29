import 'package:flutter/material.dart';

/// Central light/dark theme definitions. A calm, restrained steel-blue seed
/// reads as "secure/private" rather than the default Material purple, and
/// keeping both brightnesses derived from the same seed keeps them visually
/// paired instead of independently drifting over time.
class AppTheme {
  const AppTheme._();

  static const Color _seed = Color(0xFF2F6690);

  static ThemeData get light => _themeFrom(Brightness.light);

  static ThemeData get dark => _themeFrom(Brightness.dark);

  static ThemeData _themeFrom(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: colorScheme.surfaceTint,
        elevation: 0,
        scrolledUnderElevation: 2,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.secondaryContainer,
        labelStyle: TextStyle(color: colorScheme.onSecondaryContainer),
        side: BorderSide.none,
      ),
    );
  }
}
