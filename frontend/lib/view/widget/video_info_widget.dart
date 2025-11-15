import 'package:flutter/material.dart';
import 'package:vayu/model/video_model.dart';
import 'package:vayu/core/constants/app_constants.dart';
import 'package:vayu/view/screens/profile_screen.dart';
import 'package:vayu/view/widget/follow_button_widget.dart';
import 'package:url_launcher/url_launcher.dart';

class VideoInfoWidget extends StatefulWidget {
  final VideoModel video;

  const VideoInfoWidget({
    Key? key,
    required this.video,
  }) : super(key: key);

  @override
  State<VideoInfoWidget> createState() => _VideoInfoWidgetState();
}

class _VideoInfoWidgetState extends State<VideoInfoWidget> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    // Check if title is long enough to need truncation (reduced threshold for better UX)
    final isLongTitle = widget.video.videoName.length > 20;

    return RepaintBoundary(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Video title with "view more" functionality
          GestureDetector(
            onTap: isLongTitle
                ? () {
                    setState(() {
                      _isExpanded = !_isExpanded;
                    });
                  }
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.video.videoName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: _isExpanded ? null : 1,
                  overflow: _isExpanded
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                ),
                // Show "view more" / "view less" text if title is long
                if (isLongTitle)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _isExpanded ? 'view less' : 'view more',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // **REDUCED spacing from 4 to 2**
          const SizedBox(height: 2),

          // Video description (limited to 2 lines) - **REDUCED from 13 to 11**
          if (widget.video.description != null &&
              widget.video.description!.isNotEmpty)
            Text(
              widget.video.description!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          // **REDUCED spacing from 8 to 4**
          const SizedBox(height: 2),

          // Uploader information (tappable to go to profile)
          _UploaderInfoSection(video: widget.video),

          // Visit Now button below uploader info (if video has a link)
          // **DEBUG: Add logging to check link status**
          Builder(
            builder: (context) {
              if (widget.video.link != null && widget.video.link!.isNotEmpty) {
                return Column(
                  children: [
                    const SizedBox(height: 2),
                    _VisitNowButton(link: widget.video.link!),
                  ],
                );
              } else {
                return const SizedBox.shrink();
              }
            },
          ),
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
                const SizedBox(width: 6),
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
        const SizedBox(width: 4),
        FollowButtonWidget(
          uploaderId: (video.uploader.googleId?.trim().isNotEmpty == true)
              ? video.uploader.googleId!.trim()
              : video.uploader.id,
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
          // **REDUCED padding for more compact button**
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
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
