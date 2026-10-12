import 'package:flutter/material.dart';

/// ZipClip design system. Dark theme only. Values come straight from the
/// product mockup; do not "improve" them without a design review.
abstract final class ZipColors {
  static const Color background = Color(0xFF0B1020);
  static const Color surface = Color(0xFF141B31);
  static const Color surfaceRaised = Color(0xFF1C2542);
  static const Color line = Color(0xFF263057);
  static const Color text = Color(0xFFF2F4FF);
  static const Color muted = Color(0xFF98A2C8);
  static const Color accent = Color(0xFF6C4DFF);
  static const Color accentDim = Color(0xFF4A37B8);
  static const Color mint = Color(0xFF2DE2B0);
  static const Color warning = Color(0xFFFFB020);
  static const Color danger = Color(0xFFFF5C7A);
}

abstract final class ZipFonts {
  static const String heading = 'Sora';
  static const String ui = 'DMSans';
  static const String mono = 'IBMPlexMono';
}

abstract final class ZipRadii {
  static const double pill = 26;
  static const double card = 20;
  static const double sheet = 24;
}

abstract final class ZipTheme {
  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: ZipColors.background,
      colorScheme: const ColorScheme.dark(
        primary: ZipColors.accent,
        secondary: ZipColors.mint,
        surface: ZipColors.surface,
        surfaceContainerHighest: ZipColors.surfaceRaised,
        error: ZipColors.danger,
        onSurface: ZipColors.text,
      ),
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          fontFamily: ZipFonts.heading,
          fontWeight: FontWeight.w800,
          fontSize: 30,
          height: 1.15,
          color: ZipColors.text,
        ),
        headlineSmall: TextStyle(
          fontFamily: ZipFonts.heading,
          fontWeight: FontWeight.w700,
          fontSize: 22,
          height: 1.25,
          color: ZipColors.text,
        ),
        titleLarge: TextStyle(
          fontFamily: ZipFonts.heading,
          fontWeight: FontWeight.w700,
          fontSize: 18,
          height: 1.3,
          color: ZipColors.text,
        ),
        titleMedium: TextStyle(
          fontFamily: ZipFonts.ui,
          fontWeight: FontWeight.w600,
          fontSize: 16,
          height: 1.35,
          color: ZipColors.text,
        ),
        bodyLarge: TextStyle(
          fontFamily: ZipFonts.ui,
          fontWeight: FontWeight.w500,
          fontSize: 15,
          height: 1.45,
          color: ZipColors.text,
        ),
        bodyMedium: TextStyle(
          fontFamily: ZipFonts.ui,
          fontWeight: FontWeight.w500,
          fontSize: 14,
          height: 1.45,
          color: ZipColors.muted,
        ),
        bodySmall: TextStyle(
          fontFamily: ZipFonts.ui,
          fontWeight: FontWeight.w500,
          fontSize: 12.5,
          height: 1.45,
          color: ZipColors.muted,
        ),
        labelLarge: TextStyle(
          fontFamily: ZipFonts.ui,
          fontWeight: FontWeight.w700,
          fontSize: 14,
          color: ZipColors.text,
        ),
      ),
      cardTheme: CardThemeData(
        color: ZipColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZipRadii.card),
          side: const BorderSide(color: ZipColors.line, width: 1),
        ),
        margin: EdgeInsets.zero,
        elevation: 0,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Colors.white
              : ZipColors.muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? ZipColors.mint
              : ZipColors.surfaceRaised,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      dividerColor: ZipColors.line,
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: ZipColors.surfaceRaised,
        contentTextStyle: TextStyle(
          fontFamily: ZipFonts.ui,
          color: ZipColors.text,
          fontSize: 14,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: ZipColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZipRadii.sheet),
          side: const BorderSide(color: ZipColors.line),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: ZipColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(ZipRadii.sheet),
          ),
        ),
      ),
    );
  }

  /// Monospace style for links, sizes, speeds and timestamps.
  static TextStyle mono({
    double size = 13,
    FontWeight weight = FontWeight.w500,
    Color color = ZipColors.text,
  }) =>
      TextStyle(
        fontFamily: ZipFonts.mono,
        fontWeight: weight,
        fontSize: size,
        color: color,
        height: 1.4,
      );

  /// Small uppercase section label, e.g. "SAVE AS".
  static const TextStyle sectionLabel = TextStyle(
    fontFamily: ZipFonts.ui,
    fontWeight: FontWeight.w700,
    fontSize: 12,
    letterSpacing: 1.6,
    color: ZipColors.muted,
  );
}
