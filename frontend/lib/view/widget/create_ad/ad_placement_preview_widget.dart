import 'package:flutter/material.dart';
import 'dart:io';

/// Visual preview showing where ads appear in the app
class AdPlacementPreviewWidget extends StatelessWidget {
  final String selectedAdType;
  final File? selectedImage;
  final File? selectedVideo;
  final List<File> selectedImages;

  const AdPlacementPreviewWidget({
    Key? key,
    required this.selectedAdType,
    this.selectedImage,
    this.selectedVideo,
    this.selectedImages = const [],
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (selectedAdType == 'banner' && selectedImage == null) {
      return const SizedBox.shrink();
    }
    if (selectedAdType == 'carousel' &&
        selectedImages.isEmpty &&
        selectedVideo == null) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.phone_android, color: Colors.blue.shade600),
                const SizedBox(width: 8),
                const Text(
                  'Ad Placement Preview',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildPhoneMockup(context),
          ],
        ),
      ),
    );
  }

  Widget _buildPhoneMockup(BuildContext context) {
    return Center(
      child: Container(
        width: 280,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.grey.shade800, width: 8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Column(
            children: [
              // Phone notch
              Container(
                height: 30,
                color: Colors.black,
                child: Center(
                  child: Container(
                    width: 150,
                    height: 25,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ),
              // Screen content
              Expanded(
                child: Container(
                  color: Colors.black,
                  child: _buildFeedPreview(context),
                ),
              ),
              // Bottom navigation bar
              Container(
                height: 50,
                color: Colors.grey.shade900,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    const Icon(Icons.home, color: Colors.white),
                    Icon(Icons.search, color: Colors.grey.shade600),
                    Icon(Icons.add_box, color: Colors.grey.shade600),
                    Icon(Icons.favorite_border, color: Colors.grey.shade600),
                    Icon(Icons.person_outline, color: Colors.grey.shade600),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeedPreview(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Status bar
          Container(
            height: 20,
            color: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('9:41',
                    style: TextStyle(color: Colors.white, fontSize: 10)),
                Row(
                  children: [
                    Icon(Icons.signal_cellular_4_bar,
                        color: Colors.white, size: 12),
                    const SizedBox(width: 4),
                    Icon(Icons.wifi, color: Colors.white, size: 12),
                    const SizedBox(width: 4),
                    Icon(Icons.battery_full, color: Colors.white, size: 12),
                  ],
                ),
              ],
            ),
          ),
          // App header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.black,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Yug',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                Icon(Icons.more_vert, color: Colors.white, size: 20),
              ],
            ),
          ),

          // Video feed item with ad placement (banner shows as top overlay)
          _buildVideoFeedItem(1),

          // Carousel ad placement (only for carousel ads)
          if (selectedAdType == 'carousel') _buildCarouselAdPlacement(),
        ],
      ),
    );
  }

  // (Removed old separate banner preview; banner now overlays top of video)

  Widget _buildCarouselAdPlacement() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.blue, width: 3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: Container(
              height: 400,
              color: Colors.grey.shade900,
              child: selectedVideo != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.play_circle_filled,
                              color: Colors.white, size: 40),
                          SizedBox(height: 8),
                          Text('Video Ad',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 12)),
                        ],
                      ),
                    )
                  : selectedImages.isNotEmpty
                      ? PageView.builder(
                          itemCount: selectedImages.length,
                          itemBuilder: (context, index) => Image.file(
                            selectedImages[index],
                            fit: BoxFit.cover,
                          ),
                        )
                      : Container(),
            ),
          ),
          // Highlight overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
          // Placement indicator
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.ads_click, color: Colors.white, size: 12),
                  SizedBox(width: 4),
                  Text(
                    'Carousel Ad',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoFeedItem(int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      height: 400,
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: [
          // Video placeholder
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.play_circle_outline,
                    color: Colors.grey.shade600, size: 50),
                SizedBox(height: 8),
                Text(
                  'Video $index',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ),

          // Banner ad overlay at the TOP of the video (only for banner ads)
          if (selectedAdType == 'banner' && selectedImage != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 60,
                margin: const EdgeInsets.symmetric(horizontal: 0),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.blue, width: 3),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8),
                    topRight: Radius.circular(8),
                  ),
                ),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(5),
                        topRight: Radius.circular(5),
                      ),
                      child: Image.file(
                        selectedImage!,
                        width: double.infinity,
                        height: 60,
                        fit: BoxFit.cover,
                      ),
                    ),
                    // subtle highlight
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.10),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(5),
                            topRight: Radius.circular(5),
                          ),
                        ),
                      ),
                    ),
                    // small badge
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Banner (Top)',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    )
                  ],
                ),
              ),
            ),
          // Video actions (match Yug UI): vertical action rail on RIGHT
          Positioned(
            right: 8,
            bottom: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.favorite_border, color: Colors.white, size: 26),
                SizedBox(height: 14),
                Icon(Icons.comment_outlined, color: Colors.white, size: 26),
                SizedBox(height: 14),
                Icon(Icons.share_outlined, color: Colors.white, size: 26),
                SizedBox(height: 14),
                Icon(Icons.bookmark_border, color: Colors.white, size: 26),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
