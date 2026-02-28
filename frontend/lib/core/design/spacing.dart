import 'package:flutter/material.dart';

class AppSpacing {
  AppSpacing._();

  // Base spacing unit: 8px
  static const double _baseUnit = 8.0;

  // Numerical Margins / Paddings
  static const double spacing0 = 0.0;
  static const double spacing1 = _baseUnit * 0.5; // 4.0
  static const double spacing2 = _baseUnit * 1.0; // 8.0
  static const double spacing3 = _baseUnit * 1.5; // 12.0
  static const double spacing4 = _baseUnit * 2.0; // 16.0
  static const double spacing5 = _baseUnit * 2.5; // 20.0
  static const double spacing6 = _baseUnit * 3.0; // 24.0
  static const double spacing8 = _baseUnit * 4.0; // 32.0
  static const double spacing10 = _baseUnit * 5.0; // 40.0
  static const double spacing12 = _baseUnit * 6.0; // 48.0
  static const double spacing16 = _baseUnit * 8.0; // 64.0
  static const double spacing20 = _baseUnit * 10.0; // 80.0
  static const double spacing24 = _baseUnit * 12.0; // 96.0

  // Standard EdgeInsets Helpers
  static const EdgeInsets edgeInsetsAll4 = EdgeInsets.all(spacing1);
  static const EdgeInsets edgeInsetsAll8 = EdgeInsets.all(spacing2);
  static const EdgeInsets edgeInsetsAll12 = EdgeInsets.all(spacing3);
  static const EdgeInsets edgeInsetsAll16 = EdgeInsets.all(spacing4);
  static const EdgeInsets edgeInsetsAll24 = EdgeInsets.all(spacing6);

  // AppLayout legacy variables for backward compatibility during transition
  static const double space4 = 4.0;
  static const double space8 = 8.0;
  static const double space12 = 12.0;
  static const double space16 = 16.0;
  static const double space24 = 24.0;
  static const double space32 = 32.0;
  static const double space48 = 48.0;
  static const double space64 = 64.0;

  // Pre-defined SizedBoxes for vertical spacing
  static const SizedBox vSpace4 = SizedBox(height: space4);
  static const SizedBox vSpace8 = SizedBox(height: space8);
  static const SizedBox vSpace12 = SizedBox(height: space12);
  static const SizedBox vSpace16 = SizedBox(height: space16);
  static const SizedBox vSpace24 = SizedBox(height: space24);
  static const SizedBox vSpace32 = SizedBox(height: space32);
  static const SizedBox vSpace48 = SizedBox(height: space48);

  // Pre-defined SizedBoxes for horizontal spacing
  static const SizedBox hSpace4 = SizedBox(width: space4);
  static const SizedBox hSpace8 = SizedBox(width: space8);
  static const SizedBox hSpace12 = SizedBox(width: space12);
  static const SizedBox hSpace16 = SizedBox(width: space16);
  static const SizedBox hSpace24 = SizedBox(width: space24);
  static const SizedBox hSpace32 = SizedBox(width: space32);

  // Target Touch Areas
  static const double minTouchTarget = 48.0;
}
