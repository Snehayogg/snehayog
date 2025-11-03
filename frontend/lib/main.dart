import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:vayu/view/homescreen.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:vayu/controller/google_sign_in_controller.dart';
import 'package:vayu/controller/main_controller.dart';
import 'package:vayu/core/providers/video_provider.dart';
import 'package:vayu/core/providers/user_provider.dart';
import 'package:vayu/view/screens/login_screen.dart';
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
import 'package:vayu/services/authservices.dart';
import 'package:vayu/services/background_profile_preloader.dart';
import 'package:vayu/services/location_onboarding_service.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // **OPTIMIZED: Start app immediately, initialize services in background**
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => GoogleSignInController()),
        ChangeNotifierProvider(create: (_) => MainController()),
        ChangeNotifierProvider(create: (_) => VideoProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
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
  _initializeServicesInBackground();

  // **NEW: Check server connectivity and set optimal URL**
  _checkServerConnectivity();
}

/// **NEW: Check server connectivity and set optimal URL**
void _checkServerConnectivity() async {
  try {
    print('🔍 Main: Checking server connectivity...');
    // Clear any cached URLs to force fresh check
    AppConfig.clearCache();
    final workingUrl = await AppConfig.checkAndUpdateServerUrl();
    print('✅ Main: Using server URL: $workingUrl');
  } catch (e) {
    print('❌ Main: Error checking server connectivity: $e');
  }
}

/// **OPTIMIZED: Initialize heavy services in background**
void _initializeServicesInBackground() async {
  try {
    // Initialize AdMob in background
    await MobileAds.instance.initialize();
    ErrorLoggingService.logServiceInitialization('AdMob');

    // Set orientation in background
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    print('✅ Background services initialized successfully');

    // Splash-time prefetch: fetch first page and warm up first few videos
    unawaited(_splashPrefetch());
  } catch (e) {
    print('⚠️ Error initializing background services: $e');
  }
}

/// Prefetch first page of videos and warm HLS while splash/logo is visible
Future<void> _splashPrefetch() async {
  try {
    final videoService = vsvc.VideoService();
    final cacheManager = SmartCacheManager();
    await cacheManager.initialize();

    // Warm up TLS/DNS with a lightweight health ping (best-effort)
    unawaited(() async {
      try {
        final base = await vsvc.VideoService.getBaseUrlWithFallback();
        await http
            .get(Uri.parse('$base/api/health'))
            .timeout(const Duration(seconds: 3));
        print('✅ TLS warmup ok');
      } catch (_) {}
    }());

    // Cache the first page in SmartCacheManager for instant loading
    const cacheKey = 'videos_page_1_yog';
    final result = await cacheManager.get<Map<String, dynamic>>(
      cacheKey,
      fetchFn: () async {
        print('🚀 SplashPrefetch: Fetching first page for cache');
        return await videoService.getVideos(
            page: 1, limit: 6, videoType: 'yog');
      },
      cacheType: 'videos',
      maxAge: const Duration(minutes: 15), // Cache for 15 minutes
    );

    if (result != null) {
      final List<VideoModel> videos =
          (result['videos'] as List<dynamic>).cast<VideoModel>();
      print('✅ SplashPrefetch: Cached ${videos.length} videos');

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
      }
    }
  } catch (e) {
    print('⚠️ SplashPrefetch failed: $e');
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
        // **HOT UI: Restore state when app resumes**
        hotUIManager.handleAppLifecycleChange(state);
        break;
      case AppLifecycleState.inactive:
        ErrorLoggingService.logAppLifecycle('Inactive');
        hotUIManager.handleAppLifecycleChange(state);
        break;
      case AppLifecycleState.paused:
        ErrorLoggingService.logAppLifecycle('Paused');
        mainController.setAppInForeground(false);
        // **HOT UI: Preserve state when app goes to background**
        hotUIManager.handleAppLifecycleChange(state);
        break;
      case AppLifecycleState.detached:
        ErrorLoggingService.logAppLifecycle('Detached');
        hotUIManager.handleAppLifecycleChange(state);
        break;
      case AppLifecycleState.hidden:
        ErrorLoggingService.logAppLifecycle('Hidden');
        break;
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
      print('❌ Error getting initial URI: $e');
    }

    // Listen for links while app is running
    _sub = appLinks.uriLinkStream.listen((Uri uri) {
      _handleIncomingUri(uri);
    }, onError: (err) {
      print('❌ Deep link stream error: $err');
    });
  }

  Future<void> _handleIncomingUri(Uri uri) async {
    print('🔗 Deep link received: $uri');

    // **FIX: Handle referral code from query parameters**
    final referralCode = uri.queryParameters['ref'];
    if (referralCode != null && referralCode.isNotEmpty) {
      print('🎁 Referral code detected: $referralCode');
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('pending_referral_code', referralCode);
        print('✅ Referral code saved to SharedPreferences');
      } catch (e) {
        print('❌ Error saving referral code: $e');
      }
    }

    // Handle payment callback
    if (uri.scheme == 'snehayog' && uri.host == 'payment-callback') {
      final orderId = uri.queryParameters['razorpay_order_id'] ?? '';
      final paymentId = uri.queryParameters['razorpay_payment_id'] ?? '';
      final signature = uri.queryParameters['razorpay_signature'] ?? '';

      if (orderId.isEmpty || paymentId.isEmpty || signature.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Payment callback missing data'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Razorpay payment verification removed - service not available
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment verification not available'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
    // Handle video deep links
    else if ((uri.scheme == 'snehayog' && uri.host == 'video') ||
        (uri.scheme == 'https' &&
            uri.host == 'snehayog.site' &&
            (uri.path.startsWith('/video') || uri.path == '/'))) {
      final videoId = uri.queryParameters['id'] ?? uri.pathSegments.last;

      if (videoId.isNotEmpty && videoId != '/') {
        print('🎬 Opening video with ID: $videoId');
        _navigateToVideo(videoId);
      } else {
        // If it's a referral root link without a specific video, just open home
        print('ℹ️ Referral/root link received, opening home');
        if (mounted) Navigator.pushNamed(context, '/home');
      }
    }
    // **FIX: Handle root URL with referral code**
    else if (uri.scheme == 'https' &&
        uri.host == 'snehayog.site' &&
        (uri.path == '/' || uri.path.isEmpty) &&
        referralCode != null) {
      print('ℹ️ Root referral link received, opening home');
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
    // Force a check of authentication status when the widget initializes
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
        print(
            '✅ AuthWrapper: User is authenticated, starting background profile preloading');
        final preloader = BackgroundProfilePreloader();
        await preloader.forcePreload();
      } else {
        print(
            'ℹ️ AuthWrapper: User not authenticated, skipping background preloading');
      }
    } catch (e) {
      print('⚠️ AuthWrapper: Error starting background preloading: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GoogleSignInController>(
      builder: (context, authController, _) {
        // Show loading screen while checking authentication status
        if (authController.isLoading) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Checking authentication...'),
                ],
              ),
            ),
          );
        }

        // If user is signed in, check location permission and navigate to MainScreen
        if (authController.isSignedIn) {
          print(
              '✅ AuthWrapper: User is signed in, checking location permission');
          return const LocationPermissionWrapper();
        }

        // Show login screen if not signed in
        print('ℹ️ AuthWrapper: User is not signed in, showing LoginScreen');
        return const LoginScreen();
      },
    );
  }
}

class LocationPermissionWrapper extends StatefulWidget {
  const LocationPermissionWrapper({super.key});

  @override
  State<LocationPermissionWrapper> createState() =>
      _LocationPermissionWrapperState();
}

class _LocationPermissionWrapperState extends State<LocationPermissionWrapper> {
  bool _isCheckingLocation = true;

  @override
  void initState() {
    super.initState();
    _checkLocationPermission();
  }

  Future<void> _checkLocationPermission() async {
    try {
      print('📍 LocationPermissionWrapper: Checking location permission...');

      // Check if we should show location onboarding
      final shouldShow =
          await LocationOnboardingService.shouldShowLocationOnboarding();

      print(
          '📍 LocationPermissionWrapper: Should show location dialog: $shouldShow');

      setState(() {
        _isCheckingLocation = false;
      });

      // If we should show the native permission dialog, show it after a short delay
      if (shouldShow && mounted) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _requestNativeLocationPermission();
          }
        });
      }
    } catch (e) {
      print(
          '❌ LocationPermissionWrapper: Error checking location permission: $e');
      setState(() {
        _isCheckingLocation = false;
      });
    }
  }

  Future<void> _requestNativeLocationPermission() async {
    if (!mounted) return;

    try {
      print(
          '📍 LocationPermissionWrapper: Requesting native location permission...');

      // Use the native permission request directly
      final granted =
          await LocationOnboardingService.showLocationOnboarding(context);

      print('📍 LocationPermissionWrapper: Native permission result: $granted');

      if (granted) {
        print('✅ Location permission granted via native dialog');
      } else {
        print('❌ Location permission denied via native dialog');
      }
    } catch (e) {
      print(
          '❌ LocationPermissionWrapper: Error requesting native permission: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading while checking location permission
    if (_isCheckingLocation) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Checking location permission...'),
            ],
          ),
        ),
      );
    }

    // Show main screen
    return const MainScreen();
  }
}
