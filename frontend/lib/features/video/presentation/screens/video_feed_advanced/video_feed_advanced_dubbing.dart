part of '../video_feed_advanced.dart';

extension _VideoFeedDubbing on _VideoFeedAdvancedState {
  /// Start the Smart Dub process for the current video
  Future<void> _handleSmartDub(VideoModel video, {String? targetLang}) async {
    if (!FeatureFlags.isDubbingEnabled) return;
    final videoId = video.id;

    // 1. If already dubbed and active, toggle back to original
    if (_isDubbedActiveVN[videoId]?.value == true) {
      _toggleDubbing(videoId, false);
      return;
    }

    // 1.5. If already locally dubbed for this session, toggle it on.
    final sessionDubbedUrl = _dubbedVideoUrls[videoId];
    if (_isValidDubbedPlaybackSource(sessionDubbedUrl)) {
      _toggleDubbing(videoId, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Switched to dubbed version.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }
    
    final progressVN =
        _dubbingProgressVN.putIfAbsent(videoId, () => ValueNotifier<double>(0));
    if (progressVN.value > 0 && progressVN.value < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dubbing is already in progress.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 1),
        ),
      );
      return;
    } else if (sessionDubbedUrl != null) {
      _dubbedVideoUrls.remove(videoId);
    }

    // 2. Language Selection (If not provided)
    if (targetLang == null) {
      targetLang = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: AppColors.backgroundPrimary,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Choose Dubbing Language',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.language, color: AppColors.primary),
                title: const Text('English', style: TextStyle(color: AppColors.textPrimary)),
                onTap: () => Navigator.pop(context, 'english'),
              ),
              ListTile(
                leading: const Icon(Icons.language, color: AppColors.primary),
                title: const Text('Hindi', style: TextStyle(color: AppColors.textPrimary)),
                onTap: () => Navigator.pop(context, 'hindi'),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      );

      // If user dismissed the bottom sheet without selecting
      if (targetLang == null) return;
    }
    final selectedTargetLang = targetLang.toLowerCase();

    // 3. Check if video already has a cached dubbed version for the selected language
    if (video.dubbedUrls != null && video.dubbedUrls!.isNotEmpty) {
      if (video.dubbedUrls!.containsKey(selectedTargetLang)) {
        final cachedUrl = video.dubbedUrls![selectedTargetLang];
        if (_isValidRemoteDubbedUrl(cachedUrl)) {
           final validCachedUrl = cachedUrl!.trim();
           _dubbedVideoUrls[videoId] = validCachedUrl;
           _toggleDubbing(videoId, true);
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(
               content: Text('Instant Switch: Using cached $selectedTargetLang version.'),
               backgroundColor: Colors.green,
             ),
           );
           return;
        }
      }
    }

    // 4. Hardware RAM Check (Minimum 6GB for local processing)
    if (!localDubbingService.isDeviceCapable()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Local dubbing needs at least 6GB RAM. Cached dubbed version is not available for this language.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // 5. Start Local Dubbing Pipeline (Zero-Cost for Server)
    try {
      progressVN.value = 0.05;

      // Get local path of video for efficient FFmpeg processing
      String? localVideoPath = await videoCacheProxy.getCachedFilePath(video.videoUrl);
      
      // If not fully cached, we use the URL directly (FFmpeg supports certain protocols)
      // but ideally we should wait for a healthy chunk or pre-download.
      localVideoPath ??= video.videoUrl;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Preparing $selectedTargetLang dubbing... this may take a moment.'),
          backgroundColor: Colors.blue,
          duration: const Duration(seconds: 2),
        ),
      );

      final result = await localDubbingService.processDubbing(
        videoPath: localVideoPath,
        videoId: videoId,
        targetLang: selectedTargetLang,
        onProgress: (message, progress) {
          if (mounted) {
            _dubbingProgressVN[videoId]?.value = progress;
            AppLogger.log('🎙️ Local Dub [$videoId]: $message ($progress)');
          }
        },
      );

      if (result != null && _isValidDubbedPlaybackSource(result)) {
        progressVN.value = 1.0;
        _dubbedVideoUrls[videoId] = result;
        final index = _videos.indexWhere((v) => v.id == videoId);
        if (index != -1) {
          final updatedDubbedUrls = Map<String, String>.from(
            _videos[index].dubbedUrls ?? <String, String>{},
          );
          // Persist only real remote URLs in dubbedUrls.
          if (_isValidRemoteDubbedUrl(result)) {
            updatedDubbedUrls[selectedTargetLang] = result;
          }
          safeSetState(() {
            _videos[index] = _videos[index].copyWith(
              dubbedUrls: updatedDubbedUrls,
            );
          });
        }
        _toggleDubbing(videoId, true);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Dubbing complete! Switched to ${selectedTargetLang[0].toUpperCase()}${selectedTargetLang.substring(1)}.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw Exception(
            'Failed to generate a valid dubbed output (placeholder/invalid output rejected)');
      }
    } catch (e) {
      AppLogger.log('❌ Local Dub Error: $e');
      _dubbingProgressVN[videoId]?.value = 0;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Local processing failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }


  /// Toggle between original and dubbed URL
  void _toggleDubbing(String videoId, bool active) {
    if (!mounted) return;

    safeSetState(() {
      _isDubbedActiveVN.putIfAbsent(videoId, () => ValueNotifier<bool>(false)).value = active;
      
      // Force reload the controller with the new URL
      final index = _videos.indexWhere((v) => v.id == videoId);
      if (index != -1) {
        // **EXPERT FIX: Eject from Shared Pool singleton**
        // Without this, _preloadVideo will simply reuse the old controller 
        // that's still pointing to the original network URL.
        SharedVideoControllerPool().disposeController(videoId);
        
        // We need to dispose and recreate the local tracking state
        _videoControllerManager.disposeAllControllers(); 
        _controllerPool.clear();
        _preloadedVideos.clear();
        _initializingVideos.clear(); // Clear any pending loads for this video
        _loadingVideos.remove(videoId);
        _videoErrors.remove(videoId);
        
        _preloadVideo(index).then((_) {
          if (mounted && index == _currentIndex) {
            _tryAutoplayCurrent();
          }
        });
      }
    });
  }

}
