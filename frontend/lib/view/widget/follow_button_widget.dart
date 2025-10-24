import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vayu/core/providers/user_provider.dart';
import 'package:vayu/services/authservices.dart';

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

  @override
  void initState() {
    super.initState();
    _isOwnVideoNotifier = ValueNotifier<bool>(false);
    _isInitializedNotifier = ValueNotifier<bool>(false);

    _checkIfOwnVideo();
    _initializeFollowStatus();
  }

  /// Initialize follow status from provider
  void _initializeFollowStatus() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        try {
          print(
              '🎯 FollowButtonWidget: Initializing follow status for ${widget.uploaderName} (ID: ${widget.uploaderId})');

          final userProvider =
              Provider.of<UserProvider>(context, listen: false);
          final authService = Provider.of<AuthService>(context, listen: false);

          // Check authentication first
          final userData = await authService.getUserData();
          if (userData != null && userData['token'] != null) {
            print(
                '🎯 FollowButtonWidget: User authenticated, checking follow status');
            await userProvider.checkFollowStatus(widget.uploaderId);
          } else {
            print(
                '⚠️ FollowButtonWidget: User not authenticated, skipping follow status check');
          }

          _isInitializedNotifier.value = true;
        } catch (e) {
          print('❌ FollowButtonWidget: Error initializing follow status: $e');
        }
      }
    });
  }

  /// Check if the current user is the uploader of this video
  void _checkIfOwnVideo() {
    // For now, we'll skip this check to avoid dependency issues
    // This can be implemented later when we have proper user context
    _isOwnVideoNotifier.value = false;
  }

  /// Handle follow/unfollow button tap
  Future<void> _handleFollowTap() async {
    if (_isOwnVideoNotifier.value) return;

    try {
      print(
          '🎯 FollowButtonWidget: Attempting to toggle follow for ${widget.uploaderName} (ID: ${widget.uploaderId})');

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

      final success = await userProvider.toggleFollow(widget.uploaderId);

      if (success) {
        final isFollowing = userProvider.isFollowingUser(widget.uploaderId);
        _showSnackBar(isFollowing
            ? 'Followed ${widget.uploaderName}'
            : 'Unfollowed ${widget.uploaderName}');

        print(
            '✅ FollowButtonWidget: Successfully ${isFollowing ? 'followed' : 'unfollowed'} ${widget.uploaderName}');

        // Refresh user data to update follower counts in real-time
        await userProvider.refreshUserData();

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
    return Consumer<UserProvider>(
      builder: (context, userProvider, child) {
        final isFollowing = userProvider.isFollowingUser(widget.uploaderId);
        final isOwnVideo = _isOwnVideoNotifier.value;

        // Don't show follow button for own videos
        if (isOwnVideo) {
          return const SizedBox.shrink();
        }

        return ValueListenableBuilder<bool>(
          valueListenable: _isInitializedNotifier,
          builder: (context, isInitialized, child) {
            if (!isInitialized) {
              return Container(
                width: 80,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }

            return Container(
              width: 80,
              height: 32, // **FIXED: Increased height for better visibility**
              decoration: BoxDecoration(
                color: isFollowing ? Colors.grey[600] : Colors.blue,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(
                        0.3), // **FIXED: Increased shadow for visibility**
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
                border: Border.all(
                  // **NEW: Added border for better visibility**
                  color: Colors.white.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _handleFollowTap,
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isFollowing ? Icons.check : Icons.add,
                          color: Colors.white,
                          size: 18, // **FIXED: Increased icon size**
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isFollowing ? 'Following' : 'Follow',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13, // **FIXED: Increased font size**
                            fontWeight:
                                FontWeight.bold, // **FIXED: Made text bold**
                            shadows: [
                              // **NEW: Added text shadow for better visibility**
                              Shadow(
                                offset: Offset(1, 1),
                                blurRadius: 2,
                                color: Colors.black54,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
