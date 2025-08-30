/// Optimized app constants for better performance and smaller size
class AppConstants {
  // Video player constants - optimized for performance
  static const int preloadDistance = 2;
  static const int maxActiveControllers = 3;
  static const Duration healthCheckInterval =
      Duration(seconds: 10); // increased from 5
  static const Duration videoTransitionDelay = Duration(milliseconds: 100);

  // UI constants - optimized sizes
  static const double actionButtonSize =
      26.0; // **REDUCED from 28.0 for more compact look**
  static const double avatarRadius =
      10.0; // **REDUCED from 12.0 for better proportion with compact follow button**
  static const double commentSheetHeight = 200.0; // reduced from 250.0
  static const double followButtonHeight =
      20.0; // reduced from 22.0 for more professional look
  static const double followButtonPadding =
      6.0; // reduced from 8.0 for more compact design

  // API constants
  static const int initialPage = 1;
  static const int scrollThreshold = 150; // reduced from 200

  // Animation constants - optimized durations
  static const Duration fadeAnimationDuration =
      Duration(milliseconds: 200); // reduced from 300
  static const Duration slideAnimationDuration =
      Duration(milliseconds: 200); // reduced from 250
}
