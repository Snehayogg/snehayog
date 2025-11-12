part of 'package:vayu/view/screens/video_feed_advanced.dart';

extension _VideoFeedDataOperations on _VideoFeedAdvancedState {
  Future<void> _loadVideos({int page = 1, bool append = false}) async {
    try {
      AppLogger.log('🔄 Loading videos - Page: $page, Append: $append');
      _printCacheStatus();

      AppLogger.log('🔍 VideoFeedAdvanced: Loading videos directly from API');
      final response = await _videoService.getVideos(
        page: page,
        limit: _videosPerPage,
        videoType: widget.videoType,
      );

      AppLogger.log('✅ VideoFeedAdvanced: Successfully loaded videos from API');
      AppLogger.log(
          '🔍 VideoFeedAdvanced: Response keys: ${response.keys.toList()}');

      final newVideos = response['videos'] as List<VideoModel>;
      final hasMore = response['hasMore'] as bool? ?? false;
      final total = response['total'] as int? ?? 0;
      final currentPage = response['currentPage'] as int? ?? page;
      final totalPages = response['totalPages'] as int? ?? 1;

      AppLogger.log('📊 Video Loading Complete:');
      AppLogger.log('   New Videos Loaded: ${newVideos.length}');
      AppLogger.log('   Page: $currentPage / $totalPages');
      AppLogger.log('   Has More: $hasMore');
      AppLogger.log('   Total Videos Available: $total');

      if (newVideos.isEmpty && page == 1) {
        AppLogger.log(
          '⚠️ VideoFeedAdvanced: Empty videos received, invalidating cache to prevent stale data',
        );
        try {
          final cacheManager = SmartCacheManager();
          await cacheManager.invalidateVideoCache(videoType: widget.videoType);

          AppLogger.log('🔄 VideoFeedAdvanced: Retrying with force refresh...');
          final retryResponse = await _videoService.getVideos(
            page: page,
            limit: _videosPerPage,
            videoType: widget.videoType,
          );
          final retryVideos = retryResponse['videos'] as List<VideoModel>;

          if (retryVideos.isNotEmpty) {
            AppLogger.log(
              '✅ VideoFeedAdvanced: Retry successful, got ${retryVideos.length} videos',
            );
            if (mounted) {
              setState(() {
                _videos = retryVideos;
                _currentPage = retryResponse['currentPage'] as int? ?? page;
                _hasMore = retryResponse['hasMore'] as bool? ?? false;
                _totalVideos = retryResponse['total'] as int? ?? 0;
              });
              return;
            }
          }
        } catch (retryError) {
          AppLogger.log('❌ VideoFeedAdvanced: Retry failed: $retryError');
        }
      }

      if (mounted) {
        setState(() {
          if (append) {
            _videos.addAll(newVideos);
            AppLogger.log('📝 Appended videos, total: ${_videos.length}');
          } else {
            _videos = newVideos;
            AppLogger.log('📝 Set videos, total: ${_videos.length}');
          }
          _currentPage = currentPage;
          final bool inferredHasMore =
              hasMore || newVideos.length == _videosPerPage;
          _hasMore = inferredHasMore;
          _totalVideos = total;
        });

        _loadFollowingUsers();

        if (_currentIndex >= _videos.length) {
          _currentIndex = 0;
        }

        _preloadVideo(_currentIndex);
        _preloadNearbyVideos();

        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _tryAutoplayCurrent();
          });
        }

        _precacheThumbnails();
      }
    } catch (e) {
      AppLogger.log('❌ Error loading videos: $e');
      AppLogger.log('❌ Error stack trace: ${StackTrace.current}');
      if (mounted) {
        setState(() {
          _hasMore = false;
        });
      }
    }
  }

  Future<void> refreshVideos() async {
    AppLogger.log('🔄 VideoFeedAdvanced: refreshVideos() called');

    if (_isLoading || _isRefreshing) {
      AppLogger.log(
        '⚠️ VideoFeedAdvanced: Already refreshing/loading, ignoring duplicate call',
      );
      return;
    }

    AppLogger.log('🛑 Stopping all videos before refresh...');
    await _stopAllVideosAndClearControllers();

    _isRefreshing = true;

    try {
      if (mounted) {
        setState(() {
          _isLoading = true;
          _errorMessage = null;
        });
      }

      final cacheManager = SmartCacheManager();
      await cacheManager.invalidateVideoCache(videoType: widget.videoType);

      _currentPage = 1;
      await _loadVideos(page: 1, append: false);

      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = null;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            if (_mainController?.currentIndex == 0) {
              _tryAutoplayCurrent();
            }
          }
        });
      }

      AppLogger.log('✅ VideoFeedAdvanced: Videos refreshed successfully');
      _restoreRetainedControllersAfterRefresh();
      _loadActiveAds();

      AppLogger.log(
        '🔄 VideoFeedAdvanced: Reloading carousel ads after manual refresh...',
      );
      _carouselAdManager.loadCarouselAds();

      if (mounted && _videos.isNotEmpty) {
        if (_currentIndex >= _videos.length) {
          _currentIndex = 0;
        }

        _preloadVideo(_currentIndex);
        _preloadNearbyVideos();
        _precacheThumbnails();
      }
    } catch (e) {
      AppLogger.log('❌ VideoFeedAdvanced: Error refreshing videos: $e');

      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Failed to refresh: ${_getUserFriendlyErrorMessage(e)}',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () {
                refreshVideos();
              },
            ),
          ),
        );
      }
    } finally {
      _isRefreshing = false;
    }
  }

  Future<void> _stopAllVideosAndClearControllers() async {
    AppLogger.log('🛑 _stopAllVideosAndClearControllers: Starting cleanup...');

    _retainedByVideoId.clear();
    _retainedIndices.clear();
    final toRetain = <int>{
      if (_currentIndex >= 0) _currentIndex,
      if (_currentIndex - 1 >= 0) _currentIndex - 1,
      if (_currentIndex + 1 < _videos.length) _currentIndex + 1,
    };

    _controllerPool.forEach((index, controller) {
      try {
        if (controller.value.isInitialized && controller.value.isPlaying) {
          controller.pause();
          AppLogger.log('⏸️ Paused video at index $index');
        }

        controller.removeListener(_bufferingListeners[index] ?? () {});
        controller.removeListener(_videoEndListeners[index] ?? () {});

        if (toRetain.contains(index) && index < _videos.length) {
          final vid = _videos[index].id;
          _retainedByVideoId[vid] = controller;
          _retainedIndices.add(index);
          AppLogger.log(
              '🔒 Retaining controller at index $index for video $vid');
        } else {
          controller.dispose();
          AppLogger.log('🗑️ Disposed controller at index $index');
        }
      } catch (e) {
        AppLogger.log('⚠️ Error stopping video at index $index: $e');
      }
    });

    _initializingVideos.clear();
    _preloadRetryCount.clear();
    _controllerPool.clear();
    _controllerStates.clear();
    _userPaused.clear();
    _isBuffering.clear();
    _preloadedVideos.clear();
    _loadingVideos.clear();
    _bufferingListeners.clear();
    _videoEndListeners.clear();
    _wasPlayingBeforeNavigation.clear();
    for (final notifier in _firstFrameReady.values) {
      notifier.dispose();
    }
    _firstFrameReady.clear();
    for (final notifier in _forceMountPlayer.values) {
      notifier.dispose();
    }
    _forceMountPlayer.clear();

    try {
      final sharedPool = SharedVideoControllerPool();
      final keep = <String>[];
      if (_controllerPool.containsKey(_currentIndex) &&
          _currentIndex < _videos.length) {
        keep.add(_videos[_currentIndex].id);
      }
      if (_controllerPool.containsKey(_currentIndex + 1) &&
          _currentIndex + 1 < _videos.length) {
        keep.add(_videos[_currentIndex + 1].id);
      }
      if (keep.isEmpty) {
        sharedPool.clearAll();
      } else {
        sharedPool.clearExcept(keep);
      }
      AppLogger.log(
          '🗑️ Refreshed SharedVideoControllerPool, kept warm: ${keep.length}');
    } catch (e) {
      AppLogger.log('⚠️ Error refreshing SharedVideoControllerPool: $e');
    }

    try {
      _viewTracker.dispose();
      AppLogger.log('🎯 Stopped view tracking');
    } catch (e) {
      AppLogger.log('⚠️ Error stopping view tracking: $e');
    }

    try {
      _videoControllerManager.disposeAllControllers();
      AppLogger.log('🗑️ Disposed VideoControllerManager controllers');
    } catch (e) {
      AppLogger.log('⚠️ Error disposing VideoControllerManager: $e');
    }

    if (_videos.isEmpty && mounted) {
      setState(() {
        _currentIndex = 0;
      });
      AppLogger.log('🔄 Reset current index to 0');
    }

    AppLogger.log('✅ _stopAllVideosAndClearControllers: Cleanup complete');
  }

  Future<void> _invalidateVideoCache() async {
    try {
      AppLogger.log('🗑️ VideoFeedAdvanced: Invalidating video cache keys');
      final cacheManager = SmartCacheManager();
      await cacheManager.invalidateVideoCache(videoType: widget.videoType);
      AppLogger.log('✅ VideoFeedAdvanced: Video cache invalidated');
    } catch (e) {
      AppLogger.log('⚠️ VideoFeedAdvanced: Error invalidating cache: $e');
    }
  }

  Future<void> refreshAds() async {
    AppLogger.log('🔄 VideoFeedAdvanced: refreshAds() called');

    try {
      await _activeAdsService.clearAdsCache();

      if (mounted) {
        setState(() {
          _lockedBannerAdByVideoId.clear();
          AppLogger.log(
              '🧹 Cleared locked banner ads to allow new ads to display');
        });
      }

      await _loadActiveAds();

      if (widget.videoType == 'yug') {
        await _loadCarouselAds();
      }

      AppLogger.log('✅ VideoFeedAdvanced: Ads refreshed successfully');
    } catch (e) {
      AppLogger.log('❌ Error refreshing ads: $e');
    }
  }

  Future<void> _loadCarouselAds() async {
    try {
      AppLogger.log(
          '🎯 VideoFeedAdvanced: Loading carousel ads for Yug tab...');

      await _carouselAdManager.loadCarouselAds();
      final carouselAds = _carouselAdManager.carouselAds;

      if (mounted) {
        setState(() {
          _carouselAds = carouselAds;
        });
        AppLogger.log(
          '✅ VideoFeedAdvanced: Loaded ${_carouselAds.length} carousel ads',
        );
      }
    } catch (e) {
      AppLogger.log('❌ Error loading carousel ads: $e');
    }
  }

  void _onVideoChanged(int newIndex) {
    if (_currentIndex != newIndex) {
      setState(() => _currentIndex = newIndex);
      AppLogger.log('🔄 VideoFeedAdvanced: Video changed to index $newIndex');
    }
  }

  Future<void> _loadMoreVideos() async {
    if (!_hasMore) {
      AppLogger.log('✅ All videos loaded (hasMore: false)');
      return;
    }

    if (_isLoadingMore) {
      AppLogger.log('⏳ Already loading more videos');
      return;
    }

    AppLogger.log('📡 Loading more videos: Page ${_currentPage + 1}');
    setState(() => _isLoadingMore = true);

    try {
      await _loadVideos(page: _currentPage + 1, append: true);
      AppLogger.log('✅ Loaded more videos successfully');
    } catch (e) {
      AppLogger.log('❌ Error loading more videos: $e');
      if (mounted) {
        setState(() {
          _hasMore = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }
}
