import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Primary Colors
  static const Color primary = Color(0xFF2563EB); // Website Blue
  static const Color primaryLight = Color(0xFF3B82F6);
  static const Color primaryDark = Color(0xFF1D4ED8);
  static const Color white = Colors.white;
  static const Color iconPrimary = Color(0xFFFFFFFF);

  // Text & Foreground Colors
  static const Color textPrimary = Color(0xFFFFFFFF); // Pure white for better visibility
  static const Color textSecondary = Color(0xFF94A3B8); // Website text-dim
  static const Color textTertiary = Color(0xFF64748B); // Muted text
  static const Color textInverse = Color(0xFF0F172A); // Dark text on light backgrounds

  // Background Colors
  static const Color backgroundPrimary = Color(0xFF0F172A); // Website bg (Dark Blue)
  static const Color backgroundSecondary = Color(0xFF1E293B); // Website card-bg
  static const Color backgroundTertiary = Color(0xFF334155); // Subtle background

  // Surface Colors
  static const Color surfacePrimary = Color(0xFF1E293B); // Using card-bg for surfaces
  static const Color surfaceSecondary = Color(0xFF0F172A);
  static const Color surfaceElevated = Color(0xFF1E293B);

  // Semantic Colors
  static const Color success = Color(0xFF10B981); // Emerald
  static const Color error = Color(0xFFEF4444); // Red
  static const Color warning = Color(0xFFF59E0B); // Website accent (Amber)
  static const Color info = Color(0xFF3B82F6);

  // Border & Divider Colors
  static const Color borderPrimary = Color(0xFF334155);
  static const Color borderSecondary = Color(0xFF1E293B);
  static const Color divider = Color(0xFF334155);

  // Shadow Colors
  static const Color shadowPrimary = Color(0x0A000000);
  static const Color shadowSecondary = Color(0x0F000000);
  static const Color shadowElevated = Color(0x1A000000);

  // Overlay Colors
  static const Color overlayLight = Color(0x0A000000);
  static const Color overlayMedium = Color(0x1A000000);
  static const Color overlayDark = Color(0x4D000000);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primaryLight],
    stops: [0.0, 1.0],
  );

  static const LinearGradient surfaceGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [surfacePrimary, surfaceSecondary],
    stops: [0.0, 1.0],
  );
}
