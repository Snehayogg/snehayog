import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/core/design/radius.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';

class EpisodeGridWidget extends StatelessWidget {
  final List<dynamic> episodes;
  final String currentVideoId;
  final Function(Map<String, dynamic> episode, int index) onEpisodeTap;
  final Function(Map<String, dynamic> episode, int index)? onLongPressEpisode;
  final double aspectRatio;

  const EpisodeGridWidget({
    Key? key,
    required this.episodes,
    required this.currentVideoId,
    required this.onEpisodeTap,
    this.onLongPressEpisode,
    this.aspectRatio = 0.66, // Restored to original tall aspect ratio (2:3)
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.spacing4),
      physics: const BouncingScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: AppSpacing.spacing2,
        mainAxisSpacing: AppSpacing.spacing2,
        childAspectRatio: aspectRatio,
      ),
      itemCount: episodes.length,
      itemBuilder: (context, index) {
        final ep = episodes[index] as Map<String, dynamic>;
        final String epId = (ep['id'] ?? ep['_id'])?.toString() ?? '';
        final bool isCurrent = epId == currentVideoId;
        
        return GestureDetector(
          onTap: () => onEpisodeTap(ep, index),
          onLongPress: onLongPressEpisode != null ? () => onLongPressEpisode!(ep, index) : null,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: AppRadius.borderRadiusCard,
              color: AppColors.backgroundSecondary,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (ep['thumbnailUrl'] != null)
                  CachedNetworkImage(
                    imageUrl: ep['thumbnailUrl'], 
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(color: AppColors.backgroundSecondary),
                    errorWidget: (context, url, error) => Container(color: AppColors.backgroundSecondary),
                  ),
                
                // Blur Overlay with large numbers in the background
                Positioned.fill(
                  child: ClipRRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                      child: Container(
                        color: Colors.transparent,
                        alignment: Alignment.center,
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4), // Slightly lower alpha for better legibility on shorter cards
                            fontSize: 72, // Maintained look
                            fontWeight: FontWeight.w900,
                            shadows: [
                              Shadow(
                                color: Colors.black.withValues(alpha: 0.6),
                                blurRadius: 8.0,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                
                // Active Border
                if (isCurrent)
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.primary, width: 2), 
                      borderRadius: AppRadius.borderRadiusCard,
                    ),
                  ),

                // Title at bottom
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Container(
                    padding: EdgeInsets.all(AppSpacing.spacing2),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter, 
                        end: Alignment.topCenter, 
                        colors: [
                          Colors.black.withValues(alpha: 0.8), 
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Text(
                      ep['videoName'] ?? 'Ep ${index + 1}', 
                      maxLines: 1, // Only 1 line since cards are shorter
                      overflow: TextOverflow.ellipsis, 
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.white, 
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
