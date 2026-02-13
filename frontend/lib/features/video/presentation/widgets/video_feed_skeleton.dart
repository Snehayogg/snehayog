import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class VideoFeedSkeleton extends StatelessWidget {
  const VideoFeedSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Right Side Action Buttons Skeleton
          Positioned(
            right: 8,
            bottom: 100,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildShimmerCircle(50), // Profile
                const SizedBox(height: 24),
                _buildShimmerCircle(40), // Like
                const SizedBox(height: 8),
                _buildShimmerText(30, 10), // Like Count
                const SizedBox(height: 24),
                _buildShimmerCircle(40), // Share
                const SizedBox(height: 8),
                _buildShimmerText(30, 10), // Share label
                const SizedBox(height: 24),
                _buildShimmerCircle(40), // More
              ],
            ),
          ),

          // 2. Bottom Text Area Skeleton
          Positioned(
            left: 16,
            right: 80, // Leave space for right buttons
            bottom: 40,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Username Row
                Row(
                  children: [
                    _buildShimmerCircle(32), // Tiny Profile
                    const SizedBox(width: 10),
                    _buildShimmerText(120, 16), // Username
                    const SizedBox(width: 10),
                    _buildShimmerContainer(60, 24, 4), // Follow Button
                  ],
                ),
                const SizedBox(height: 12),
                // Title / Description
                _buildShimmerText(200, 14),
                const SizedBox(height: 6),
                _buildShimmerText(150, 14),
                const SizedBox(height: 24), // Space from bottom
              ],
            ),
          ),
          
           // 3. Central Loading Indicator (Subtle overlay)
           const Center(
             child: SizedBox(
               width: 40,
               height: 40,
               child: CircularProgressIndicator(
                 strokeWidth: 2,
                 color: Colors.white24,
               ),
             ),
           ),
        ],
      ),
    );
  }

  Widget _buildShimmerCircle(double size) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[900]!,
      highlightColor: Colors.grey[800]!,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  Widget _buildShimmerText(double width, double height) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[900]!,
      highlightColor: Colors.grey[800]!,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  Widget _buildShimmerContainer(double width, double height, double radius) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[900]!,
      highlightColor: Colors.grey[800]!,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}
