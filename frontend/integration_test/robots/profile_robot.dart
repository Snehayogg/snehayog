import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vayug/features/profile/core/presentation/screens/profile_screen.dart';
import 'package:vayug/shared/widgets/vayu_bottom_sheet.dart';

/// **Robot Pattern Implementation for Profile**
/// This class abstracts all UI interactions related to the profile screen.
class ProfileRobot {
  final WidgetTester tester;

  ProfileRobot(this.tester);

  /// Verifies that the ProfileScreen is currently visible
  void verifyProfileVisible() {
    expect(find.byType(ProfileScreen), findsOneWidget);
  }

  /// Taps on a video card in the profile grid by index
  Future<void> tapVideoCard(int index) async {
    final videoCards = find.byType(InkWell); // Profile grid items are InkWells
    expect(videoCards, findsWidgets);
    await tester.tap(videoCards.at(index));
    await tester.pumpAndSettle();
  }

  /// Verifies that the episode list bottom sheet is visible
  void verifyEpisodeBottomSheetVisible() {
    expect(find.text('More Episodes'), findsOneWidget);
    expect(find.byType(VayuBottomSheet), findsOneWidget);
  }

  /// Verifies that the 'SERIES' badge is visible on a video card
  void verifySeriesBadgeVisible(int index) {
    // This is more complex as it's an internal widget, but we can search for the text 'SERIES'
    expect(find.text('SERIES'), findsWidgets);
  }
}
