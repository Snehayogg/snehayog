import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snehayog/view/screens/profilescreen.dart';
import 'package:snehayog/view/screens/searchscren.dart';
import 'package:snehayog/view/screens/upload_screen.dart';
import 'package:snehayog/view/screens/videoscreen.dart';
import 'package:snehayog/controller/main_controller.dart';

class MainScreen extends StatelessWidget {
  MainScreen({super.key});

  final List<Widget> _screens = [
    const VideoScreen(),
    const SearchScreen(),
    const UploadScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer<MainController>(
      builder: (context, controller, _) {
        return Scaffold(
          backgroundColor: const Color(0xFF002B36), // Solarized Dark Base
          body: _screens[controller.currentIndex],
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF002B36), // Solarized Dark Base
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: BottomNavigationBar(
              backgroundColor: const Color(0xFF002B36), // Solarized Dark Base
              selectedItemColor: const Color(0xFF268BD2), // Solarized Blue
              unselectedItemColor: const Color(0xFF586E75), // Solarized Base1
              currentIndex: controller.currentIndex,
              onTap: controller.changeIndex,
              type: BottomNavigationBarType.fixed,
              elevation: 0,
              items: [
                BottomNavigationBarItem(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color:
                          controller.currentIndex == 0
                              ? const Color(0xFF073642).withOpacity(
                                0.5,
                              ) // Solarized Dark Content
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.video_call_sharp),
                  ),
                  label: 'Videos',
                ),
                BottomNavigationBarItem(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color:
                          controller.currentIndex == 1
                              ? const Color(0xFF073642).withOpacity(
                                0.5,
                              ) // Solarized Dark Content
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.search),
                  ),
                  label: 'Search',
                ),
                BottomNavigationBarItem(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color:
                          controller.currentIndex == 2
                              ? const Color(0xFF073642).withOpacity(
                                0.5,
                              ) // Solarized Dark Content
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
                      color:
                          controller.currentIndex == 3
                              ? const Color(0xFF073642).withOpacity(
                                0.5,
                              ) // Solarized Dark Content
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
