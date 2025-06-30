import 'dart:async';
import 'package:flutter/material.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/services/video_service.dart';
import 'package:snehayog/view/widget/video_player_widget.dart';

class VideoScreen extends StatefulWidget {
  const VideoScreen({Key? key}) : super(key: key);

  @override
  _VideoScreenState createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  final VideoService _videoService = VideoService();
  final List<VideoModel> _videos = [];
  final PageController _pageController = PageController();

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 1;
  int _activePage = 0;

  @override
  void initState() {
    super.initState();
    _loadVideos();
    _pageController.addListener(() {
      if (_pageController.position.pixels >=
              _pageController.position.maxScrollExtent - 200 &&
          !_isLoadingMore) {
        _loadVideos(isInitialLoad: false);
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadVideos({bool isInitialLoad = true}) async {
    if (!_hasMore || (_isLoadingMore && !isInitialLoad)) return;

    setState(() {
      if (isInitialLoad) {
        _isLoading = true;
      } else {
        _isLoadingMore = true;
      }
    });

    try {
      final response = await _videoService.getVideos(page: _currentPage);
      final List<VideoModel> fetchedVideos = response['videos'];
      final bool hasMore = response['hasMore'];

      if (mounted) {
        setState(() {
          _videos.addAll(fetchedVideos);
          _hasMore = hasMore;
          _currentPage++;
          if (isInitialLoad) {
            _isLoading = false;
          } else {
            _isLoadingMore = false;
          }
        });
      }
    } catch (e) {
      print("Error loading videos: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _buildVideoPlayer(),
    );
  }

  Widget _buildVideoPlayer() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_videos.isEmpty) {
      return const Center(child: Text("No videos found."));
    }

    return PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.vertical,
      itemCount: _videos.length + (_hasMore ? 1 : 0),
      onPageChanged: (index) {
        setState(() {
          _activePage = index;
        });
      },
      itemBuilder: (context, index) {
        if (index == _videos.length) {
          return const Center(child: CircularProgressIndicator());
        }
        final video = _videos[index];
        return Stack(
          fit: StackFit.expand,
          children: [
            VideoPlayerWidget(
              key: ValueKey(video.id),
              videoUrl: video.videoUrl,
              isCurrentPage: index == _activePage,
            ),
            _buildVideoOverlay(video),
          ],
        );
      },
    );
  }

  Widget _buildVideoOverlay(VideoModel video) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            video.videoName,
            style: const TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            video.description,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Placeholder for uploader info
              Row(
                children: [
                  const CircleAvatar(radius: 16, backgroundColor: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    video.uploader.name,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  )
                ],
              ),
              // Action buttons
              Row(
                children: [
                  _buildActionButton(
                      icon: Icons.favorite, label: video.likes.toString()),
                  const SizedBox(width: 20),
                  _buildActionButton(
                      icon: Icons.comment,
                      label: video.comments.length.toString()),
                  const SizedBox(width: 20),
                  _buildActionButton(
                      icon: Icons.share, label: video.shares.toString()),
                ],
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _buildActionButton({required IconData icon, required String label}) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 30),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ],
    );
  }
}
