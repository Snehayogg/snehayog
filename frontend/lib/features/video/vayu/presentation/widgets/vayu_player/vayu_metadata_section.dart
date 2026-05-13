import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/shared/utils/format_utils.dart';
import 'package:shimmer/shimmer.dart';

class VayuMetadataSection extends StatelessWidget {
  final VideoModel video;
  final bool isPortrait;
  final bool isLoading;
  final VoidCallback onShare;
  final VoidCallback onSave;
  final VoidCallback onVisitLink;
  final VoidCallback onMoreOptions;
  final VoidCallback onEpisodes;
  final VoidCallback onSuggestion;
  final Function(String) onShowError;

  const VayuMetadataSection({
    super.key,
    required this.video,
    this.isPortrait = true,
    this.isLoading = false,
    required this.onShare,
    required this.onSave,
    required this.onVisitLink,
    required this.onMoreOptions,
    required this.onEpisodes,
    required this.onSuggestion,
    required this.onShowError,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return _buildShimmer(context);
    }
    return Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.spacing3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            video.videoName,
            style: AppTypography.bodyLarge.copyWith(
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.textPrimary
                  : Colors.black87,
              fontWeight: FontWeight.bold,
              height: 1.2,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            '${FormatUtils.formatViews(video.views)} views • ${FormatUtils.formatTimeAgo(video.uploadedAt)}',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textTertiary,
              fontSize: isPortrait ? 11 : 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (video.tags != null && video.tags!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: video.tags!
                  .map((tag) => Text(
                        '#$tag',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ))
                  .toList(),
            ),
          ],
          const SizedBox(height: 12),
          // ── ACTION BAR (Glassmorphic & Progressive) ──────────
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                // Primary Tier: Save & Share (Most frequent)
                _buildActionButton(
                  context,
                  icon: Icon(
                    video.isSaved ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
                    color: video.isSaved ? AppColors.primary : Colors.white70,
                    size: 18,
                  ),
                  onPressed: onSave,
                  label: video.isSaved ? 'Saved' : 'Save',
                ),
                _buildActionButton(
                  context,
                  icon: const Icon(Icons.share_outlined, color: Colors.white70, size: 18),
                  onPressed: onShare,
                  label: 'Share',
                ),
                
                // Secondary Tier: Discovery
                if (video.episodes != null && video.episodes!.isNotEmpty)
                  _buildActionButton(
                    context,
                    icon: const Icon(Icons.playlist_play_rounded, color: Colors.white70, size: 18),
                    onPressed: onEpisodes,
                    label: 'Episodes',
                  ),
                  
                _buildActionButton(
                  context,
                  icon: const Icon(Icons.tips_and_updates_outlined, color: Colors.white70, size: 18),
                  onPressed: onSuggestion,
                  label: 'Suggest',
                ),

                if (video.link?.isNotEmpty == true)
                  _buildActionButton(
                    context,
                    icon: const Icon(Icons.open_in_new_rounded, color: Colors.white70, size: 18),
                    onPressed: onVisitLink,
                    label: 'Visit',
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmer(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white12 : Colors.grey[300]!;
    final highlightColor = isDark ? Colors.white24 : Colors.grey[100]!;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.spacing3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 200, height: 20, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 8),
            Row(children: [
              Container(width: 60, height: 12, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
              const SizedBox(width: 8),
              Container(width: 80, height: 12, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
            ]),
            const SizedBox(height: 16),
            Row(
              children: List.generate(4, (index) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Container(width: 80, height: 32, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20))),
              )),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required Widget icon,
    required VoidCallback onPressed,
    required String label,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    icon,
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
