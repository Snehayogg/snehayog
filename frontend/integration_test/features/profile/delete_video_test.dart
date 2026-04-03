import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:vayug/features/profile/core/presentation/screens/profile_screen.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import '../../robots/profile_robot.dart';
import '../../test_app_wrapper.dart';

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

    // Mock successful authentication
    when(() => mockAuthService.getUserData(forceRefresh: any(named: 'forceRefresh')))
        .thenAnswer((_) async => {
              'id': 'test-user-google-id',
              'googleId': 'test-user-google-id',
              'name': 'Test User',
              'email': 'test@example.com',
              'token': 'test-token',
            });

    // Mock current user ID for ownership checks
    when(() => mockAuthService.currentUserId).thenReturn('test-user-google-id');

    // Mock base URL
    when(() => mockVideoService.getBaseUrlWithFallback())
        .thenAnswer((_) async => 'https://api.example.com');

    // Mock initial video list (one video)
    final testVideo = VideoModel(
      id: 'test-video-id',
      videoName: 'Test Video to Delete',
      uploader: Uploader(
        id: 'test-user-id',
        name: 'Test User',
        profilePic: '',
        googleId: 'test-user-google-id',
      ),
      videoUrl: 'https://example.com/video.m3u8',
      thumbnailUrl: 'https://example.com/thumb.jpg',
      videoType: 'yog',
      uploadedAt: DateTime.now(),
      likes: 0,
      views: 0,
      shares: 0,
      likedBy: [],
      aspectRatio: 9 / 16,
      duration: const Duration(minutes: 1),
    );

    when(() => mockVideoService.getUserVideos(any(),
            forceRefresh: any(named: 'forceRefresh'),
            page: any(named: 'page'),
            limit: any(named: 'limit')))
        .thenAnswer((_) async => [testVideo]);

    // Mock successful deletion
    when(() => mockVideoService.deleteVideos(any())).thenAnswer((_) async => 1);
  });

  testWidgets('Video deletion flow test - success', (WidgetTester tester) async {
    final robot = ProfileRobot(tester);

    // 1. Load the ProfileScreen
    await tester.pumpWidget(
      TestAppWrapper(
        mockAuthService: mockAuthService,
        mockVideoService: mockVideoService,
        mockFilePickerService: mockFilePickerService,
        mockAdService: mockAdService,
        child: const ProfileScreen(),
      ),
    );

    // Wait for the mock data to load
    await tester.pumpAndSettle();

    // 2. Verify video is present initially
    expect(find.text('Test Video to Delete'), findsOneWidget);

    // 3. Long-press the video to enter selection mode
    await robot.longPressVideoCard(0);

    // 4. Tap the delete button in the toolbar
    await robot.tapDeleteButton();

    // 5. Confirm deletion in the dialog
    await robot.confirmDeletion();

    // 6. Verify that the delete API was called with the correct ID
    verify(() => mockVideoService.deleteVideos(['test-video-id'])).called(1);

    // 7. Mock the updated list (empty after deletion)
    when(() => mockVideoService.getUserVideos(any(),
            forceRefresh: any(named: 'forceRefresh'),
            page: any(named: 'page'),
            limit: any(named: 'limit')))
        .thenAnswer((_) async => []);

    // Trigger UI update simulated after deletion success
    await tester.pumpAndSettle();

    // 8. Verify video is gone and "No videos yet" is visible
    expect(find.text('Test Video to Delete'), findsNothing);
    robot.verifyNoVideosMessageVisible();
  });
}
