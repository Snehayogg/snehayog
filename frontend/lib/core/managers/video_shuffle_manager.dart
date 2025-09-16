import 'dart:math';
import 'package:snehayog/model/video_model.dart';

/// Manages infinite random video order with no consecutive repeats
class VideoShuffleManager {
  final List<VideoModel> _originalVideos;
  final Random _random = Random();

  // Track the last shown video to prevent consecutive repeats
  VideoModel? _lastShownVideo;

  // Cache for better performance
  final List<VideoModel> _shuffledVideos = [];
  int _shuffleIndex = 0;

  VideoShuffleManager(this._originalVideos) {
    _generateShuffledList();
  }

  /// Generate a shuffled list ensuring no consecutive repeats
  void _generateShuffledList() {
    _shuffledVideos.clear();
    _shuffleIndex = 0;

    if (_originalVideos.isEmpty) return;

    // Create a copy of original videos for shuffling
    final availableVideos = List<VideoModel>.from(_originalVideos);

    // Shuffle the list
    availableVideos.shuffle(_random);

    // If we have a last shown video, ensure it's not the first in our new shuffle
    if (_lastShownVideo != null &&
        availableVideos.isNotEmpty &&
        availableVideos.first.id == _lastShownVideo!.id) {
      // Swap first video with a random other video
      if (availableVideos.length > 1) {
        final swapIndex = _random.nextInt(availableVideos.length - 1) + 1;
        final temp = availableVideos[0];
        availableVideos[0] = availableVideos[swapIndex];
        availableVideos[swapIndex] = temp;
      }
    }

    _shuffledVideos.addAll(availableVideos);
  }

  /// Get video at specific index (for infinite scrolling)
  VideoModel getVideoAtIndex(int index) {
    if (_originalVideos.isEmpty) {
      throw Exception('No videos available');
    }

    // **FIXED: Generate proper shuffled videos instead of using modulo**
    // If we need more videos than we have shuffled, generate more
    while (index >= _shuffledVideos.length) {
      _generateShuffledList();
    }

    final video = _shuffledVideos[index];
    _lastShownVideo = video;

    print('🎬 VideoShuffleManager: Getting video at index $index: ${video.videoName}');
    return video;
  }

  /// Get the next video ensuring no consecutive repeats
  VideoModel getNextVideo() {
    // If we're at the end of current shuffle, generate new one
    if (_shuffleIndex >= _shuffledVideos.length) {
      _generateShuffledList();
    }

    final video = _shuffledVideos[_shuffleIndex];
    _shuffleIndex++;
    _lastShownVideo = video;

    return video;
  }

  /// Reset the shuffle (useful when videos list changes)
  void resetShuffle() {
    _lastShownVideo = null;
    _generateShuffledList();
  }

  /// Update the original videos list
  void updateVideos(List<VideoModel> newVideos) {
    _originalVideos.clear();
    _originalVideos.addAll(newVideos);
    resetShuffle();
  }

  /// Get total available videos count
  int get totalVideos => _originalVideos.length;

  /// Check if we have videos available
  bool get hasVideos => _originalVideos.isNotEmpty;
}
