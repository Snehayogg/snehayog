import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/view/widget/videoplayeritem.dart';
import 'package:snehayog/model/carousel_model.dart';
import 'package:snehayog/view/widget/carousel_item.dart';
import 'package:snehayog/view/widget/carousel_indicator.dart';

class VideoScreen extends StatelessWidget {
  const VideoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF002B36),
      body: const ReelsWithAds(),
    );
  }
}

class ReelsWithAds extends StatefulWidget {
  const ReelsWithAds({super.key});
  @override
  State<ReelsWithAds> createState() => _ReelsWithAdsState();
}

class _ReelsWithAdsState extends State<ReelsWithAds> {
  final PageController _verticalPageController = PageController();
  final PageController _horizontalPageController = PageController();
  final List<VideoPlayerController> _controllers = [];
  List<VideoModel> _videos = [];
  List<CarouselItem> _ads = [];
  int _videoIndex = 0;
  int _adIndex = 0;
  bool _showAds = false;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    _verticalPageController.dispose();
    _horizontalPageController.dispose();
    super.dispose();
  }

  Future<void> _loadContent() async {
    // Load ads data
    _ads = [
      CarouselItem(
        id: 'ad1',
        type: 'ad',
        imageUrl: 'https://picsum.photos/800/600',
        adTitle: 'Special Discount',
        adDescription: 'Get 20% Off on Yoga Gear!',
        adLink: 'https://example.com',
      ),
      CarouselItem(
        id: 'ad2',
        type: 'ad',
        imageUrl: 'https://picsum.photos/800/601',
        adTitle: 'Mindfulness App',
        adDescription: 'Try free for 7 days!',
        adLink: 'https://mindapp.com',
      ),
    ];

    // Load video data
    _videos = [
      VideoModel(
        videoName: "Yoga Session",
        description: "Peaceful yoga routine",
        videoUrl: "https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4",
        views: 0,
        likes: 0,
        uploader: "Instructor A",
        uploadedAt: DateTime.now(),
        videoType: 'yog',
        duration: const Duration(seconds: 30),
      ),
      VideoModel(
        videoName: "Meditation",
        description: "Short breathing practice",
        videoUrl: "https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4",
        views: 0,
        likes: 0,
        uploader: "Instructor B",
        uploadedAt: DateTime.now(),
        videoType: 'yog',
        duration: const Duration(seconds: 40),
      ),
    ];

    // Initialize controllers for each video
    for (var video in _videos) {
      final controller = VideoPlayerController.network(video.videoUrl);
      await controller.initialize();
      controller.setLooping(true);
      _controllers.add(controller);
    }

    // Play the first video if controllers are initialized
    if (_controllers.isNotEmpty) {
      _controllers[0].play();
    }

    // Update UI after loading content
    setState(() {});
  }

  void _onVerticalPageChanged(int index) {
    if (_controllers.isNotEmpty && index < _controllers.length) {
      _controllers[_videoIndex].pause();
      _videoIndex = index;
      _controllers[_videoIndex].play();
    }
  }

  void _onHorizontalPageChanged(int index) {
    if (_ads.isNotEmpty && index < _ads.length) {
      setState(() {
        _adIndex = index;
      });
    }
  }

  void _handleHorizontalSwipe(DragEndDetails details) {
    if (!_showAds) {
      setState(() {
        if (_controllers.isNotEmpty && _videoIndex < _controllers.length) {
          _controllers[_videoIndex].pause();
        }
        _showAds = true;
      });
    }
  }

  void _handleVerticalSwipe(DragEndDetails details) {
    if (_showAds) {
      setState(() {
        _showAds = false;
        if (_controllers.isNotEmpty && _videoIndex < _controllers.length) {
          _controllers[_videoIndex].play();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Offstage(
          offstage: _showAds,
          child: PageView.builder(
            scrollDirection: Axis.vertical,
            controller: _verticalPageController,
            onPageChanged: _onVerticalPageChanged,
            itemCount: _videos.length,
            itemBuilder: (context, index) {
              if (index < _videos.length && index < _controllers.length) {
                return VideoPlayerItem(
                  videoName: _videos[index].videoName,
                  description: _videos[index].description,
                  views: _videos[index].views,
                  likes: _videos[index].likes,
                  controller: _controllers[index],
                  videoUrl: _videos[index].videoUrl,
                  onLikePressed: () {},
                  onVisitPressed: () {},
                );
              }
              return Container(); // Default empty container if index is out of range
            },
          ),
        ),
        Offstage(
          offstage: !_showAds,
          child: PageView.builder(
            scrollDirection: Axis.horizontal,
            controller: _horizontalPageController,
            onPageChanged: _onHorizontalPageChanged,
            itemCount: _ads.length,
            itemBuilder: (context, index) {
              if (index < _ads.length) {
                return CarouselItemWidget(
                  item: _ads[index],
                  onAdTap: () => print('Ad tapped: ${_ads[index].adLink}'),
                );
              }
              return Container(); // Default empty container if index is out of range
            },
          ),
        ),
        Positioned.fill(
          child: GestureDetector(
            onHorizontalDragEnd: _handleHorizontalSwipe,
            onVerticalDragEnd: _handleVerticalSwipe,
          ),
        ),
      ],
    );
  }
}
