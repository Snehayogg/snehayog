class ProfileConstants {
  // Profile picture dimensions
  static const double mobileProfileRadius = 50.0;
  static const double desktopProfileRadius = 75.0;
  static const double profileIconSize = 24.0;

  // Spacing and padding
  static const double smallSpacing = 8.0;
  static const double mediumSpacing = 16.0;
  static const double largeSpacing = 24.0;
  static const double extraLargeSpacing = 32.0;

  // Border radius
  static const double smallBorderRadius = 8.0;
  static const double mediumBorderRadius = 12.0;
  static const double largeBorderRadius = 16.0;

  // Font sizes
  static const double smallFontSize = 12.0;
  static const double mediumFontSize = 14.0;
  static const double largeFontSize = 16.0;
  static const double titleFontSize = 24.0;
  static const double headingFontSize = 20.0;

  // Colors
  static const int primaryColor = 0xFF424242;
  static const int secondaryColor = 0xFF757575;
  static const int backgroundColor = 0xFFF5F5F5;
  static const int blueColor = 0xFF2196F3;
  static const int redColor = 0xFFF44336;
  static const int greyColor = 0xFF9E9E9E;

  // Opacity values
  static const double lightOpacity = 0.1;
  static const double mediumOpacity = 0.3;
  static const double heavyOpacity = 0.7;

  // Border widths
  static const double thinBorder = 1.0;
  static const double thickBorder = 2.0;

  // Animation durations
  static const Duration shortAnimation = Duration(milliseconds: 200);
  static const Duration mediumAnimation = Duration(milliseconds: 300);
  static const Duration longAnimation = Duration(milliseconds: 500);

  // Selection mode constants
  static const String selectionModeTitle = 'Selection Mode';
  static const String videosSelectedText = 'video(s) selected';
  static const String deleteSelectedText = 'Delete Selected';
  static const String clearSelectionText = 'Clear Selection';
  static const String exitSelectionText = 'Exit Selection';

  // Profile actions
  static const String selectDeleteVideosText = 'Select & Delete Videos';
  static const String logoutText = 'Logout';
  static const String editText = 'Edit';
  static const String saveText = 'Save';
  static const String cancelText = 'Cancel';
  static const String nameLabelText = 'Name';
  static const String nameHintText = 'Enter a unique name';

  // Error messages
  static const String errorLoadingData = 'Could not load user data.';
  static const String errorLoadingVideos = 'Failed to load videos: ';
  static const String connectionTimeout =
      'Connection timed out. Please check your internet connection and try again.';
  static const String errorLoadingUserData = 'Error loading user data: ';

  // Success messages
  static const String profileUpdated = 'Profile updated successfully!';
  static const String videosDeleted = 'Videos deleted successfully!';
}
