import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:snehayog/utils/responsive_helper.dart';
import 'package:snehayog/view/screens/video_detail_screen.dart';
import 'package:snehayog/services/video_service.dart';

class SnehaScreen extends StatefulWidget {
  const SnehaScreen({super.key});

  @override
  State<SnehaScreen> createState() => _SnehaScreenState();
}

class _SnehaScreenState extends State<SnehaScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _videos = [];
  bool _isLoading = false;
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  final bool _isPlaying = false;
  int? _selectedVideoIndex;

  static const int maxShortVideoDuration = 120;

  Future<Duration?> _getVideoDuration(String videoPath) async {
    try {
      final controller = VideoPlayerController.file(File(videoPath));
      await controller.initialize();
      final duration = controller.value.duration;
      await controller.dispose();
      return duration;
    } catch (e) {
      print('Error getting video duration: $e');
      return null;
    }
  }

  Future<bool> _isLongVideo(String videoPath) async {
    final duration = await _getVideoDuration(videoPath);
    return duration != null && duration.inSeconds > maxShortVideoDuration;
  }

  Future<void> _handleVideoUpload(String videoPath) async {
    try {
      final isLong = await _isLongVideo(videoPath);
      if (isLong) {
        // Show dialog for title and description
        final result = await showDialog<Map<String, String>>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Enter Video Details'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    hintText: 'Enter video title',
                  ),
                  onChanged: (value) => _tempTitle = value,
                ),
                const SizedBox(height: 16),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'Enter video description',
                  ),
                  maxLines: 3,
                  onChanged: (value) => _tempDescription = value,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  if (_tempTitle?.isNotEmpty == true) {
                    Navigator.pop(context, {
                      'title': _tempTitle!,
                      'description': _tempDescription ?? '',
                    });
                  }
                },
                child: const Text('Upload'),
              ),
            ],
          ),
        );

        if (result != null) {
          setState(() => _isLoading = true);

          // Upload video using VideoService
          final videoService = VideoService();
          final uploadedVideo = await videoService.uploadVideo(
            File(videoPath),
            result['title']!,
            result['description']!,
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Video uploaded successfully!'),
                backgroundColor: Colors.green,
              ),
            );

            // Add the uploaded video to the list
            setState(() {
              _videos.add({
                'title': uploadedVideo['title'],
                'thumbnail': uploadedVideo['thumbnail'],
                'duration': 'Long Video',
                'views': '0 views',
                'uploader': uploadedVideo['uploader'],
                'uploadTime': 'Just now',
                'videoUrl': uploadedVideo['videoUrl'],
              });
              _isLoading = false;
            });
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'This video is too short for long videos section. Please upload it in the short videos section.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      print('Error uploading video: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error uploading video: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String? _tempTitle;
  String? _tempDescription;

  @override
  void initState() {
    super.initState();
    _loadDummyVideos();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  void _loadDummyVideos() {
    _videos = [
      {
        'title': 'Complete Yoga Tutorial for Beginners',
        'thumbnail': 'https://picsum.photos/400/225?random=1',
        'duration': '15:30',
        'views': '1.2M views',
        'uploader': 'Yoga Master',
        'uploadTime': '2 weeks ago',
        'videoUrl':
            'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4',
      },
      {
        'title': 'Advanced Meditation Techniques',
        'thumbnail': 'https://picsum.photos/400/225?random=2',
        'duration': '20:15',
        'views': '856K views',
        'uploader': 'Mind & Body',
        'uploadTime': '1 month ago',
        'videoUrl':
            'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4',
      },
      // Add more dummy videos as needed...
    ];
  }

  Future<void> _playVideo(String videoUrl) async {
    final video = _videos.firstWhere((v) => v['videoUrl'] == videoUrl);
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VideoDetailScreen(video: video),
        ),
      );
    }
  }

  Future<void> _performSearch() async {
    setState(() => _isLoading = true);
    final query = _searchController.text.toLowerCase();

    if (query.isEmpty) {
      _loadDummyVideos();
    } else {
      _videos = _videos.where((video) {
        return video['title'].toLowerCase().contains(query) ||
            video['uploader'].toLowerCase().contains(query);
      }).toList();
    }

    setState(() => _isLoading = false);
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: ResponsiveHelper.getAdaptivePadding(context),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          onSubmitted: (_) => _performSearch(),
          style: TextStyle(
            color: const Color(0xFF424242),
            fontSize: ResponsiveHelper.getAdaptiveFontSize(context, 16),
          ),
          decoration: InputDecoration(
            hintText: 'Search videos...',
            hintStyle: TextStyle(
              color: const Color(0xFF757575).withOpacity(0.7),
              fontSize: ResponsiveHelper.getAdaptiveFontSize(context, 16),
            ),
            prefixIcon: Icon(
              Icons.search,
              color: const Color(0xFF424242),
              size: ResponsiveHelper.getAdaptiveIconSize(context),
            ),
            suffixIcon: IconButton(
              icon: Icon(
                Icons.clear,
                color: const Color(0xFF757575),
                size: ResponsiveHelper.getAdaptiveIconSize(context),
              ),
              onPressed: () {
                _searchController.clear();
                _loadDummyVideos();
              },
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(30),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: Colors.transparent,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoCard(Map<String, dynamic> video) {
    return GestureDetector(
      onTap: () => _playVideo(video['videoUrl']),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(15)),
                  child: Image.network(
                    video['thumbnail'],
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      video['duration'],
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video['title'],
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      video['uploader'],
                      style: const TextStyle(
                          color: Color(0xFF757575), fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${video['views']} • ${video['uploadTime']}',
                      style: const TextStyle(
                          color: Color(0xFF757575), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            _buildSearchBar(),
            if (_isPlaying && _chewieController != null) ...[
              const SizedBox(height: 16),
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Chewie(controller: _chewieController!),
              ),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Padding(
                      padding: ResponsiveHelper.getAdaptivePadding(context),
                      child: GridView.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount:
                              ResponsiveHelper.isMobile(context) ? 1 : 2,
                          childAspectRatio: 1.5,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        itemCount: _videos.length,
                        itemBuilder: (context, index) {
                          return _buildVideoCard(_videos[index]);
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
