import 'package:flutter/material.dart';
import 'package:vayu/model/video_model.dart';

class BottomMetaSection extends StatelessWidget {
  final VideoModel video;
  final VoidCallback onProfileTap;
  final VoidCallback? onVisitNow;

  const BottomMetaSection({
    super.key,
    required this.video,
    required this.onProfileTap,
    this.onVisitNow,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onProfileTap,
            child: Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onProfileTap,
                  child: CircleAvatar(
                    radius: 16,
                    backgroundImage: video.uploader.profilePic.isNotEmpty
                        ? NetworkImage(video.uploader.profilePic)
                        : null,
                    child: video.uploader.profilePic.isEmpty
                        ? Text(
                            video.uploader.name.isNotEmpty
                                ? video.uploader.name[0].toUpperCase()
                                : 'U',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: onProfileTap,
                    child: Text(
                      video.uploader.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            video.videoName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          if (video.link?.isNotEmpty == true && onVisitNow != null)
            GestureDetector(
              onTap: onVisitNow,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.75,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.open_in_new, color: Colors.white, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'Visit Now',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
