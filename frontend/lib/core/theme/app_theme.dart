import 'package:flutter/material.dart';

/// Professional theme system for Snehayog app
/// Implements a minimal but sharp design with teal accent guiding actions
class AppTheme {
  // ===========================================================================
  // COLOR PALETTE - Semantic naming for professional development
  // ===========================================================================

  // Primary Colors
  static const Color primary = Color(0xFF10A37F); // Teal green - main accent
  static const Color primaryLight = Color(0xFF2DB894);
  static const Color primaryDark = Color(0xFF0A7A5F);

  // Text & Foreground Colors
  static const Color textPrimary =
      Color(0xFF202123); // Near-black for important content
  static const Color textSecondary = Color(0xFF565869); // Secondary text
  static const Color textTertiary = Color(0xFF8E8EA0); // Muted text
  static const Color textInverse =
      Color(0xFFFFFFFF); // White text on dark backgrounds

  // Background Colors
  static const Color backgroundPrimary = Color(0xFFFFFFFF); // Pure white
  static const Color backgroundSecondary = Color(0xFFF7F7F8); // Off-white
  static const Color backgroundTertiary =
      Color(0xFFF0F0F1); // Subtle background

  // Surface Colors
  static const Color surfacePrimary = Color(0xFFFFFFFF);
  static const Color surfaceSecondary = Color(0xFFF7F7F8);
  static const Color surfaceElevated = Color(0xFFFFFFFF);

  // Semantic Colors
  static const Color success = Color(0xFF10A37F); // Use primary for success
  static const Color error = Color(0xFFDC2626);
  static const Color warning = Color(0xFFF59E0B);
  static const Color info = Color(0xFF3B82F6);

  // Border & Divider Colors
  static const Color borderPrimary = Color(0xFFE5E7EB);
  static const Color borderSecondary = Color(0xFFF3F4F6);
  static const Color divider = Color(0xFFE5E7EB);

  // Shadow Colors
  static const Color shadowPrimary = Color(0x0A000000);
  static const Color shadowSecondary = Color(0x0F000000);
  static const Color shadowElevated = Color(0x1A000000);

  // Overlay Colors
  static const Color overlayLight = Color(0x0A000000);
  static const Color overlayMedium = Color(0x1A000000);
  static const Color overlayDark = Color(0x4D000000);

  // ===========================================================================
  // SPACING SYSTEM - Consistent 8px grid system
  // ===========================================================================

  // Base spacing unit: 8px
  static const double _baseUnit = 8.0;

  // Spacing scale
  static const double spacing0 = 0.0;
  static const double spacing1 = _baseUnit * 0.5; // 4px
  static const double spacing2 = _baseUnit * 1.0; // 8px
  static const double spacing3 = _baseUnit * 1.5; // 12px
  static const double spacing4 = _baseUnit * 2.0; // 16px
  static const double spacing5 = _baseUnit * 2.5; // 20px
  static const double spacing6 = _baseUnit * 3.0; // 24px
  static const double spacing8 = _baseUnit * 4.0; // 32px
  static const double spacing10 = _baseUnit * 5.0; // 40px
  static const double spacing12 = _baseUnit * 6.0; // 48px
  static const double spacing16 = _baseUnit * 8.0; // 64px
  static const double spacing20 = _baseUnit * 10.0; // 80px
  static const double spacing24 = _baseUnit * 12.0; // 96px

  // ===========================================================================
  // BORDER RADIUS SYSTEM - Consistent corner rounding
  // ===========================================================================

  static const double radiusNone = 0.0;
  static const double radiusSmall = 4.0;
  static const double radiusMedium = 8.0;
  static const double radiusLarge = 12.0;
  static const double radiusXLarge = 16.0;
  static const double radiusXXLarge = 24.0;
  static const double radiusFull = 9999.0;

  // ===========================================================================
  // TYPOGRAPHY SYSTEM - Professional font hierarchy
  // ===========================================================================

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
  static const TextStyle displayLarge = TextStyle(
    fontSize: fontSize5XL,
    fontWeight: weightBold,
    color: textPrimary,
    height: 1.2,
    letterSpacing: -0.5,
  );

  static const TextStyle displayMedium = TextStyle(
    fontSize: fontSize4XL,
    fontWeight: weightBold,
    color: textPrimary,
    height: 1.2,
    letterSpacing: -0.25,
  );

  static const TextStyle displaySmall = TextStyle(
    fontSize: fontSize3XL,
    fontWeight: weightBold,
    color: textPrimary,
    height: 1.3,
  );

  static const TextStyle headlineLarge = TextStyle(
    fontSize: fontSize2XL,
    fontWeight: weightSemiBold,
    color: textPrimary,
    height: 1.4,
  );

  static const TextStyle headlineMedium = TextStyle(
    fontSize: fontSizeXL,
    fontWeight: weightSemiBold,
    color: textPrimary,
    height: 1.4,
  );

  static const TextStyle headlineSmall = TextStyle(
    fontSize: fontSizeLG,
    fontWeight: weightSemiBold,
    color: textPrimary,
    height: 1.5,
  );

  static const TextStyle titleLarge = TextStyle(
    fontSize: fontSizeLG,
    fontWeight: weightMedium,
    color: textPrimary,
    height: 1.5,
  );

  static const TextStyle titleMedium = TextStyle(
    fontSize: fontSizeBase,
    fontWeight: weightMedium,
    color: textPrimary,
    height: 1.5,
  );

  static const TextStyle titleSmall = TextStyle(
    fontSize: fontSizeSM,
    fontWeight: weightMedium,
    color: textPrimary,
    height: 1.5,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontSize: fontSizeLG,
    fontWeight: weightRegular,
    color: textPrimary,
    height: 1.6,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: fontSizeBase,
    fontWeight: weightRegular,
    color: textPrimary,
    height: 1.6,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: fontSizeSM,
    fontWeight: weightRegular,
    color: textSecondary,
    height: 1.6,
  );

  static const TextStyle labelLarge = TextStyle(
    fontSize: fontSizeBase,
    fontWeight: weightMedium,
    color: textPrimary,
    height: 1.4,
  );

  static const TextStyle labelMedium = TextStyle(
    fontSize: fontSizeSM,
    fontWeight: weightMedium,
    color: textPrimary,
    height: 1.4,
  );

  static const TextStyle labelSmall = TextStyle(
    fontSize: fontSizeXS,
    fontWeight: weightMedium,
    color: textSecondary,
    height: 1.4,
  );

  // ===========================================================================
  // SHADOW SYSTEM - Subtle depth and elevation
  // ===========================================================================

  static const List<BoxShadow> shadowSm = [
    BoxShadow(
      color: shadowPrimary,
      blurRadius: 4,
      offset: Offset(0, 1),
      spreadRadius: 0,
    ),
  ];

  static const List<BoxShadow> shadowMd = [
    BoxShadow(
      color: shadowSecondary,
      blurRadius: 8,
      offset: Offset(0, 2),
      spreadRadius: 0,
    ),
  ];

  static const List<BoxShadow> shadowLg = [
    BoxShadow(
      color: shadowElevated,
      blurRadius: 16,
      offset: Offset(0, 4),
      spreadRadius: 0,
    ),
  ];

  static const List<BoxShadow> shadowXl = [
    BoxShadow(
      color: shadowElevated,
      blurRadius: 24,
      offset: Offset(0, 8),
      spreadRadius: 0,
    ),
  ];

  // ===========================================================================
  // GRADIENT SYSTEM - Subtle visual interest
  // ===========================================================================

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primaryLight],
    stops: [0.0, 1.0],
  );

  static const LinearGradient surfaceGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [surfacePrimary, surfaceSecondary],
    stops: [0.0, 1.0],
  );

  // ===========================================================================
  // THEME DATA - Flutter ThemeData implementation
  // ===========================================================================

  /// Light theme for the app
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,

      // Color scheme
      colorScheme: const ColorScheme.light(
        primary: primary,
        onPrimary: textInverse,
        secondary: textSecondary,
        onSecondary: textInverse,
        surface: surfacePrimary,
        onSurface: textPrimary,
        error: error,
        onError: textInverse,
        outline: borderPrimary,
        outlineVariant: borderSecondary,
      ),

      // App bar theme
      appBarTheme: const AppBarTheme(
        backgroundColor: surfacePrimary,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: titleLarge,
        centerTitle: false,
      ),

      // Bottom navigation bar theme
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surfacePrimary,
        selectedItemColor: primary,
        unselectedItemColor: textTertiary,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        selectedLabelStyle: labelSmall,
        unselectedLabelStyle: labelSmall,
      ),

      // Card theme
      cardTheme: CardThemeData(
        color: surfacePrimary,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
        margin: const EdgeInsets.all(spacing2),
      ),

      // Elevated button theme
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: textInverse,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: spacing4,
            vertical: spacing3,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
          ),
          textStyle: labelLarge,
        ),
      ),

      // Outlined button theme
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: primary, width: 1.5),
          padding: const EdgeInsets.symmetric(
            horizontal: spacing4,
            vertical: spacing3,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
          ),
          textStyle: labelLarge,
        ),
      ),

      // Text button theme
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          padding: const EdgeInsets.symmetric(
            horizontal: spacing3,
            vertical: spacing2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSmall),
          ),
          textStyle: labelLarge,
        ),
      ),

      // Input decoration theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: backgroundSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: const BorderSide(color: borderPrimary),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: const BorderSide(color: borderPrimary),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: const BorderSide(color: error, width: 1.5),
        ),
        contentPadding: const EdgeInsets.all(spacing3),
        labelStyle: bodyMedium.copyWith(color: textSecondary),
        hintStyle: bodyMedium.copyWith(color: textTertiary),
      ),

      // Chip theme
      chipTheme: ChipThemeData(
        backgroundColor: backgroundSecondary,
        selectedColor: primary,
        disabledColor: backgroundTertiary,
        labelStyle: labelMedium,
        padding: const EdgeInsets.symmetric(
          horizontal: spacing2,
          vertical: spacing1,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusFull),
        ),
      ),

      // Divider theme
      dividerTheme: const DividerThemeData(
        color: divider,
        thickness: 1,
        space: spacing4,
      ),

      // Icon theme
      iconTheme: const IconThemeData(
        color: textSecondary,
        size: 24,
      ),

      // Text theme
      textTheme: const TextTheme(
        displayLarge: displayLarge,
        displayMedium: displayMedium,
        displaySmall: displaySmall,
        headlineLarge: headlineLarge,
        headlineMedium: headlineMedium,
        headlineSmall: headlineSmall,
        titleLarge: titleLarge,
        titleMedium: titleMedium,
        titleSmall: titleSmall,
        bodyLarge: bodyLarge,
        bodyMedium: bodyMedium,
        bodySmall: bodySmall,
        labelLarge: labelLarge,
        labelMedium: labelMedium,
        labelSmall: labelSmall,
      ),

      // Primary text theme
      primaryTextTheme: const TextTheme(
        displayLarge: displayLarge,
        displayMedium: displayMedium,
        displaySmall: displaySmall,
        headlineLarge: headlineLarge,
        headlineMedium: headlineMedium,
        headlineSmall: headlineSmall,
        titleLarge: titleLarge,
        titleMedium: titleMedium,
        titleSmall: titleSmall,
        bodyLarge: bodyLarge,
        bodyMedium: bodyMedium,
        bodySmall: bodySmall,
        labelLarge: labelLarge,
        labelMedium: labelMedium,
        labelSmall: labelSmall,
      ),

      // Scaffold background color
      scaffoldBackgroundColor: backgroundPrimary,

      // Dialog theme
      dialogTheme: DialogThemeData(
        backgroundColor: surfacePrimary,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
        ),
        titleTextStyle: headlineMedium,
        contentTextStyle: bodyMedium,
      ),

      // Bottom sheet theme
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surfacePrimary,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(radiusLarge)),
        ),
      ),

      // Snack bar theme
      snackBarTheme: SnackBarThemeData(
        backgroundColor: textPrimary,
        contentTextStyle: bodyMedium.copyWith(color: textInverse),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 8,
      ),

      // Progress indicator theme
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: backgroundSecondary,
        circularTrackColor: backgroundSecondary,
      ),

      // Switch theme
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primary;
          return textTertiary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return primary.withOpacity(0.3);
          }
          return backgroundTertiary;
        }),
      ),

      // Checkbox theme
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primary;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(textInverse),
        side: const BorderSide(color: borderPrimary, width: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
      ),

      // Radio theme
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primary;
          return textTertiary;
        }),
      ),

      // Slider theme
      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        inactiveTrackColor: backgroundSecondary,
        thumbColor: primary,
        overlayColor: primary.withOpacity(0.2),
        valueIndicatorColor: primary,
        valueIndicatorTextStyle: labelSmall.copyWith(color: textInverse),
      ),

      // Tab bar theme
      tabBarTheme: const TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: textSecondary,
        indicatorColor: primary,
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: labelMedium,
        unselectedLabelStyle: labelMedium,
      ),

      // Expansion tile theme
      expansionTileTheme: const ExpansionTileThemeData(
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        textColor: textPrimary,
        iconColor: textSecondary,
        collapsedTextColor: textPrimary,
        collapsedIconColor: textSecondary,
      ),

      // List tile theme
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(
          horizontal: spacing4,
          vertical: spacing2,
        ),
        titleTextStyle: titleMedium,
        subtitleTextStyle: bodySmall,
        leadingAndTrailingTextStyle: bodyMedium,
        iconColor: textSecondary,
        textColor: textPrimary,
      ),
    );
  }

  // ===========================================================================
  // UTILITY METHODS - Helper functions for consistent theming
  // ===========================================================================

  /// Get responsive spacing based on screen size
  static double getResponsiveSpacing(BuildContext context, double baseSpacing) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < 600) return baseSpacing * 0.8; // Mobile
    if (screenWidth < 900) return baseSpacing; // Tablet
    return baseSpacing * 1.2; // Desktop
  }

  /// Get responsive font size based on screen size
  static double getResponsiveFontSize(BuildContext context, double baseSize) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < 600) return baseSize * 0.9; // Mobile
    if (screenWidth < 900) return baseSize; // Tablet
    return baseSize * 1.1; // Desktop
  }

  /// Create a custom button style with consistent theming
  static ButtonStyle createButtonStyle({
    Color? backgroundColor,
    Color? foregroundColor,
    double? elevation,
    EdgeInsetsGeometry? padding,
    double? borderRadius,
    BorderSide? side,
  }) {
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.all(backgroundColor ?? primary),
      foregroundColor:
          WidgetStateProperty.all(foregroundColor ?? textInverse),
      elevation: WidgetStateProperty.all(elevation ?? 0),
      padding: WidgetStateProperty.all(padding ??
          const EdgeInsets.symmetric(
            horizontal: spacing4,
            vertical: spacing3,
          )),
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius ?? radiusMedium),
          side: side ?? BorderSide.none,
        ),
      ),
    );
  }

  /// Create a custom card style with consistent theming
  static BoxDecoration createCardDecoration({
    Color? backgroundColor,
    double? borderRadius,
    List<BoxShadow>? shadows,
    BorderSide? border,
  }) {
    return BoxDecoration(
      color: backgroundColor ?? surfacePrimary,
      borderRadius: BorderRadius.circular(borderRadius ?? radiusMedium),
      boxShadow: shadows ?? shadowSm,
      border: border != null
          ? Border.all(color: border.color, width: border.width)
          : null,
    );
  }
}
