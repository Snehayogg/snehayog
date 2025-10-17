import 'package:flutter/material.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/view/screens/image_feed_advanced.dart';

class VayuScreen extends StatefulWidget {
  final int? initialIndex;
  final List<VideoModel>? initialVideos;
  final String? initialVideoId;

  const VayuScreen({
    Key? key,
    this.initialIndex,
    this.initialVideos,
    this.initialVideoId,
  }) : super(key: key);

  @override
  State<VayuScreen> createState() => _VayuScreenState();
}

class _VayuScreenState extends State<VayuScreen> {
  final GlobalKey _videoFeedKey = GlobalKey();

  /// **PUBLIC: Refresh image list after upload**
  Future<void> refreshImages() async {
    final imageFeedState = _videoFeedKey.currentState;
    if (imageFeedState != null) {
      // Cast to dynamic to access the refreshVideos method
      await (imageFeedState as dynamic).refreshVideos();
    }
  }

  /// **Show Vayu Benefits Guide**
  void _showVayuGuide() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) => Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              controller: scrollController,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade100,
                          shape: BoxShape.circle,
                        ),
                        child:
                            Icon(Icons.storefront, color: Colors.blue.shade700),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'What is Vayu?',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      )
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildBenefitPoint(
                    icon: Icons.local_offer,
                    title: '25-30% Discount on Every Product',
                    description:
                        'You will get exclusive discounts on all products. Snehayog connects you directly with brands for better deals.',
                    color: Colors.green,
                  ),
                  _buildBenefitPoint(
                    icon: Icons.money_off,
                    title: 'Zero Commission for Sellers',
                    description:
                        'Unlike Amazon, Flipkart, and other marketplaces that charge 15-25% commission, Snehayog charges NO commission. Keep 100% of your profits and grow your business faster.',
                    color: Colors.orange,
                  ),
                  _buildBenefitPoint(
                    icon: Icons.business,
                    title: 'Direct Customer Ownership',
                    description:
                        'On Amazon, customers remember Amazon, not your brand. With Snehayog, customers remember YOUR brand, building long-term relationships and repeat business.',
                    color: Colors.purple,
                  ),
                  _buildBenefitPoint(
                    icon: Icons.trending_up,
                    title: 'Long-term Brand Building vs Short-term Sales',
                    description:
                        'Amazon = Great for short-term sales, Snehayog = Great for long-term brand building. Build a sustainable business that customers trust and return to.',
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        // Navigate to upload screen
                        Navigator.pushNamed(context, '/upload');
                      },
                      icon: const Icon(Icons.upload),
                      label: const Text('Start Uploading Images'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: Colors.blue.shade600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBenefitPoint({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Vayu',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.blue[600],
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _showVayuGuide,
            icon: const Icon(Icons.help_outline, color: Colors.white),
            tooltip: 'Why Choose Snehayog?',
          ),
        ],
      ),
      body: ImageFeedAdvanced(
        key: _videoFeedKey,
        initialIndex: widget.initialIndex,
        initialImages: widget.initialVideos,
        initialImageId: widget.initialVideoId,
        videoType: 'vayu',
      ),
    );
  }
}
