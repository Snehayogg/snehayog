import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snehayog/controller/profileController.dart';
import 'controller/main_controller.dart';
import 'package:snehayog/view/homescreen.dart';
import 'package:snehayog/services/authservices.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AuthService authService = AuthService();
  bool isLoggedIn = await authService.isLoggedIn();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ProfileController()),
        ChangeNotifierProvider(create: (_) => MainController()),
      ],
      child: MyApp(loggedIn: isLoggedIn),
    ),
  );
}

class MyApp extends StatelessWidget {
  final bool loggedIn;
  const MyApp({required this.loggedIn, super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MainScreen(),
    );
  }
}
