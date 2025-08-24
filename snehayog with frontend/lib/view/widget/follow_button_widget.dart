import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snehayog/controller/google_sign_in_controller.dart';
import 'package:snehayog/core/providers/user_provider.dart';
import 'package:snehayog/core/constants/app_constants.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        userProvider.checkFollowStatus(widget.uploaderId);
        _isInitializedNotifier.value = true;
      }
    });
  }

  /// Check if the current user is the uploader of this video
  void _checkIfOwnVideo() {
    final controller =
        Provider.of<GoogleSignInController>(context, listen: false);
    final currentUserId = controller.userData?['id'];

    if (mounted) {
      _isOwnVideoNotifier.value = currentUserId == widget.uploaderId;
    }
  }

  /// Handle follow/unfollow button tap
  Future<void> _handleFollowTap() async {
    if (_isOwnVideoNotifier.value) return;

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final success = await userProvider.toggleFollow(widget.uploaderId);

      if (success) {
        final isFollowing = userProvider.isFollowingUser(widget.uploaderId);
        _showSnackBar(isFollowing
            ? 'Followed ${widget.uploaderName}'
            : 'Unfollowed ${widget.uploaderName}');

        // Refresh user data to update follower counts in real-time
        await userProvider.refreshUserData();

        // Notify parent about follow status change
        widget.onFollowChanged?.call();
      } else {
        _showSnackBar('Failed to update follow status');
      }
    } catch (e) {
      _showSnackBar('Error: $e');
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
    return ValueListenableBuilder<bool>(
      valueListenable: _isOwnVideoNotifier,
      builder: (context, isOwnVideo, child) {
        // Don't show follow button for own videos
        if (isOwnVideo) {
          return const SizedBox.shrink();
        }

        return Consumer<UserProvider>(
          builder: (context, userProvider, child) {
            final isFollowing = userProvider.isFollowingUser(widget.uploaderId);
            final isLoading =
                userProvider.isLoadingFollowStatus(widget.uploaderId);

            return SizedBox(
              height: AppConstants.followButtonHeight,
              child: ElevatedButton(
                onPressed: isLoading ? null : _handleFollowTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isFollowing
                      ? Colors.grey[400]?.withOpacity(0.8)
                      : Colors.blue[600]?.withOpacity(0.9),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppConstants.followButtonPadding,
                      vertical: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                  shadowColor: Colors.transparent,
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isFollowing
                                ? Icons.person_remove
                                : Icons.person_add,
                            size: 12,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            isFollowing ? 'Following' : 'Follow',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
              ),
            );
          },
        );
      },
    );
  }
}
