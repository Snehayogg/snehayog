import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snehayog/controller/profileController.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ProfileController>(
      builder: (context, controller, _) {
        return Scaffold(
          backgroundColor: const Color(0xFF002B36), // Solarized Dark Base
          body: SafeArea(
            child:
                controller.isLoading
                    ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF268BD2), // Solarized Blue
                      ),
                    )
                    : controller.error != null
                    ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 60,
                            color: Color(0xFF268BD2), // Solarized Blue
                          ),
                          const SizedBox(height: 20),
                          Text(
                            controller.error!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton(
                            onPressed: controller.signInWithGoogle,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(
                                0xFF268BD2,
                              ), // Solarized Blue
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 30,
                                vertical: 15,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                            child: const Text("Retry Sign In"),
                          ),
                        ],
                      ),
                    )
                    : controller.user == null
                    ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.person_outline,
                            size: 80,
                            color: Color(0xFF586E75), // Solarized Base1
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            "Sign in to view your profile",
                            style: TextStyle(color: Colors.white, fontSize: 18),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton(
                            onPressed: controller.signInWithGoogle,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(
                                0xFF268BD2,
                              ), // Solarized Blue
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 30,
                                vertical: 15,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                            child: const Text("Sign in with Google"),
                          ),
                        ],
                      ),
                    )
                    : _buildProfileContent(controller),
          ),
        );
      },
    );
  }

  Widget _buildProfileContent(ProfileController controller) {
    final user = controller.user!;
    return Column(
      children: [
        AppBar(
          backgroundColor: const Color(0xFF002B36), // Solarized Dark Base
          elevation: 0,
          title: const Text(
            "My Profile",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          actions: [
            IconButton(
              icon: const Icon(
                Icons.logout,
                color: Color(0xFF268BD2),
              ), // Solarized Blue
              onPressed: controller.logout,
            ),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(20),
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: const Color(0xFF073642), // Solarized Dark Content
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            children: [
              CircleAvatar(
                radius: 50,
                backgroundColor: const Color(0xFF268BD2), // Solarized Blue
                child: CircleAvatar(
                  radius: 48,
                  backgroundImage: NetworkImage(user.profilePic),
                ),
              ),
              const SizedBox(height: 15),
              Text(
                user.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                user.email,
                style: const TextStyle(
                  color: Color(0xFF586E75), // Solarized Base1
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF073642), // Solarized Dark Content
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "My Videos",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              user.videos.isEmpty
                  ? Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.video_library_outlined,
                          size: 60,
                          color: const Color(
                            0xFF586E75,
                          ).withOpacity(0.5), // Solarized Base1
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          "No videos uploaded yet",
                          style: TextStyle(
                            color: Color(0xFF586E75), // Solarized Base1
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                  : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: user.videos.length,
                    itemBuilder: (context, index) {
                      final videoUrl = user.videos[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF002B36), // Solarized Dark Base
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          leading: const Icon(
                            Icons.videocam,
                            color: Color(0xFF268BD2), // Solarized Blue
                          ),
                          title: Text(
                            "Video ${index + 1}",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            videoUrl,
                            style: const TextStyle(
                              color: Color(0xFF586E75), // Solarized Base1
                            ),
                          ),
                          trailing: const Icon(
                            Icons.play_circle_outline,
                            color: Color(0xFF268BD2), // Solarized Blue
                          ),
                        ),
                      );
                    },
                  ),
            ],
          ),
        ),
      ],
    );
  }
}
