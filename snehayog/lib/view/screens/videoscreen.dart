import 'package:flutter/material.dart';
import 'package:snehayog/utils/constant.dart';
import 'package:video_player/video_player.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:snehayog/view/widget/videoplayeritem.dart';

class VideoScreen extends StatefulWidget {
  const VideoScreen({super.key});

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  late PageController _pageController;
  List<VideoModel> _videos = [];
  int _currentIndex = 0;
  final List<VideoPlayerController> _controllers = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _initializeVideos();
  }

  Future<void> _initializeVideos() async {
    try {
      await loadVideos();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<List<VideoModel>> fetchVideos() async {
    try {
      final response = await http.get(
        Uri.parse('$BASE_URL/api/upload/videos'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        List jsonResponse = json.decode(response.body);
        return jsonResponse.map((data) => VideoModel.fromJson(data)).toList();
      } else {
        throw Exception('Failed to load videos: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to load videos: $e');
    }
  }

  Future<void> loadVideos() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final videos = await fetchVideos();

      if (videos.isEmpty) {
        setState(() {
          _isLoading = false;
          _videos = [];
          _controllers.clear();
        });
        return;
      }

      _videos = videos;
      _controllers.clear();

      for (var video in _videos) {
        try {
          final controller = VideoPlayerController.networkUrl(
            Uri.parse('$BASE_URL${video.url}'),
          );
          await controller.initialize();
          controller.setLooping(true);
          _controllers.add(controller);
        } catch (e) {
          print('Error initializing video controller: $e');
        }
      }

      if (_controllers.isNotEmpty) {
        _controllers[0].play();
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    if (_controllers.isNotEmpty) {
      _controllers[_currentIndex].pause();
      _controllers[index].play();
      _currentIndex = index;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body:
          _isLoading
              ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
              : _error != null
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Error: $_error',
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _initializeVideos,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
              : _controllers.isEmpty
              ? const Center(
                child: Text(
                  'No videos available',
                  style: TextStyle(color: Colors.white),
                ),
              )
              : PageView.builder(
                scrollDirection: Axis.vertical,
                controller: _pageController,
                itemCount: _controllers.length,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, index) {
                  final controller = _controllers[index];
                  return VideoPlayerItem(
                    description: _videos[index].description,
                    views: _videos[index].views,
                    likes: _videos[index].likes,
                    controller: controller,
                    videoName: _videos[index].videoName,
                    videoUrl: '$BASE_URL${_videos[index].videoUrl}',
                  );
                },
              ),
    );
  }
}
