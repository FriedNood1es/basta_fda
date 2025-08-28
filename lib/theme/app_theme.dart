import 'package:flutter/material.dart';

class AppTheme {
  static const double radius = 14;

  static ThemeData light() {
    final color = Colors.blue;
    final scheme = ColorScheme.fromSeed(seedColor: color);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: Typography.blackMountainView,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          // Avoid infinite width in unconstrained Rows; only enforce height
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
      chipTheme: ChipThemeData(
        shape: StadiumBorder(side: BorderSide(color: scheme.outlineVariant)),
        selectedColor: scheme.primaryContainer,
        backgroundColor: scheme.surfaceVariant,
        labelStyle: TextStyle(color: scheme.onSurface),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
    );
  }
}
