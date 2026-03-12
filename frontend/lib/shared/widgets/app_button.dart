import 'package:flutter/material.dart';
import 'package:vayu/core/design/spacing.dart';
import 'package:vayu/core/design/radius.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vayu/core/design/colors.dart';
import 'package:vayu/core/design/typography.dart';
import 'package:vayu/shared/widgets/interactive_scale_button.dart';

enum AppButtonVariant {
  primary,
  secondary,
  outline,
  text,
  danger,
}

enum AppButtonSize {
  small,
  medium,
  large,
}

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final bool isLoading;
  final bool isDisabled;
  final Widget? icon;
  final bool isFullWidth;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.medium,
    this.isLoading = false,
    this.isDisabled = false,
    this.icon,
    this.isFullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Determine dimensions based on size
    double height;
    double fontSize;
    double iconSize;
    EdgeInsets padding;

    switch (size) {
      case AppButtonSize.small:
        height = 36.0;
        fontSize = AppTypography.fontSizeSM;
        iconSize = 16.0;
        padding = EdgeInsets.all(AppSpacing.spacing3);
        break;
      case AppButtonSize.medium:
        height = 48.0;
        fontSize = AppTypography.fontSizeBase;
        iconSize = 20.0;
        padding = EdgeInsets.all(AppSpacing.spacing4);
        break;
      case AppButtonSize.large:
        height = 56.0;
        fontSize = AppTypography.fontSizeLG;
        iconSize = 24.0;
        padding = EdgeInsets.all(AppSpacing.spacing5);
        break;
    }

    // Determine colors based on variant and state
    Color backgroundColor;
    Color foregroundColor;
    Color borderColor = Colors.transparent;
    double elevation = 0;

    const disabledOpacity = 0.5;
    final bool effectiveDisabled = isDisabled || isLoading || onPressed == null;

    switch (variant) {
      case AppButtonVariant.primary:
        backgroundColor = AppColors.primary;
        foregroundColor = AppColors.white;
        elevation = 2;
        break;
      case AppButtonVariant.secondary:
        backgroundColor = AppColors.surfacePrimary;
        foregroundColor = AppColors.textPrimary;
        borderColor = AppColors.borderPrimary;
        break;
      case AppButtonVariant.outline:
        backgroundColor = Colors.transparent;
        foregroundColor = AppColors.primary;
        borderColor = AppColors.primary;
        break;
      case AppButtonVariant.text:
        backgroundColor = Colors.transparent;
        foregroundColor = AppColors.primary;
        break;
      case AppButtonVariant.danger:
        backgroundColor = AppColors.error;
        foregroundColor = AppColors.white;
        break;
    }

    if (effectiveDisabled) {
      backgroundColor = backgroundColor.withValues(
          alpha: backgroundColor == Colors.transparent ? 1.0 : disabledOpacity);
      foregroundColor = foregroundColor.withValues(alpha: disabledOpacity);
      if (borderColor != Colors.transparent) {
        borderColor = borderColor.withValues(alpha: disabledOpacity);
      }
      elevation = 0;
    }

    // Build button content
    Widget content = Row(
      mainAxisSize: isFullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isLoading) ...[
          SizedBox(
            width: iconSize,
            height: iconSize,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
            ),
          ),
          SizedBox(width: AppSpacing.spacing2),
        ] else if (icon != null) ...[
          SizedBox(width: AppSpacing.spacing2),
        ],
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            fontSize: fontSize,
            fontWeight: AppTypography.weightSemiBold,
            color: foregroundColor,
          ),
        ),
      ],
    );

    // Build the outer button
    Widget buttonWidget;

    if (variant == AppButtonVariant.text) {
      buttonWidget = TextButton(
        onPressed: effectiveDisabled ? null : onPressed,
        style: TextButton.styleFrom(
          foregroundColor: foregroundColor,
          padding: padding,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          minimumSize: Size(isFullWidth ? double.infinity : 0, height),
        ),
        child: content,
      );
    } else if (variant == AppButtonVariant.outline ||
        variant == AppButtonVariant.secondary) {
      buttonWidget = OutlinedButton(
        onPressed: effectiveDisabled ? null : onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          side: BorderSide(color: borderColor, width: 1.5),
          padding: padding,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          minimumSize: Size(isFullWidth ? double.infinity : 0, height),
        ),
        child: content,
      );
    } else {
      buttonWidget = ElevatedButton(
        onPressed: effectiveDisabled ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          elevation: elevation,
          padding: padding,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          minimumSize: Size(isFullWidth ? double.infinity : 0, height),
        ),
        child: content,
      );
    }

    // Wrap the outgoing widget in our custom scaling button
    // only if the button is enabled to give it tactile feedback
    return SizedBox(
      height: height,
      width: isFullWidth ? double.infinity : null,
      child: effectiveDisabled
          ? buttonWidget
          : InteractiveScaleButton(
              onTap: onPressed,
              // We don't want the InteractiveScaleButton to actually fire the onTap callback
              // because the underlying Material button (ElevatedButton, etc) already handles it.
              // So we pass a dummy callback if it's not disabled just so the scale effect works.
              // The actual logic is handled by the inner `buttonWidget`'s `onPressed`.
              behavior: HitTestBehavior.deferToChild,
              // A 0.96 scale looks great on large primary buttons
              scaleDownFactor: 0.96,
              child: buttonWidget,
            ),
    );
  }
}
