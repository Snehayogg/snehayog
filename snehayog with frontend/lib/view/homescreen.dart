import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snehayog/controller/main_controller.dart';
import 'package:snehayog/view/screens/profile_screen.dart';
import 'package:snehayog/view/screens/long_video.dart';
import 'package:snehayog/view/screens/upload_screen.dart';
import 'package:snehayog/view/screens/video_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  final _videoScreenKey = GlobalKey(); // Use untyped GlobalKey

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    final mainController = Provider.of<MainController>(context, listen: false);

    // Pause videos when app goes to background
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      mainController.setAppInForeground(false);
      _pauseVideos();
    } else if (state == AppLifecycleState.resumed) {
      mainController.setAppInForeground(true);
      if (mainController.isVideoScreen) {
        _resumeVideos();
      }
    }
  }

  // Method to pause videos when switching screens
  void _pauseVideos() {
    // The VideoScreen will handle pausing automatically through visibility detection
  }

  // Method to resume videos when returning to video screen
  void _resumeVideos() {
    // The VideoScreen will handle resuming automatically through visibility detection
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MainController>(
      builder: (context, mainController, child) {
        return Scaffold(
          backgroundColor: Colors.white,
          body: IndexedStack(
            index: mainController.currentIndex,
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
              currentIndex: mainController.currentIndex,
              onTap: (index) {
                // Pause videos before switching screens
                if (index != mainController.currentIndex) {
                  _pauseVideos();
                }

                mainController.changeIndex(index);

                // Resume videos if returning to video screen
                if (index == 0) {
                  // Use a small delay to ensure the screen is fully loaded
                  Future.delayed(const Duration(milliseconds: 100), () {
                    if (mainController.isAppInForeground) {
                      _resumeVideos();
                    }
                  });
                }
              },
              type: BottomNavigationBarType.fixed,
              elevation: 0,
              items: [
                BottomNavigationBarItem(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: mainController.currentIndex == 0
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
                      color: mainController.currentIndex == 1
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
                      color: mainController.currentIndex == 2
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
                      color: mainController.currentIndex == 3
                          ? const Color(0xFF424242).withOpacity(0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.person_outline),
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
