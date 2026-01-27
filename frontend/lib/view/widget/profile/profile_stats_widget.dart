import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vayu/core/managers/profile_state_manager.dart';
import 'package:vayu/core/providers/user_provider.dart';
import 'package:vayu/core/services/profile_screen_logger.dart';
import 'package:vayu/core/theme/app_theme.dart';




class ProfileStatsWidget extends StatefulWidget {
  final ProfileStateManager stateManager;
  final String? userId;
  final bool isVideosLoaded;
  final bool isFollowersLoaded;
  final VoidCallback? onFollowersTap;
  final VoidCallback? onEarningsTap;
  final int? refreshKey; // **NEW: Key to force refresh when profile refreshes**

  const ProfileStatsWidget({
    super.key,
    required this.stateManager,
    this.userId,
    required this.isVideosLoaded,
    required this.isFollowersLoaded,
    this.onFollowersTap,
    this.onEarningsTap,
    this.refreshKey, // **NEW: Optional refresh key**
  });

  @override
  State<ProfileStatsWidget> createState() => _ProfileStatsWidgetState();
}

class _ProfileStatsWidgetState extends State<ProfileStatsWidget> {
  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: AppTheme.backgroundPrimary,
          borderRadius: BorderRadius.circular(AppTheme.radiusXLarge),
          boxShadow: [
            BoxShadow(
              color: AppTheme.shadowPrimary,
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Consumer<ProfileStateManager>(
          builder: (context, stateManager, child) {
             // **FIXED: Also listen to UserProvider to get real-time follower count updates**
            return Consumer<UserProvider>(
              builder: (context, userProvider, child) {
                final videosLoading = stateManager.isVideosLoading;
                final videoCountValue = videosLoading
                    ? '...'
                    : (stateManager.totalVideoCount > 0
                        ? stateManager.totalVideoCount
                        : stateManager.userVideos.length);

                // **FIX: Smart Loading State for Earnings**
                // Show "Loading..." if:
                // 1. Explicitly loading earnings
                // 2. Videos are loading (since we need them for fallback) AND we don't have a cached value
                // 3. Earnings are 0.0 AND we are in a loading state (avoids showing 0.00 confusingly)
                final bool shouldShowLoading = stateManager.isEarningsLoading || 
                                              (stateManager.isVideosLoading && stateManager.cachedEarnings == 0);

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatColumn(
                      'Videos',
                      videoCountValue,
                      isLoading: videosLoading,
                    ),
                    Container(
                        width: 1, height: 40, color: AppTheme.borderPrimary),
                    _buildStatColumn(
                      'Followers',
                      widget.isFollowersLoaded
                          ? _getFollowersCount(context)
                          : '...',
                      isLoading: !widget.isFollowersLoaded,
                      onTap: widget.onFollowersTap,
                    ),
                    Container(
                        width: 1, height: 40, color: AppTheme.borderPrimary),
                    _buildStatColumn(
                      'Earnings',
                      shouldShowLoading ? 'Loading...' : stateManager.cachedEarnings,
                      isEarnings: true,
                      isLoading: shouldShowLoading,
                      loadingText: 'Loading...', // **Explicit loading text**
                      onTap: widget.onEarningsTap,
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatColumn(
    String label,
    dynamic value, {
    bool isEarnings = false,
    VoidCallback? onTap,
    bool isLoading = false,
    String? loadingText, // **NEW: Allow custom loading text**
  }) {
    return RepaintBoundary(
      child: Builder(
        builder: (context) => Column(
          children: [
            GestureDetector(
              onTap: onTap,
              child: MouseRegion(
                cursor: isEarnings && onTap != null
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
                child: Text(
                  isLoading
                      ? (loadingText ?? '...') // **Use custom text or default**
                      : (isEarnings
                          ? '₹${(value is double ? value : double.tryParse(value.toString()) ?? 0.0).toStringAsFixed(2)}'
                          : value.toString()),
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper method to get followers count using MongoDB ObjectID
  int _getFollowersCount(BuildContext context) {
    ProfileScreenLogger.logDebugInfo('=== GETTING FOLLOWERS COUNT ===');
    ProfileScreenLogger.logDebugInfo('userId: ${widget.userId}');
    ProfileScreenLogger.logDebugInfo(
      'stateManager.userData: ${widget.stateManager.userData != null}',
    );

    // **FIXED: Prioritize ProfileStateManager.userData first (loaded immediately)**
    // This ensures follower count displays immediately when viewing another creator's profile
    if (widget.stateManager.userData != null) {
      // Try both field names for compatibility
      final followersCount = widget.stateManager.userData!['followersCount'] ??
          widget.stateManager.userData!['followers'];

      if (followersCount != null && followersCount != 0) {
        ProfileScreenLogger.logDebugInfo(
          '✅ Using followers count from ProfileStateManager: $followersCount',
        );
        return followersCount is int
            ? followersCount
            : (int.tryParse(followersCount.toString()) ?? 0);
      }
    }

    // **FALLBACK: Check UserProvider cache (populated asynchronously)**
    final List<String> idsToTry = <String?>[
      widget.userId,
      widget.stateManager.userData?['googleId'],
      widget.stateManager.userData?['_id'] ??
          widget.stateManager.userData?['id'],
    ]
        .where((e) => e != null && (e).isNotEmpty)
        .map((e) => e as String)
        .toList()
        .toSet()
        .toList();

    if (idsToTry.isNotEmpty) {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      for (final candidateId in idsToTry) {
        final userModel = userProvider.getUserData(candidateId);
        if (userModel?.followersCount != null &&
            userModel!.followersCount > 0) {
          ProfileScreenLogger.logDebugInfo(
            '✅ Using followers count from UserProvider for $candidateId: ${userModel.followersCount}',
          );
          return userModel.followersCount;
        }
      }
    }

    // Final fallback
    ProfileScreenLogger.logDebugInfo(
      '⚠️ No followers count available, using default: 0',
    );
    return 0;
  }
}
