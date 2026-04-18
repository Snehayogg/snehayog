import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class AppRadius {
  AppRadius._();

  // Numerical Radii - Responsive via .r
  static double get none => 0.0;
  static double get xs => 4.0.r;
  static double get sm => 8.0.r;
  static double get md => 12.0.r;
  static double get lg => 16.0.r;
  static double get xl => 24.0.r;
  static double get card => 12.0.r; // Apple TV style unified radius
  static double get pill => 999.0.r;

  // Legacy variables for mapping to AppTheme/AppLayout exactly - Responsive via .r
  static double get radiusNone => 0.0;
  static double get radiusSmall => 4.0.r;
  static double get radiusMedium => 8.0.r;
  static double get radiusLarge => 12.0.r;
  static double get radiusXLarge => 16.0.r;
  static double get radiusXXLarge => 24.0.r;
  static double get radiusFull => 9999.0.r;

  static double get radiusXS => 4.0.r;
  static double get radiusSM => 8.0.r;
  static double get radiusMD => 12.0.r;
  static double get radiusLG => 16.0.r;
  static double get radiusXL => 24.0.r;
  static double get radiusPill => 999.0.r;

  // Pre-defined BorderRadius objects for instant usage - Dynamic getters
  static BorderRadius get borderRadiusXS => BorderRadius.circular(xs);
  static BorderRadius get borderRadiusSM => BorderRadius.circular(sm);
  static BorderRadius get borderRadiusMD => BorderRadius.circular(md);
  static BorderRadius get borderRadiusLG => BorderRadius.circular(lg);
  static BorderRadius get borderRadiusXL => BorderRadius.circular(xl);
  static BorderRadius get borderRadiusCard => BorderRadius.circular(card);
  static BorderRadius get borderRadiusPill => BorderRadius.circular(pill);
}
