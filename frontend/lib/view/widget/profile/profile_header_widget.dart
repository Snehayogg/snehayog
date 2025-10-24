import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vayu/core/managers/profile_state_manager.dart';
import 'package:vayu/core/providers/user_provider.dart';
import 'package:vayu/core/services/profile_screen_logger.dart';
import 'dart:io';

class ProfileHeaderWidget extends StatelessWidget {
  final ProfileStateManager stateManager;
  final String? userId;
  final VoidCallback? onEditProfile;
  final VoidCallback? onSaveProfile;
  final VoidCallback? onCancelEdit;
  final VoidCallback? onProfilePhotoChange;
  final VoidCallback? onShowHowToEarn;

  const ProfileHeaderWidget({
    super.key,
    required this.stateManager,
    this.userId,
    this.onEditProfile,
    this.onSaveProfile,
    this.onCancelEdit,
    this.onProfilePhotoChange,
    this.onShowHowToEarn,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          children: [
            // Row: Profile photo left, username and CTA on right
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Avatar stack
                RepaintBoundary(
                  child: Stack(
                    children: [
                      Consumer<ProfileStateManager>(
                        builder: (context, stateManager, child) {
                          return Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFFE5E7EB),
                                width: 3,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: CircleAvatar(
                              radius: 45,
                              backgroundColor: const Color(0xFFF3F4F6),
                              backgroundImage: _getProfileImage(context),
                              onBackgroundImageError: (exception, stackTrace) {
                                ProfileScreenLogger.logError(
                                    'Error loading profile image: $exception');
                              },
                              child: _getProfileImage(context) == null
                                  ? const Icon(
                                      Icons.person,
                                      size: 40,
                                      color: Color(0xFF9CA3AF),
                                    )
                                  : null,
                            ),
                          );
                        },
                      ),
                      Consumer<ProfileStateManager>(
                        builder: (context, stateManager, child) {
                          if (stateManager.isEditing) {
                            return Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF3B82F6),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 6,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.camera_alt,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                  onPressed: onProfilePhotoChange,
                                  padding: EdgeInsets.zero,
                                ),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Username and How to earn
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Consumer<ProfileStateManager>(
                        builder: (context, stateManager, child) {
                          if (stateManager.isEditing) {
                            return RepaintBoundary(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: const Color(0xFFE5E7EB)),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.04),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: TextField(
                                  controller: stateManager.nameController,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1A1A1A),
                                  ),
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    hintText: 'Enter your name',
                                    hintStyle: TextStyle(
                                      color: Color(0xFF9CA3AF),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          } else {
                            return RepaintBoundary(
                              child: Text(
                                _getUserName(context),
                                style: const TextStyle(
                                  color: Color(0xFF1A1A1A),
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.4,
                                ),
                              ),
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 36,
                        child: OutlinedButton.icon(
                          onPressed: onShowHowToEarn,
                          icon: const Icon(Icons.info_outline, size: 18),
                          label: const Text('How to earn'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            side: const BorderSide(color: Color(0xFF3B82F6)),
                            foregroundColor: const Color(0xFF3B82F6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Edit Action Buttons
            Consumer<ProfileStateManager>(
              builder: (context, stateManager, child) {
                if (stateManager.isEditing) {
                  return RepaintBoundary(
                    child: Container(
                      margin: const EdgeInsets.only(top: 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton(
                            onPressed: onCancelEdit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFF3F4F6),
                              foregroundColor: const Color(0xFF6B7280),
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide.none,
                              ),
                            ),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton(
                            onPressed: onSaveProfile,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3B82F6),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide.none,
                              ),
                            ),
                            child: const Text(
                              'Save',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                } else {
                  return const SizedBox.shrink();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // Helper method to get profile image with fallback logic
  ImageProvider? _getProfileImage(BuildContext context) {
    if (stateManager.userData != null &&
        stateManager.userData!['profilePic'] != null) {
      final profilePic = stateManager.userData!['profilePic'];
      ProfileScreenLogger.logDebugInfo(
          'Using profile pic from ProfileStateManager: $profilePic');

      if (profilePic.startsWith('http')) {
        return NetworkImage(profilePic);
      } else if (profilePic.isNotEmpty) {
        try {
          return FileImage(File(profilePic));
        } catch (e) {
          ProfileScreenLogger.logWarning('Error creating FileImage: $e');
          return null;
        }
      }
    }

    // Fall back to UserProvider data
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    if (userId != null) {
      final userModel = userProvider.getUserData(userId!);
      if (userModel?.profilePic != null) {
        final profilePic = userModel!.profilePic;
        ProfileScreenLogger.logDebugInfo(
            'Using profile pic from UserProvider: $profilePic');

        if (profilePic.startsWith('http')) {
          return NetworkImage(profilePic);
        } else if (profilePic.isNotEmpty) {
          try {
            return FileImage(File(profilePic));
          } catch (e) {
            ProfileScreenLogger.logWarning('Error creating FileImage: $e');
            return null;
          }
        }
      }
    }

    ProfileScreenLogger.logDebugInfo('No profile pic available');
    return null;
  }

  // Helper method to get user name with fallback logic
  String _getUserName(BuildContext context) {
    // Prioritize ProfileStateManager data, then fall back to UserProvider data
    if (stateManager.userData != null &&
        stateManager.userData!['name'] != null) {
      final name = stateManager.userData!['name'];
      ProfileScreenLogger.logDebugInfo(
          'Using name from ProfileStateManager: $name');
      return name;
    }

    // Fall back to UserProvider data
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    if (userId != null) {
      final userModel = userProvider.getUserData(userId!);
      if (userModel?.name != null) {
        final name = userModel!.name;
        ProfileScreenLogger.logDebugInfo('Using name from UserProvider: $name');
        return name;
      }
    }

    // Final fallback
    ProfileScreenLogger.logDebugInfo('No name available, using default');
    return 'User';
  }
}
