import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vayu/core/design/colors.dart';
import 'package:vayu/core/design/typography.dart';
import 'package:vayu/core/providers/user_data_providers.dart';
import 'package:vayu/features/profile/presentation/managers/profile_state_manager.dart';
import 'package:vayu/shared/utils/app_logger.dart';
import 'package:vayu/shared/utils/app_text.dart';

class ProfileHeaderWidget extends ConsumerWidget {
  final bool isViewingOwnProfile;
  final ProfileStateManager stateManager;
  final bool hasReferralBillingUnlock;
  final VoidCallback? onProfilePhotoChange;
  final VoidCallback? onAddUpiId;
  final VoidCallback? onReferFriends;
  final VoidCallback? onEarningsTap;
  final VoidCallback? onSaveProfile;
  final VoidCallback? onCancelEdit;

  const ProfileHeaderWidget({
    super.key,
    required this.isViewingOwnProfile,
    required this.stateManager,
    this.hasReferralBillingUnlock = false,
    this.onProfilePhotoChange,
    this.onAddUpiId,
    this.onReferFriends,
    this.onEarningsTap,
    this.onSaveProfile,
    this.onCancelEdit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppLogger.log(
        '🎨 ProfileHeaderWidget: Rebuilding (Videos: ${stateManager.totalVideoCount})');
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
                        label: AppText.get('profile_stat_subscribers'),
                        value:
                            _getFollowersCountString(context, stateManager, ref),
                      ),
                    ),
                    Container(
                      height: 24,
                      width: 1,
                      color: AppColors.borderPrimary,
                    ),
                    Expanded(
                      child: _buildStatItem(
                        context,
                        label: AppText.get('profile_stat_content'),
                        value: stateManager.totalVideoCount.toString(),
                      ),
                    ),
                    Container(
                      height: 24,
                      width: 1,
                      color: AppColors.borderPrimary,
                    ),
                    Expanded(
                      child: _buildStatItem(
                        context,
                        label: isViewingOwnProfile
                            ? AppText.get('profile_stat_earnings')
                            : AppText.get('profile_stat_rank'),
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
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (stateManager.userData?['websiteUrl'] != null &&
              stateManager.userData!['websiteUrl'].toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () async {
                final urlStr = stateManager.userData!['websiteUrl'].toString();
                final uri = Uri.tryParse(urlStr.startsWith('http')
                    ? urlStr
                    : 'https://$urlStr');
                if (uri != null && await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.link,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      stateManager.userData!['websiteUrl'],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          _buildActionButtons(stateManager),
        ],
      ),
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
                color: AppColors.borderPrimary,
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
                  color: AppColors.backgroundSecondary,
                  child: const HugeIcon(
                      icon: HugeIcons.strokeRoundedUser,
                      color: AppColors.textTertiary,
                      size: 40),
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
                child: const HugeIcon(
                  icon: HugeIcons.strokeRoundedCamera01,
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
            style: AppTypography.titleMedium.copyWith(
              color: isHighlighted ? AppColors.primary : AppColors.textPrimary,
              fontSize: isLoadingText ? 10 : 18,
              fontWeight: isLoadingText ? FontWeight.w600 : FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
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
          : stateManager.cachedEarnings.toStringAsFixed(2);
    } else {
      final rank = stateManager.userData?['rank'] ?? 0;
      return rank > 0 ? '#$rank' : '—';
    }
  }

  String _getFollowersCountString(
      BuildContext context, ProfileStateManager stateManager, WidgetRef ref) {
    if (stateManager.userData != null) {
      final followersCount = stateManager.userData!['followersCount'] ??
          stateManager.userData!['followers'];

      if (followersCount != null) {
        if (followersCount is int) return followersCount.toString();
        if (followersCount is List) return followersCount.length.toString();

        final count = int.tryParse(followersCount.toString());
        if (count != null && count > 0) return count.toString();
      }
    }

    try {
      final userProviderRef = ref.read(userProvider);
      final userIdCandidates = [
        stateManager.userData?['googleId'],
        stateManager.userData?['_id'] ?? stateManager.userData?['id'],
      ].whereType<String>().toSet();

      for (final id in userIdCandidates) {
        final userModel = userProviderRef.getUserData(id);
        if (userModel?.followersCount != null &&
            userModel!.followersCount > 0) {
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
        if (stateManager.isEditing ||
            (stateManager.totalVideoCount >= 2 || hasReferralBillingUnlock))
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
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(AppText.get('btn_cancel')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: onSaveProfile,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(AppText.get('btn_save')),
                        ),
                      ),
                    ],
                  )
                : ElevatedButton.icon(
                    onPressed: onAddUpiId,
                    icon: const HugeIcon(
                        icon: HugeIcons.strokeRoundedWallet01, size: 18),
                    label: Text(
                      AppText.get('btn_add_upi_id'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                  ),
          ),
        if (!stateManager.isEditing) ...[
          if (stateManager.totalVideoCount >= 2 || hasReferralBillingUnlock)
            const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton(
              onPressed: onReferFriends,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                side: const BorderSide(color: AppColors.borderPrimary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                AppText.get('btn_refer_friends'),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ]
      ],
    );
  }
}
