import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/core/services/video_state_persistence_service.dart';
import 'package:snehayog/core/services/video_screen_logger.dart';

class VideoScreenStateService {
  // State persistence variables
  final Map<int, double> _videoPositions = {};
  final Map<int, bool> _playbackStates = {};
  bool _isStateRestored = false;
  bool _shouldResumeFromSavedState = false;

  // Getters
  Map<int, double> get videoPositions => _videoPositions;
  Map<int, bool> get playbackStates => _playbackStates;
  bool get isStateRestored => _isStateRestored;
  bool get shouldResumeFromSavedState => _shouldResumeFromSavedState;

  Future<bool> checkForSavedStateAndInitialize() async {
    try {
      VideoScreenLogger.logInfo('Checking for saved video state...');

      final hasValidState =
          await VideoStatePersistenceService.hasValidCachedState();

      if (hasValidState) {
        VideoScreenLogger.logInfo('Valid cached state found, will restore');
        _shouldResumeFromSavedState = true;

        // Restore state immediately
        final savedState =
            await VideoStatePersistenceService.restoreVideoScreenState();

        if (savedState['isStateValid'] == true) {
          // Restore positions and playback states
          _videoPositions.clear();
          _playbackStates.clear();

          if (savedState['videoPositions'] != null) {
            _videoPositions
                .addAll(Map<int, double>.from(savedState['videoPositions']));
          }
          if (savedState['playbackStates'] != null) {
            _playbackStates
                .addAll(Map<int, bool>.from(savedState['playbackStates']));
          }

          VideoScreenLogger.logSuccess('Restored video state from cache');
        }
      } else {
        VideoScreenLogger.logInfo(
            'No valid cached state found, will load fresh');
        _shouldResumeFromSavedState = false;
      }

      return _shouldResumeFromSavedState;
    } catch (e) {
      VideoScreenLogger.logError('Error in state check and initialization: $e');
      _shouldResumeFromSavedState = false;
      return false;
    }
  }

  /// Save current video state
  Future<void> saveCurrentVideoState({
    required int activeIndex,
    required List<VideoModel> videos,
    required Map<int, double> positions,
    required Map<int, bool> playbackStates,
    required bool isPlaying,
  }) async {
    try {
      if (videos.isEmpty) return;

      // Update local state
      _videoPositions.clear();
      _playbackStates.clear();
      _videoPositions.addAll(positions);
      _playbackStates.addAll(playbackStates);

      // Save complete state
      await VideoStatePersistenceService.saveVideoScreenState(
        activeIndex: activeIndex,
        videos: videos,
        videoPositions: _videoPositions,
        playbackStates: _playbackStates,
        isPlaying: isPlaying,
      );

      VideoScreenLogger.logSuccess('Video state saved successfully');
    } catch (e) {
      VideoScreenLogger.logError('Error saving video state: $e');
    }
  }

  /// Save state periodically
  Timer startPeriodicStateSaving({
    required VoidCallback saveCallback,
    required bool Function() isVisibleCallback,
  }) {
    return Timer.periodic(const Duration(seconds: 30), (timer) {
      if (isVisibleCallback()) {
        saveCallback();
      } else {
        timer.cancel();
      }
    });
  }

  /// Save state when video changes
  void onVideoChanged(int newIndex, VoidCallback saveCallback) {
    saveCallback();
  }

  /// Save state when user manually controls video playback
  Future<void> onManualPlaybackChange(int videoIndex, bool isPlaying) async {
    try {
      // Update local state
      _playbackStates[videoIndex] = isPlaying;

      // Save to persistence service
      await VideoStatePersistenceService.savePlaybackState(
          videoIndex, isPlaying);

      VideoScreenLogger.logInfo(
          'Manual playback change saved: video $videoIndex, playing: $isPlaying');
    } catch (e) {
      VideoScreenLogger.logError('Error saving manual playback change: $e');
    }
  }

  /// Save state when video position changes significantly
  Future<void> onVideoPositionChange(int videoIndex, double position) async {
    try {
      // Only save if position changed significantly (more than 5 seconds)
      final currentPosition = _videoPositions[videoIndex] ?? 0.0;
      if ((position - currentPosition).abs() > 5.0) {
        _videoPositions[videoIndex] = position;
        await VideoStatePersistenceService.saveVideoPosition(
            videoIndex, position);

        VideoScreenLogger.logInfo(
            'Video position saved: video $videoIndex, position: $position');
      }
    } catch (e) {
      VideoScreenLogger.logError('Error saving video position: $e');
    }
  }

  /// Start monitoring video progress for position saving
  Timer startVideoProgressMonitoring({
    required bool Function() isVisibleCallback,
    required int Function() getActiveIndexCallback,
    required VideoPlayerController? Function(int) getControllerCallback,
    required Function(int, double) onPositionChangeCallback,
  }) {
    return Timer.periodic(const Duration(seconds: 10), (timer) {
      if (isVisibleCallback()) {
        final activeIndex = getActiveIndexCallback();
        final controller = getControllerCallback(activeIndex);

        if (controller != null &&
            controller.value.isInitialized &&
            controller.value.isPlaying) {
          final position = controller.value.position.inMilliseconds / 1000.0;
          onPositionChangeCallback(activeIndex, position);
        }
      } else {
        timer.cancel();
      }
    });
  }

  /// Clear all saved video state
  Future<void> clearSavedVideoState() async {
    try {
      await VideoStatePersistenceService.clearAllState();

      // Clear local state
      _videoPositions.clear();
      _playbackStates.clear();
      _isStateRestored = false;
      _shouldResumeFromSavedState = false;

      VideoScreenLogger.logSuccess('All saved video state cleared');
    } catch (e) {
      VideoScreenLogger.logError('Error clearing saved video state: $e');
    }
  }

  /// Get current video state information for debugging
  Future<Map<String, dynamic>> getVideoStateInfo() async {
    try {
      final stateSummary = await VideoStatePersistenceService.getStateSummary();

      return {
        'lastActiveIndex': stateSummary['lastActiveIndex'] ?? 'None',
        'lastActiveTime': stateSummary['lastActiveTime'] ?? 'None',
        'hasCachedVideos': stateSummary['hasCachedVideos'] ?? false,
        'hasVideoPositions': stateSummary['hasVideoPositions'] ?? false,
        'hasPlaybackStates': stateSummary['hasPlaybackStates'] ?? false,
        'isPlaying': stateSummary['isPlaying'] ?? false,
        'isStateValid': stateSummary['isStateValid'] ?? false,
        'isStateRestored': _isStateRestored,
        'shouldResumeFromSavedState': _shouldResumeFromSavedState,
      };
    } catch (e) {
      VideoScreenLogger.logError('Error getting video state info: $e');
      return {};
    }
  }

  /// Mark state as restored
  void markStateAsRestored() {
    _isStateRestored = true;
  }

  /// Reset state
  void reset() {
    _videoPositions.clear();
    _playbackStates.clear();
    _isStateRestored = false;
    _shouldResumeFromSavedState = false;
  }
}
