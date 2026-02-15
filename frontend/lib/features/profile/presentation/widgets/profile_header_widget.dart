import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vayu/shared/theme/app_theme.dart';
import 'package:vayu/features/profile/presentation/managers/profile_state_manager.dart';
import 'package:vayu/shared/providers/user_provider.dart';
import 'package:vayu/shared/utils/app_logger.dart';

class ProfileHeaderWidget extends StatelessWidget {
  final bool isViewingOwnProfile;
  final VoidCallback? onProfilePhotoChange;
  final VoidCallback? onAddUpiId;
  final VoidCallback? onReferFriends;
  final VoidCallback? onEarningsTap;
  final VoidCallback? onSaveProfile;
  final VoidCallback? onCancelEdit;
  final GlobalKey? upiButtonKey;

  const ProfileHeaderWidget({
    super.key,
    required this.isViewingOwnProfile,
    this.onProfilePhotoChange,
    this.onAddUpiId,
    this.onReferFriends,
    this.onEarningsTap,
    this.onSaveProfile,
    this.onCancelEdit,
    this.upiButtonKey,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ProfileStateManager>(
      builder: (context, stateManager, child) {
        AppLogger.log('🎨 ProfileHeaderWidget: Rebuilding (Videos: ${stateManager.totalVideoCount})');
        return Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildAvatar(stateManager),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: _buildStatItem(
                            context,
                            label: 'Subscribers',
                            value: _getFollowersCountString(context, stateManager),
                          ),
                        ),
                        Container(
                          height: 24,
                          width: 1,
                          color: AppTheme.borderPrimary,
                        ),
                        Expanded(
                          child: _buildStatItem(
                            context,
                            label: 'Content',
                            value: stateManager.totalVideoCount.toString(),
                          ),
                        ),
                        Container(
                          height: 24,
                          width: 1,
                          color: AppTheme.borderPrimary,
                        ),
                        Expanded(
                          child: _buildStatItem(
                            context,
                            label: isViewingOwnProfile ? 'Earnings' : 'Ranking',
                            isHighlighted: true,
                            value: _getEarningsOrRankValue(stateManager),
                            onTap: isViewingOwnProfile ? onEarningsTap : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                stateManager.userData?['bio'] ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.bodySmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              _buildActionButtons(stateManager),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAvatar(ProfileStateManager stateManager) {
    return GestureDetector(
      onTap: stateManager.isEditing ? onProfilePhotoChange : null,
      child: Stack(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppTheme.borderPrimary,
                width: 2,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(40),
              child: () {
                final profilePic = stateManager.userData?['profilePic'];
                if (profilePic != null && profilePic.isNotEmpty) {
                  if (profilePic.startsWith('http')) {
                    return Image.network(profilePic, fit: BoxFit.cover);
                  } else {
                    return Image.file(File(profilePic), fit: BoxFit.cover);
                  }
                }
                return Container(
                  color: AppTheme.backgroundSecondary,
                  child: const Icon(Icons.person, color: AppTheme.textTertiary, size: 40),
                );
              }(),
            ),
          ),
          if (stateManager.isEditing)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.camera_alt,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context, {
    required String label,
    required String value,
    bool isHighlighted = false,
    VoidCallback? onTap,
  }) {
    final bool isLoadingText = value.contains('Loading');
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Text(
            value,
            style: AppTheme.titleMedium.copyWith(
              color: isHighlighted ? AppTheme.primary : AppTheme.textPrimary,
              fontSize: isLoadingText ? 10 : 18,
              fontWeight: isLoadingText ? FontWeight.w600 : FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTheme.bodySmall.copyWith(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _getEarningsOrRankValue(ProfileStateManager stateManager) {
    if (isViewingOwnProfile) {
      return (stateManager.isEarningsLoading || stateManager.isVideosLoading)
          ? 'Loading...'
          : '₹${stateManager.cachedEarnings.toStringAsFixed(2)}';
    } else {
      final rank = stateManager.userData?['rank'] ?? 0;
      return rank > 0 ? '#$rank' : '—';
    }
  }

  String _getFollowersCountString(BuildContext context, ProfileStateManager stateManager) {
    if (stateManager.userData != null) {
      final followersCount = stateManager.userData!['followersCount'] ??
          stateManager.userData!['followers'];

      if (followersCount != null) {
        final count = followersCount is int
            ? followersCount
            : (int.tryParse(followersCount.toString()) ?? 0);
        if (count > 0) return count.toString();
      }
    }

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final userIdCandidates = [
        stateManager.userData?['googleId'],
        stateManager.userData?['_id'] ?? stateManager.userData?['id'],
      ].whereType<String>().toSet();

      for (final id in userIdCandidates) {
        final userModel = userProvider.getUserData(id);
        if (userModel?.followersCount != null && userModel!.followersCount > 0) {
          return userModel.followersCount.toString();
        }
      }
    } catch (_) {}

    return '0';
  }

  Widget _buildActionButtons(ProfileStateManager stateManager) {
    if (!isViewingOwnProfile) return const SizedBox.shrink();

    return Row(
      children: [
        Expanded(
          child: stateManager.isEditing
              ? Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onCancelEdit,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: onSaveProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.success,
                          foregroundColor: AppTheme.textInverse,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Save'),
                      ),
                    ),
                  ],
                )
              : ElevatedButton.icon(
                  key: upiButtonKey,
                  onPressed: onAddUpiId,
                  icon: const Icon(Icons.account_balance_wallet, size: 18),
                  label: const Text('Add UPI ID'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: AppTheme.textInverse,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                ),
        ),
        if (!stateManager.isEditing) ...[
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton(
              onPressed: onReferFriends,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textSecondary,
                side: const BorderSide(color: AppTheme.borderPrimary),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Refer Friends'),
            ),
          ),
        ]
      ],
    );
  }
}
