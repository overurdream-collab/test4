import 'package:flutter/material.dart';

import 'tokens.dart';

abstract final class QTheme {
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: QColors.brightGreen,
          brightness: brightness,
        ).copyWith(
          primary: QColors.brightGreen,
          onPrimary: isDark ? QColors.night : QColors.charcoal,
          primaryContainer: isDark ? const Color(0xFF173D27) : QColors.softMint,
          onPrimaryContainer: isDark ? QColors.lightGreen : QColors.charcoal,
          secondary: QColors.freshGreen,
          onSecondary: QColors.charcoal,
          secondaryContainer: isDark
              ? const Color(0xFF1C3427)
              : QColors.softMint,
          onSecondaryContainer: isDark ? QColors.pureWhite : QColors.charcoal,
          surface: isDark ? QColors.nightSurface : QColors.pearlWhite,
          onSurface: isDark ? QColors.nightText : QColors.charcoal,
          surfaceContainerHighest: isDark
              ? QColors.nightCard
              : QColors.pureWhite,
          onSurfaceVariant: isDark ? QColors.nightMuted : QColors.neutralGray,
          outline: isDark ? const Color(0xFF385044) : const Color(0xFFDDE8E1),
          outlineVariant: isDark
              ? const Color(0xFF243A2E)
              : const Color(0xFFEAF2ED),
          error: isDark ? const Color(0xFFFFB4AB) : QColors.rejectedFg,
          onError: isDark ? const Color(0xFF690005) : QColors.pureWhite,
          errorContainer: QColors.rejectedBg,
          onErrorContainer: QColors.rejectedFg,
        );

    final textTheme = TextTheme(
      displayLarge: _style(40, FontWeight.w700, scheme.onSurface, 1.15),
      displayMedium: _style(32, FontWeight.w700, scheme.onSurface, 1.2),
      headlineLarge: _style(28, FontWeight.w700, scheme.onSurface, 1.25),
      headlineMedium: _style(24, FontWeight.w700, scheme.onSurface, 1.3),
      headlineSmall: _style(20, FontWeight.w600, scheme.onSurface, 1.35),
      titleLarge: _style(18, FontWeight.w600, scheme.onSurface, 1.4),
      titleMedium: _style(16, FontWeight.w600, scheme.onSurface, 1.45),
      titleSmall: _style(14, FontWeight.w600, scheme.onSurface, 1.5),
      bodyLarge: _style(16, FontWeight.w400, scheme.onSurface, 1.65),
      bodyMedium: _style(14, FontWeight.w400, scheme.onSurface, 1.7),
      bodySmall: _style(12, FontWeight.w400, scheme.onSurfaceVariant, 1.6),
      labelLarge: _style(14, FontWeight.w600, scheme.onSurface, 1.4),
      labelMedium: _style(12, FontWeight.w500, scheme.onSurfaceVariant, 1.4),
      labelSmall: _style(11, FontWeight.w500, scheme.onSurfaceVariant, 1.4),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? QColors.night : QColors.pearlWhite,
      fontFamily: 'IBM Plex Sans Arabic',
      visualDensity: VisualDensity.standard,
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? QColors.night : QColors.pearlWhite,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.headlineSmall,
      ),
      cardTheme: CardThemeData(
        color: isDark ? QColors.nightCard : QColors.pureWhite,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(QRadius.lg),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? QColors.nightCard : QColors.pureWhite,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: QSpace.lg,
          vertical: QSpace.md,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(color: QColors.neutralGray),
        labelStyle: textTheme.bodyMedium,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(QRadius.md),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(QRadius.md),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(QRadius.md),
          borderSide: const BorderSide(color: QColors.brightGreen, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(QRadius.md),
          borderSide: BorderSide(color: scheme.error),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: QColors.brightGreen,
          foregroundColor: QColors.charcoal,
          minimumSize: const Size(48, 52),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(QRadius.md),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          minimumSize: const Size(48, 52),
          side: BorderSide(color: scheme.outline),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(QRadius.md),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isDark ? QColors.lightGreen : QColors.brightGreen,
          minimumSize: const Size(48, 48),
          textStyle: textTheme.labelLarge,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? QColors.nightCard : QColors.pureWhite,
        selectedColor: QColors.softMint,
        disabledColor: scheme.outlineVariant,
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: textTheme.labelMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(QRadius.pill),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: QSpace.md,
          vertical: QSpace.sm,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: isDark ? QColors.nightSurface : QColors.pureWhite,
        selectedItemColor: isDark ? QColors.lightGreen : QColors.brightGreen,
        unselectedItemColor: QColors.neutralGray,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? QColors.nightSurface : QColors.pureWhite,
        indicatorColor: isDark ? const Color(0xFF1E4A30) : QColors.softMint,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 72,
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelSmall),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? QColors.nightCard : QColors.charcoal,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: QColors.pureWhite,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(QRadius.md),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? QColors.nightCard : QColors.pureWhite,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(QRadius.lg),
        ),
      ),
      scaffoldBackgroundColor: isDark ? QColors.night : QColors.pearlWhite,
    );
  }

  static TextStyle _style(
    double size,
    FontWeight weight,
    Color color,
    double height,
  ) {
    return TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: 0,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }
}
