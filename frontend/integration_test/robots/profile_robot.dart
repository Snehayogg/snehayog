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
    // Grid items use GestureDetector or InkWell
    final videoCards = find.byType(GestureDetector);
    expect(videoCards, findsWidgets);
    await tester.tap(videoCards.at(index));
    await tester.pumpAndSettle();
  }

  /// Long-presses on a video card to enter selection mode
  Future<void> longPressVideoCard(int index) async {
    final videoCards = find.byType(GestureDetector);
    expect(videoCards, findsWidgets);
    await tester.longPress(videoCards.at(index));
    await tester.pumpAndSettle();
  }

  /// Taps the delete button in the top toolbar
  Future<void> tapDeleteButton() async {
    final deleteButton = find.byTooltip('Delete Selected Videos');
    expect(deleteButton, findsOneWidget);
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
  }

  /// Confirms the deletion in the popup dialog
  Future<void> confirmDeletion() async {
    final confirmButton = find.text('Delete');
    expect(confirmButton, findsOneWidget);
    await tester.tap(confirmButton);
    await tester.pumpAndSettle();
  }

  /// Verifies that the video grid is empty
  void verifyNoVideosMessageVisible() {
    expect(find.text('No videos yet'), findsOneWidget);
  }

  /// Verifies that the episode list bottom sheet is visible
  void verifyEpisodeBottomSheetVisible() {
    expect(find.text('More Episodes'), findsOneWidget);
    expect(find.byType(VayuBottomSheet), findsOneWidget);
  }

  /// Verifies that the 'SERIES' badge is visible on a video card
  void verifySeriesBadgeVisible(int index) {
    expect(find.text('SERIES'), findsWidgets);
  }
}
