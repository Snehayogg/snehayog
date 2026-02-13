import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:vayu/shared/models/video_model.dart';
import 'package:vayu/shared/models/carousel_ad_model.dart';
import 'package:vayu/features/ads/presentation/widgets/carousel_ad_widget.dart';

/// Optimized widget components extracted from VideoFeedAdvanced
/// These widgets use const constructors and RepaintBoundary for better performance

/// Green spinner widget - memoized with const
class GreenSpinner extends StatelessWidget {
  final double size;

  const GreenSpinner({Key? key, this.size = 24}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: const CircularProgressIndicator(
        strokeWidth: 3,
        color: Colors.green,
      ),
    );
  }
}

/// Video progress bar - wrapped in RepaintBoundary for isolation
class VideoProgressBarWidget extends StatelessWidget {
  final VideoPlayerController controller;
  final Function(VideoPlayerController, dynamic) onSeek;

  const VideoProgressBarWidget({
    Key? key,
    required this.controller,
    required this.onSeek,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: controller,
        builder: (context, value, child) {
          if (!value.isInitialized) {
            return const SizedBox.shrink();
          }

          final duration = value.duration;
          final position = value.position;
          final progress = duration.inMilliseconds > 0
              ? position.inMilliseconds / duration.inMilliseconds
              : 0.0;

          return GestureDetector(
            onPanUpdate: (details) => onSeek(controller, details),
            onTapDown: (details) => onSeek(controller, details),
            child: Container(
              height: 4,
              color: Colors.black.withOpacity(0.2),
              child: Stack(
                children: [
                  Container(
                    height: 2,
                    margin: const EdgeInsets.only(top: 1),
                    color: Colors.grey.withOpacity(0.2),
                  ),
                  Positioned(
                    top: 1,
                    left: 0,
                    child: Container(
                      height: 2,
                      width: MediaQuery.of(context).size.width * progress,
                      color: Colors.green[400],
                    ),
                  ),
                  if (progress > 0)
                    Positioned(
                      top: 0,
                      left: (MediaQuery.of(context).size.width * progress) - 4,
                      child: Container(
                        width: 8,
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.green[400],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Earnings label widget - memoized
class EarningsLabelWidget extends StatelessWidget {
  final VideoModel video;
  final double Function(VideoModel) calculateEarnings;

  const EarningsLabelWidget({
    Key? key,
    required this.video,
    required this.calculateEarnings,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final earnings = calculateEarnings(video) * 0.8;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.green.withOpacity(0.6),
          width: 1,
        ),
      ),
      child: Text(
        '₹${earnings.toStringAsFixed(2)}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Carousel ad page widget - wrapped in RepaintBoundary
class CarouselAdPageWidget extends StatelessWidget {
  final List<CarouselAdModel> carouselAds;
  final int videoIndex;
  final Function(int) onAdClosed;

  const CarouselAdPageWidget({
    Key? key,
    required this.carouselAds,
    required this.videoIndex,
    required this.onAdClosed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (carouselAds.isEmpty) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        child: const Center(
          child: Text(
            'No carousel ads available',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    final carouselAd = carouselAds[0];

    return RepaintBoundary(
      child: CarouselAdWidget(
        carouselAd: carouselAd,
        onAdClosed: () => onAdClosed(videoIndex),
        autoPlay: true,
      ),
    );
  }
}

/// Processing indicator widget - memoized and wrapped in RepaintBoundary
class ProcessingIndicatorWidget extends StatelessWidget {
  final VideoModel video;
  final Function(String) onRetry;

  const ProcessingIndicatorWidget({
    Key? key,
    required this.video,
    required this.onRetry,
  }) : super(key: key);

  String _getProcessingStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'Video Uploaded\nProcessing will start soon...';
      case 'processing':
        return 'Processing Video\nPlease wait...';
      case 'failed':
        return 'Processing Failed\nPlease try again';
      default:
        return 'Video Processing\nPlease wait...';
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 80,
                height: 80,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 80,
                      height: 80,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.green.withOpacity(0.3),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 60,
                      height: 60,
                      child: CircularProgressIndicator(
                        strokeWidth: 4,
                        value: video.processingProgress / 100,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.green,
                        ),
                      ),
                    ),
                    Icon(
                      video.processingStatus == 'failed'
                          ? Icons.error_outline
                          : Icons.video_library_outlined,
                      size: 32,
                      color: video.processingStatus == 'failed'
                          ? Colors.red
                          : Colors.white54,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _getProcessingStatusText(video.processingStatus),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              if (video.processingStatus == 'processing')
                Text(
                  '${video.processingProgress}% complete',
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                ),
              if (video.processingStatus == 'failed' &&
                  video.processingError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    video.processingError!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: 16),
              if (video.processingStatus == 'failed')
                ElevatedButton.icon(
                  onPressed: () => onRetry(video.id),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
