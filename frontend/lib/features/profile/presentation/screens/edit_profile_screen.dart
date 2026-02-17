import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:vayu/features/profile/presentation/managers/profile_state_manager.dart';
import 'package:vayu/shared/theme/app_theme.dart';
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
              backgroundColor: AppTheme.success,
            ),
          );
          Navigator.pop(context, true); // Return true to indicate update
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error updating profile: $e'),
              backgroundColor: AppTheme.error,
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
            backgroundColor: AppTheme.surfacePrimary,
            title: Text(
                AppText.get('profile_change_photo', fallback: 'Change Photo'),
                style: AppTheme.headlineSmall),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.camera_alt, color: AppTheme.textPrimary),
                  title: Text(
                      AppText.get('profile_take_photo', fallback: 'Take Photo'),
                      style: AppTheme.bodyMedium),
                  onTap: () async {
                    final XFile? photo =
                        await _imagePicker.pickImage(source: ImageSource.camera);
                    if (context.mounted) Navigator.pop(context, photo);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library, color: AppTheme.textPrimary),
                  title: Text(AppText.get('profile_choose_gallery',
                      fallback: 'Choose from Gallery'),
                      style: AppTheme.bodyMedium),
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
        backgroundColor: AppTheme.backgroundPrimary,
        appBar: AppBar(
          backgroundColor: AppTheme.backgroundPrimary,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: AppTheme.textPrimary, size: 20),
            onPressed: () {
              widget.stateManager.cancelEditing();
              Navigator.pop(context);
            },
          ),
          title: Text(
            'Edit Profile',
            style: AppTheme.headlineSmall.copyWith(
              fontWeight: AppTheme.weightBold,
              letterSpacing: -0.5,
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
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
                        ),
                      ),
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: TextButton(
                    onPressed: _handleSave,
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusXXLarge)),
                    ),
                    child: Text(
                      'Save',
                      style: AppTheme.labelLarge.copyWith(
                        fontWeight: AppTheme.weightBold,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
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

                            return Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: AppTheme.borderPrimary, width: 4),
                                boxShadow: AppTheme.shadowMd,
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  CircleAvatar(
                                    radius: 70,
                                    backgroundColor: AppTheme.backgroundTertiary,
                                    backgroundImage: imageProvider,
                                    child: imageProvider == null
                                        ? Opacity(
                                            opacity: 0.5,
                                            child: Image.asset(
                                              'assets/images/placeholder_profile.png',
                                              width: 140,
                                              height: 140,
                                              errorBuilder: (context, error, stackTrace) =>
                                                  const Icon(Icons.person, size: 70, color: AppTheme.textSecondary),
                                            ),
                                          )
                                        : null,
                                  ),
                                  if (manager.isPhotoLoading)
                                    Container(
                                      width: 140,
                                      height: 140,
                                      decoration: BoxDecoration(
                                        color: AppTheme.overlayDark,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Center(
                                        child: CircularProgressIndicator(
                                          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.textPrimary),
                                          strokeWidth: 3,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                        Positioned(
                          bottom: 5,
                          right: 5,
                          child: GestureDetector(
                            onTap: _pickImage,
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.primary,
                                shape: BoxShape.circle,
                                border: Border.all(color: AppTheme.backgroundPrimary, width: 3),
                                boxShadow: AppTheme.shadowSm,
                              ),
                              child: const Icon(
                                Icons.camera_alt_rounded,
                                color: AppTheme.textPrimary,
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 48),
                  Consumer<ProfileStateManager>(
                    builder: (context, manager, _) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
                            child: Text(
                              'Display Name',
                              style: AppTheme.labelSmall.copyWith(
                                color: AppTheme.textSecondary,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                          TextFormField(
                            controller: manager.nameController,
                            style: AppTheme.bodyLarge.copyWith(
                              color: AppTheme.textPrimary,
                              fontWeight: AppTheme.weightMedium,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Enter your name',
                              hintStyle: TextStyle(color: AppTheme.textTertiary),
                              prefixIcon: Icon(Icons.person_rounded, color: AppTheme.primary.withOpacity(0.7)),
                              filled: true,
                              fillColor: AppTheme.backgroundSecondary,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppTheme.radiusXLarge),
                                borderSide: const BorderSide(color: AppTheme.borderPrimary),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppTheme.radiusXLarge),
                                borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
                              ),
                              errorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppTheme.radiusXLarge),
                                borderSide: const BorderSide(color: AppTheme.error, width: 1),
                              ),
                              focusedErrorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppTheme.radiusXLarge),
                                borderSide: const BorderSide(color: AppTheme.error, width: 1.5),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please enter your name';
                              }
                              if (value.trim().length < 2) {
                                return 'Name is too short';
                              }
                              return null;
                            },
                          ),
                        ],
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
