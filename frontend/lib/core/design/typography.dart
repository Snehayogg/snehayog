import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'colors.dart';

class AppTypography {
  AppTypography._();

  // Font weights
  static const FontWeight weightLight = FontWeight.w300;
  static const FontWeight weightRegular = FontWeight.w400;
  static const FontWeight weightMedium = FontWeight.w500;
  static const FontWeight weightSemiBold = FontWeight.w600;
  static const FontWeight weightBold = FontWeight.w700;
  static const FontWeight weightExtraBold = FontWeight.w800;

  // Font sizes - Responsive via .sp
  static double get fontSizeXS => 10.0.sp;
  static double get fontSizeSM => 12.0.sp;
  static double get fontSizeBase => 14.0.sp;
  static double get fontSizeLG => 16.0.sp;
  static double get fontSizeXL => 18.0.sp;
  static double get fontSize2XL => 20.0.sp;
  static double get fontSize3XL => 24.0.sp;
  static double get fontSize4XL => 30.0.sp;
  static double get fontSize5XL => 36.0.sp;

  // Text styles with semantic naming - Dynamic getters
  static TextStyle get displayLarge => GoogleFonts.inter(
    fontSize: fontSize5XL,
    fontWeight: weightBold,
    color: AppColors.textPrimary,
    height: 1.2,
    letterSpacing: -0.5,
  );

  static TextStyle get displayMedium => GoogleFonts.inter(
    fontSize: fontSize4XL,
    fontWeight: weightBold,
    color: AppColors.textPrimary,
    height: 1.2,
    letterSpacing: -0.25,
  );

  static TextStyle get displaySmall => GoogleFonts.inter(
    fontSize: fontSize3XL,
    fontWeight: weightBold,
    color: AppColors.textPrimary,
    height: 1.3,
  );

  static TextStyle get headlineLarge => GoogleFonts.inter(
    fontSize: fontSize2XL,
    fontWeight: weightSemiBold,
    color: AppColors.textPrimary,
    height: 1.4,
  );

  static TextStyle get headlineMedium => GoogleFonts.inter(
    fontSize: fontSizeXL,
    fontWeight: weightSemiBold,
    color: AppColors.textPrimary,
    height: 1.4,
  );

  static TextStyle get headlineSmall => GoogleFonts.inter(
    fontSize: fontSizeLG,
    fontWeight: weightSemiBold,
    color: AppColors.textPrimary,
    height: 1.5,
  );

  static TextStyle get titleLarge => GoogleFonts.inter(
    fontSize: fontSizeLG,
    fontWeight: weightMedium,
    color: AppColors.textPrimary,
    height: 1.5,
  );

  static TextStyle get titleMedium => GoogleFonts.inter(
    fontSize: fontSizeBase,
    fontWeight: weightMedium,
    color: AppColors.textPrimary,
    height: 1.5,
  );

  static TextStyle get titleSmall => GoogleFonts.inter(
    fontSize: fontSizeSM,
    fontWeight: weightMedium,
    color: AppColors.textPrimary,
    height: 1.5,
  );

  static TextStyle get bodyLarge => GoogleFonts.inter(
    fontSize: fontSizeLG,
    fontWeight: weightRegular,
    color: AppColors.textPrimary,
    height: 1.6,
  );

  static TextStyle get bodyMedium => GoogleFonts.inter(
    fontSize: fontSizeBase,
    fontWeight: weightRegular,
    color: AppColors.textPrimary,
    height: 1.6,
  );

  static TextStyle get bodySmall => GoogleFonts.inter(
    fontSize: fontSizeSM,
    fontWeight: weightRegular,
    color: AppColors.textSecondary,
    height: 1.6,
  );

  static TextStyle get labelLarge => GoogleFonts.inter(
    fontSize: fontSizeBase,
    fontWeight: weightMedium,
    color: AppColors.textPrimary,
    height: 1.4,
  );

  static TextStyle get labelMedium => GoogleFonts.inter(
    fontSize: fontSizeSM,
    fontWeight: weightMedium,
    color: AppColors.textPrimary,
    height: 1.4,
  );

  static TextStyle get labelSmall => GoogleFonts.inter(
    fontSize: fontSizeXS,
    fontWeight: weightMedium,
    color: AppColors.textSecondary,
    height: 1.4,
  );
}
