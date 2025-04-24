
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

  const VideoPlayerItem({
    required this.controller,
    required this.videoName,
    required this.videoUrl,
    required this.views,
    required this.likes,
    required this.description,
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
                color: Colors.red.withValues(alpha: 10),
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
                    setState(() => isLiked = !isLiked);
                  },
                ),
                SizedBox(height: 16),
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
                SizedBox(height: 16),
                IconButton(
                  icon: Icon(Icons.share, color: Colors.white, size: 28),
                  onPressed: _onShare,
                ),
              ],
            ),
          ),
          Positioned(
            left: 16,
            bottom: 16,
            child: Text(
              widget.videoName,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                shadows: [
                  Shadow(
                    blurRadius: 6,
                    color: Colors.black,
                    offset: Offset(1, 1),
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
