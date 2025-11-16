import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vayu/core/managers/profile_state_manager.dart';
import 'package:vayu/core/providers/user_provider.dart';
import 'package:vayu/core/services/profile_screen_logger.dart';
import 'package:vayu/view/widget/follow_button_widget.dart';
import 'package:vayu/controller/google_sign_in_controller.dart';
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
                          final profileImage = _getProfileImage(context);
                          final profilePic =
                              stateManager.userData?['profilePic'];
                          final hasProfilePic =
                              profilePic != null && profilePic.isNotEmpty;

                          return Container(
                            width: 80,
                            height: 80,
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
                            child: Stack(
                              children: [
                                CircleAvatar(
                                  radius: 45,
                                  backgroundColor: const Color(0xFFF3F4F6),
                                  backgroundImage: profileImage,
                                  onBackgroundImageError:
                                      (exception, stackTrace) {
                                    ProfileScreenLogger.logError(
                                        'Error loading profile image: $exception');
                                  },
                                  child: profileImage == null
                                      ? const Icon(
                                          Icons.person,
                                          size: 40,
                                          color: Color(0xFF9CA3AF),
                                        )
                                      : null,
                                ),
                                // Show loading indicator when image is being loaded
                                if (hasProfilePic &&
                                    profilePic.startsWith('http'))
                                  Positioned.fill(
                                    child: _ProfileImageLoader(
                                        imageUrl: profilePic),
                                  ),
                              ],
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
                // Username and How to earn / Follow button
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
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.4,
                                ),
                              ),
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      // Show follow button when viewing someone else's profile
                      // Show "How to earn" button when viewing own profile
                      Consumer<GoogleSignInController>(
                        builder: (context, authController, _) {
                          final loggedInUserId = authController.userData?['id']
                                  ?.toString() ??
                              authController.userData?['googleId']?.toString();
                          final displayedUserId = userId ??
                              stateManager.userData?['googleId']?.toString() ??
                              stateManager.userData?['id']?.toString();
                          final bool isViewingOwnProfile =
                              loggedInUserId != null &&
                                  loggedInUserId.isNotEmpty &&
                                  loggedInUserId == displayedUserId;

                          // Show follow button when viewing someone else's profile
                          if (!isViewingOwnProfile && displayedUserId != null) {
                            final userName = _getUserName(context);
                            return FollowButtonWidget(
                              uploaderId: displayedUserId,
                              uploaderName: userName,
                            );
                          }

                          // Show "How to earn" button when viewing own profile
                          if (isViewingOwnProfile && onShowHowToEarn != null) {
                            return SizedBox(
                              height: 32,
                              child: OutlinedButton.icon(
                                onPressed: onShowHowToEarn,
                                icon: const Icon(Icons.info_outline, size: 16),
                                label: const Text(
                                  'How to earn',
                                  style: TextStyle(fontSize: 12),
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  side: const BorderSide(
                                      color: Color(0xFF3B82F6)),
                                  foregroundColor: const Color(0xFF3B82F6),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
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
                                  horizontal: 20, vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                                side: BorderSide.none,
                              ),
                            ),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: onSaveProfile,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3B82F6),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                                side: BorderSide.none,
                              ),
                            ),
                            child: const Text(
                              'Save',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
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

/// Widget that shows a loading indicator while the profile image is being loaded
/// This uses Image.network to detect when the image is loading/loaded
class _ProfileImageLoader extends StatefulWidget {
  final String imageUrl;

  const _ProfileImageLoader({required this.imageUrl});

  @override
  State<_ProfileImageLoader> createState() => _ProfileImageLoaderState();
}

class _ProfileImageLoaderState extends State<_ProfileImageLoader> {
  bool _isLoading = true;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Image.network(
        widget.imageUrl,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) {
            // Image loaded successfully
            if (mounted && _isLoading) {
              setState(() {
                _isLoading = false;
              });
            }
            return const SizedBox.shrink();
          }

          // Still loading - show spinner overlay
          return Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          // Image failed to load
          if (mounted && _isLoading) {
            setState(() {
              _isLoading = false;
            });
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}
