import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:snehayog/controller/main_controller.dart';
import 'package:snehayog/view/homescreen.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:snehayog/controller/google_sign_in_controller.dart';
import 'package:snehayog/view/screens/login_screen.dart';
import 'package:snehayog/services/video_service.dart';

/// Main entry point of the application
/// This file serves as the application's bootstrap and configuration
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => GoogleSignInController()),
        ChangeNotifierProvider(create: (_) => MainController()),
      ],
      child: ScreenUtilInit(
        designSize: const Size(375, 812), // iPhone X design size
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (context, child) => const MyApp(),
      ),
    ),
  );
}

/// Root widget of the application
/// Implements the MVC pattern where:
/// - Model: Data models in /model directory
/// - View: UI components in /view directory
/// - Controller: Business logic in /controller directory
class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
          primary: Color(0xFF424242), // Dark Grey
          secondary: Color(0xFF757575), // Medium Grey
          surface: Colors.white, // White
          error: Colors.black, // Black
          onPrimary: Colors.white, // White
          onSecondary: Colors.white, // White
          onSurface: Color(0xFF424242), // Dark Grey
          onError: Colors.white, // White
        ),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF424242), // Dark Grey
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.dark,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF424242), // Dark Grey
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8.r),
            ),
          ),
        ),
        textTheme: TextTheme(
          bodyLarge: TextStyle(
              color: const Color(0xFF424242), fontSize: 16.sp), // Dark Grey
          bodyMedium: TextStyle(
              color: const Color(0xFF757575), fontSize: 14.sp), // Medium Grey
          titleLarge: TextStyle(color: Colors.black, fontSize: 20.sp), // Black
        ),
      ),
      builder: (context, child) {
        // Ensure consistent text scaling
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.0)),
          child: child!,
        );
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
            body: Center(
              child: CircularProgressIndicator(),
            ),
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
