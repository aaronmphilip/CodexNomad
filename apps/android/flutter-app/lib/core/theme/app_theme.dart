import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const _purple = Color(0xFFA855F7);
  static const _purpleSoft = Color(0xFFC4B5FD);
  static const _black = Color(0xFF05030A);
  static const _panel = Color(0xFF100B18);
  static const _panelHigh = Color(0xFF191124);
  static const _outline = Color(0xFF35264A);

  static ThemeData light() {
    return dark();
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _purple,
      brightness: Brightness.dark,
    ).copyWith(
      primary: _purple,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFF3A176A),
      onPrimaryContainer: const Color(0xFFF4E9FF),
      secondary: _purpleSoft,
      onSecondary: _black,
      surface: _black,
      onSurface: const Color(0xFFF7F2FF),
      surfaceContainerHighest: _panelHigh,
      outline: _outline,
      outlineVariant: const Color(0xFF241832),
      error: const Color(0xFFFF5F7A),
    );
    return _theme(scheme);
  }

  static ThemeData _theme(ColorScheme scheme) {
    final baseTextTheme = scheme.brightness == Brightness.dark
        ? Typography.material2021(platform: TargetPlatform.android).white
        : Typography.material2021(platform: TargetPlatform.android).black;
    final textTheme = _zeroLetterSpacing(
      GoogleFonts.bricolageGrotesqueTextTheme(baseTextTheme),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: _panelHigh.withValues(alpha: 0.86),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _panel,
        indicatorColor: _purple.withValues(alpha: 0.22),
        labelTextStyle: WidgetStatePropertyAll(
          textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? _purpleSoft : scheme.onSurfaceVariant,
            size: 23,
          );
        }),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: _purple,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _purple,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          minimumSize: const Size(48, 48),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _purpleSoft,
          side: const BorderSide(color: _outline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          minimumSize: const Size(48, 48),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _panel,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  static TextTheme _zeroLetterSpacing(TextTheme theme) {
    return theme.copyWith(
      displayLarge: theme.displayLarge?.copyWith(letterSpacing: 0),
      displayMedium: theme.displayMedium?.copyWith(letterSpacing: 0),
      displaySmall: theme.displaySmall?.copyWith(letterSpacing: 0),
      headlineLarge: theme.headlineLarge?.copyWith(letterSpacing: 0),
      headlineMedium: theme.headlineMedium?.copyWith(letterSpacing: 0),
      headlineSmall: theme.headlineSmall?.copyWith(letterSpacing: 0),
      titleLarge: theme.titleLarge?.copyWith(letterSpacing: 0),
      titleMedium: theme.titleMedium?.copyWith(letterSpacing: 0),
      titleSmall: theme.titleSmall?.copyWith(letterSpacing: 0),
      bodyLarge: theme.bodyLarge?.copyWith(letterSpacing: 0),
      bodyMedium: theme.bodyMedium?.copyWith(letterSpacing: 0),
      bodySmall: theme.bodySmall?.copyWith(letterSpacing: 0),
      labelLarge: theme.labelLarge?.copyWith(letterSpacing: 0),
      labelMedium: theme.labelMedium?.copyWith(letterSpacing: 0),
      labelSmall: theme.labelSmall?.copyWith(letterSpacing: 0),
    );
  }
}
