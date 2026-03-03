import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class AppSpacing {
  AppSpacing._();

  // Base spacing unit: 8px
  static const double _baseUnit = 8.0;

  // Numerical Margins / Paddings - Responsive via .r
  static double get spacing0 => 0.0;
  static double get spacing1 => (_baseUnit * 0.5).r; // 4.0
  static double get spacing2 => (_baseUnit * 1.0).r; // 8.0
  static double get spacing3 => (_baseUnit * 1.5).r; // 12.0
  static double get spacing4 => (_baseUnit * 2.0).r; // 16.0
  static double get spacing5 => (_baseUnit * 2.5).r; // 20.0
  static double get spacing6 => (_baseUnit * 3.0).r; // 24.0
  static double get spacing8 => (_baseUnit * 4.0).r; // 32.0
  static double get spacing10 => (_baseUnit * 5.0).r; // 40.0
  static double get spacing12 => (_baseUnit * 6.0).r; // 48.0
  static double get spacing16 => (_baseUnit * 8.0).r; // 64.0
  static double get spacing20 => (_baseUnit * 10.0).r; // 80.0
  static double get spacing24 => (_baseUnit * 12.0).r; // 96.0

  // Standard EdgeInsets Helpers - Dynamic getters
  static EdgeInsets get edgeInsetsAll4 => EdgeInsets.all(spacing1);
  static EdgeInsets get edgeInsetsAll8 => EdgeInsets.all(spacing2);
  static EdgeInsets get edgeInsetsAll12 => EdgeInsets.all(spacing3);
  static EdgeInsets get edgeInsetsAll16 => EdgeInsets.all(spacing4);
  static EdgeInsets get edgeInsetsAll24 => EdgeInsets.all(spacing6);

  // AppLayout legacy variables for backward compatibility during transition
  static double get space4 => 4.0.r;
  static double get space8 => 8.0.r;
  static double get space12 => 12.0.r;
  static double get space16 => 16.0.r;
  static double get space24 => 24.0.r;
  static double get space32 => 32.0.r;
  static double get space48 => 48.0.r;
  static double get space64 => 64.0.r;

  // Pre-defined SizedBoxes for vertical spacing - Dynamic getters
  static SizedBox get vSpace4 => SizedBox(height: space4);
  static SizedBox get vSpace8 => SizedBox(height: space8);
  static SizedBox get vSpace12 => SizedBox(height: space12);
  static SizedBox get vSpace16 => SizedBox(height: space16);
  static SizedBox get vSpace24 => SizedBox(height: space24);
  static SizedBox get vSpace32 => SizedBox(height: space32);
  static SizedBox get vSpace48 => SizedBox(height: space48);

  // Pre-defined SizedBoxes for horizontal spacing - Dynamic getters
  static SizedBox get hSpace4 => SizedBox(width: space4);
  static SizedBox get hSpace8 => SizedBox(width: space8);
  static SizedBox get hSpace12 => SizedBox(width: space12);
  static SizedBox get hSpace16 => SizedBox(width: space16);
  static SizedBox get hSpace24 => SizedBox(width: space24);
  static SizedBox get hSpace32 => SizedBox(width: space32);

  // Target Touch Areas
  static const double minTouchTarget = 48.0;
}
