import 'package:flutter/material.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize AdMob
  await MobileAds.instance.initialize();
  ErrorLoggingService.logServiceInitialization('AdMob');

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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ErrorLoggingService.logAppLifecycle('started');
  }

  @override
  void dispose() {
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
