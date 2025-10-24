import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vayu/model/video_model.dart';
import 'package:vayu/services/video_service.dart';
import 'package:vayu/services/authservices.dart';

/// **SIMPLE VIDEO SCREEN: No complex managers, no freezing**
class VideoScreenSimple extends StatefulWidget {
  final int? initialIndex;
  final List<VideoModel>? initialVideos;
  final String? initialVideoId;

  const VideoScreenSimple({
    Key? key,
    this.initialIndex,
    this.initialVideos,
    this.initialVideoId,
  }) : super(key: key);

  @override
  _VideoScreenSimpleState createState() => _VideoScreenSimpleState();
}

class _VideoScreenSimpleState extends State<VideoScreenSimple> {
  // **SIMPLE STATE: No complex managers**
  List<VideoModel> _videos = [];
  bool _isLoading = true;
  String? _currentUserId;

  // **SIMPLE SERVICES**
  late VideoService _videoService;
  late AuthService _authService;

  @override
  void initState() {
    super.initState();
    _videoService = VideoService();
    _authService = AuthService();
    _loadVideos();
    _loadCurrentUserId();
  }

  Future<void> _loadVideos() async {
    try {
      setState(() => _isLoading = true);

      final response = await _videoService.getVideos();
      final videos = response['videos'] as List<VideoModel>;

      if (mounted) {
        setState(() {
          _videos = videos;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error loading videos: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// **SIMPLE USER ID LOADING**
  Future<void> _loadCurrentUserId() async {
    try {
      final userData = await _authService.getUserData();
      if (mounted) {
        setState(() {
          _currentUserId = userData?['id'];
        });
      }
    } catch (e) {
      print('❌ Error loading user ID: $e');
    }
  }

  /// **SIMPLE REFRESH**
  Future<void> _refreshVideos() async {
    await _loadVideos();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'Videos',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _refreshVideos,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white),
            )
          : _videos.isEmpty
              ? const Center(
                  child: Text(
                    'No videos available',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                )
              : _buildVideoList(),
    );
  }

  /// **SIMPLE VIDEO LIST: No PageView, no complex scrolling**
  Widget _buildVideoList() {
    return RefreshIndicator(
      onRefresh: _refreshVideos,
      color: Colors.blue,
      backgroundColor: Colors.black,
      child: ListView.builder(
        itemCount: _videos.length,
        itemBuilder: (context, index) {
          final video = _videos[index];
          return _buildVideoCard(video, index);
        },
      ),
    );
  }

  /// **SIMPLE VIDEO CARD: Minimal widget to prevent freezing**
  Widget _buildVideoCard(VideoModel video, int index) {
    return Container(
      height: 300,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Video thumbnail
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
                image: video.thumbnailUrl.isNotEmpty
                    ? DecorationImage(
                        image: NetworkImage(video.thumbnailUrl),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: video.thumbnailUrl.isEmpty
                  ? const Center(
                      child: Icon(Icons.video_library,
                          size: 64, color: Colors.white54),
                    )
                  : Stack(
                      children: [
                        // Play button overlay
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_arrow,
                              color: Colors.white,
                              size: 48,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),

          // Video info
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  video.videoName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'By ${video.uploader.name}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.favorite_border,
                        color: Colors.white70, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '${video.likes}',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(width: 16),
                    const Icon(Icons.comment_outlined,
                        color: Colors.white70, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '${video.comments.length}',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const Spacer(),
                    // Like button
                    GestureDetector(
                      onTap: () => _handleLike(video, index),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isLiked(video)
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color: _isLiked(video) ? Colors.red : Colors.white70,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// **SIMPLE LIKE HANDLING**
  bool _isLiked(VideoModel video) {
    return _currentUserId != null && video.likedBy.contains(_currentUserId);
  }

  /// **SIMPLE LIKE ACTION**
  void _handleLike(VideoModel video, int index) {
    if (_currentUserId == null) return;

    setState(() {
      if (video.likedBy.contains(_currentUserId)) {
        video.likedBy.remove(_currentUserId);
        video.likes = (video.likes - 1).clamp(0, double.infinity).toInt();
      } else {
        video.likedBy.add(_currentUserId!);
        video.likes++;
      }
    });
  }

  @override
  void dispose() {
    // **SIMPLE DISPOSE: No complex cleanup needed**
    super.dispose();
  }
}
