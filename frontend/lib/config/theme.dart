import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Brand colours  
  static const Color bgDeep       = Color(0xFF070B18);
  static const Color bgCard       = Color(0xFF11182A);
  static const Color bgCardAlt    = Color(0xFF18203A);
  static const Color accent       = Color(0xFF5AA7FF);
  static const Color accentGreen  = Color(0xFF24D0A3);
  static const Color accentPurple = Color(0xFFAA6CFF);
  static const Color accentOrange = Color(0xFFFFA24A);
  static const Color accentRed    = Color(0xFFFF6672);
  static const Color accentYellow = Color(0xFFF7D35B);
  static const Color border       = Color(0xFF27324B);
  static const Color textPrimary  = Color(0xFFF3F6FF);
  static const Color textMuted    = Color(0xFF9CA7C2);
  static const Color textDimmed   = Color(0xFF66708C);
  static const Color textSecondary = textMuted;
  static const Color bgInput = bgCardAlt;

  static const LinearGradient appBackground = LinearGradient(
    colors: [Color(0xFF050816), Color(0xFF090F22), Color(0xFF0D1430)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient panelGradient = LinearGradient(
    colors: [Color(0xFF10182A), Color(0xFF0E1324)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

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
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: border, width: 1),
      ),
    ),
    dividerColor: border,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: bgCardAlt,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
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
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: textPrimary,
        side: const BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: bgCardAlt,
      disabledColor: bgCardAlt,
      selectedColor: accent.withValues(alpha: 0.22),
      secondarySelectedColor: accent.withValues(alpha: 0.22),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      labelStyle: const TextStyle(color: textPrimary, fontSize: 11),
      secondaryLabelStyle: const TextStyle(color: textPrimary, fontSize: 11),
      brightness: Brightness.dark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: const BorderSide(color: border),
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
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: border),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: bgCardAlt,
      contentTextStyle: const TextStyle(color: textPrimary, fontWeight: FontWeight.w500),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: border)),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actionTextColor: accent,
      showCloseIcon: true,
      closeIconColor: textMuted,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: const Color(0xFF0E1527),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      textStyle: const TextStyle(color: textPrimary, fontSize: 11),
      waitDuration: const Duration(milliseconds: 300),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: border),
      ),
    ),
    dataTableTheme: DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(Colors.white.withValues(alpha: 0.03)),
      dataRowColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered)) {
          return accent.withValues(alpha: 0.05);
        }
        return Colors.transparent;
      }),
      headingTextStyle: const TextStyle(color: textMuted, fontSize: 12, fontWeight: FontWeight.w600),
      dataTextStyle: const TextStyle(color: textPrimary, fontSize: 12),
      dividerThickness: 0.3,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}
