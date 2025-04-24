import 'package:flutter/material.dart';
import 'package:snehayog/utils/constant.dart';
import 'package:video_player/video_player.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:snehayog/view/widget/videoplayeritem.dart';

class VideoScreen extends StatelessWidget {
  const VideoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
            title: const TabBar(
              indicatorColor: Colors.white,
              indicatorSize: TabBarIndicatorSize.label,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.grey,
              labelStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              tabs: [Tab(text: 'Yog'), Tab(text: 'Sneha')],
            ),
          ),
        ),
        body: const TabBarView(
          children: [
            ForYouFeed(), // You can swap these if you want different logic
            FollowingFeed(),
          ],
        ),
      ),
    );
  }
}

// You can reuse the same widget for both tabs or customize if needed
class ForYouFeed extends StatefulWidget {
  const ForYouFeed({super.key});
  @override
  State<ForYouFeed> createState() => _ForYouFeedState();
}

class FollowingFeed extends StatefulWidget {
  const FollowingFeed({super.key});
  @override
  State<FollowingFeed> createState() => _FollowingFeedState();
}

class _ForYouFeedState extends State<ForYouFeed> {
  late PageController _pageController;
  List<VideoModel> _videos = [];
  int _currentIndex = 0;
  final List<VideoPlayerController> _controllers = [];
  bool _isLoading = true;
  String? _error;

  void _incrementViews(int index) {
    setState(() {
      _videos[index] = _videos[index].copyWith(views: _videos[index].views + 1);
    });
  }

  void _incrementLikes(int index) {
    setState(() {
      _videos[index] = _videos[index].copyWith(likes: _videos[index].likes + 1);
    });
  }

  void _handleVisit(int index) {
    // Here you can implement what happens when Visit Now is pressed
    // For example, navigate to a details page or open a URL
    print('Visit Now pressed for video: ${_videos[index].videoName}');
    // You can add navigation logic here
  }

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
    // Dummy video data for testing UI with real video URLs
    return [
      VideoModel(
        videoName: "Sample Video 1",
        description: "This is a sample video description",
        videoUrl:
            "https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4",
        views: 0, // Start with 0 views
        likes: 0, // Start with 0 likes
        uploader: "User1",
        uploadedAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
      VideoModel(
        videoName: "Sample Video 2",
        description: "Another sample video for testing",
        videoUrl:
            "https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4",
        views: 0,
        likes: 0,
        uploader: "User2",
        uploadedAt: DateTime.now().subtract(const Duration(days: 2)),
      ),
      VideoModel(
        videoName: "Sample Video 3",
        description: "Testing the video player UI",
        videoUrl:
            "https://flutter.github.io/assets-for-api-docs/assets/videos/sea.mp4",
        views: 0,
        likes: 0,
        uploader: "User3",
        uploadedAt: DateTime.now().subtract(const Duration(days: 3)),
      ),
    ];
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
            Uri.parse(video.videoUrl),
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
      _incrementViews(index); // Increment views when video is viewed
      _currentIndex = index;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? const Center(child: CircularProgressIndicator(color: Colors.white))
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
              videoUrl: _videos[index].videoUrl,
              onLikePressed: () => _incrementLikes(index),
              onVisitPressed: () => _handleVisit(index),
            );
          },
        );
  }
}

class _FollowingFeedState extends State<FollowingFeed> {
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
    // Dummy video data for testing UI with real video URLs
    return [
      VideoModel(
        videoName: "Sample Video 1",
        description: "This is a sample video description",
        videoUrl:
            "https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4",
        views: 1000,
        likes: 500,
        uploader: "User1",
        uploadedAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
      VideoModel(
        videoName: "Sample Video 2",
        description: "Another sample video for testing",
        videoUrl:
            "https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4",
        views: 2000,
        likes: 800,
        uploader: "User2",
        uploadedAt: DateTime.now().subtract(const Duration(days: 2)),
      ),
      VideoModel(
        videoName: "Sample Video 3",
        description: "Testing the video player UI",
        videoUrl:
            "https://flutter.github.io/assets-for-api-docs/assets/videos/sea.mp4",
        views: 3000,
        likes: 1200,
        uploader: "User3",
        uploadedAt: DateTime.now().subtract(const Duration(days: 3)),
      ),
    ];
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
            Uri.parse(video.videoUrl),
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
    return _isLoading
        ? const Center(child: CircularProgressIndicator(color: Colors.white))
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
        );
  }
}
