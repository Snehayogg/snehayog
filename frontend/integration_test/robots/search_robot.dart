import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vayug/features/profile/core/presentation/screens/profile_screen.dart';

/// **Robot Pattern Implementation for Search**
/// This class abstracts all UI interactions related to searching.
class SearchRobot {
  final WidgetTester tester;

  SearchRobot(this.tester);

  /// Opens the search by tapping the search icon
  Future<void> openSearch() async {
    final searchIcon = find.byIcon(Icons.search_rounded);
    expect(searchIcon, findsOneWidget);
    await tester.tap(searchIcon);
    await tester.pumpAndSettle();
  }

  /// Types a query into the search field
  Future<void> typeQuery(String query) async {
    await tester.enterText(find.byType(TextField), query);
    await tester.pumpAndSettle(const Duration(seconds: 2)); // Wait for debounce
  }

  /// Taps on a creator suggestion by name
  Future<void> tapCreatorSuggestion(String name) async {
    final suggestion = find.text(name);
    expect(suggestion, findsOneWidget);
    await tester.tap(suggestion);
    await tester.pumpAndSettle();
  }

  /// Taps on a creator result in the "Creators" tab
  Future<void> tapCreatorResult(String name) async {
    // Navigate to Creators tab if not already there
    final creatorsTab = find.text('Creators');
    expect(creatorsTab, findsOneWidget);
    await tester.tap(creatorsTab);
    await tester.pumpAndSettle();

    final result = find.text(name);
    expect(result, findsWidgets); // Might find multiple in results
    await tester.tap(result.first);
    await tester.pumpAndSettle();
  }

  /// Verifies that the ProfileScreen is currently visible
  void verifyProfileVisible() {
    expect(find.byType(ProfileScreen), findsOneWidget);
  }

  /// Verifies that the Search UI is closed (not visible)
  void verifySearchClosed() {
    expect(find.byType(TextField), findsNothing);
  }
}
