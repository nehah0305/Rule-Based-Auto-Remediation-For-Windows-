import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Windows 11 Fluent Design Colors
  static const Color bgDeep       = Color(0xFF0D0D0D);
  static const Color bgCard       = Color(0xFF1A1A1A);
  static const Color bgCardAlt    = Color(0xFF2A2A2A);
  static const Color accent       = Color(0xFF0078D4);
  static const Color accentGreen  = Color(0xFF107C10);
  static const Color accentPurple = Color(0xFF8661C5);
  static const Color accentOrange = Color(0xFFF25022);
  static const Color accentRed    = Color(0xFFE74856);
  static const Color accentYellow = Color(0xFFFFC107);
  static const Color border       = Color(0xFF3A3A3A);
  static const Color textPrimary  = Color(0xFFF5F5F5);
  static const Color textMuted    = Color(0xFFB4B4B4);
  static const Color textDimmed   = Color(0xFF808080);
  static const Color textSecondary = textMuted;
  static const Color bgInput      = Color(0xFF1F1F1F);

  static const LinearGradient appBackground = LinearGradient(
    colors: [Color(0xFF0D0D0D), Color(0xFF1A1A1A), Color(0xFF0F0F0F)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient panelGradient = LinearGradient(
    colors: [Color(0xFF1F1F1F), Color(0xFF1A1A1A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient gradientPrimary = LinearGradient(
    colors: [Color(0xFF0078D4), Color(0xFF0063B1)],
    begin: Alignment.topLeft, end: Alignment.bottomRight,
  );
  
  static const LinearGradient gradientSuccess = LinearGradient(
    colors: [Color(0xFF107C10), Color(0xFF0B5F0B)],
    begin: Alignment.topLeft, end: Alignment.bottomRight,
  );
  
  static const LinearGradient gradientDanger = LinearGradient(
    colors: [Color(0xFFE74856), Color(0xFFC50F1F)],
    begin: Alignment.topLeft, end: Alignment.bottomRight,
  );
  
  static const LinearGradient gradientWarning = LinearGradient(
    colors: [Color(0xFFFFC107), Color(0xFFFFB81C)],
    begin: Alignment.topLeft, end: Alignment.bottomRight,
  );
  
  static const LinearGradient gradientPurple = LinearGradient(
    colors: [Color(0xFF8661C5), Color(0xFF6B46A8)],
    begin: Alignment.topLeft, end: Alignment.bottomRight,
  );
  
  static const LinearGradient gradientInfo = LinearGradient(
    colors: [Color(0xFF0078D4), Color(0xFF005A9E)],
    begin: Alignment.topLeft, end: Alignment.bottomRight,
  );
  
  static const LinearGradient gradientAccent = gradientPrimary;
  
  static const LinearGradient gradientSecondary = LinearGradient(
    colors: [Color(0xFF3A3A3A), Color(0xFF2A2A2A)],
    begin: Alignment.topLeft, end: Alignment.bottomRight,
  );
  
  static const LinearGradient gradientHighCpu = LinearGradient(
    colors: [Color(0xFFE74856), Color(0xFFC50F1F)],
    begin: Alignment.topLeft, end: Alignment.bottomRight,
  );

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bgDeep,
    colorScheme: const ColorScheme.dark(
      primary: accent,
      secondary: accentGreen,
      surface: bgCard,
      error: accentRed,
    ),
    textTheme: GoogleFonts.latoTextTheme(ThemeData.dark().textTheme).apply(
      bodyColor: textPrimary,
      displayColor: textPrimary,
    ),
    cardTheme: CardThemeData(
      color: bgCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: border, width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: bgInput,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: border, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: border, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: accent, width: 2),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
  );
}
