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
import 'package:snehayog/services/video_service.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:snehayog/core/services/error_logging_service.dart';
import 'package:snehayog/core/theme/app_theme.dart';
import 'package:snehayog_monetization/services/razorpay_service.dart';
import 'package:snehayog/config/app_config.dart';
import 'package:app_links/app_links.dart';

// Shared instance for Razorpay
final RazorpayService razorpayService = RazorpayService();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize AdMob
  await MobileAds.instance.initialize();
  ErrorLoggingService.logServiceInitialization('AdMob');

  // Initialize Razorpay
  razorpayService.initialize(
    keyId: AppConfig.razorpayKeyId,
    keySecret: AppConfig.razorpayKeySecret,
    webhookSecret: AppConfig.razorpayWebhookSecret,
    baseUrl: AppConfig.baseUrl,
  );

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

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

    switch (state) {
      case AppLifecycleState.resumed:
        ErrorLoggingService.logAppLifecycle('Resumed');
        mainController.setAppInForeground(true);
        break;
      case AppLifecycleState.inactive:
        ErrorLoggingService.logAppLifecycle('Inactive');
        break;
      case AppLifecycleState.paused:
        ErrorLoggingService.logAppLifecycle('Paused');
        mainController.setAppInForeground(false);
        break;
      case AppLifecycleState.detached:
        ErrorLoggingService.logAppLifecycle('Detached');
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
      final initial = await appLinks.getInitialAppLink();
      if (initial != null) {
        _handleIncomingUri(initial);
      }
    } catch (_) {}

    // Listen for links while app is running
    _sub = appLinks.uriLinkStream.listen((Uri? uri) {
      if (uri != null) {
        _handleIncomingUri(uri);
      }
    }, onError: (err) {});
  }

  Future<void> _handleIncomingUri(Uri uri) async {
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
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: VideoService.navigatorKey,
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
      },
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<GoogleSignInController>(
      builder: (context, authController, _) {
        if (authController.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (authController.isSignedIn) {
          return const MainScreen();
        }

        return const LoginScreen();
      },
    );
  }
}
