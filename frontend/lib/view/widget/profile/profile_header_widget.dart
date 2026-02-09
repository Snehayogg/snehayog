import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vayu/core/managers/profile_state_manager.dart';
import 'package:vayu/core/providers/user_provider.dart';
import 'package:vayu/core/services/profile_screen_logger.dart';
import 'package:vayu/view/widget/follow_button_widget.dart';
import 'package:vayu/core/theme/app_theme.dart';
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
                                color: AppTheme.borderPrimary,
                                width: 2,
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
                                    backgroundColor: AppTheme.backgroundSecondary,
                                  foregroundImage: profileImage,
                                  onForegroundImageError:
                                      (exception, stackTrace) {
                                    ProfileScreenLogger.logError(
                                        'Error loading profile image: $exception');
                                  },
                                  child: const Icon(
                                          Icons.person,
                                          size: 40,
                                          color: AppTheme.textTertiary,
                                        ),
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
                                  color: Theme.of(context).primaryColor,
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
                                      color: AppTheme.borderPrimary),
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
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    hintText: 'Enter your name',
                                    hintStyle: TextStyle(
                                      color: AppTheme.textTertiary,
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
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.4,
                                ),
                              ),
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      // **FIX: Show "How to earn" button for own profile, Follow button for others**
                      Builder(
                        builder: (context) {
                          // Show "How to earn" button if callback is provided (own profile)
                          if (onShowHowToEarn != null) {
                            return ElevatedButton.icon(
                              onPressed: onShowHowToEarn,
                              icon:
                                  const Icon(Icons.workspace_premium, size: 18),
                              label: const Text('How to earn'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.success,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                elevation: 0,
                              ),
                            );
                          }

                          // Show Follow button for other users' profiles
                          final displayedUserId = userId ??
                              stateManager.userData?['googleId']?.toString() ??
                              stateManager.userData?['id']?.toString();

                          if (displayedUserId != null) {
                            final userName = _getUserName(context);
                            return FollowButtonWidget(
                              uploaderId: displayedUserId,
                              uploaderName: userName,
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
                              backgroundColor: AppTheme.backgroundSecondary,
                              foregroundColor: AppTheme.textSecondary,
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
                              backgroundColor: Theme.of(context).primaryColor,
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
