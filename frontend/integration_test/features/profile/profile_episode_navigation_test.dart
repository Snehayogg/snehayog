import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:vayug/features/profile/core/presentation/screens/profile_screen.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/shared/utils/app_logger.dart';

import '../../test_app_wrapper.dart';
import '../../robots/profile_robot.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late MockAuthService mockAuthService;
  late MockVideoService mockVideoService;
  late MockFilePickerService mockFilePickerService;
  late MockAdService mockAdService;

  setUp(() {
    mockAuthService = MockAuthService();
    mockVideoService = MockVideoService();
    mockFilePickerService = MockFilePickerService();
    mockAdService = MockAdService();

    // Default Auth Mocks
    when(() => mockAuthService.isLoggedIn()).thenAnswer((_) async => true);
    when(() => mockAuthService.currentUserId).thenReturn('test_user_id');
    when(() => mockAuthService.getUserData(forceRefresh: any(named: 'forceRefresh')))
        .thenAnswer((_) async => <String, dynamic>{
              'id': 'test_user_id',
              'googleId': 'test_user_id',
              'name': 'Test User',
              'profilePic': ''
            });

    // Default Ad Mocks
    when(() => mockAdService.getCreatorRevenueSummary(
          userId: any(named: 'userId'),
          forceRefresh: any(named: 'forceRefresh'),
        )).thenAnswer((_) async => {
          'thisMonth': 0.0,
          'lastMonth': 0.0,
          'totalRevenue': 0.0,
        });
    when(() => mockAdService.getActiveAds()).thenAnswer((_) async => []);
  });

  testWidgets('Profile Episode Navigation: Tapping a series video should open the bottom sheet',
      (tester) async {
    // 1. Setup sample series data
    final seriesVideo = VideoModel(
      id: 'series_1',
      videoName: 'Series Video 1',
      videoUrl: 'https://example.com/video.mp4',
      thumbnailUrl: 'https://example.com/thumb.jpg',
      likes: 10,
      views: 100,
      shares: 5,
      uploadedAt: DateTime.now(),
      uploader: Uploader(id: 'test_user_id', name: 'Test User', profilePic: ''),
      likedBy: [],
      videoType: 'yog',
      aspectRatio: 9 / 16,
      duration: const Duration(minutes: 1),
      seriesId: 'series_abc',
      episodes: [
        {
          'id': 'ep_1',
          'videoName': 'Episode 1',
          'thumbnailUrl': 'https://example.com/ep1.jpg',
          'processingStatus': 'completed'
        },
        {
          'id': 'ep_2',
          'videoName': 'Episode 2',
          'thumbnailUrl': 'https://example.com/ep2.jpg',
          'processingStatus': 'processing' // Testing processing indicator too
        }
      ],
    );

    when(() => mockVideoService.getVideos(
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          videoType: any(named: 'videoType'),
          clearSession: any(named: 'clearSession'),
        )).thenAnswer((_) async => {
          'videos': [seriesVideo],
          'total': 1
        });

    when(() => mockVideoService.getUserVideos(
          any(),
          page: any(named: 'page'),
          limit: any(named: 'limit'),
        )).thenAnswer((_) async => [seriesVideo]);

    // 2. Start the App in Test Wrapper
    await tester.pumpWidget(
      TestAppWrapper(
        mockAuthService: mockAuthService,
        mockVideoService: mockVideoService,
        mockFilePickerService: mockFilePickerService,
        mockAdService: mockAdService,
        child: const Scaffold(
          body: ProfileScreen(),
        ),
      ),
    );

    // Initial pump and settle
    await tester.pumpAndSettle();
    
    // 3. Initialize Robot
    final profileRobot = ProfileRobot(tester);

    // 4. Verify Series Badge exists
    profileRobot.verifySeriesBadgeVisible(0);

    // 5. Tap the series video card
    await profileRobot.tapVideoCard(0);
    
    // 6. Verify Episodes Bottom Sheet opens
    profileRobot.verifyEpisodeBottomSheetVisible();
    
    // 7. Verify processing indicator for Episode 2
    expect(find.text('Processing'), findsOneWidget);

    AppLogger.log('✅ Profile Episode Navigation Integration Test passed');
  });
}
