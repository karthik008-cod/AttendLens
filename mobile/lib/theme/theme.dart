import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AttendLensTheme {
  // Brand Colors
  static const Color backgroundDark = Color(0xFF0B0F19);
  static const Color surfaceDark = Color(0xFF151B2B);
  static const Color cardDark = Color(0xFF1E2638);
  
  static const Color primaryIndigo = Color(0xFF6366F1);
  static const Color primaryPurple = Color(0xFF8B5CF6);
  static const Color accentCyan = Color(0xFF06B6D4);
  
  static const Color statusPresent = Color(0xFF10B981); // Emerald
  static const Color statusAbsent = Color(0xFFF43F5E);  // Rose / Coral
  static const Color statusLate = Color(0xFFF59E0B);    // Amber
  
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: backgroundDark,
      primaryColor: primaryIndigo,
      colorScheme: const ColorScheme.dark(
        primary: primaryIndigo,
        secondary: primaryPurple,
        surface: surfaceDark,
        error: statusAbsent,
      ),
      textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme).copyWith(
        displayLarge: GoogleFonts.outfit(color: textPrimary, fontWeight: FontWeight.bold, fontSize: 32),
        titleLarge: GoogleFonts.outfit(color: textPrimary, fontWeight: FontWeight.w600, fontSize: 22),
        bodyLarge: GoogleFonts.outfit(color: textPrimary, fontSize: 16),
        bodyMedium: GoogleFonts.outfit(color: textSecondary, fontSize: 14),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: backgroundDark.withOpacity(0.8),
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.outfit(color: textPrimary, fontSize: 22, fontWeight: FontWeight.bold),
        iconTheme: const IconThemeData(color: textPrimary),
      ),
      cardTheme: CardThemeData(
        color: surfaceDark,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withOpacity(0.08), width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryIndigo,
          foregroundColor: Colors.white,
          elevation: 6,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  // Glassmorphism Box Decoration helper
  static BoxDecoration get glassDecoration => BoxDecoration(
    color: surfaceDark.withOpacity(0.7),
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.3),
        blurRadius: 16,
        offset: const Offset(0, 8),
      ),
    ],
  );

  static BoxDecoration get gradientButtonDecoration => BoxDecoration(
    gradient: const LinearGradient(
      colors: [primaryIndigo, primaryPurple],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    borderRadius: BorderRadius.circular(16),
    boxShadow: [
      BoxShadow(
        color: primaryIndigo.withOpacity(0.4),
        blurRadius: 12,
        offset: const Offset(0, 6),
      ),
    ],
  );
}
