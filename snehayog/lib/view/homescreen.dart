import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snehayog/view/screens/profilescreen.dart';
import 'package:snehayog/view/screens/searchscren.dart';
import 'package:snehayog/view/screens/uploadscreen.dart';
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
          backgroundColor: Colors.black,
          body: _screens[controller.currentIndex],
          bottomNavigationBar: BottomNavigationBar(
            backgroundColor: Colors.black,
            selectedItemColor: Colors.black,
            unselectedItemColor: Colors.grey,
            currentIndex: controller.currentIndex,
            onTap: controller.changeIndex,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.video_call_sharp),
                label: 'Videos',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.search),
                label: 'Search',
              ),
               BottomNavigationBarItem(
                icon: Icon(Icons.add_box_outlined),
                label: 'Upload',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person),
                label: 'Profile',
              ),
            ],
          ),
        );
      },
    );
  }
}
