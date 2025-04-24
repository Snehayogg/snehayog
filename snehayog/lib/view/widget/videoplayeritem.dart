import 'package:share_plus/share_plus.dart'; // For sharing
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

    Future.delayed(Duration(milliseconds: 800), () {
      setState(() {
        isLiked = false;
      });
    });
  }

  void _onShare() {
    Share.share('Check out this video: ${widget.videoUrl}');
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
                color: Colors.red.withOpacity(0.5),
              ),
            ),
          Positioned(
            bottom: 80,
            right: 10,
            child: Column(
              children: [
                IconButton(
                  icon: Icon(
                    Icons.favorite,
                    color: isLiked ? Colors.red : Colors.white,
                    size: 32,
                  ),
                  onPressed: () {
                    setState(() {
                      isLiked = !isLiked;
                      if (isLiked) {
                        widget.onLikePressed?.call();
                      }
                    });
                  },
                ),
                Text(
                  '${widget.likes}',
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 16),
                IconButton(
                  icon: Icon(
                    Icons.bookmark,
                    color: isSaved ? Colors.yellow : Colors.white,
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
          Positioned(
            bottom: 26,
            left: 10,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.videoName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.description,
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  '${widget.views} views',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
          // Visit Now Button
          Positioned(
            bottom: 5,
            left: 13,
            right: 39,
            child: Container(
              height: 40,
              margin: const EdgeInsets.symmetric(horizontal: 13),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: widget.onVisitPressed,
                  child: const Center(
                    child: Text(
                      'Visit Now',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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
