import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:vayu/shared/theme/app_theme.dart';
import 'package:vayu/features/profile/presentation/managers/profile_state_manager.dart';
import 'package:vayu/shared/utils/app_logger.dart';
import 'package:vayu/shared/utils/app_text.dart';

class EditProfileScreen extends StatefulWidget {
  final ProfileStateManager stateManager;

  const EditProfileScreen({super.key, required this.stateManager});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    // Initialize controller with current name
    // Using a post-frame callback to avoid building widget during build if notifyListeners is called
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.stateManager.startEditing();
    });
  }

  Future<void> _handleSave() async {
    if (_formKey.currentState!.validate()) {
      try {
        await widget.stateManager.saveProfile();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppText.get('profile_updated_success',
                  fallback: 'Profile updated successfully')),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true); // Return true to indicate update
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error updating profile: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await showDialog<XFile>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(
                AppText.get('profile_change_photo', fallback: 'Change Photo')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.camera_alt),
                  title: Text(
                      AppText.get('profile_take_photo', fallback: 'Take Photo')),
                  onTap: () async {
                    final XFile? photo =
                        await _imagePicker.pickImage(source: ImageSource.camera);
                    if (context.mounted) Navigator.pop(context, photo);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: Text(AppText.get('profile_choose_gallery',
                      fallback: 'Choose from Gallery')),
                  onTap: () async {
                    final XFile? photo = await _imagePicker.pickImage(
                        source: ImageSource.gallery);
                    if (context.mounted) Navigator.pop(context, photo);
                  },
                ),
              ],
            ),
          );
        },
      );

      if (image != null) {
        await widget.stateManager.updateProfilePhoto(image.path);
        // Assuming updateProfilePhoto updates the stateManager.userData['profilePic']
      }
    } catch (e) {
      AppLogger.log('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick image: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.stateManager,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () {
              widget.stateManager.cancelEditing();
              Navigator.pop(context);
            },
          ),
          title: const Text(
            'Edit Profile',
            style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
          actions: [
            Consumer<ProfileStateManager>(
              builder: (context, manager, child) {
                if (manager.isLoading) {
                  return const Center(
                      child: Padding(
                    padding: EdgeInsets.only(right: 16.0),
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ));
                }
                return TextButton(
                  onPressed: _handleSave,
                  child: const Text('Save',
                      style: TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                );
              },
            )
          ],
        ),
        body: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            widget.stateManager.cancelEditing();
            if (context.mounted) Navigator.pop(context);
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  Center(
                    child: Stack(
                      children: [
                        Consumer<ProfileStateManager>(
                          builder: (context, manager, _) {
                            final profilePic = manager.userData?['profilePic'];
                            ImageProvider? imageProvider;
                            if (profilePic != null && profilePic.isNotEmpty) {
                              if (profilePic.startsWith('http')) {
                                imageProvider = NetworkImage(profilePic);
                              } else {
                                imageProvider = FileImage(File(profilePic));
                              }
                            }

                            return CircleAvatar(
                              radius: 60,
                              backgroundColor: Colors.grey[200],
                              backgroundImage: imageProvider,
                              child: imageProvider == null
                                  ? const Icon(Icons.person,
                                      size: 60, color: Colors.grey)
                                  : null,
                            );
                          },
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: _pickImage,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  Consumer<ProfileStateManager>(
                    builder: (context, manager, _) {
                      return TextFormField(
                        controller: manager.nameController,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter your name';
                          }
                          return null;
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
