import 'package:flutter/material.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/services/video_service.dart';
import 'package:snehayog/view/widget/image_item_with_interactions.dart';

/// Advanced Image Feed Screen for Vayu Tab
/// Professional light mode design with infinite scroll
class ImageFeedAdvanced extends StatefulWidget {
  final int? initialIndex;
  final List<VideoModel>? initialImages;
  final String? initialImageId;
  final String videoType;

  const ImageFeedAdvanced({
    Key? key,
    this.initialIndex,
    this.initialImages,
    this.initialImageId,
    required this.videoType,
  }) : super(key: key);

  @override
  State<ImageFeedAdvanced> createState() => _ImageFeedAdvancedState();
}

class _ImageFeedAdvancedState extends State<ImageFeedAdvanced> {
  final VideoService _videoService = VideoService();
  final ScrollController _scrollController = ScrollController();

  List<VideoModel> _images = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _currentPage = 1;

  @override
  void initState() {
    super.initState();
    _initializeImages();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _initializeImages() {
    if (widget.initialImages != null && widget.initialImages!.isNotEmpty) {
      setState(() {
        _images = widget.initialImages!;
      });
    } else {
      _loadImages();
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && _hasMore) {
        _loadMoreImages();
      }
    }
  }

  Future<void> _loadImages({bool refresh = false}) async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      if (refresh) {
        _currentPage = 1;
        _images.clear();
        _hasMore = true;
      }
    });

    try {
      final response = await _videoService.getVideos(
        page: _currentPage,
        limit: 10,
        videoType: widget.videoType,
      );

      final List<VideoModel> newImages = response['videos'] ?? [];

      setState(() {
        if (refresh) {
          _images = newImages;
        } else {
          _images.addAll(newImages);
        }
        _hasMore = newImages.length == 10;
        _currentPage++;
      });
    } catch (e) {
      print('❌ Error loading images: $e');
      _showErrorSnackbar('Failed to load images');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMoreImages() async {
    await _loadImages();
  }

  Future<void> refreshVideos() async {
    await _loadImages(refresh: true);
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[50],
      child: _images.isEmpty && _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _images.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: () => _loadImages(refresh: true),
                  child: CustomScrollView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            if (index < _images.length) {
                              return ImageItemWithInteractions(
                                image: _images[index],
                                onLike: () => _handleLike(_images[index]),
                                onComment: () => _handleComment(_images[index]),
                                onShare: () => _handleShare(_images[index]),
                                onVisit: () => _handleVisit(_images[index]),
                              );
                            } else if (_isLoading) {
                              return const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            } else {
                              return const SizedBox.shrink();
                            }
                          },
                          childCount: _images.length + (_isLoading ? 1 : 0),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.image,
                size: 64,
                color: Colors.blue.shade600,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No Images Yet',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Be the first to share beautiful images with the community!',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                // Navigate to upload screen
                Navigator.pushNamed(context, '/upload');
              },
              icon: const Icon(Icons.add),
              label: const Text('Upload Image'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[600],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleLike(VideoModel image) {
    // TODO: Implement like functionality
    print('👍 Liked image: ${image.id}');
  }

  void _handleComment(VideoModel image) {
    // TODO: Implement comment functionality
    print('💬 Comment on image: ${image.id}');
  }

  void _handleShare(VideoModel image) {
    // TODO: Implement share functionality
    print('📤 Share image: ${image.id}');
  }

  void _handleVisit(VideoModel image) {
    if (image.link != null && image.link!.isNotEmpty) {
      // TODO: Open link in browser
      print('🔗 Visit link: ${image.link}');
    }
  }
}
