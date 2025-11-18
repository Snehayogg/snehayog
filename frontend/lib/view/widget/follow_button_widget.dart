import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vayu/core/providers/user_provider.dart';
import 'package:vayu/core/managers/profile_state_manager.dart';
import 'package:vayu/services/authservices.dart';
import 'package:vayu/controller/google_sign_in_controller.dart';

class FollowButtonWidget extends StatefulWidget {
  final String uploaderId;
  final String uploaderName;
  final VoidCallback? onFollowChanged;

  const FollowButtonWidget({
    Key? key,
    required this.uploaderId,
    required this.uploaderName,
    this.onFollowChanged,
  }) : super(key: key);

  @override
  State<FollowButtonWidget> createState() => _FollowButtonWidgetState();
}

class _FollowButtonWidgetState extends State<FollowButtonWidget> {
  late final ValueNotifier<bool> _isOwnVideoNotifier;
  late final ValueNotifier<bool> _isInitializedNotifier;
  bool _hasCheckedOwnVideo =
      false; // **FIX: Prevent re-checking on every build**
  bool _isInitializing = false; // **FIX: Prevent duplicate initialization**

  @override
  void initState() {
    super.initState();
    _isOwnVideoNotifier = ValueNotifier<bool>(false);
    _isInitializedNotifier = ValueNotifier<bool>(false);

    // **FIX: Only initialize once, not on every build**
    _checkIfOwnVideo();
    _initializeFollowStatus();
  }

  /// Initialize follow status from provider
  /// **FIX: Only initialize once, not on every build**
  void _initializeFollowStatus() {
    if (_isInitializing) return; // **FIX: Prevent duplicate initialization**
    _isInitializing = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted && _isInitializing) {
        try {
          final trimmedUploaderId = widget.uploaderId.trim();
          if (trimmedUploaderId.isEmpty || trimmedUploaderId == 'unknown') {
            _isInitializedNotifier.value = true;
            _isInitializing = false;
            return;
          }

          final userProvider =
              Provider.of<UserProvider>(context, listen: false);
          final authService = Provider.of<AuthService>(context, listen: false);

          // Check authentication first - use cached check if available
          final userData = await authService.getUserData();
          if (userData != null && userData['token'] != null) {
            // **OPTIMIZATION: checkFollowStatus already checks cache first**
            // So it won't make duplicate API calls if already cached
            await userProvider.checkFollowStatus(trimmedUploaderId);
          }

          _isInitializedNotifier.value = true;
          _isInitializing = false;
        } catch (e) {
          print('❌ FollowButtonWidget: Error initializing follow status: $e');
          _isInitializedNotifier.value = true;
          _isInitializing = false;
        }
      }
    });
  }

  /// Check if the current user is the uploader of this video
  /// **FIX: Only check once, not on every build**
  void _checkIfOwnVideo() {
    if (_hasCheckedOwnVideo) return; // **FIX: Prevent re-checking**
    _hasCheckedOwnVideo = true; // **FIX: Mark as checked immediately**

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        try {
          // Get current user ID from GoogleSignInController or AuthService
          final authController =
              Provider.of<GoogleSignInController>(context, listen: false);
          final authService = AuthService();

          String? currentUserId;

          // Try GoogleSignInController first (more reliable)
          if (authController.isSignedIn && authController.userData != null) {
            currentUserId = authController.userData!['id'] ??
                authController.userData!['googleId'] ??
                authController.userData!['_id'];
          }

          // Fallback to AuthService if GoogleSignInController doesn't have data
          if (currentUserId == null) {
            final userData = await authService.getUserData();
            if (userData != null) {
              currentUserId =
                  userData['id'] ?? userData['googleId'] ?? userData['_id'];
            }
          }

          // Compare with uploader ID
          final trimmedUploaderId = widget.uploaderId.trim();

          if (currentUserId != null &&
              trimmedUploaderId.isNotEmpty &&
              trimmedUploaderId != 'unknown') {
            final isOwnVideo = currentUserId == trimmedUploaderId;
            _isOwnVideoNotifier.value = isOwnVideo;
          } else {
            // If no current user, assume not own video (user not signed in)
            _isOwnVideoNotifier.value = false;
          }
        } catch (e) {
          print('❌ FollowButtonWidget: Error checking if own video: $e');
          _isOwnVideoNotifier.value = false;
        }
      }
    });
  }

  /// Handle follow/unfollow button tap
  Future<void> _handleFollowTap() async {
    if (_isOwnVideoNotifier.value) return;

    try {
      print(
          '🎯 FollowButtonWidget: Attempting to toggle follow for ${widget.uploaderName} (ID: ${widget.uploaderId})');

      final trimmedUploaderId = widget.uploaderId.trim();
      if (trimmedUploaderId.isEmpty || trimmedUploaderId == 'unknown') {
        _showSnackBar('Unable to follow right now. Please try again later.');
        print('❌ FollowButtonWidget: Uploader ID is empty');
        return;
      }

      final userProvider = Provider.of<UserProvider>(context, listen: false);

      // **NEW: Check authentication status first**
      final authService = Provider.of<AuthService>(context, listen: false);
      final userData = await authService.getUserData();
      if (userData == null || userData['token'] == null) {
        _showSnackBar('Please sign in to follow users');
        print('❌ FollowButtonWidget: No authentication token found');
        return;
      }

      print(
          '🎯 FollowButtonWidget: Authentication token found, proceeding with follow toggle');

      final success = await userProvider.toggleFollow(trimmedUploaderId);

      if (success) {
        final isFollowing = userProvider.isFollowingUser(trimmedUploaderId);
        _showSnackBar(isFollowing
            ? 'Followed ${widget.uploaderName}'
            : 'Unfollowed ${widget.uploaderName}');

        print(
            '✅ FollowButtonWidget: Successfully ${isFollowing ? 'followed' : 'unfollowed'} ${widget.uploaderName}');

        // **FIXED: Update follower count optimistically in both UserProvider and ProfileStateManager**
        // This ensures the follower count updates instantly on the profile screen

        // 1. UserProvider cache is already updated via followUser/unfollowUser methods
        // which optimistically update the follower count in the cache
        print(
            '🔄 FollowButtonWidget: UserProvider cache updated via followUser/unfollowUser');

        // 2. Update ProfileStateManager immediately (optimistic update)
        try {
          final profileStateManager = Provider.of<ProfileStateManager>(
            context,
            listen: false,
          );
          profileStateManager.updateFollowerCount(
            trimmedUploaderId,
            increment: isFollowing,
          );
          print(
              '✅ FollowButtonWidget: ProfileStateManager updated optimistically');
        } catch (e) {
          print(
              '⚠️ FollowButtonWidget: Could not update ProfileStateManager: $e');
        }

        // 3. Refresh follow status separately using dedicated API endpoint (more reliable)
        // This ensures follow status syncs correctly even if user data refresh has stale data
        Future.delayed(const Duration(seconds: 1), () async {
          try {
            // Force refresh follow status using dedicated API endpoint
            // This bypasses cache and fetches fresh data from backend
            await userProvider.checkFollowStatus(trimmedUploaderId,
                forceRefresh: true);
            print('✅ FollowButtonWidget: Follow status refreshed from backend');
          } catch (e) {
            print('⚠️ FollowButtonWidget: Error refreshing follow status: $e');
          }
        });

        // 4. Refresh user data from backend after a delay (for follower count, etc.)
        Future.delayed(const Duration(seconds: 1), () async {
          try {
            await userProvider.refreshUserDataForId(trimmedUploaderId);
            print('✅ FollowButtonWidget: UserProvider refreshed from backend');
          } catch (e) {
            print('⚠️ FollowButtonWidget: Error refreshing UserProvider: $e');
          }
        });

        // Also refresh current user data if needed
        Future.delayed(const Duration(milliseconds: 500), () async {
          try {
            await userProvider.refreshUserData();
          } catch (e) {
            print(
                '⚠️ FollowButtonWidget: Error refreshing current user data: $e');
          }
        });

        // Notify parent about follow status change
        widget.onFollowChanged?.call();
      } else {
        _showSnackBar('Failed to update follow status');
        print('❌ FollowButtonWidget: Follow toggle failed');
      }
    } catch (e) {
      _showSnackBar('Error: $e');
      print('❌ FollowButtonWidget: Exception during follow toggle: $e');
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void dispose() {
    _isOwnVideoNotifier.dispose();
    _isInitializedNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // **FIX: Remove unnecessary postFrameCallback from build - only initialize once in initState**
    return Consumer<UserProvider>(
      builder: (context, userProvider, child) {
        // **SYNC: Consumer automatically rebuilds when UserProvider.notifyListeners() is called**
        // When follow happens from profile screen, followUser() updates cache and calls notifyListeners()
        // This ensures follow status syncs across all FollowButtonWidgets in the app (video feed, profile, etc.)
        final trimmedUploaderId = widget.uploaderId.trim();
        final isFollowing = userProvider.isFollowingUser(trimmedUploaderId);

        // Use ValueListenableBuilder to listen to _isOwnVideoNotifier changes
        return ValueListenableBuilder<bool>(
          valueListenable: _isOwnVideoNotifier,
          builder: (context, isOwnVideo, child) {
            // Don't show follow button for own videos
            if (isOwnVideo) {
              return const SizedBox.shrink();
            }

            return ValueListenableBuilder<bool>(
              valueListenable: _isInitializedNotifier,
              builder: (context, isInitialized, child) {
                if (!isInitialized) {
                  // **MODERN LOADING STATE: Professional skeleton loader**
                  return Container(
                    width: 90,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                        width: 1.5,
                      ),
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      ),
                    ),
                  );
                }

                // **MODERN PROFESSIONAL FOLLOW BUTTON DESIGN**
                // Clean white background for both states with gray text
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  width: isFollowing ? 110 : 85,
                  height: 36,
                  decoration: BoxDecoration(
                    // **UNIFIED DESIGN: White background for both states**
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.grey.shade300,
                      width: 1.5,
                    ),
                    boxShadow: [
                      // **PROFESSIONAL SHADOWS: Subtle depth**
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                        spreadRadius: 0,
                      ),
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                        spreadRadius: -1,
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: _handleFollowTap,
                      splashColor: Colors.grey.shade200,
                      highlightColor: Colors.grey.shade100,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isFollowing ? 16 : 18,
                          vertical: 9,
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          transitionBuilder: (child, animation) {
                            return ScaleTransition(
                              scale: animation,
                              child: child,
                            );
                          },
                          child: Row(
                            key: ValueKey(isFollowing),
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // **SHOW CHECKMARK ONLY FOR FOLLOWING STATE**
                              if (isFollowing) ...[
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 250),
                                  transitionBuilder: (child, animation) {
                                    return RotationTransition(
                                      turns: animation,
                                      child: child,
                                    );
                                  },
                                  child: Icon(
                                    Icons.check_circle_rounded,
                                    key: const ValueKey('following'),
                                    color: const Color(0xFF10B981), // Green-500
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Text(
                                isFollowing ? 'Following' : 'Follow',
                                style: const TextStyle(
                                  color: Color(
                                      0xFF374151), // Gray-700 (same for both)
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                  height: 1.0,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
