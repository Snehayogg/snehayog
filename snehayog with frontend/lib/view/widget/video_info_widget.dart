import 'package:flutter/material.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/core/constants/app_constants.dart';
import 'package:snehayog/view/screens/profile_screen.dart';
import 'package:snehayog/view/widget/follow_button_widget.dart';

class VideoInfoWidget extends StatelessWidget {
  final VideoModel video;

  const VideoInfoWidget({
    Key? key,
    required this.video,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Video title
          Text(
            video.videoName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),

          // Video description (limited to 2 lines)
          Text(
            video.description,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),

          // Uploader information (tappable to go to profile)
          _UploaderInfoSection(video: video),
        ],
      ),
    );
  }
}

// Lightweight uploader info section widget
class _UploaderInfoSection extends StatelessWidget {
  final VideoModel video;

  const _UploaderInfoSection({required this.video});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Uploader avatar and name (tappable)
        Expanded(
          child: GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      ProfileScreen(userId: video.uploader.id),
                ),
              );
            },
            child: Row(
              children: [
                _UploaderAvatar(uploader: video.uploader),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    video.uploader.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Follow button
        const SizedBox(width: 6),
        FollowButtonWidget(
          uploaderId: video.uploader.id,
          uploaderName: video.uploader.name,
          onFollowChanged: () {
            // Optionally refresh video data or update UI
            print('Follow status changed for ${video.uploader.name}');
          },
        ),

        // Debug: Show link status (temporary)
        if (video.link != null) ...[
          const SizedBox(width: 8),
          _LinkStatusBadge(link: video.link!),
        ],
      ],
    );
  }
}

// Lightweight uploader avatar widget
class _UploaderAvatar extends StatelessWidget {
  final Uploader uploader;

  const _UploaderAvatar({required this.uploader});

  @override
  Widget build(BuildContext context) {
    // Debug logging to see what data we're getting
    print(
        '🖼️ _UploaderAvatar: Building avatar for uploader: ${uploader.name}');
    print('🖼️ _UploaderAvatar: profilePic: "${uploader.profilePic}"');
    print(
        '🖼️ _UploaderAvatar: profilePic.isEmpty: ${uploader.profilePic.isEmpty}');
    print(
        '🖼️ _UploaderAvatar: profilePic.length: ${uploader.profilePic.length}');

    return CircleAvatar(
      radius: AppConstants.avatarRadius,
      backgroundColor: Colors.grey,
      child: uploader.profilePic.isNotEmpty
          ? ClipOval(
              child: Image.network(
                uploader.profilePic,
                width: AppConstants.avatarRadius * 2,
                height: AppConstants.avatarRadius * 2,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  print('🖼️ _UploaderAvatar: Image.network error: $error');
                  return _buildInitialsAvatar();
                },
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  );
                },
              ),
            )
          : _buildInitialsAvatar(),
    );
  }

  Widget _buildInitialsAvatar() {
    // Get initials from the user's name
    final initials = uploader.name.isNotEmpty
        ? uploader.name
            .split(' ')
            .map((n) => n.isNotEmpty ? n[0] : '')
            .take(2)
            .join('')
            .toUpperCase()
        : '?';

    return Container(
      width: AppConstants.avatarRadius * 2,
      height: AppConstants.avatarRadius * 2,
      decoration: BoxDecoration(
        color: Colors.blue[600],
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// Lightweight link status badge widget
class _LinkStatusBadge extends StatelessWidget {
  final String link;

  const _LinkStatusBadge({required this.link});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xCC4CAF50), // Colors.green.withOpacity(0.8)
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Link: $link',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
