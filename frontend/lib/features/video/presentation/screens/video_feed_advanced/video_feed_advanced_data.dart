part of '../video_feed_advanced.dart';

extension _VideoFeedDataOperations on _VideoFeedAdvancedState {

  Future<void> _loadVideos(
      {int page = 1,
      bool append = false,
      bool useCache = true,
      bool clearSession = true,
      bool forceResetIndex = false}) async {
    try {
      AppLogger.log(
          '🔄 Loading videos - Page: $page, Append: $append, UseCache: $useCache');

    if (page == 1 && !append && AppInitializationManager.instance.isInitialVideosFresh) {
      final preFetchedVideos = AppInitializationManager.instance.initialVideos!;
      if (preFetchedVideos.isNotEmpty) {
        AppLogger.log('🚀 VideoFeedAdvanced: Using Stage 2 Pre-fetched videos (${preFetchedVideos.length})');
        
        if (mounted) {
          safeSetState(() {
            _videos = preFetchedVideos;
            _syncLikeStateWithModels(preFetchedVideos);
            _currentIndex = 0;
            _hasMore = AppInitializationManager.instance.hasInitialVideosMore;
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

    await _loadVideosFromAPI(
        page: page, 
        append: append, 
        clearSession: clearSession,
        forceResetIndex: forceResetIndex);

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
      bool clearSession = false,
      bool forceResetIndex = false}) async {
    try {
      final hasNetwork = await ConnectivityService.hasNetworkConnectivity();
      if (!hasNetwork) {
        AppLogger.log('📡 VideoFeedAdvanced: No network connectivity detected');
        
        // **NEW: Offline Gallery Fallback**
        if (page == 1 && !append) {
          AppLogger.log('🎞️ VideoFeedAdvanced: Attempting gallery fallback...');
          final galleryVideos = await localGalleryService.fetchGalleryVideos(limit: _videosPerPage);
          
          if (galleryVideos.isNotEmpty && mounted) {
            safeSetState(() {
              _videos = galleryVideos;
              _currentIndex = 0;
              _hasMore = galleryVideos.length >= _videosPerPage;
              _isLoading = false;
              _errorMessage = null;
            });
            _preloadVideo(0);
            _tryAutoplayCurrent();
            return;
          }
        }

        if (mounted) {
          safeSetState(() {
            _isLoading = false;
            _isLoadingMore = false;
            _errorMessage = 'No internet connection';
          });
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
          // No cache invalidation needed as cache is removed

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

      if (newVideos.isEmpty && page > 1) {
        _consecutiveEmptyBatches++;
        if (_consecutiveEmptyBatches >= 3) {
          AppLogger.log('🛑 VideoFeedAdvanced: 3 consecutive empty batches. Stopping pagination.');
          safeSetState(() {
             _hasMore = false;
             _isLoadingMore = false;
          });
          return;
        }
      } else if (newVideos.isNotEmpty) {
        _consecutiveEmptyBatches = 0;
      }

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
          // Identify if we should reset the index
          final bool shouldResetIndex = forceResetIndex || _videos.isEmpty;

          // **CRITICAL FIX: Only clear existing videos if we are resetting the index**
          if (shouldResetIndex) {
            _videos.clear();
            _controllerPool.clear(); // Also clear controllers to force fresh start
            _currentIndex = 0;
            if (_pageController.hasClients) {
              _pageController.jumpToPage(0);
            }
          }
          
          _videos = newVideos;
          _syncLikeStateWithModels(newVideos);
          
          // If not resetting, ensure current index is still valid
          if (!shouldResetIndex) {
            if (_currentIndex >= _videos.length) {
              _currentIndex = _videos.isNotEmpty ? _videos.length - 1 : 0;
            }
          }

          _currentPage = currentPage;
          _hasMore = hasMore;
          _errorMessage = null;
          _markCurrentVideoAsSeen();
        });
        
        if (page == 1 && newVideos.isNotEmpty) {
          Future.microtask(() {
              if (mounted && _hasMore && !_isLoadingMore) {
                 _isLoadingMore = true;
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
    } finally {
      if (mounted) {
        _isLoadingMore = false;
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
    final videosToRemoveCount = _videos.length - VideoFeedStateFieldsMixin._maxVideosInMemory;

    if (videosToRemoveCount > 0) {
      final actualRemoveCount = (keepStart > 0) ? keepStart.clamp(0, videosToRemoveCount) : videosToRemoveCount;
      if (actualRemoveCount > 0) {
        // Find IDs of videos being removed
        final removedVideoIds = _videos.take(actualRemoveCount).map((v) => v.id).toList();
        
        _videos.removeRange(0, actualRemoveCount);
        _currentIndex = (_currentIndex - actualRemoveCount).clamp(0, _videos.length - 1);
        
        _cleanupVideoStateMapsByIds(removedVideoIds);
      }
    }
  }

  void _cleanupVideoStateMapsByIds(List<String> removedVideoIds) {
    for (final videoId in removedVideoIds) {
      // 1. Dispose controller if it exists locally (+ Safety check)
      if (_controllerPool.containsKey(videoId)) {
        try {
          final controller = _controllerPool[videoId];
          if (controller != null) {
             controller.pause();
             controller.dispose();
          }
        } catch (_) {}
      }
      
      // 2. Remove from all maps/sets
      _controllerPool.remove(videoId);
      _controllerStates.remove(videoId);
      _userPaused.remove(videoId);
      _isBuffering.remove(videoId);
      _preloadedVideos.remove(videoId);
      _loadingVideos.remove(videoId);
      _initializingVideos.remove(videoId);
      _preloadRetryCount.remove(videoId);
      _videoErrors.remove(videoId);
      _lastAccessedLocal.remove(videoId);
      _wasPlayingBeforeNavigation.remove(videoId);
      _showHeartAnimation.remove(videoId);
      _currentHorizontalPage.remove(videoId);
      
      // Cleanup ValueNotifiers
      _firstFrameReady[videoId]?.dispose();
      _firstFrameReady.remove(videoId);
      _forceMountPlayer[videoId]?.dispose();
      _forceMountPlayer.remove(videoId);
      _isBufferingVN[videoId]?.dispose();
      _isBufferingVN.remove(videoId);
      _isSlowConnectionVN[videoId]?.dispose();
      _isSlowConnectionVN.remove(videoId);
      _userPausedVN[videoId]?.dispose();
      _userPausedVN.remove(videoId);
      
      // Cleanup listeners
      _bufferingListeners.remove(videoId);
      _videoEndListeners.remove(videoId);
      _errorListeners.remove(videoId);
      
      // Cleanup timers
      _bufferingTimers[videoId]?.cancel();
      _bufferingTimers.remove(videoId);
    }
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
      _currentPage = 1;
      await _loadVideos(page: 1, append: false, clearSession: true, forceResetIndex: true);
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
      // **REFACTORED: Use safeSetState to trigger UI rebuild even if local state is gone**
      // This ensures all IndexedStacks and builders are notified that ads are ready
      safeSetState(() {});
      AppLogger.log('✅ VideoFeedAdvanced: Applied ${_carouselAdManager.getTotalCarouselAds()} carousel ads to state via Manager');
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
      _getOrCreateNotifier<bool>(_isLikedVN, video.id, video.isLiked);
      _getOrCreateNotifier<int>(_likeCountVN, video.id, video.likes);
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
