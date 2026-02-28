import 'package:flutter/material.dart';

class AppRadius {
  AppRadius._();

  // Numerical Radii
  static const double none = 0.0;
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double pill = 999.0;

  // Legacy variables for mapping to AppTheme/AppLayout exactly
  static const double radiusNone = 0.0;
  static const double radiusSmall = 4.0;
  static const double radiusMedium = 8.0;
  static const double radiusLarge = 12.0;
  static const double radiusXLarge = 16.0;
  static const double radiusXXLarge = 24.0;
  static const double radiusFull = 9999.0;

  static const double radiusXS = 4.0;
  static const double radiusSM = 8.0;
  static const double radiusMD = 12.0;
  static const double radiusLG = 16.0;
  static const double radiusXL = 24.0;
  static const double radiusPill = 999.0;

  // Pre-defined BorderRadius objects for instant usage
  static final BorderRadius borderRadiusXS = BorderRadius.circular(xs);
  static final BorderRadius borderRadiusSM = BorderRadius.circular(sm);
  static final BorderRadius borderRadiusMD = BorderRadius.circular(md);
  static final BorderRadius borderRadiusLG = BorderRadius.circular(lg);
  static final BorderRadius borderRadiusXL = BorderRadius.circular(xl);
  static final BorderRadius borderRadiusPill = BorderRadius.circular(pill);
}
