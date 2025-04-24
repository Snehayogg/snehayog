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
          backgroundColor: Colors.black,
          body: SafeArea(
            child:
                controller.isLoading
                    ? const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                    : controller.error != null
                    ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            controller.error!,
                            style: const TextStyle(color: Colors.white),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton(
                            onPressed: controller.signInWithGoogle,
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
                          const Text(
                            "Sign in to view your profile",
                            style: TextStyle(color: Colors.white, fontSize: 18),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton(
                            onPressed: controller.signInWithGoogle,
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
          backgroundColor: Colors.black,
          title: const Text(
            "My Profile",
            style: TextStyle(color: Colors.white),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.white),
              onPressed: controller.logout,
            ),
          ],
        ),
        const SizedBox(height: 20),
        CircleAvatar(
          radius: 50,
          backgroundImage: NetworkImage(user.profilePic),
        ),
        const SizedBox(height: 10),
        Text(
          user.name,
          style: const TextStyle(color: Colors.white, fontSize: 20),
        ),
        const SizedBox(height: 20),
        const Text(
          "My Videos",
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        const SizedBox(height: 10),
        Expanded(
          child:
              user.videos.isEmpty
                  ? const Center(
                    child: Text(
                      "No videos uploaded yet",
                      style: TextStyle(color: Colors.white),
                    ),
                  )
                  : ListView.builder(
                    itemCount: user.videos.length,
                    itemBuilder: (context, index) {
                      final videoUrl = user.videos[index];
                      return Card(
                        color: Colors.grey[900],
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: ListTile(
                          title: Text(
                            "Video ${index + 1}",
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            videoUrl,
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ),
                      );
                    },
                  ),
        ),
      ],
    );
  }
}
