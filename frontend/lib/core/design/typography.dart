import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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

  // Font sizes
  static const double fontSizeXS = 10.0;
  static const double fontSizeSM = 12.0;
  static const double fontSizeBase = 14.0;
  static const double fontSizeLG = 16.0;
  static const double fontSizeXL = 18.0;
  static const double fontSize2XL = 20.0;
  static const double fontSize3XL = 24.0;
  static const double fontSize4XL = 30.0;
  static const double fontSize5XL = 36.0;

  // Text styles with semantic naming
  static TextStyle displayLarge = GoogleFonts.inter(
    fontSize: fontSize5XL,
    fontWeight: weightBold,
    color: AppColors.textPrimary,
    height: 1.2,
    letterSpacing: -0.5,
  );

  static TextStyle displayMedium = GoogleFonts.inter(
    fontSize: fontSize4XL,
    fontWeight: weightBold,
    color: AppColors.textPrimary,
    height: 1.2,
    letterSpacing: -0.25,
  );

  static TextStyle displaySmall = GoogleFonts.inter(
    fontSize: fontSize3XL,
    fontWeight: weightBold,
    color: AppColors.textPrimary,
    height: 1.3,
  );

  static TextStyle headlineLarge = GoogleFonts.inter(
    fontSize: fontSize2XL,
    fontWeight: weightSemiBold,
    color: AppColors.textPrimary,
    height: 1.4,
  );

  static TextStyle headlineMedium = GoogleFonts.inter(
    fontSize: fontSizeXL,
    fontWeight: weightSemiBold,
    color: AppColors.textPrimary,
    height: 1.4,
  );

  static TextStyle headlineSmall = GoogleFonts.inter(
    fontSize: fontSizeLG,
    fontWeight: weightSemiBold,
    color: AppColors.textPrimary,
    height: 1.5,
  );

  static TextStyle titleLarge = GoogleFonts.inter(
    fontSize: fontSizeLG,
    fontWeight: weightMedium,
    color: AppColors.textPrimary,
    height: 1.5,
  );

  static TextStyle titleMedium = GoogleFonts.inter(
    fontSize: fontSizeBase,
    fontWeight: weightMedium,
    color: AppColors.textPrimary,
    height: 1.5,
  );

  static TextStyle titleSmall = GoogleFonts.inter(
    fontSize: fontSizeSM,
    fontWeight: weightMedium,
    color: AppColors.textPrimary,
    height: 1.5,
  );

  static TextStyle bodyLarge = GoogleFonts.inter(
    fontSize: fontSizeLG,
    fontWeight: weightRegular,
    color: AppColors.textPrimary,
    height: 1.6,
  );

  static TextStyle bodyMedium = GoogleFonts.inter(
    fontSize: fontSizeBase,
    fontWeight: weightRegular,
    color: AppColors.textPrimary,
    height: 1.6,
  );

  static TextStyle bodySmall = GoogleFonts.inter(
    fontSize: fontSizeSM,
    fontWeight: weightRegular,
    color: AppColors.textSecondary,
    height: 1.6,
  );

  static TextStyle labelLarge = GoogleFonts.inter(
    fontSize: fontSizeBase,
    fontWeight: weightMedium,
    color: AppColors.textPrimary,
    height: 1.4,
  );

  static TextStyle labelMedium = GoogleFonts.inter(
    fontSize: fontSizeSM,
    fontWeight: weightMedium,
    color: AppColors.textPrimary,
    height: 1.4,
  );

  static TextStyle labelSmall = GoogleFonts.inter(
    fontSize: fontSizeXS,
    fontWeight: weightMedium,
    color: AppColors.textSecondary,
    height: 1.4,
  );
}
