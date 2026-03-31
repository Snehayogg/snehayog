import 'package:flutter/material.dart';
import 'package:vayug/features/profile/core/presentation/managers/profile_state_manager.dart';

class EditProfileScreen extends StatelessWidget {
  final ProfileStateManager? stateManager;
  
  const EditProfileScreen({super.key, this.stateManager});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
      ),
      body: const Center(
        child: Text('Edit Profile Screen (Recovered)'),
      ),
    );
  }
}
