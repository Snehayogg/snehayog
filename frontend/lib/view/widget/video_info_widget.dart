import 'package:flutter/material.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/core/constants/app_constants.dart';
import 'package:snehayog/view/screens/profile_screen.dart';
import 'package:snehayog/view/widget/follow_button_widget.dart';
import 'package:url_launcher/url_launcher.dart';

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
          // Video title - **REDUCED from 15 to 13**
          Text(
            video.videoName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          // **REDUCED spacing from 4 to 2**
          const SizedBox(height: 2),

          // Video description (limited to 2 lines) - **REDUCED from 13 to 11**
          if (video.description != null && video.description!.isNotEmpty)
            Text(
              video.description!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          // **REDUCED spacing from 8 to 4**
          const SizedBox(height: 4),

          // Uploader information (tappable to go to profile)
          _UploaderInfoSection(video: video),

          // Visit Now button below uploader info (if video has a link)
          if (video.link != null && video.link!.isNotEmpty) ...[
            const SizedBox(height: 4),
            _VisitNowButton(link: video.link!),
          ],
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
                      // **REDUCED from 13 to 11**
                      fontSize: 11,
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
            // **REDUCED from 12 to 10 to match smaller avatar**
            fontSize: 10,
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

// Visit Now button widget
class _VisitNowButton extends StatelessWidget {
  final String link;

  const _VisitNowButton({required this.link});

  @override
  Widget build(BuildContext context) {
    return Container(
      // **UPDATED: Increased width significantly while keeping height same**
      width: MediaQuery.of(context).size.width * 0.75, // 60% of screen width
      margin: const EdgeInsets.only(right: 8),
      child: ElevatedButton(
        onPressed: () async {
          final Uri uri = Uri.parse(link);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } else {
            // Handle error, e.g., show a snackbar
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not open link: $link')),
            );
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(
              0x99444444), // Grey color with 0.6 opacity (99 in hex = 153/255 ≈ 0.6)
          foregroundColor: Colors.white,
          surfaceTintColor:
              Colors.transparent, // Remove Material 3 surface tint
          shadowColor: Colors.transparent, // Remove shadow
          // **KEEPING same height - only vertical padding unchanged**
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
          elevation: 0, // Set to 0 for transparent effect
          // **NEW: Ensure button takes full width of container**
          minimumSize: const Size(double.infinity, 0),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          // **UPDATED: Use max to fill the button width**
          mainAxisSize: MainAxisSize.max,
          children: [
            // **REDUCED icon size from 16 to 14**
            Icon(Icons.open_in_new, color: Colors.white, size: 14),
            // **REDUCED spacing from 8 to 6**
            SizedBox(width: 6),
            Text(
              'Visit Now',
              style: TextStyle(
                color: Colors.white,
                // **REDUCED from 13 to 11**
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
