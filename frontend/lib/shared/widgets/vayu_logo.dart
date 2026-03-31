import 'package:flutter/material.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/core/design/radius.dart';
import 'package:google_fonts/google_fonts.dart';


class VayuLogo extends StatelessWidget {
  final double fontSize;
  final Color? textColor;
  final bool withBackground;
  final double? borderRadius;

  const VayuLogo({
    super.key,
    this.fontSize = 24.0,
    this.textColor,
    this.withBackground = false,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final textWidget = Text(
      'ᴠᴀʏᴜ',
      style: GoogleFonts.inter(
        fontSize: fontSize,
        fontWeight: AppTypography.weightBold, // Bold for logo prominence
        color: textColor ?? AppColors.primary,
        letterSpacing: -0.5, // Slightly tighter tracking for modern look
        height: 1.2,
      ),
    );

    if (withBackground) {
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: fontSize * 0.5,
          vertical: fontSize * 0.25,
        ),
        decoration: BoxDecoration(
          color: AppColors.backgroundPrimary,
          borderRadius: BorderRadius.circular(
            borderRadius ?? AppRadius.md,
          ),
          border: Border.all(
            color: AppColors.borderPrimary.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        child: textWidget,
      );
    }

    return textWidget;
  }
}
