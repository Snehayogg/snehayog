import 'package:flutter/material.dart';
import 'package:vayu/core/design/colors.dart';
import 'package:vayu/core/design/typography.dart';

enum VayuSnackBarType { 
  success, 
  error, 
  info, 
  warning 
}

class VayuSnackBar {
  VayuSnackBar._();

  /// Shows a consistent, orientation-aware SnackBar.
  static void show(
    BuildContext context, 
    String message, {
    VayuSnackBarType type = VayuSnackBarType.info,
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
    IconData? icon,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    // Clear existing snackbars
    messenger.hideCurrentSnackBar();

    Color backgroundColor;
    IconData? defaultIcon;
    Color iconColor = Colors.white;

    switch (type) {
      case VayuSnackBarType.success:
        backgroundColor = AppColors.success.withValues(alpha: 0.95);
        defaultIcon = Icons.check_circle_rounded;
        break;
      case VayuSnackBarType.error:
        backgroundColor = AppColors.error.withValues(alpha: 0.95);
        defaultIcon = Icons.error_rounded;
        break;
      case VayuSnackBarType.warning:
        backgroundColor = AppColors.warning.withValues(alpha: 0.95);
        defaultIcon = Icons.warning_rounded;
        break;
      case VayuSnackBarType.info:
        backgroundColor = AppColors.surfacePrimary.withValues(alpha: 0.95);
        defaultIcon = Icons.info_rounded;
        break;
    }

    final effectiveIcon = icon ?? defaultIcon;

    messenger.showSnackBar(
      SnackBar(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(effectiveIcon, color: iconColor, size: isLandscape ? 18 : 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: AppTypography.bodyMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: isLandscape ? 13.0 : null,
                ),
                textAlign: isLandscape ? TextAlign.center : TextAlign.start,
              ),
            ),
          ],
        ),
        duration: duration,
        action: action,
        behavior: SnackBarBehavior.floating,
        backgroundColor: backgroundColor,
        width: isLandscape ? 340.0 : null,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(isLandscape ? 16 : 12),
        ),
        margin: isLandscape 
          ? null 
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      ),
    );
  }

  // Helper methods for common types
  static void showSuccess(BuildContext context, String message, {Duration? duration, SnackBarAction? action}) {
    show(context, message, type: VayuSnackBarType.success, duration: duration ?? const Duration(seconds: 3), action: action);
  }

  static void showError(BuildContext context, String message, {Duration? duration, SnackBarAction? action}) {
    show(context, message, type: VayuSnackBarType.error, duration: duration ?? const Duration(seconds: 4), action: action);
  }

  static void showInfo(BuildContext context, String message, {Duration? duration, SnackBarAction? action}) {
    show(context, message, type: VayuSnackBarType.info, duration: duration ?? const Duration(seconds: 3), action: action);
  }

  static void showWarning(BuildContext context, String message, {Duration? duration, SnackBarAction? action}) {
    show(context, message, type: VayuSnackBarType.warning, duration: duration ?? const Duration(seconds: 3), action: action);
  }
}
