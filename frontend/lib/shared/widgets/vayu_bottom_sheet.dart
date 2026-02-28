import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:vayu/core/design/colors.dart';
import 'package:vayu/core/design/radius.dart';
import 'package:vayu/core/design/spacing.dart';
import 'package:vayu/core/design/typography.dart';

class VayuBottomSheet extends StatelessWidget {
  final Widget child;
  final String? title;
  final bool showHandle;
  final EdgeInsetsGeometry? padding;
  final List<Widget>? actions;
  final ScrollController? scrollController;
  final double? height;

  const VayuBottomSheet({
    super.key,
    required this.child,
    this.title,
    this.showHandle = true,
    this.padding,
    this.actions,
    this.scrollController,
    this.height,
  });

  /// Static helper to show the bottom sheet with consistent styling.
  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    String? title,
    bool showHandle = true,
    bool isScrollControlled = true,
    EdgeInsetsGeometry? padding,
    List<Widget>? actions,
    double initialChildSize = 0.5,
    double minChildSize = 0.3,
    double maxChildSize = 0.9,
    bool useDraggable = false,
    double? height,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.overlayDark.withOpacity(0.5),
      builder: (context) {
        if (useDraggable) {
          return DraggableScrollableSheet(
            initialChildSize: initialChildSize,
            minChildSize: minChildSize,
            maxChildSize: maxChildSize,
            expand: false,
            builder: (context, scrollController) => VayuBottomSheet(
              title: title,
              showHandle: showHandle,
              padding: padding,
              actions: actions,
              scrollController: scrollController,
              height: height,
              child: child,
            ),
          );
        }
        return VayuBottomSheet(
          title: title,
          showHandle: showHandle,
          padding: padding,
          actions: actions,
          height: height,
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadius.xl),
      ),
      child: BackdropFilter(
        filter: ColorFilter.mode(
          Colors.transparent,
          BlendMode.srcOver,
        ), // Necessary for some platforms
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: AppColors.surfacePrimary.withOpacity(0.7),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.xl),
              ),
              border: Border(
                top: BorderSide(
                  color: AppColors.white.withOpacity(0.12),
                  width: 1,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showHandle)
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.symmetric(vertical: AppSpacing.spacing3),
                    decoration: BoxDecoration(
                      color: AppColors.textTertiary.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                if (title != null || actions != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.spacing5,
                      AppSpacing.spacing2,
                      AppSpacing.spacing3,
                      AppSpacing.spacing2,
                    ),
                    child: Row(
                      children: [
                        if (title != null)
                          Expanded(
                            child: Text(
                              title!,
                              style: const TextStyle(
                                fontSize: AppTypography.fontSizeXL,
                                fontWeight: AppTypography.weightBold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        if (actions != null) ...actions!,
                        IconButton(
                          icon: const Icon(Icons.close, color: AppColors.textSecondary),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                if (title != null) Divider(height: 1, color: AppColors.white.withOpacity(0.05)),
                Flexible(
                  child: Padding(
                    padding: padding ?? const EdgeInsets.all(AppSpacing.spacing5),
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
