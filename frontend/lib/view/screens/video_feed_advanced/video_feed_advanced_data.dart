part of 'package:vayu/view/screens/video_feed_advanced.dart';

extension _VideoFeedDataOperations on _VideoFeedAdvancedState {

  Future<void> _loadVideos(
      {int page = 1,
      bool append = false,
      bool useCache = true,
      bool clearSession = true}) async {
    try {
      AppLogger.log(
          '🔄 Loading videos - Page: $page, Append: $append, UseCache: $useCache');

    if (page == 1 && !append && AppInitializationManager.instance.initialVideos != null) {
      final preFetchedVideos = AppInitializationManager.instance.initialVideos!;
      if (preFetchedVideos.isNotEmpty) {
        AppLogger.log('🚀 VideoFeedAdvanced: Using Stage 2 Pre-fetched videos (${preFetchedVideos.length})');
        
        if (mounted) {
          safeSetState(() {
            _videos = preFetchedVideos;
            _currentIndex = 0;
            _isLoading = false;
            _errorMessage = null;
          });
          
          AppInitializationManager.instance.initialVideos = null;

          WidgetsBinding.instance.addPostFrameCallback((_) {
             if (mounted && _videos.isNotEmpty) {
                 _preloadVideo(0);
                 _tryAutoplayCurrent();
                 Future.microtask(() => _loadMoreVideos());
             }
          });
          return;
        }
      }
    }

    if (_videos.isNotEmpty && page == 1 && !append) {
      AppLogger.log('⏳ Aggressive Caching: Delaying API fetch by 2s to prioritize UI/Player...');
      Future.delayed(const Duration(seconds: 2), () async {
        if (mounted) {
          await _loadVideosFromAPI(
              page: page, append: append, clearSession: clearSession);
        }
      });
    } else {
       await _loadVideosFromAPI(
          page: page, append: append, clearSession: clearSession);
    }

    } catch (e) {
      AppLogger.log('❌ Error loading videos: $e');
      if (mounted) {
        _isLoading = false;
        _errorMessage = e.toString();
      }
    }
  }

  Future<void> _loadVideosFromAPI(
      {int page = 1,
      bool append = false,
      bool clearSession = false}) async {
    
    try {
      final hasNetwork = await ConnectivityService.hasNetworkConnectivity();
      if (!hasNetwork) {
        AppLogger.log('📡 VideoFeedAdvanced: No network connectivity detected');
        if (mounted) {
          _showSnackBar('No internet connection. Please check your network.', isError: true);
          _isLoading = false;
        }
        return;
      }

      final response = await _videoService.getVideos(
        page: page,
        limit: _videosPerPage,
        videoType: widget.videoType,
        clearSession: clearSession,
      );

      List<VideoModel> newVideos;
      try {
        final videosList = response['videos'];
        if (videosList == null) {
          newVideos = <VideoModel>[];
        } else if (videosList is List) {
          if (videosList.isNotEmpty) {
             newVideos = await compute(_parseVideosInIsolate, videosList);
          } else {
            newVideos = <VideoModel>[];
          }
        } else {
          newVideos = <VideoModel>[];
        }
      } catch (e) {
        AppLogger.log('❌ VideoFeedAdvanced: Error parsing videos list: $e');
        newVideos = <VideoModel>[];
      }

      final hasMore = response['hasMore'] as bool? ?? false;
      final currentPage = response['currentPage'] as int? ?? page;
      final existingCurrentKey = (_currentIndex >= 0 && _currentIndex < _videos.length)
              ? videoIdentityKey(_videos[_currentIndex])
              : null;

      if (newVideos.isEmpty && page == 1) {
        AppLogger.log('⚠️ VideoFeedAdvanced: Empty videos received. Retrying...');
        try {
          await _cacheManager.initialize();
          await _cacheManager.invalidateVideoCache(videoType: widget.videoType);

          final retryResponse = await _videoService.getVideos(
            page: page,
            limit: _videosPerPage,
            videoType: widget.videoType,
          );

          List<VideoModel> retryVideos = <VideoModel>[];
          final retryList = retryResponse['videos'];
          if (retryList is List) {
             retryVideos = retryList.map((item) {
               try { return VideoModel.fromJson(item as Map<String, dynamic>); } catch (_) { return null; }
             }).whereType<VideoModel>().toList();
          }

          if (retryVideos.isNotEmpty) {
            final rankedRetryVideos = await _rankVideosWithEngagement(retryVideos, preserveVideoKey: existingCurrentKey);
            safeSetState(() {
              _videos = rankedRetryVideos;
              _syncLikeStateWithModels(rankedRetryVideos);
              _currentIndex = 0;
              _currentPage = retryResponse['currentPage'] as int? ?? page;
              _hasMore = retryResponse['hasMore'] as bool? ?? false;
              _errorMessage = null;
            });
            _markCurrentVideoAsSeen();
            return;
          }
        } catch (e) {
          AppLogger.log('❌ VideoFeedAdvanced: Retry failed: $e');
        }
      }

      if (!mounted) return;

      if (append) {
        safeSetState(() {
          if (newVideos.isNotEmpty) {
             _videos.addAll(newVideos);
             _syncLikeStateWithModels(newVideos);
             _cleanupOldVideosFromList();
          }
          _errorMessage = null; 
          _currentPage = currentPage;
          _hasMore = hasMore;
          _markCurrentVideoAsSeen();
        });
      } else {
        safeSetState(() {
          final hasCachedVideos = _videos.isNotEmpty;
          if (hasCachedVideos) {
             if (newVideos.isNotEmpty) {
                _videos.addAll(newVideos);  
                _syncLikeStateWithModels(newVideos);  
             }
             _errorMessage = null;
             _currentPage = currentPage; 
             _hasMore = hasMore || newVideos.isNotEmpty; 
          } else {
             _videos = newVideos;
             _syncLikeStateWithModels(newVideos);
             _currentIndex = 0;
             _currentPage = currentPage;
             _hasMore = hasMore;
             if (_pageController.hasClients) {
                _pageController.jumpToPage(0);
             }
          }
          _errorMessage = null;
          _markCurrentVideoAsSeen();
        });
        
        if (page == 1 && newVideos.isNotEmpty) {
           Future.microtask(() {
              if (mounted && _hasMore) {
                 _loadVideosFromAPI(page: 2, append: true, clearSession: false);
              }
           });
        }
      }

      _markCurrentVideoAsSeen();
      if (mounted && _isLoading) {
        _isLoading = false;
      }

      _loadFollowingUsers();
      if (_currentIndex >= _videos.length) {
        _currentIndex = 0;
      }

      _preloadVideo(_currentIndex);
      _preloadNearbyVideos();
      _precacheThumbnails();

    } catch (e) {
      AppLogger.log('❌ Error loading videos: $e');
      if (mounted) {
          _errorMessage = _getUserFriendlyErrorMessage(e);
          _hasMore = false;
          _isLoading = false;
      }
    }
  }

  Future<List<VideoModel>> _rankVideosWithEngagement(
    List<VideoModel> videos, {
    String? preserveVideoKey,
  }) async {
    return videos;
  }

  void _markVideoAsSeen(VideoModel video) {
    final key = videoIdentityKey(video);
    if (key.isEmpty) return;
    if (_seenVideoKeys.add(key)) {
      _saveSeenVideoKeysToStorage();
    }
  }

  void _markCurrentVideoAsSeen() {
    if (_currentIndex < 0 || _currentIndex >= _videos.length) return;
    _markVideoAsSeen(_videos[_currentIndex]);
  }

  void _cleanupOldVideosFromList() {
    if (_videos.length <= VideoFeedStateFieldsMixin._videosCleanupThreshold) {
      return;
    }
    final currentIndex = _currentIndex;
    final keepStart = (currentIndex - VideoFeedStateFieldsMixin._videosKeepRange).clamp(0, _videos.length);
    final videosToRemove = _videos.length - VideoFeedStateFieldsMixin._maxVideosInMemory;

    if (videosToRemove > 0) {
      final removeCount = (keepStart > 0) ? keepStart.clamp(0, videosToRemove) : videosToRemove;
      if (removeCount > 0) {
        _videos.removeRange(0, removeCount);
        _currentIndex = (_currentIndex - removeCount).clamp(0, _videos.length - 1);
        _cleanupVideoStateMaps(removeCount);
      }
    }
  }

  void _cleanupVideoStateMaps(int removedCount) {
    final keysToUpdate = <int, dynamic>{};
    final keysToRemove = <int>[];

    for (final key in _controllerPool.keys.toList()) {
      if (key < removedCount) {
        try { _controllerPool[key]?.dispose(); } catch (_) {}
        keysToRemove.add(key);
      } else {
        keysToUpdate[key - removedCount] = _controllerPool[key];
        keysToRemove.add(key);
      }
    }

    for (final key in keysToRemove) {
      _controllerPool.remove(key);
      _controllerStates.remove(key);
      _userPaused.remove(key);
      _isBuffering.remove(key);
      _preloadedVideos.remove(key);
      _loadingVideos.remove(key);
      _firstFrameReady.remove(key);
      _forceMountPlayer.remove(key);
      _showHeartAnimation.remove(key);
      _bufferingListeners.remove(key);
      _videoEndListeners.remove(key);
      _lastAccessedLocal.remove(key);
      _initializingVideos.remove(key);
      _preloadRetryCount.remove(key);
      _wasPlayingBeforeNavigation.remove(key);
    }

    _controllerPool.addAll(keysToUpdate.map((k, v) => MapEntry(k, v as VideoPlayerController)));

    for (final key in keysToRemove) {
      _isBufferingVN[key]?.dispose();
      _isBufferingVN.remove(key);
      _firstFrameReady[key]?.dispose();
      _forceMountPlayer[key]?.dispose();
    }

    final bufferingVNToUpdate = <int, ValueNotifier<bool>>{};
    final firstFrameToUpdate = <int, ValueNotifier<bool>>{};
    final forceMountToUpdate = <int, ValueNotifier<bool>>{};

    for (final entry in _isBufferingVN.entries) {
      if (entry.key >= removedCount) bufferingVNToUpdate[entry.key - removedCount] = entry.value;
    }
    for (final entry in _firstFrameReady.entries) {
      if (entry.key >= removedCount) firstFrameToUpdate[entry.key - removedCount] = entry.value;
    }
    for (final entry in _forceMountPlayer.entries) {
      if (entry.key >= removedCount) forceMountToUpdate[entry.key - removedCount] = entry.value;
    }

    _isBufferingVN.clear();
    _isBufferingVN.addAll(bufferingVNToUpdate);
    _firstFrameReady.clear();
    _firstFrameReady.addAll(firstFrameToUpdate);
    _forceMountPlayer.clear();
    _forceMountPlayer.addAll(forceMountToUpdate);
  }

  Future<void> refreshVideos() async {
    if (_isLoading || _isRefreshing) return;
    await _stopAllVideosAndClearControllers();
    _isRefreshing = true;
    try {
      if (mounted) {
        _isLoading = true;
        _errorMessage = null;
      }
      await _cacheManager.initialize();
      await _cacheManager.invalidateVideoCache(videoType: widget.videoType);
      _currentPage = 1;
      await _loadVideos(page: 1, append: false, clearSession: false);
      if (mounted) {
        _isLoading = false;
        _errorMessage = null;
      }
    } catch (e) {
      if (mounted) {
        _isLoading = false;
        _errorMessage = e.toString();
      }
    } finally {
      _isRefreshing = false;
    }
  }

  Future<void> startOver() async {
    await _stopAllVideosAndClearControllers();
    _videos.clear();
    _currentIndex = 0;
    _currentPage = 1;
    _hasMore = true;
    _errorMessage = null;
    _isLoading = true;
    await _loadVideos(page: 1, append: false, clearSession: true);
  }

  Future<void> _stopAllVideosAndClearControllers() async {
     for (final controller in _controllerPool.values) {
       try { controller.pause(); controller.dispose(); } catch (_) {}
     }
     _controllerPool.clear();
     _controllerStates.clear();
     _userPaused.clear();
     _isBuffering.clear();
     _preloadedVideos.clear();
     _loadingVideos.clear();
     _initializingVideos.clear();
     _preloadRetryCount.clear();
     _firstFrameReady.clear();
     _forceMountPlayer.clear();
  }

  Future<void> refreshAds() async {
    await _loadActiveAds();
  }

  Future<void> _loadCarouselAds() async {
     await _carouselAdManager.loadCarouselAds();
     if (mounted) {
       _carouselAds = _carouselAdManager.carouselAds;
     }
  }

  Future<void> _loadMoreVideos() async {
    if (_isLoadingMore || !_hasMore) return;
    _isLoadingMore = true;
    try {
      final nextPage = _currentPage + 1;
      await _loadVideos(page: nextPage, append: true, useCache: true, clearSession: false);
    } finally {
      _isLoadingMore = false; 
    }
  }

  void _syncLikeStateWithModels(List<VideoModel> videos) {
    for (final video in videos) {
      if (_isLikedVN.containsKey(video.id)) {
        _isLikedVN[video.id]!.value = video.isLiked;
      }
      if (_likeCountVN.containsKey(video.id)) {
        _likeCountVN[video.id]!.value = video.likes;
      }
    }
  }
}

List<VideoModel> _parseVideosInIsolate(dynamic rawList) {
  if (rawList is! List) return [];
  return rawList.map((item) {
    if (item is VideoModel) return item;
    if (item is Map) {
       try {
         final Map<String, dynamic> typedMap = Map<String, dynamic>.from(item);
         return VideoModel.fromJson(typedMap);
       } catch (e) { return null; }
    }
    return null;
  }).whereType<VideoModel>().toList();
}
