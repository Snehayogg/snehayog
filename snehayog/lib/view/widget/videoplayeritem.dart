import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoPlayerItem extends StatefulWidget {
  final VideoPlayerController controller;
  final String videoName;
  final String videoUrl;
  final int likes;
  final int views;
  final String description;
  final VoidCallback? onLikePressed;
  final VoidCallback? onVisitPressed;

  const VideoPlayerItem({
    required this.controller,
    required this.videoName,
    required this.videoUrl,
    required this.views,
    required this.likes,
    required this.description,
    this.onLikePressed,
    this.onVisitPressed,
    super.key,
  });

  @override
  State<VideoPlayerItem> createState() => _VideoPlayerItemState();
}

class _VideoPlayerItemState extends State<VideoPlayerItem> {
  bool isLiked = false;
  bool isSaved = false;

  void _onDoubleTap() {
    setState(() {
      isLiked = true;
    });
    widget.onLikePressed?.call();

    Future.delayed(const Duration(milliseconds: 800), () {
      setState(() {
        isLiked = false;
      });
    });
  }

  void _onShare() {
    Share.share('Check out this video: ${widget.videoUrl}');
  }

  void _onCommentTap() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF002B36),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 4,
                width: 40,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Comments',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const TextField(
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Add a comment...',
                  hintStyle: TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: Color(0xFF073642),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: _onDoubleTap,
      onTap: () {
        setState(() {
          widget.controller.value.isPlaying
              ? widget.controller.pause()
              : widget.controller.play();
        });
      },
      child: Stack(
        children: [
          SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: widget.controller.value.size.width,
                height: widget.controller.value.size.height,
                child: VideoPlayer(widget.controller),
              ),
            ),
          ),
          if (isLiked)
            Center(
              child: Icon(
                Icons.favorite,
                size: 100,
                color: const Color(0xFF268BD2).withOpacity(0.5),
              ),
            ),

          // Right-side Buttons
          Positioned(
            bottom: 80,
            right: 10,
            child: Column(
              children: [
                IconButton(
                  icon: Icon(
                    Icons.favorite,
                    color: isLiked ? const Color(0xFF268BD2) : Colors.white,
                    size: 32,
                  ),
                  onPressed: () {
                    setState(() {
                      isLiked = !isLiked;
                      if (isLiked) widget.onLikePressed?.call();
                    });
                  },
                ),
                Text(
                  '${widget.likes}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
                IconButton(
                  icon: const Icon(Icons.comment, color: Colors.white, size: 30),
                  onPressed: _onCommentTap,
                ),
                const SizedBox(height: 16),
                IconButton(
                  icon: Icon(
                    Icons.bookmark,
                    color: isSaved ? const Color(0xFF268BD2) : Colors.white,
                    size: 30,
                  ),
                  onPressed: () {
                    setState(() => isSaved = !isSaved);
                  },
                ),
                const SizedBox(height: 16),
                IconButton(
                  icon: const Icon(Icons.share, color: Colors.white, size: 30),
                  onPressed: _onShare,
                ),
              ],
            ),
          ),

          // Video Info & Visit Button (left side)
          Positioned(
            bottom: 90,
            left: 12,
            right: 80,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.videoName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.description,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                const SizedBox(height: 6),
                Text(
                  '${widget.views} views',
                  style: const TextStyle(
                    color: Color(0xFF586E75),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          Positioned(
            bottom: 20,
            left: 14,
            right: 14,
            child: SizedBox(
              height: 42,
              child: ElevatedButton(
                onPressed: widget.onVisitPressed,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  backgroundColor: const Color(0xFF268BD2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Visit Now',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
