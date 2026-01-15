import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:vayu/view/homescreen.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:vayu/controller/google_sign_in_controller.dart';
import 'package:vayu/controller/main_controller.dart';
import 'package:vayu/core/providers/video_provider.dart';
import 'package:vayu/core/providers/user_provider.dart';
import 'package:vayu/view/screens/video_screen.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:vayu/core/services/error_logging_service.dart';
import 'package:vayu/core/managers/hot_ui_state_manager.dart';
import 'package:vayu/core/theme/app_theme.dart';
import 'package:vayu/config/app_config.dart';
import 'package:app_links/app_links.dart';
import 'package:vayu/services/video_service.dart' as vsvc;
import 'package:vayu/core/services/hls_warmup_service.dart';
import 'package:vayu/core/managers/smart_cache_manager.dart';
import 'package:vayu/model/video_model.dart';
import 'package:vayu/services/notification_service.dart';
import 'package:vayu/services/authservices.dart';
import 'package:vayu/services/background_profile_preloader.dart';
import 'package:vayu/services/location_onboarding_service.dart';
import 'package:vayu/services/welcome_onboarding_service.dart';
import 'package:vayu/view/screens/welcome_onboarding_screen.dart';
import 'package:vayu/core/services/http_client_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayu/core/managers/shared_video_controller_pool.dart';
import 'package:vayu/core/managers/video_controller_manager.dart';
import 'package:vayu/utils/app_logger.dart';
import 'package:vayu/services/app_remote_config_service.dart';
import 'package:vayu/services/video_cache_proxy_service.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // **NEW: Initialize Video Cache Proxy for persistent caching**
  await videoCacheProxy.initialize();

  // **NEW: Initialize Hive for Instant Data Loading**
  await Hive.initFlutter();
  await Hive.openBox('video_feed_cache');

  // **SPLASH PREFETCH: Start network calls immediately while splash is visible**
  // This runs in parallel with app startup to ensure fresh data is ready ASAP
  unawaited(_splashPrefetch());

  // **OPTIMIZED: Firebase and notifications enabled**
  try {
    await Firebase.initializeApp();
    final notificationService = NotificationService();
    unawaited(notificationService.initialize()); // Initialize in background
  } catch (e) {
    print('Error initializing Firebase: $e');
  }

  // **OPTIMIZED: Start app immediately, initialize services in background**
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => GoogleSignInController()),
        ChangeNotifierProvider(create: (_) => MainController()),
        ChangeNotifierProvider(create: (_) => VideoProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        Provider(create: (_) => AuthService()),
      ],
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (context, child) => const MyApp(),
      ),
    ),
  );

  // **BACKGROUND: Initialize heavy services after app starts**
  // **OPTIMIZED: Delay heavy initialization to let UI settle first (Fixes startup lag/audio break)**
  Future.delayed(const Duration(seconds: 3), () {
     _initializeServicesInBackground();
  });

  // **OPTIMIZED: Check server connectivity non-blocking (don't wait for it)**
  unawaited(_checkServerConnectivity());
}

/// **OPTIMIZED: Check server connectivity and set optimal URL (non-blocking)**
Future<void> _checkServerConnectivity() async {
  try {

    // Clear any cached URLs to force fresh check
    AppConfig.clearCache();
    final workingUrl = await AppConfig.checkAndUpdateServerUrl();


    // In development mode, verify local server is accessible
    if (workingUrl.contains('192.168') ||
        workingUrl.contains('localhost') ||
        workingUrl.contains('127.0.0.1')) {

    }
  } catch (e) {

  }
}

/// **OPTIMIZED: Initialize heavy services in background**
void _initializeServicesInBackground() async {
  try {
    // **NEW: Initialize backend-driven config first (non-blocking)**
    unawaited(AppRemoteConfigService.instance.initialize().then((_) {

    }).catchError((e) {

    }));

    // **OPTIMIZED: Initialize AdMob non-blocking (don't wait for it)**
    unawaited(() async {
      try {
        await MobileAds.instance.initialize();

        // Configure AdMob RequestConfiguration for better ad loading
        // This helps with ad delivery and debugging
        try {
          final requestConfiguration = RequestConfiguration(
            // In release builds, real ads will be served
            // Test device IDs can be added here if needed for testing
            testDeviceIds: kDebugMode ? [] : [], // Empty in release = real ads
          );
          await MobileAds.instance
              .updateRequestConfiguration(requestConfiguration);

        } catch (e) {

        }

        ErrorLoggingService.logServiceInitialization('AdMob');

      } catch (e) {

      }
    }());

    // Set orientation in background
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);



    // **CLEANUP: Perform periodic proxy cache cleanup (LOW PRIORITY)**
    // Delay further to ensure it doesn't compete with video playback
    Future.delayed(const Duration(seconds: 5), () {
       unawaited(videoCacheProxy.cleanCache());
    });

    // Splash-time prefetch: fetch first page and warm up first few videos
    // This is less critical now that we have "Instant Splash" from Hive
    // Splash-time prefetch has been moved to main() for earlier execution
    // unawaited(_splashPrefetch());
  } catch (e) {

  }
}

/// Prefetch first page of videos and warm HLS while splash/logo is visible
Future<void> _splashPrefetch() async {
  try {
    final videoService = vsvc.VideoService();
    final cacheManager = SmartCacheManager();
    await cacheManager.initialize();

    unawaited(() async {
      try {
        final base = await vsvc.VideoService.getBaseUrlWithFallback();
        await httpClientService.get(
          Uri.parse('$base/api/health'),
          timeout: const Duration(seconds: 3),
        );

      } catch (_) {}
    }());

    // **ENHANCED: Cache Yug tab videos (most common tab) for instant loading**
    const yogCacheKey = 'videos_page_1_yog';
    final yogResult = await cacheManager.get<Map<String, dynamic>>(
      yogCacheKey,
      fetchFn: () async {

        return await videoService.getVideos(
            page: 1,
            limit: 10,
            videoType: 'yog'); // Increased limit for better cache
      },
      cacheType: 'videos',
      maxAge: const Duration(minutes: 15), // Cache for 15 minutes
    );

    if (yogResult != null) {
      final List<VideoModel> videos =
          (yogResult['videos'] as List<dynamic>).cast<VideoModel>();


      // **NEW: Pre-initialize first video controller for instant playback**
      if (videos.isNotEmpty) {
        try {
          final firstVideo = videos.first;
          final controllerManager = VideoControllerManager();
          // Pre-create controller for faster first video load
          unawaited(controllerManager.preloadController(0, firstVideo));

        } catch (e) {

        }
      }

      // Warm-up manifests for first few HLS URLs
      for (final video in videos.take(3)) {
        final url = video.hlsPlaylistUrl?.isNotEmpty == true
            ? video.hlsPlaylistUrl!
            : (video.hlsMasterPlaylistUrl?.isNotEmpty == true
                ? video.hlsMasterPlaylistUrl!
                : video.videoUrl);
        if (url.contains('.m3u8')) {
          unawaited(HlsWarmupService().warmUp(url));
        }

        // **NEW: Persistent chunk caching for instant reload**
        unawaited(videoCacheProxy.prefetchChunk(url));
        
        // **OPTIMIZED: Throttle warmup to avoid CPU spikes during playback**
        // Yield to main thread between heavy network/disk ops
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }

    // **OPTIONAL: Also preload Vayu tab videos in background (non-blocking)**
    unawaited(() async {
      try {
        const vayuCacheKey = 'videos_page_1_vayu';
        await cacheManager.get<Map<String, dynamic>>(
          vayuCacheKey,
          fetchFn: () async {
            return await videoService.getVideos(
                page: 1, limit: 10, videoType: 'vayu');
          },
          cacheType: 'videos',
          maxAge: const Duration(minutes: 15),
        );

      } catch (e) {

      }
    }());
  } catch (e) {

    // Best-effort prefetch; ignore failures
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ErrorLoggingService.logAppLifecycle('started');

    _initUniLinks();
  }

  @override
  void dispose() {
    _sub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final mainController = Provider.of<MainController>(context, listen: false);
    final hotUIManager = HotUIStateManager();

    switch (state) {
      case AppLifecycleState.resumed:
        ErrorLoggingService.logAppLifecycle('Resumed');
        mainController.setAppInForeground(true);
        hotUIManager.handleAppLifecycleChange(state);
        // **NEW: Restore tab index when app resumes (if different from current)**
        mainController.restoreLastTabIndex().then((restoredIndex) {
          // restoreLastTabIndex already sets _currentIndex and notifies
          // Just ensure UI reflects the change if needed
          if (restoredIndex != mainController.currentIndex) {
            // This shouldn't happen as restoreLastTabIndex sets it, but safety check
            mainController.changeIndex(restoredIndex);
          }
        });
        break;
      case AppLifecycleState.inactive:
        ErrorLoggingService.logAppLifecycle('Inactive');
        // **NEW: Save tab index when app becomes inactive (going to background)**
        mainController.saveStateForBackground();
        // **NEW: Pause all videos when app becomes inactive**
        _pauseAllVideosGlobally();
        // **AGGRESSIVE CACHING: Save stale videos for next cold start**
        Provider.of<VideoProvider>(context, listen: false).saveStaleVideos();
        hotUIManager.handleAppLifecycleChange(state);
        break;
      case AppLifecycleState.paused:
        ErrorLoggingService.logAppLifecycle('Paused');
        mainController.setAppInForeground(false);
        // **NEW: Save tab index when app is paused (minimized)**
        mainController.saveStateForBackground();
        // **NEW: Pause all videos when app is paused (minimized)**
        _pauseAllVideosGlobally();
        // **AGGRESSIVE CACHING: Save stale videos for next cold start**
        Provider.of<VideoProvider>(context, listen: false).saveStaleVideos();
        // **HOT UI: Preserve state when app goes to background**
        hotUIManager.handleAppLifecycleChange(state);
        break;
      case AppLifecycleState.detached:
        ErrorLoggingService.logAppLifecycle('Detached');
        // **NEW: Pause all videos when app is detached**
        _pauseAllVideosGlobally();
        // **AGGRESSIVE CACHING: Save stale videos for next cold start**
        // Note: Context might be unstable here, but worth a try
        try {
           Provider.of<VideoProvider>(context, listen: false).saveStaleVideos();
        } catch (_) {}
        hotUIManager.handleAppLifecycleChange(state);
        break;
      case AppLifecycleState.hidden:
        ErrorLoggingService.logAppLifecycle('Hidden');
        // **NEW: Pause all videos when app is hidden**
        _pauseAllVideosGlobally();
        break;
    }
  }

  /// **NEW: Pause all videos globally regardless of which screen user is on**
  void _pauseAllVideosGlobally() {
    try {
      AppLogger.log('⏸️ MyApp: Pausing all videos globally (app minimized)');

      // 1. Pause videos from MainController
      try {
        final mainController =
            Provider.of<MainController>(context, listen: false);
        mainController.forcePauseVideos();
        AppLogger.log('✅ MyApp: Paused videos via MainController');
      } catch (e) {
        AppLogger.log('⚠️ MyApp: Error pausing via MainController: $e');
      }

      // 2. Pause videos from SharedVideoControllerPool (singleton - used across all screens)
      try {
        final sharedPool = SharedVideoControllerPool();
        sharedPool.pauseAllControllers();
        AppLogger.log(
            '✅ MyApp: Paused all videos from SharedVideoControllerPool');
      } catch (e) {
        AppLogger.log('⚠️ MyApp: Error pausing SharedVideoControllerPool: $e');
      }

      // 3. Pause videos from VideoControllerManager (singleton)
      try {
        final videoManager = VideoControllerManager();
        videoManager.onAppPaused();
        AppLogger.log('✅ MyApp: Paused videos via VideoControllerManager');
      } catch (e) {
        AppLogger.log('⚠️ MyApp: Error pausing VideoControllerManager: $e');
      }

      AppLogger.log('✅ MyApp: All videos paused globally');
    } catch (e) {
      AppLogger.log('❌ MyApp: Error pausing videos globally: $e');
    }
  }

  Future<void> _initUniLinks() async {
    final appLinks = AppLinks();

    // Handle initial link if app launched from deep link
    try {
      final initial = await appLinks.getInitialLink();
      if (initial != null) {
        _handleIncomingUri(initial);
      }
    } catch (e) {

    }

    // Listen for links while app is running
    _sub = appLinks.uriLinkStream.listen((Uri uri) {
      _handleIncomingUri(uri);
    }, onError: (err) {

    });
  }

  Future<void> _handleIncomingUri(Uri uri) async {


    // **FIX: Handle referral code from query parameters**
    final referralCode = uri.queryParameters['ref'];
    if (referralCode != null && referralCode.isNotEmpty) {

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('pending_referral_code', referralCode);

      } catch (e) {

      }
    }

    // **OPTIMIZED: Razorpay payment callback disabled (not in use)**
    // TODO: Uncomment when payment system is active
    // if (uri.scheme == 'snehayog' && uri.host == 'payment-callback') {
    //   final orderId = uri.queryParameters['razorpay_order_id'] ?? '';
    //   final paymentId = uri.queryParameters['razorpay_payment_id'] ?? '';
    //   final signature = uri.queryParameters['razorpay_signature'] ?? '';
    //
    //   if (orderId.isEmpty || paymentId.isEmpty || signature.isEmpty) {
    //     if (mounted) {
    //       ScaffoldMessenger.of(context).showSnackBar(
    //         const SnackBar(
    //           content: Text('Payment callback missing data'),
    //           backgroundColor: Colors.red,
    //         ),
    //       );
    //     }
    //     return;
    //   }
    //
    //   // Razorpay payment verification removed - service not available
    //   if (mounted) {
    //     ScaffoldMessenger.of(context).showSnackBar(
    //       const SnackBar(
    //         content: Text('Payment verification not available'),
    //         backgroundColor: Colors.orange,
    //       ),
    //     );
    //   }
    // }

    // Handle video deep links
    else if ((uri.scheme == 'snehayog' && uri.host == 'video') ||
        (uri.scheme == 'https' &&
            uri.host == 'snehayog.site' &&
            (uri.path.startsWith('/video') || uri.path == '/'))) {
      // **ENHANCED: Robust video ID extraction from deep links**
      String? videoId;

      // **METHOD 1: Try query parameter first (e.g., ?id=abc123)**
      if (uri.queryParameters.containsKey('id')) {
        videoId = uri.queryParameters['id']?.trim();
        if (videoId?.isNotEmpty == true) {
  
        }
      }

      // **METHOD 2: Try path segments (e.g., /video/abc123)**
      if ((videoId == null || videoId.isEmpty) && uri.pathSegments.isNotEmpty) {
        final segments = uri.pathSegments;

        // Find 'video' segment and get the next segment as ID
        final videoIndex =
            segments.indexWhere((s) => s.toLowerCase() == 'video');
        if (videoIndex != -1 && videoIndex < segments.length - 1) {
          videoId = segments[videoIndex + 1].trim();

        } else if (segments.isNotEmpty) {
          // Fallback: use last segment if it's not 'video'
          final lastSegment = segments.last;
          if (lastSegment.isNotEmpty &&
              lastSegment.toLowerCase() != 'video' &&
              lastSegment != '/') {
            videoId = lastSegment.trim();

          }
        }
      }

      // **METHOD 3: Extract from full path string (e.g., /video/abc123)**
      if ((videoId == null || videoId.isEmpty) && uri.path.isNotEmpty) {
        final pathParts =
            uri.path.split('/').where((p) => p.isNotEmpty).toList();
        if (pathParts.isNotEmpty) {
          final videoIndex =
              pathParts.indexWhere((p) => p.toLowerCase() == 'video');
          if (videoIndex != -1 && videoIndex < pathParts.length - 1) {
            videoId = pathParts[videoIndex + 1].trim();

          } else if (pathParts.length == 1 &&
              pathParts[0].toLowerCase() != 'video') {
            // Single segment that's not 'video' might be the ID
            videoId = pathParts[0].trim();

          }
        }
      }

      // **VALIDATION: Ensure video ID is valid**
      if (videoId != null && videoId.isNotEmpty && videoId != '/') {

        _navigateToVideo(videoId);
      } else {
        // If it's a referral root link without a specific video, just open home

        if (mounted) Navigator.pushNamed(context, '/home');
      }
    }
    // **FIX: Handle root URL with referral code**
    else if (uri.scheme == 'https' &&
        uri.host == 'snehayog.site' &&
        (uri.path == '/' || uri.path.isEmpty) &&
        referralCode != null) {

      if (mounted) Navigator.pushNamed(context, '/home');
    }
  }

  void _navigateToVideo(String videoId) {
    if (!mounted) return;

    // Navigate to video screen with the specific video ID
    Navigator.pushNamed(
      context,
      '/video',
      arguments: {'videoId': videoId},
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: AuthService.navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Vayug',
      theme: AppTheme.lightTheme,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.0)),
          child: child!,
        );
      },
      routes: {
        '/home': (context) => const MainScreen(),
        '/video': (context) {
          final args = ModalRoute.of(context)?.settings.arguments
              as Map<String, dynamic>?;
          final videoId = args?['videoId'] as String?;
          return VideoScreen(initialVideoId: videoId);
        },
      },
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  void initState() {
    super.initState();
    // Start auth check in background (non-blocking)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authController =
          Provider.of<GoogleSignInController>(context, listen: false);
      authController.checkAuthStatus();

      // **BACKGROUND PRELOADING: Preload profile data after authentication check**
      _startBackgroundPreloadingIfAuthenticated();
    });
  }

  /// **Start background preloading if user is authenticated**
  Future<void> _startBackgroundPreloadingIfAuthenticated() async {
    try {
      final authService = AuthService();
      final userData = await authService.getUserData();

      if (userData != null) {

        final preloader = BackgroundProfilePreloader();
        unawaited(preloader.forcePreload()); // Non-blocking
      } else {

      }
    } catch (e) {

    }
  }

  @override
  Widget build(BuildContext context) {
    // **ALWAYS: Show MainScreen directly, skip login screen entirely**
    // Users can access login from settings/profile if needed
    return const MainScreenWithLocationCheck();
  }
}

/// **NEW: MainScreen with background location check**
class MainScreenWithLocationCheck extends StatefulWidget {
  const MainScreenWithLocationCheck({super.key});

  @override
  State<MainScreenWithLocationCheck> createState() =>
      _MainScreenWithLocationCheckState();
}

class _MainScreenWithLocationCheckState
    extends State<MainScreenWithLocationCheck> {
  bool _hasCheckedLocation = false;
  bool _hasCheckedWelcome = false;
  bool _shouldShowWelcome = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // **CHECK: Check if welcome onboarding should be shown FIRST**
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkWelcomeOnboarding();
    });
  }

  /// **Check if welcome onboarding should be shown**
  Future<void> _checkWelcomeOnboarding() async {
    if (_hasCheckedWelcome) return;
    _hasCheckedWelcome = true;

    try {

      final shouldShow =
          await WelcomeOnboardingService.shouldShowWelcomeOnboarding();

      if (mounted) {
        setState(() {
          _shouldShowWelcome = shouldShow;
          _isLoading = false;
        });

        // If not showing welcome, check location in background
        if (!shouldShow) {
          _checkLocationInBackground();
        }
      }
    } catch (e) {

      if (mounted) {
        setState(() {
          _shouldShowWelcome = false;
          _isLoading = false;
        });
        _checkLocationInBackground();
      }
    }
  }

  /// **Handle Get Started button click**
  void _handleGetStarted() {
    setState(() {
      _shouldShowWelcome = false;
    });
    // Check location in background after welcome screen
    _checkLocationInBackground();
  }

  /// **Check location permission in background without blocking UI**
  Future<void> _checkLocationInBackground() async {
    if (_hasCheckedLocation) return;
    _hasCheckedLocation = true;

    try {


      // Check if we should show location onboarding
      final shouldShow =
          await LocationOnboardingService.shouldShowLocationOnboarding();



      // If we should show the native permission dialog, show it after a delay
      if (shouldShow && mounted) {
        // Wait a bit so user sees the main screen first
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            _requestLocationPermission();
          }
        });
      }
    } catch (e) {

    }
  }

  /// **Request location permission and show dialog if needed**
  Future<void> _requestLocationPermission() async {
    if (!mounted) return;

    try {


      // Check current permission status first
      final hasPermission =
          await LocationOnboardingService.isLocationPermissionGranted();

      if (!hasPermission) {
        // Show location onboarding dialog
        final granted =
            await LocationOnboardingService.showLocationOnboarding(context);



        if (granted) {

        } else {

        }
      } else {

      }
    } catch (e) {

    }
  }

  @override
  Widget build(BuildContext context) {
    // **SHOW: Welcome onboarding screen if user hasn't seen it yet**
    if (_isLoading) {
      // Show MainScreen while checking (brief moment)
      return const MainScreen();
    }

    if (_shouldShowWelcome) {
      return WelcomeOnboardingScreen(
        onGetStarted: _handleGetStarted,
      );
    }

    // **INSTANT: Show MainScreen, location check happens in background**
    return const MainScreen();
  }
}
