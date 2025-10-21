import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:snehayog/view/homescreen.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:snehayog/controller/google_sign_in_controller.dart';
import 'package:snehayog/controller/main_controller.dart';
import 'package:snehayog/core/providers/video_provider.dart';
import 'package:snehayog/core/providers/user_provider.dart';
import 'package:snehayog/view/screens/login_screen.dart';
import 'package:snehayog/view/screens/video_screen.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:snehayog/core/services/error_logging_service.dart';
import 'package:snehayog/core/managers/hot_ui_state_manager.dart';
import 'package:snehayog/core/theme/app_theme.dart';
import 'package:snehayog_monetization/services/razorpay_service.dart';
import 'package:snehayog/config/app_config.dart';
import 'package:app_links/app_links.dart';
import 'package:snehayog/services/video_service.dart' as vsvc;
import 'package:snehayog/core/services/hls_warmup_service.dart';
import 'package:snehayog/core/managers/smart_cache_manager.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/services/authservices.dart';
import 'package:snehayog/services/background_profile_preloader.dart';
import 'package:snehayog/services/location_onboarding_service.dart';

final RazorpayService razorpayService = RazorpayService();

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

    // Initialize Razorpay in background
    razorpayService.initialize(
      keyId: AppConfig.razorpayKeyId,
      keySecret: AppConfig.razorpayKeySecret,
      webhookSecret: AppConfig.razorpayWebhookSecret,
      baseUrl: AppConfig.baseUrl,
    );

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

      try {
        final result = await razorpayService.verifyPaymentWithBackend(
          orderId: orderId,
          paymentId: paymentId,
          signature: signature,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Payment verified'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Verification failed: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
    // Handle video deep links
    else if ((uri.scheme == 'snehayog' && uri.host == 'video') ||
        (uri.scheme == 'https' &&
            uri.host == 'snehayog.app' &&
            uri.path.startsWith('/video'))) {
      final videoId = uri.queryParameters['id'] ?? uri.pathSegments.last;

      if (videoId.isNotEmpty) {
        print('🎬 Opening video with ID: $videoId');
        _navigateToVideo(videoId);
      } else {
        print('❌ No video ID found in deep link');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invalid video link'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
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
      title: 'Snehayog',
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
