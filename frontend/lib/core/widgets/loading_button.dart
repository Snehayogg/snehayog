import 'package:flutter/material.dart';
import 'package:snehayog/core/theme/app_theme.dart';

class LoadingButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isLoading;
  final Widget child;
  final double? width;
  final double? height;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double? borderRadius;
  final EdgeInsetsGeometry? padding;
  final List<BoxShadow>? boxShadow;

  const LoadingButton({
    super.key,
    required this.onPressed,
    required this.isLoading,
    required this.child,
    this.width,
    this.height,
    this.backgroundColor,
    this.foregroundColor,
    this.borderRadius,
    this.padding,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: backgroundColor ?? AppTheme.primary,
        borderRadius:
            BorderRadius.circular(borderRadius ?? AppTheme.radiusMedium),
        boxShadow: boxShadow ?? AppTheme.shadowMd,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius:
              BorderRadius.circular(borderRadius ?? AppTheme.radiusMedium),
          child: Container(
            padding: padding ?? const EdgeInsets.all(AppTheme.spacing4),
            child: Center(
              child: isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          foregroundColor ?? AppTheme.textInverse,
                        ),
                      ),
                    )
                  : child,
            ),
          ),
        ),
      ),
    );
  }
}

class LoadingTextButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isLoading;
  final String text;
  final TextStyle? textStyle;
  final Color? textColor;
  final double? fontSize;
  final FontWeight? fontWeight;

  const LoadingTextButton({
    super.key,
    required this.onPressed,
    required this.isLoading,
    required this.text,
    this.textStyle,
    this.textColor,
    this.fontSize,
    this.fontWeight,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: isLoading ? null : onPressed,
      style: TextButton.styleFrom(
        foregroundColor: textColor ?? AppTheme.primary,
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing4,
          vertical: AppTheme.spacing2,
        ),
      ),
      child: isLoading
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  textColor ?? AppTheme.primary,
                ),
              ),
            )
          : Text(
              text,
              style: textStyle ??
                  TextStyle(
                    fontSize: fontSize ?? 16,
                    fontWeight: fontWeight ?? FontWeight.w600,
                    color: textColor ?? AppTheme.primary,
                  ),
            ),
    );
  }
}

class LoadingIconButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData icon;
  final double? iconSize;
  final Color? iconColor;
  final Color? backgroundColor;
  final double? borderRadius;
  final EdgeInsetsGeometry? padding;

  const LoadingIconButton({
    super.key,
    required this.onPressed,
    required this.isLoading,
    required this.icon,
    this.iconSize,
    this.iconColor,
    this.backgroundColor,
    this.borderRadius,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor ?? AppTheme.primary,
        borderRadius:
            BorderRadius.circular(borderRadius ?? AppTheme.radiusMedium),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius:
              BorderRadius.circular(borderRadius ?? AppTheme.radiusMedium),
          child: Container(
            padding: padding ?? const EdgeInsets.all(AppTheme.spacing4),
            child: Center(
              child: isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          iconColor ?? AppTheme.textInverse,
                        ),
                      ),
                    )
                  : Icon(
                      icon,
                      size: iconSize ?? 24,
                      color: iconColor ?? AppTheme.textInverse,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
