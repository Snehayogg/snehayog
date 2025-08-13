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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
    debugPrint("App started");
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
        debugPrint("🟢 App Resumed");
        mainController.setAppInForeground(true);
        break;
      case AppLifecycleState.inactive:
        debugPrint("🔘 App Inactive");
        break;
      case AppLifecycleState.paused:
        debugPrint("🟡 App Paused");
        mainController.setAppInForeground(false);
        break;
      case AppLifecycleState.detached:
        debugPrint("🔴 App Detached");
        break;
      case AppLifecycleState.hidden:
        debugPrint("⚫ App Hidden");
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: VideoService.navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Snehayog',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF424242),
          secondary: Color(0xFF757575),
          surface: Colors.white,
          error: Colors.black,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: Color(0xFF424242),
          onError: Colors.white,
        ),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF424242),
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.dark,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF424242),
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8.r),
            ),
          ),
        ),
        textTheme: TextTheme(
          bodyLarge: TextStyle(color: const Color(0xFF424242), fontSize: 16.sp),
          bodyMedium:
              TextStyle(color: const Color(0xFF757575), fontSize: 14.sp),
          titleLarge: TextStyle(color: Colors.black, fontSize: 20.sp),
        ),
      ),
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
