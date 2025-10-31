import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vayu/core/managers/profile_state_manager.dart';
import 'package:vayu/core/providers/user_provider.dart';
import 'package:vayu/core/services/profile_screen_logger.dart';

class ProfileStatsWidget extends StatelessWidget {
  final ProfileStateManager stateManager;
  final String? userId;
  final bool isVideosLoaded;
  final bool isFollowersLoaded;
  final VoidCallback? onFollowersTap;
  final VoidCallback? onEarningsTap;

  const ProfileStatsWidget({
    super.key,
    required this.stateManager,
    this.userId,
    required this.isVideosLoaded,
    required this.isFollowersLoaded,
    this.onFollowersTap,
    this.onEarningsTap,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Consumer<ProfileStateManager>(
          builder: (context, stateManager, child) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatColumn(
                  'Videos',
                  isVideosLoaded ? stateManager.userVideos.length : '...',
                  isLoading: !isVideosLoaded,
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: const Color(0xFFE5E7EB),
                ),
                _buildStatColumn(
                  'Followers',
                  isFollowersLoaded ? _getFollowersCount(context) : '...',
                  isLoading: !isFollowersLoaded,
                  onTap: onFollowersTap,
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: const Color(0xFFE5E7EB),
                ),
                _buildStatColumn(
                  'Earnings',
                  _getCurrentMonthRevenue(),
                  isEarnings: true,
                  onTap: onEarningsTap,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatColumn(String label, dynamic value,
      {bool isEarnings = false, VoidCallback? onTap, bool isLoading = false}) {
    return RepaintBoundary(
      child: Builder(
        builder: (context) => Column(
          children: [
            GestureDetector(
              onTap: onTap,
              child: MouseRegion(
                cursor: isEarnings
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
                child: Text(
                  isLoading
                      ? '...'
                      : (isEarnings
                          ? '₹${value.toStringAsFixed(2)}'
                          : value.toString()),
                  style: const TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 12,
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
    ProfileScreenLogger.logDebugInfo('userId: $userId');
    ProfileScreenLogger.logDebugInfo(
        'stateManager.userData: ${stateManager.userData != null}');

    // Build candidate IDs to query provider with
    final List<String> idsToTry = <String?>[
      userId,
      stateManager.userData?['googleId'],
      stateManager.userData?['_id'] ?? stateManager.userData?['id'],
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
        if (userModel?.followersCount != null) {
          ProfileScreenLogger.logDebugInfo(
              'Using followers count from UserProvider for $candidateId: ${userModel!.followersCount}');
          return userModel.followersCount;
        }
      }
    }

    // Check if we're viewing own profile
    if (userId == null && stateManager.userData != null) {
      ProfileScreenLogger.logDebugInfo('Viewing own profile');

      // Prefer counts available in userData
      final followersCount = stateManager.userData!['followers'] ??
          stateManager.userData!['followersCount'] ??
          0;
      if (followersCount != 0) {
        ProfileScreenLogger.logDebugInfo(
            'Using followers count from ProfileStateManager: $followersCount');
        return followersCount;
      }
    }

    // Fall back to ProfileStateManager data
    if (stateManager.userData != null &&
        stateManager.userData!['followersCount'] != null) {
      final followersCount = stateManager.userData!['followersCount'];
      ProfileScreenLogger.logDebugInfo(
          'Using followers count from ProfileStateManager: $followersCount');
      return followersCount;
    }

    // Final fallback
    ProfileScreenLogger.logDebugInfo(
        'No followers count available, using default: 0');
    return 0;
  }

  // Calculate earnings the same way as Yug tab (sum across creator videos)
  double _getCurrentMonthRevenue() {
    try {
      // Use the same simplified model as in Yug/video feed:
      // Banner ads show on all videos at ₹10 CPM; creator share = 80%
      const double bannerCpm = 10.0;
      const double creatorShare = 0.80;

      double total = 0.0;
      for (final video in stateManager.userVideos) {
        final int views = video.views;
        final double earnings = (views / 1000.0) * bannerCpm;
        total += earnings;
      }

      return total * creatorShare;
    } catch (_) {
      return 0.0;
    }
  }
}
