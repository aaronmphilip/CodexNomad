import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const _purple = Color(0xFF8B5CF6);
  static const _purpleSoft = Color(0xFFD8B4FE);
  static const _black = Color(0xFF03020A);
  static const _panel = Color(0xFF0C0715);
  static const _panelHigh = Color(0xFF171023);
  static const _outline = Color(0xFF3A2854);

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
      primaryContainer: const Color(0xFF392066),
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
      _compactTextTheme(
        GoogleFonts.bricolageGrotesqueTextTheme(baseTextTheme),
      ),
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
        color: _panelHigh.withValues(alpha: 0.90),
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
          backgroundColor: _purple.withValues(alpha: 0.50),
          foregroundColor: Colors.white,
          disabledBackgroundColor: _purple.withValues(alpha: 0.16),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.38),
          side: BorderSide(color: _purpleSoft.withValues(alpha: 0.26)),
          shape: const StadiumBorder(),
          minimumSize: const Size(48, 52),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _purpleSoft,
          side: const BorderSide(color: _outline),
          shape: const StadiumBorder(),
          minimumSize: const Size(48, 52),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _panel,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(26),
          borderSide: BorderSide.none,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: const CircleBorder(),
          backgroundColor: _purple.withValues(alpha: 0.10),
          foregroundColor: _purpleSoft,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return _purple.withValues(alpha: 0.50);
            }
            return _panelHigh.withValues(alpha: 0.64);
          }),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          side: WidgetStatePropertyAll(
            BorderSide(color: _purple.withValues(alpha: 0.30)),
          ),
          shape: const WidgetStatePropertyAll(StadiumBorder()),
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

  static TextTheme _compactTextTheme(TextTheme theme) {
    TextStyle? compact(TextStyle? style) {
      final size = style?.fontSize;
      if (style == null || size == null) return style;
      return style.copyWith(fontSize: size * 0.94);
    }

    return theme.copyWith(
      displayLarge: compact(theme.displayLarge),
      displayMedium: compact(theme.displayMedium),
      displaySmall: compact(theme.displaySmall),
      headlineLarge: compact(theme.headlineLarge),
      headlineMedium: compact(theme.headlineMedium),
      headlineSmall: compact(theme.headlineSmall),
      titleLarge: compact(theme.titleLarge),
      titleMedium: compact(theme.titleMedium),
      titleSmall: compact(theme.titleSmall),
      bodyLarge: compact(theme.bodyLarge),
      bodyMedium: compact(theme.bodyMedium),
      bodySmall: compact(theme.bodySmall),
      labelLarge: compact(theme.labelLarge),
      labelMedium: compact(theme.labelMedium),
      labelSmall: compact(theme.labelSmall),
    );
  }
}
