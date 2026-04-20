import 'package:flutter/material.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/shared/utils/format_utils.dart';
import 'package:url_launcher/url_launcher.dart';

class VayuMetadataSection extends StatelessWidget {
  final VideoModel video;
  final bool isPortrait;
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                Text(
                  '${FormatUtils.formatViews(video.views)} views • ${FormatUtils.formatTimeAgo(video.uploadedAt)}',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: isPortrait ? 11 : 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 12),
                if (video.link?.isNotEmpty == true)
                  _buildActionButton(
                    context,
                    icon: Icon(Icons.open_in_new_rounded,
                        color: AppColors.textSecondary, size: isPortrait ? 18 : 20),
                    onPressed: onVisitLink,
                    label: 'Visit Now',
                  ),
                _buildActionButton(
                  context,
                  icon: Icon(Icons.share_outlined,
                      color: AppColors.textSecondary, size: isPortrait ? 18 : 20),
                  onPressed: onShare,
                  label: 'Share',
                ),
                _buildActionButton(
                  context,
                  icon: Icon(Icons.tips_and_updates_outlined,
                      color: AppColors.textSecondary, size: isPortrait ? 18 : 20),
                  onPressed: onSuggestion,
                  label: 'Suggest',
                ),
                _buildActionButton(
                  context,
                  icon: Icon(
                    video.isSaved ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
                    color: video.isSaved ? AppColors.primary : AppColors.textSecondary,
                    size: isPortrait ? 18 : 20,
                  ),
                  onPressed: onSave,
                  label: video.isSaved ? 'Saved' : 'Save',
                ),
                if (video.episodes != null && video.episodes!.isNotEmpty)
                  _buildActionButton(
                    context,
                    icon: Icon(Icons.playlist_play_rounded,
                        color: AppColors.textSecondary, size: isPortrait ? 18 : 20),
                    onPressed: onEpisodes,
                    label: 'Episodes',
                  ),
              ],
            ),
          ),
        ],
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                const SizedBox(width: 4),
                Text(
                  label,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
