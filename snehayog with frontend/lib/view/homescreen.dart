import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snehayog/view/screens/profile_screen.dart';
import 'package:snehayog/view/screens/long_video.dart';
import 'package:snehayog/view/screens/upload_screen.dart';
import 'package:snehayog/view/screens/video_screen.dart'; // Import your actual VideoScreen
import 'package:snehayog/controller/main_controller.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final _videoScreenKey = GlobalKey<
      State<VideoScreen>>(); // Use State<VideoScreen> as the type parameter
  final int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Consumer<MainController>(
      builder: (context, controller, _) {
        return Scaffold(
          backgroundColor: Colors.white,
          body: IndexedStack(
            index: _currentIndex,
            children: [
              VideoScreen(key: _videoScreenKey),
              const SnehaScreen(key: PageStorageKey('snehaScreen')),
              const UploadScreen(key: PageStorageKey('uploadScreen')),
              const ProfileScreen(key: PageStorageKey('profileScreen')),
            ],
          ),
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: BottomNavigationBar(
              backgroundColor: Colors.white,
              selectedItemColor: const Color(0xFF424242),
              unselectedItemColor: const Color(0xFF757575),
              currentIndex: _currentIndex,
              onTap: (index) {},
              type: BottomNavigationBarType.fixed,
              elevation: 0,
              items: [
                BottomNavigationBarItem(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _currentIndex == 0
                          ? const Color(0xFF424242).withOpacity(0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.video_call_sharp),
                  ),
                  label: 'Yog',
                ),
                BottomNavigationBarItem(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _currentIndex == 1
                          ? const Color(0xFF424242).withOpacity(0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.video_camera_front_outlined),
                  ),
                  label: 'Sneha',
                ),
                BottomNavigationBarItem(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _currentIndex == 2
                          ? const Color(0xFF424242).withOpacity(0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.add_box_outlined),
                  ),
                  label: 'Upload',
                ),
                BottomNavigationBarItem(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _currentIndex == 3
                          ? const Color(0xFF424242).withOpacity(0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.person),
                  ),
                  label: 'Profile',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

