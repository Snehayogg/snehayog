import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Demo widget showcasing the Instant Thumbnail Preview feature
/// This demonstrates how thumbnails are shown immediately while videos load
class InstantThumbnailPreviewDemo extends StatelessWidget {
  const InstantThumbnailPreviewDemo({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Instant Thumbnail Preview Demo'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Feature explanation
          Container(
            padding: const EdgeInsets.all(16),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🎬 Instant Thumbnail Preview Feature',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '• Swipe करते ही पहले low-res thumbnail दिखा देते हैं\n'
                  '• Meanwhile video load होता है\n'
                  '• Seamlessly thumbnail से video में switch कर देते हैं\n'
                  '• User को कभी black screen नहीं दिखती',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),

          // Demo thumbnails
          Expanded(
            child: ListView.builder(
              itemCount: 5,
              itemBuilder: (context, index) {
                return _buildDemoThumbnail(index);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDemoThumbnail(int index) {
    // Simulate different thumbnail states
    final thumbnailStates = [
      {
        'title': 'High Quality Thumbnail',
        'description': 'Uses thumbnailUrl for best quality',
        'imageUrl': 'https://picsum.photos/400/600?random=1',
        'status': '✅ Ready',
      },
      {
        'title': 'Video URL Fallback',
        'description': 'Uses videoUrl as thumbnail when thumbnailUrl is empty',
        'imageUrl': 'https://picsum.photos/400/600?random=2',
        'status': '🔄 Loading',
      },
      {
        'title': 'Custom Fallback',
        'description': 'Shows video name and icon when no image available',
        'imageUrl': '',
        'status': '📱 Fallback',
      },
      {
        'title': 'HLS Streaming',
        'description': 'Shows HLS status badge during loading',
        'imageUrl': 'https://picsum.photos/400/600?random=4',
        'status': '🌐 HLS',
      },
      {
        'title': 'Error Handling',
        'description': 'Graceful fallback when image fails to load',
        'imageUrl': 'https://invalid-url-that-will-fail.com/image.jpg',
        'status': '⚠️ Error',
      },
    ];

    final state = thumbnailStates[index % thumbnailStates.length];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey[900],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail preview
          Container(
            height: 200,
            width: double.infinity,
            decoration: const BoxDecoration(
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              child: _buildThumbnailPreview(state),
            ),
          ),

          // Info section
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      state['title']!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getStatusColor(state['status']!),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        state['status']!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  state['description']!,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnailPreview(Map<String, String> state) {
    if (state['imageUrl']!.isEmpty) {
      // Custom fallback thumbnail
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.grey[800]!,
              Colors.grey[900]!,
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.video_library,
                size: 48,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 12),
              Text(
                'Sample Video ${state['title']}',
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      );
    }

    // Network image with loading states
    return CachedNetworkImage(
      imageUrl: state['imageUrl']!,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      placeholder: (context, url) => Container(
        color: Colors.grey[800],
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                strokeWidth: 2,
              ),
              const SizedBox(height: 12),
              Text(
                'Loading thumbnail...',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        color: Colors.red[900],
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Colors.red[300],
              ),
              const SizedBox(height: 12),
              Text(
                'Failed to load',
                style: TextStyle(
                  color: Colors.red[300],
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case '✅ Ready':
        return Colors.green;
      case '🔄 Loading':
        return Colors.blue;
      case '📱 Fallback':
        return Colors.orange;
      case '🌐 HLS':
        return Colors.purple;
      case '⚠️ Error':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
