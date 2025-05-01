import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:snehayog/model/video_model.dart';

class AdVideoScreen extends StatefulWidget {
  final VideoModel video;

  const AdVideoScreen({super.key, required this.video});

  @override
  State<AdVideoScreen> createState() => _AdVideoScreenState();
}

class _AdVideoScreenState extends State<AdVideoScreen> {
  late VideoPlayerController _controller;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.network(widget.video.videoUrl)
      ..initialize().then((_) {
        setState(() {});
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF002B36),
      appBar: AppBar(
        backgroundColor: const Color(0xFF002B36),
        title: Text(widget.video.videoName),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Video Player
            AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  VideoPlayer(_controller),
                  IconButton(
                    icon: Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                      size: 50,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      setState(() {
                        _isPlaying = !_isPlaying;
                        if (_isPlaying) {
                          _controller.play();
                        } else {
                          _controller.pause();
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
            // Video Details
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.video.videoName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Uploaded by ${widget.video.uploader}',
                    style: const TextStyle(
                      color: Color(0xFF586E75),
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.video.description,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.thumb_up, color: Colors.white),
                        onPressed: () {
                          // TODO: Implement like functionality
                        },
                      ),
                      Text(
                        '${widget.video.likes}',
                        style: const TextStyle(color: Colors.white),
                      ),
                      const SizedBox(width: 20),
                      IconButton(
                        icon: const Icon(Icons.visibility, color: Colors.white),
                        onPressed: () {
                          // TODO: Implement view count functionality
                        },
                      ),
                      Text(
                        '${widget.video.views}',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      // TODO: Implement visit functionality
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF268BD2),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 30,
                        vertical: 15,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: const Text('Visit Now'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
