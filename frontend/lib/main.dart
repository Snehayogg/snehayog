import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart'; // Ensure Firebase is imported
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/rendering.dart';
import 'dart:async';
import 'package:vayu/features/video/feed/presentation/screens/homescreen.dart';
import 'package:vayu/features/onboarding/presentation/screens/splash_screen.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:vayu/features/video/core/presentation/screens/video_screen.dart';
import 'package:vayu/shared/managers/hot_ui_state_manager.dart';
import 'package:vayu/core/design/theme.dart';
import 'package:vayu/features/auth/data/services/authservices.dart';
import 'package:vayu/features/profile/data/services/background_profile_preloader.dart';
import 'package:vayu/features/onboarding/data/services/location_onboarding_service.dart';
import 'package:vayu/features/onboarding/data/services/welcome_onboarding_service.dart';
import 'package:vayu/features/onboarding/data/services/gallery_permission_service.dart';
import 'package:vayu/features/onboarding/presentation/screens/welcome_onboarding_screen.dart';
import 'package:vayu/features/ads/data/services/ad_impression_service.dart';
import 'package:vayu/shared/utils/app_logger.dart';
import 'package:vayu/features/video/core/presentation/managers/shared_video_controller_pool.dart';
import 'package:vayu/features/video/core/presentation/managers/video_controller_manager.dart';
import 'package:vayu/core/providers/auth_providers.dart';
import 'package:vayu/core/providers/navigation_providers.dart';
import 'package:vayu/core/providers/video_providers.dart';
import 'package:vayu/shared/services/error_logging_service.dart';
import 'package:vayu/shared/services/deep_link_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Enable Edge-to-Edge display
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false, // Prevents Android from adding black background
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarDividerColor: Colors.transparent, 
    ),
  );

  debugRepaintRainbowEnabled = false;

  // **NEW: Ensure Firebase is initialized (if not already handled elsewhere)**
  try {
    await Firebase.initializeApp();
    
    // **NEW: Crashlytics Integration**
    // Pass all uncaught "fatal" errors from the framework to Crashlytics
    FlutterError.onError = (errorDetails) {
      FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
    };

    // Pass all uncaught asynchronous errors that aren't handled by the Flutter framework to Crashlytics
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  } catch (e) {
    debugPrint('Firebase initialization error: $e');
  }
  
  // **OPTIMIZATION: Limit Image Cache for Low-RAM devices**
  // 100MB limit (default is 1000MB which is too high for 3GB RAM phones)
  PaintingBinding.instance.imageCache.maximumSizeBytes = 100 * 1024 * 1024; 

  // **NEW: Initialize Ad Impression Service for offline syncing**
  
  AdImpressionService().initialize();

  // **STAGE 1: BASIC CONFIG (Moved to Splash Screen for Parallelism)**
  // await AppInitializationManager.instance.initializeStage1();

  // **OPTIMIZED: Start app immediately**
  runApp(
    ProviderScope(
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (context, child) => const MyApp(),
      ),
    ),
  );
}
// Removed redundant _checkServerConnectivity and _initializeServicesInBackground (moved to Manager)

// _splashPrefetch removed (logic moved to AppInitializationManager)

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ErrorLoggingService.logAppLifecycle('started');
    
    // Initialize Deep Link Service
    DeepLinkService().initialize();
  }

  @override
  void dispose() {
    DeepLinkService().dispose();
    _sub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final mainController = ref.read(mainControllerProvider);
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
        ref.read(videoProvider).saveStaleVideos();
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
        ref.read(videoProvider).saveStaleVideos();
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
           ref.read(videoProvider).saveStaleVideos();
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
        final mainController = ref.read(mainControllerProvider);
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



  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: AuthService.navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Vayug',
      theme: AppTheme.lightTheme,
      navigatorObservers: [AppNavigatorObserver()],
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
      home: const SplashScreen(),
    );
  }
}

class AuthWrapper extends ConsumerStatefulWidget {
  const AuthWrapper({super.key});

  @override
  ConsumerState<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends ConsumerState<AuthWrapper> {
  @override
  void initState() {
    super.initState();
    // Start auth check in background (non-blocking)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authController = ref.read(googleSignInProvider);
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
class MainScreenWithLocationCheck extends ConsumerStatefulWidget {
  const MainScreenWithLocationCheck({super.key});

  @override
  ConsumerState<MainScreenWithLocationCheck> createState() =>
      _MainScreenWithLocationCheckState();
}

class _MainScreenWithLocationCheckState
    extends ConsumerState<MainScreenWithLocationCheck> {
  bool _hasCheckedLocation = false;
  bool _hasCheckedGallery = false;
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

        // If not showing welcome, check permissions in background
        if (!shouldShow) {
          _checkLocationInBackground();
          _checkGalleryInBackground();
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
    // Check permissions in background after welcome screen
    _checkLocationInBackground();
    _checkGalleryInBackground();
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

  /// **Check gallery permission in background**
  Future<void> _checkGalleryInBackground() async {
    if (_hasCheckedGallery) return;
    _hasCheckedGallery = true;

    try {
      final shouldShow = await GalleryPermissionService.shouldShowGalleryOnboarding();

      if (shouldShow && mounted) {
        // Wait 2 seconds (1s after location potentially starts)
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            GalleryPermissionService.requestGalleryPermission();
          }
        });
      }
    } catch (e) {
      AppLogger.log('❌ Main: Error checking gallery permission: $e');
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

class AppNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    AppLogger.log('🚀 NAV: Pushed ${route.settings.name} (Previous: ${previousRoute?.settings.name})');
    if (route.settings.name == '/') {
       AppLogger.log('⚠️ NAV ALERT: Pushed root (Splash?) route! StackTrace:');
       AppLogger.log(StackTrace.current.toString().split('\n').take(10).join('\n'));
    }

    // **AUTO-PAUSE: Pause all playing videos whenever a new route is pushed**
    // This prevents audio leaks during any navigation transition globally
    if (previousRoute != null) {
      _pauseAllVideos();
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    AppLogger.log('🚀 NAV: Replaced ${oldRoute?.settings.name} with ${newRoute?.settings.name}');
    if (newRoute?.settings.name == '/') {
       AppLogger.log('⚠️ NAV ALERT: Replaced with root (Splash?) route! StackTrace:');
       AppLogger.log(StackTrace.current.toString().split('\n').take(10).join('\n'));
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    AppLogger.log('🚀 NAV: Popped ${route.settings.name} (Now on: ${previousRoute?.settings.name})');
    // **ROUTE-POP FIX: Notify the Yug feed to re-validate its video controllers.**
    // When a profile-launched VideoFeedAdvanced is popped, it fully disposes its
    // controllers. The Yug feed still has stale references → "Bad state: No active
    // player with ID N". This triggers _validateAndRestoreControllers() on the Yug feed.
    try {
      VideoControllerManager().notifyRoutePopped();
    } catch (_) {}
  }

  /// Pause all videos using singleton controllers (no BuildContext needed)
  void _pauseAllVideos() {
    try {
      SharedVideoControllerPool().pauseAllControllers();
      VideoControllerManager().forcePauseAllVideosSync();
    } catch (_) {}
  }
}

