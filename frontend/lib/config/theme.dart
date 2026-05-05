import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Brand colours  
  static const Color bgDeep       = Color(0xFF0a0a1a);
  static const Color bgCard       = Color(0xFF12122a);
  static const Color bgCardAlt    = Color(0xFF1a1a38);
  static const Color accent       = Color(0xFF4a9eff);
  static const Color accentGreen  = Color(0xFF20c997);
  static const Color accentPurple = Color(0xFF9d4edd);
  static const Color accentOrange = Color(0xFFfc913a);
  static const Color accentRed    = Color(0xFFff4e50);
  static const Color accentYellow = Color(0xFFf9d423);
  static const Color border       = Color(0xFF2a2a4a);
  static const Color textPrimary  = Color(0xFFe8e8ff);
  static const Color textMuted    = Color(0xFF8888aa);
  static const Color textDimmed   = Color(0xFF555577);
  static const Color textSecondary = textMuted;
  static const Color bgInput = bgCardAlt;

  // Gradient helpers
  static const LinearGradient gradientPrimary = LinearGradient(
    colors: [Color(0xFF4a9eff), Color(0xFF1a6fd4)],
    begin: Alignment.topLeft, end: Alignment.bottomRight,
  );
  static const LinearGradient gradientSuccess = LinearGradient(
    colors: [Color(0xFF20c997), Color(0xFF0d8c6a)],
    begin: Alignment.topLeft, end: Alignment.bottomRight,
  );
  static const LinearGradient gradientDanger = LinearGradient(
    colors: [Color(0xFFff4e50), Color(0xFFc0392b)],
    begin: Alignment.topLeft, end: Alignment.bottomRight,
  );
  static const LinearGradient gradientWarning = LinearGradient(
    colors: [Color(0xFFf9d423), Color(0xFFfc913a)],
    begin: Alignment.topLeft, end: Alignment.bottomRight,
  );
  static const LinearGradient gradientPurple = LinearGradient(
    colors: [Color(0xFF9d4edd), Color(0xFF6420a0)],
    begin: Alignment.topLeft, end: Alignment.bottomRight,
  );
  static const LinearGradient gradientInfo = LinearGradient(
    colors: [Color(0xFF4a9eff), Color(0xFF0077cc)],
    begin: Alignment.topLeft, end: Alignment.bottomRight,
  );
  static const LinearGradient gradientAccent = gradientPrimary;
  static const LinearGradient gradientSecondary = LinearGradient(
    colors: [Color(0xFF6c757d), Color(0xFF495057)],
    begin: Alignment.topLeft, end: Alignment.bottomRight,
  );
  static const LinearGradient gradientHighCpu = LinearGradient(
    colors: [Color(0xFFff4e50), Color(0xFFfc913a)],
    begin: Alignment.topLeft, end: Alignment.bottomRight,
  );

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bgDeep,
    colorScheme: const ColorScheme.dark(
      primary:   accent,
      secondary: accentGreen,
      surface:   bgCard,
      error:     accentRed,
    ),
    textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).apply(
      bodyColor:    textPrimary,
      displayColor: textPrimary,
    ),
    cardTheme: CardThemeData(
      color: bgCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: border, width: 1),
      ),
    ),
    dividerColor: border,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: bgCardAlt,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: accent, width: 1.5),
      ),
      labelStyle: const TextStyle(color: textMuted),
      hintStyle: const TextStyle(color: textDimmed),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
    ),
    checkboxTheme: const CheckboxThemeData(
      checkColor: WidgetStatePropertyAll(Colors.white),
      fillColor: WidgetStatePropertyAll(accent),
    ),
    switchTheme: const SwitchThemeData(
      thumbColor: WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStatePropertyAll(accent),
    ),
    scrollbarTheme: const ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(border),
      trackColor: WidgetStatePropertyAll(bgCardAlt),
      radius: Radius.circular(6),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: border),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: bgCardAlt,
      contentTextStyle: TextStyle(color: textPrimary),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: border),
      ),
    ),
  );
}
