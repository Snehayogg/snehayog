part of 'package:vayu/view/screens/video_feed_advanced.dart';

extension _VideoFeedDataOperations on _VideoFeedAdvancedState {
  Future<void> _loadVideos(
      {int page = 1, bool append = false, bool useCache = true}) async {
    try {
      AppLogger.log(
          '🔄 Loading videos - Page: $page, Append: $append, UseCache: $useCache');
      _printCacheStatus();

      // **NEW: Try to load from cache first (instant) if not appending and cache is enabled**
      if (useCache && !append && page == 1) {
        try {
          await _cacheManager.initialize();
          final cacheKey = 'videos_page_${page}_${widget.videoType ?? 'yog'}';

          // **Use peek to get cached data without triggering fetch**
          final cachedData = await _cacheManager.peek<Map<String, dynamic>>(
            cacheKey,
            cacheType: 'videos',
            allowStale: true, // Allow stale cache for instant load
          );

          if (cachedData != null && cachedData['videos'] != null) {
            final cachedVideos =
                (cachedData['videos'] as List).cast<VideoModel>();
            if (cachedVideos.isNotEmpty) {
              AppLogger.log(
                  '✅ Loaded ${cachedVideos.length} videos from cache (instant)');

              // Restore state from saved preferences
              final prefs = await SharedPreferences.getInstance();
              final savedVideoId = prefs.getString(_kSavedVideoIdKey);

              // Rank cached videos
              final rankedVideos = _rankVideosWithEngagement(
                cachedVideos,
                preserveVideoKey: savedVideoId != null
                    ? cachedVideos
                        .firstWhere((v) => v.id == savedVideoId,
                            orElse: () => cachedVideos.first)
                        .id
                    : null,
              );

              // **CRITICAL FIX: If all cached videos were filtered out, use original cached videos as fallback**
              final videosToUse =
                  rankedVideos.isEmpty && cachedVideos.isNotEmpty
                      ? cachedVideos
                      : rankedVideos;

              if (rankedVideos.isEmpty && cachedVideos.isNotEmpty) {
                AppLogger.log(
                    '⚠️ VideoFeedAdvanced: All ${cachedVideos.length} cached videos were filtered out! Using original cached videos as fallback.');
              }

              // Find saved video index
              int? restoredIndex;
              if (savedVideoId != null) {
                restoredIndex =
                    videosToUse.indexWhere((v) => v.id == savedVideoId);
                if (restoredIndex == -1) restoredIndex = null;
              }

              if (mounted) {
                setState(() {
                  _videos = videosToUse;
                  if (restoredIndex != null) {
                    _currentIndex = restoredIndex;
                  } else {
                    _currentIndex = 0;
                  }
                  _isLoading = false;
                });

                // Jump to saved index
                if (restoredIndex != null && _pageController.hasClients) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_pageController.hasClients) {
                      _pageController.jumpToPage(restoredIndex!);
                    }
                  });
                }

                // Try autoplay immediately with cached data
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _tryAutoplayCurrent();
                });

                AppLogger.log(
                    '✅ Instant resume: Showing cached videos, refreshing in background');
              }

              // **Load fresh data in background (non-blocking)**
              _loadVideosFromAPI(page: page, append: append).catchError((e) {
                AppLogger.log('⚠️ Background refresh failed: $e');
              });
              return;
            }
          }
        } catch (e) {
          AppLogger.log('⚠️ Error loading from cache: $e, falling back to API');
        }
      }

      // **FALLBACK: Load from API directly**
      await _loadVideosFromAPI(page: page, append: append);
    } catch (e) {
      AppLogger.log('❌ Error loading videos: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  /// **NEW: Load videos from API (separate method for background refresh)**
  Future<void> _loadVideosFromAPI({int page = 1, bool append = false}) async {
    // #region agent log
    _debugLog(
        'video_feed_advanced_data.dart:109',
        '_loadVideosFromAPI called',
        {
          'page': page,
          'append': append,
          'videoType': widget.videoType,
        },
        'F');
    // #endregion

    try {
      // **CONNECTIVITY CHECK: Verify internet connection before API call**
      // **FIXED: Only block if truly no network connectivity, not on timeout/false positives**
      final hasNetwork = await ConnectivityService.hasNetworkConnectivity();
      if (!hasNetwork) {
        // Only block if there's truly no network interface (WiFi/Mobile off)
        AppLogger.log(
            '📡 VideoFeedAdvanced: No network connectivity detected (WiFi/Mobile off)');
        if (mounted) {
          _showSnackBar(
            'No internet connection. Please check your network.',
            isError: true,
          );
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      // **FIXED: Don't block on internet check failure - proceed with API call anyway**
      // The actual API call will handle real connectivity issues
      final hasInternet = await ConnectivityService.hasInternetConnection();
      if (!hasInternet) {
        AppLogger.log(
            '📡 VideoFeedAdvanced: Internet check failed, but network exists - proceeding with API call');
        // Don't block - proceed with API call and let it handle errors
      }

      AppLogger.log('🔍 VideoFeedAdvanced: Loading videos from API');
      AppLogger.log('   - page: $page');
      AppLogger.log('   - limit: $_videosPerPage');
      AppLogger.log('   - videoType: ${widget.videoType}');

      final response = await _videoService.getVideos(
        page: page,
        limit: _videosPerPage,
        videoType: widget.videoType,
      );

      AppLogger.log('✅ VideoFeedAdvanced: Successfully loaded videos from API');
      AppLogger.log(
          '🔍 VideoFeedAdvanced: Response received, checking structure...');
      AppLogger.log(
          '🔍 VideoFeedAdvanced: Response keys: ${response.keys.toList()}');
      AppLogger.log(
          '🔍 VideoFeedAdvanced: Response type: ${response.runtimeType}');
      AppLogger.log(
          '🔍 VideoFeedAdvanced: Response["videos"] type: ${response['videos']?.runtimeType}');
      AppLogger.log(
          '🔍 VideoFeedAdvanced: Response["videos"] is List: ${response['videos'] is List}');
      AppLogger.log(
          '🔍 VideoFeedAdvanced: Response["videos"] length: ${(response['videos'] as List?)?.length ?? 'null'}');

      // **CRITICAL: Safe type casting with error handling**
      // **FIX: After HTTP serialization, videos come as List<Map>, not List<VideoModel>**
      List<VideoModel> newVideos;
      try {
        final videosList = response['videos'];
        if (videosList == null) {
          AppLogger.log('❌ VideoFeedAdvanced: response["videos"] is NULL!');
          newVideos = <VideoModel>[];
        } else if (videosList is List) {
          // **FIX: Convert List<Map<String, dynamic>> to List<VideoModel> using fromJson**
          AppLogger.log(
              '🔍 VideoFeedAdvanced: videosList is List, length: ${videosList.length}');
          if (videosList.isNotEmpty) {
            final firstItem = videosList.first;
            AppLogger.log(
                '🔍 VideoFeedAdvanced: First item type: ${firstItem.runtimeType}');
            AppLogger.log(
                '🔍 VideoFeedAdvanced: First item is VideoModel: ${firstItem is VideoModel}');
            AppLogger.log(
                '🔍 VideoFeedAdvanced: First item is Map: ${firstItem is Map<String, dynamic>}');

            if (firstItem is VideoModel) {
              // Already VideoModel objects (VideoService already converts them)
              newVideos = videosList.cast<VideoModel>();
              AppLogger.log(
                  '✅ VideoFeedAdvanced: Videos already VideoModel objects (from VideoService), length: ${newVideos.length}');
            } else if (firstItem is Map<String, dynamic>) {
              // Convert Map to VideoModel using fromJson (most common case after HTTP)
              newVideos = videosList
                  .map((item) {
                    try {
                      return VideoModel.fromJson(item as Map<String, dynamic>);
                    } catch (e) {
                      AppLogger.log(
                          '❌ VideoFeedAdvanced: Error parsing video: $e');
                      AppLogger.log(
                          '   Video data: ${item.toString().substring(0, 200)}');
                      return null;
                    }
                  })
                  .whereType<VideoModel>()
                  .toList();
              AppLogger.log(
                  '✅ VideoFeedAdvanced: Converted ${newVideos.length} videos from Map to VideoModel (${videosList.length - newVideos.length} failed to parse)');
            } else {
              AppLogger.log(
                  '❌ VideoFeedAdvanced: Unknown video item type: ${firstItem.runtimeType}');
              newVideos = <VideoModel>[];
            }
          } else {
            newVideos = <VideoModel>[];
            AppLogger.log('⚠️ VideoFeedAdvanced: Videos list is empty');
          }
        } else {
          AppLogger.log(
              '❌ VideoFeedAdvanced: response["videos"] is not a List! Type: ${videosList.runtimeType}');
          newVideos = <VideoModel>[];
        }
      } catch (e, stackTrace) {
        AppLogger.log('❌ VideoFeedAdvanced: Error parsing videos list: $e');
        AppLogger.log('   Stack trace: $stackTrace');
        AppLogger.log(
            '   Response["videos"] type: ${response['videos']?.runtimeType}');
        AppLogger.log(
            '   Response["videos"] length: ${(response['videos'] as List?)?.length ?? 'null'}');
        if (response['videos'] is List &&
            (response['videos'] as List).isNotEmpty) {
          AppLogger.log(
              '   First video item type: ${(response['videos'] as List).first.runtimeType}');
          AppLogger.log(
              '   First video item (first 200 chars): ${(response['videos'] as List).first.toString().substring(0, 200)}');
        }
        newVideos = <VideoModel>[];
      }

      // **CRITICAL DEBUG: Log immediately after parsing**
      AppLogger.log(
          '🔍 VideoFeedAdvanced: Parsed newVideos list length: ${newVideos.length}');
      if (newVideos.isEmpty) {
        AppLogger.log(
            '⚠️ VideoFeedAdvanced: newVideos list is EMPTY after parsing!');
        AppLogger.log('   Response total: ${response['total']}');
        AppLogger.log('   Response hasMore: ${response['hasMore']}');
      } else {
        AppLogger.log(
            '✅ VideoFeedAdvanced: newVideos list has ${newVideos.length} videos');
        AppLogger.log('   First video ID: ${newVideos.first.id}');
        AppLogger.log('   First video name: ${newVideos.first.videoName}');
      }
      final hasMore = response['hasMore'] as bool? ?? false;
      final total = response['total'] as int? ?? 0;
      final currentPage = response['currentPage'] as int? ?? page;
      final totalPages = response['totalPages'] as int? ?? 1;
      final existingCurrentKey =
          (_currentIndex >= 0 && _currentIndex < _videos.length)
              ? videoIdentityKey(_videos[_currentIndex])
              : null;
      final preserveKey = existingCurrentKey;

      // #region agent log
      _debugLog(
          'video_feed_advanced_data.dart:140',
          'API response parsed',
          {
            'newVideosCount': newVideos.length,
            'hasMore': hasMore,
            'total': total,
            'currentPage': currentPage,
            'videoType': widget.videoType,
          },
          'F');
      // #endregion

      AppLogger.log('📊 Video Loading Complete:');
      AppLogger.log('   New Videos Loaded: ${newVideos.length}');
      AppLogger.log('   Page: $currentPage / $totalPages');
      AppLogger.log('   Has More: $hasMore');
      AppLogger.log('   Total Videos Available: $total');

      if (newVideos.isEmpty && page == 1) {
        AppLogger.log(
          '⚠️ VideoFeedAdvanced: Empty videos received, invalidating cache to prevent stale data',
        );
        AppLogger.log(
          '⚠️ VideoFeedAdvanced: Debug info - page: $page, total: $total, hasMore: $hasMore, videoType: ${widget.videoType}',
        );

        try {
          await _cacheManager.initialize();
          await _cacheManager.invalidateVideoCache(
            videoType: widget.videoType,
          );

          AppLogger.log(
              '🔄 VideoFeedAdvanced: Retrying with force refresh (no cache)...');

          // **NEW: Try without videoType filter first to see if videos exist**
          Map<String, dynamic> retryResponse;
          try {
            retryResponse = await _videoService.getVideos(
              page: page,
              limit: _videosPerPage,
              videoType: widget.videoType,
            );
          } catch (error) {
            AppLogger.log(
                '❌ VideoFeedAdvanced: Retry with videoType failed: $error');
            // **FALLBACK: Try without videoType filter**
            AppLogger.log(
                '🔄 VideoFeedAdvanced: Retrying without videoType filter...');
            retryResponse = await _videoService.getVideos(
              page: page,
              limit: _videosPerPage,
              videoType: null, // Try without filter
            );
          }

          // **FIX: Parse retry videos using VideoModel.fromJson (same as main parsing)**
          List<VideoModel> retryVideos;
          try {
            final retryVideosList = retryResponse['videos'];
            if (retryVideosList == null) {
              AppLogger.log(
                  '❌ VideoFeedAdvanced: retryResponse["videos"] is NULL!');
              retryVideos = <VideoModel>[];
            } else if (retryVideosList is List) {
              if (retryVideosList.isNotEmpty) {
                final firstItem = retryVideosList.first;
                if (firstItem is VideoModel) {
                  retryVideos = retryVideosList.cast<VideoModel>();
                } else if (firstItem is Map<String, dynamic>) {
                  retryVideos = retryVideosList
                      .map((item) {
                        try {
                          return VideoModel.fromJson(
                              item as Map<String, dynamic>);
                        } catch (e) {
                          AppLogger.log(
                              '❌ VideoFeedAdvanced: Error parsing retry video: $e');
                          return null;
                        }
                      })
                      .whereType<VideoModel>()
                      .toList();
                  AppLogger.log(
                      '✅ VideoFeedAdvanced: Converted ${retryVideos.length} retry videos from Map to VideoModel');
                } else {
                  AppLogger.log(
                      '❌ VideoFeedAdvanced: Unknown retry video item type: ${firstItem.runtimeType}');
                  retryVideos = <VideoModel>[];
                }
              } else {
                retryVideos = <VideoModel>[];
              }
            } else {
              AppLogger.log(
                  '❌ VideoFeedAdvanced: retryResponse["videos"] is not a List! Type: ${retryVideosList.runtimeType}');
              retryVideos = <VideoModel>[];
            }
          } catch (e, stackTrace) {
            AppLogger.log(
                '❌ VideoFeedAdvanced: Error parsing retry videos: $e');
            AppLogger.log('   Stack trace: $stackTrace');
            retryVideos = <VideoModel>[];
          }

          AppLogger.log(
            '📊 VideoFeedAdvanced: Retry result - ${retryVideos.length} videos, total: ${retryResponse['total']}, hasMore: ${retryResponse['hasMore']}',
          );

          // **CRITICAL FIX: If retry with videoType returns empty, try without videoType filter**
          if (retryVideos.isEmpty && widget.videoType != null) {
            AppLogger.log(
              '⚠️ VideoFeedAdvanced: Retry with videoType returned empty, trying without videoType filter...',
            );
            try {
              final fallbackResponse = await _videoService.getVideos(
                page: page,
                limit: _videosPerPage,
                videoType: null, // Try without filter
              );
              // **FIX: Parse fallback videos using VideoModel.fromJson (same as main parsing)**
              List<VideoModel> fallbackVideos;
              try {
                final fallbackVideosList = fallbackResponse['videos'];
                if (fallbackVideosList == null) {
                  AppLogger.log(
                      '❌ VideoFeedAdvanced: fallbackResponse["videos"] is NULL!');
                  fallbackVideos = <VideoModel>[];
                } else if (fallbackVideosList is List) {
                  if (fallbackVideosList.isNotEmpty) {
                    final firstItem = fallbackVideosList.first;
                    if (firstItem is VideoModel) {
                      fallbackVideos = fallbackVideosList.cast<VideoModel>();
                    } else if (firstItem is Map<String, dynamic>) {
                      fallbackVideos = fallbackVideosList
                          .map((item) {
                            try {
                              return VideoModel.fromJson(
                                  item as Map<String, dynamic>);
                            } catch (e) {
                              AppLogger.log(
                                  '❌ VideoFeedAdvanced: Error parsing fallback video: $e');
                              return null;
                            }
                          })
                          .whereType<VideoModel>()
                          .toList();
                      AppLogger.log(
                          '✅ VideoFeedAdvanced: Converted ${fallbackVideos.length} fallback videos from Map to VideoModel');
                    } else {
                      AppLogger.log(
                          '❌ VideoFeedAdvanced: Unknown fallback video item type: ${firstItem.runtimeType}');
                      fallbackVideos = <VideoModel>[];
                    }
                  } else {
                    fallbackVideos = <VideoModel>[];
                  }
                } else {
                  AppLogger.log(
                      '❌ VideoFeedAdvanced: fallbackResponse["videos"] is not a List! Type: ${fallbackVideosList.runtimeType}');
                  fallbackVideos = <VideoModel>[];
                }
              } catch (e, stackTrace) {
                AppLogger.log(
                    '❌ VideoFeedAdvanced: Error parsing fallback videos: $e');
                AppLogger.log('   Stack trace: $stackTrace');
                fallbackVideos = <VideoModel>[];
              }
              if (fallbackVideos.isNotEmpty) {
                AppLogger.log(
                  '✅ VideoFeedAdvanced: Fallback without videoType successful, got ${fallbackVideos.length} videos',
                );
                if (mounted) {
                  final rankedFallbackVideos = _rankVideosWithEngagement(
                    fallbackVideos,
                    preserveVideoKey: existingCurrentKey,
                  );
                  setState(() {
                    _videos = rankedFallbackVideos;
                    _currentIndex = 0;
                    _currentPage =
                        fallbackResponse['currentPage'] as int? ?? page;
                    _hasMore = fallbackResponse['hasMore'] as bool? ?? false;
                    _totalVideos = fallbackResponse['total'] as int? ?? 0;
                    // **CRITICAL FIX: Clear error message when videos are successfully loaded**
                    _errorMessage = null;
                  });
                  _markCurrentVideoAsSeen();
                  return;
                }
              }
            } catch (fallbackError) {
              AppLogger.log(
                  '❌ VideoFeedAdvanced: Fallback without videoType failed: $fallbackError');
            }
          }

          if (retryVideos.isNotEmpty) {
            AppLogger.log(
              '✅ VideoFeedAdvanced: Retry successful, got ${retryVideos.length} videos',
            );
            if (mounted) {
              final rankedRetryVideos = _rankVideosWithEngagement(
                retryVideos,
                preserveVideoKey: existingCurrentKey,
              );
              setState(() {
                _videos = rankedRetryVideos;
                _currentIndex = 0;
                _currentPage = retryResponse['currentPage'] as int? ?? page;
                _hasMore = retryResponse['hasMore'] as bool? ?? false;
                _totalVideos = retryResponse['total'] as int? ?? 0;
                // **CRITICAL FIX: Clear error message when videos are successfully loaded**
                _errorMessage = null;
              });
              _markCurrentVideoAsSeen();
              return;
            }
          }
        } catch (retryError) {
          AppLogger.log('❌ VideoFeedAdvanced: Retry failed: $retryError');
        }
      }

      if (!mounted) return;

      if (append) {
        final rankedNewVideos = _filterAndRankNewVideos(newVideos);

        setState(() {
          if (rankedNewVideos.isNotEmpty) {
            _videos.addAll(rankedNewVideos);

            // **MEMORY MANAGEMENT: Cleanup old videos to prevent memory issues**
            // Remove videos that are far from current index to keep memory usage low
            _cleanupOldVideosFromList();
          }
          _currentPage = currentPage;
          final bool inferredHasMore =
              hasMore || newVideos.length == _videosPerPage;
          _hasMore = inferredHasMore;
          _totalVideos = total;
          // **CRITICAL FIX: Clear error message when videos are successfully loaded**
          if (_videos.isNotEmpty) {
            _errorMessage = null;
          }
        });

        _markCurrentVideoAsSeen();
      } else {
        // **NEW: Try to preserve current video ID when refreshing from background**
        String? preserveVideoId;
        if (_currentIndex >= 0 && _currentIndex < _videos.length) {
          preserveVideoId = _videos[_currentIndex].id;
        }

        // **FALLBACK: Try to get from saved preferences if current index is invalid**
        if (preserveVideoId == null) {
          try {
            final prefs = await SharedPreferences.getInstance();
            preserveVideoId = prefs.getString(_kSavedVideoIdKey);
          } catch (_) {}
        }

        // #region agent log
        _debugLog(
            'video_feed_advanced_data.dart:310',
            'Before ranking',
            {
              'inputVideosCount': newVideos.length,
              'preserveKey': preserveKey,
              'preserveVideoId': preserveVideoId,
            },
            'A');
        // #endregion

        AppLogger.log(
            '🔍 VideoFeedAdvanced: Before ranking - newVideos.length: ${newVideos.length}');
        final rankedVideos = _rankVideosWithEngagement(
          newVideos,
          preserveVideoKey: preserveKey ?? (preserveVideoId),
        );
        AppLogger.log(
            '🔍 VideoFeedAdvanced: After ranking - rankedVideos.length: ${rankedVideos.length}');

        // #region agent log
        _debugLog(
            'video_feed_advanced_data.dart:318',
            'After ranking',
            {
              'inputVideosCount': newVideos.length,
              'rankedVideosCount': rankedVideos.length,
              'filteredOut': newVideos.length - rankedVideos.length,
            },
            'A');
        // #endregion

        // **DEBUG: Log video counts after ranking**
        AppLogger.log('🔍 VideoFeedAdvanced: After ranking:');
        AppLogger.log('   Input videos: ${newVideos.length}');
        AppLogger.log('   Ranked videos: ${rankedVideos.length}');

        // **CRITICAL FIX: If all videos were filtered out, use original videos as fallback**
        final videosToUse = rankedVideos.isEmpty && newVideos.isNotEmpty
            ? newVideos
            : rankedVideos;

        if (rankedVideos.isEmpty && newVideos.isNotEmpty) {
          AppLogger.log(
              '   ⚠️ WARNING: All ${newVideos.length} videos were filtered out! Using original videos as fallback.');
          if (newVideos.isNotEmpty) {
            AppLogger.log('   First video ID: ${newVideos.first.id}');
            AppLogger.log(
                '   First video key: ${videoIdentityKey(newVideos.first)}');
            AppLogger.log(
                '   First video videoUrl: ${newVideos.first.videoUrl}');
            AppLogger.log(
                '   First video videoName: ${newVideos.first.videoName}');
          }
        }

        int? nextIndex;
        if (preserveKey != null) {
          final candidateIndex = videosToUse.indexWhere(
            (video) => videoIdentityKey(video) == preserveKey,
          );
          if (candidateIndex != -1) {
            nextIndex = candidateIndex;
          }
        } else if (preserveVideoId != null) {
          // **NEW: Try to find by video ID**
          final candidateIndex = videosToUse.indexWhere(
            (video) => video.id == preserveVideoId,
          );
          if (candidateIndex != -1) {
            nextIndex = candidateIndex;
          }
        }

        if (mounted) {
          setState(() {
            _videos = videosToUse;
            // **DEBUG: Log final state**
            AppLogger.log('✅ VideoFeedAdvanced: State updated:');
            AppLogger.log('   _videos.length: ${_videos.length}');
            AppLogger.log('   _errorMessage: $_errorMessage');
            AppLogger.log('   _isLoading: $_isLoading');
            AppLogger.log('   _currentIndex: $_currentIndex');

            if (nextIndex != null) {
              _currentIndex = nextIndex;
            } else if (_currentIndex >= _videos.length) {
              _currentIndex = 0;
            }
            _currentPage = currentPage;
            final bool inferredHasMore =
                hasMore || newVideos.length == _videosPerPage;
            _hasMore = inferredHasMore;
            _totalVideos = total;
            // **CRITICAL FIX: Clear error message when videos are successfully loaded**
            _errorMessage = null;
          });

          // **NEW: Update page controller if index changed**
          if (nextIndex != null && _pageController.hasClients) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_pageController.hasClients && _currentIndex == nextIndex) {
                _pageController.jumpToPage(nextIndex!);
              }
            });
          }
        }

        _markCurrentVideoAsSeen();

        // **FIX: Ensure isLoading is set to false after videos are loaded**
        // #region agent log
        _debugLog(
            'video_feed_advanced_data.dart:363',
            'Checking isLoading state',
            {
              'mounted': mounted,
              'isLoading': _isLoading,
              'videosLength': _videos.length,
            },
            'D');
        // #endregion

        if (mounted && _isLoading) {
          setState(() {
            _isLoading = false;

            // #region agent log
            _debugLog(
                'video_feed_advanced_data.dart:369',
                'isLoading set to false',
                {
                  'videosLength': _videos.length,
                },
                'D');
            // #endregion
          });
        }
      }

      _loadFollowingUsers();

      if (_currentIndex >= _videos.length) {
        _currentIndex = 0;
      }

      _preloadVideo(_currentIndex);
      _preloadNearbyVideos();

      // **ENHANCED: Don't add additional delay - _preloadVideo already handles immediate autoplay**
      // Only fallback if _preloadVideo's immediate autoplay didn't trigger
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // **DELAYED FALLBACK: Only try autoplay if video still hasn't started**
          // This ensures we don't interfere with immediate autoplay from _preloadVideo
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted && _currentIndex < _videos.length) {
              final controller = _controllerPool[_currentIndex];
              if (controller != null &&
                  controller.value.isInitialized &&
                  !controller.value.isPlaying &&
                  _userPaused[_currentIndex] != true) {
                AppLogger.log(
                    '🔄 VideoFeedAdvanced: Fallback autoplay trigger after video load');
                _tryAutoplayCurrent();
              }
            }
          });
        });
      }

      _precacheThumbnails();

      AppLogger.log(
        '📝 Video list prepared (total: ${_videos.length}) after engagement ranking/filtering',
      );
    } catch (e) {
      AppLogger.log('❌ Error loading videos: $e');
      AppLogger.log('❌ Error stack trace: ${StackTrace.current}');

      // **IMPROVED: Better error handling with connectivity service**
      if (mounted) {
        if (ConnectivityService.isNetworkError(e)) {
          // For slow / bad internet we only show a snackbar, don't block the feed.
          final errorMsg = ConnectivityService.getNetworkErrorMessage(e);
          _showSnackBar(errorMsg, isError: true);
          setState(() {
            _isLoading = false;
          });
        } else {
          final errorMsg = _getUserFriendlyErrorMessage(e);
          setState(() {
            _errorMessage = errorMsg;
            _hasMore = false;
            _isLoading = false;
          });
        }
      }
    }
  }

  List<VideoModel> _rankVideosWithEngagement(
    List<VideoModel> videos, {
    String? preserveVideoKey,
  }) {
    if (videos.isEmpty) return <VideoModel>[];

    AppLogger.log(
        '🔍 _rankVideosWithEngagement: Processing ${videos.length} videos');

    // **TEMPORARY DEBUG: Log first video details to check if IDs are valid**
    if (videos.isNotEmpty) {
      final firstVideo = videos.first;
      AppLogger.log('🔍 _rankVideosWithEngagement: First video details:');
      AppLogger.log('   ID: "${firstVideo.id}"');
      AppLogger.log('   ID isEmpty: ${firstVideo.id.isEmpty}');
      AppLogger.log('   videoUrl: "${firstVideo.videoUrl}"');
      AppLogger.log('   videoUrl isEmpty: ${firstVideo.videoUrl.isEmpty}');
      AppLogger.log('   videoName: "${firstVideo.videoName}"');
      AppLogger.log('   videoName isEmpty: ${firstVideo.videoName.isEmpty}');
      final testKey = videoIdentityKey(firstVideo);
      AppLogger.log('   videoIdentityKey: "$testKey"');
      AppLogger.log('   videoIdentityKey isEmpty: ${testKey.isEmpty}');
    }

    // #region agent log
    _debugLog(
        'video_feed_advanced_data.dart:462',
        'Ranking started',
        {
          'inputVideosCount': videos.length,
        },
        'A');

    // **BACKEND-FIRST: Backend already filters watched videos and shuffles**
    // Frontend only needs to:
    // 1. Remove duplicates within the same batch
    // 2. Preserve current video if needed
    // 3. Rank by engagement (optional, backend already does some ranking)

    final Map<String, VideoModel> uniqueVideos = {};
    int emptyKeyCount = 0;
    int duplicateCount = 0;

    for (final video in videos) {
      final key = videoIdentityKey(video);

      // #region agent log
      if (key.isEmpty) {
        _debugLog(
            'video_feed_advanced_data.dart:477',
            'Empty key detected',
            {
              'videoId': video.id,
              'videoUrl': video.videoUrl,
              'videoName': video.videoName,
            },
            'A');
      }
      // #endregion

      if (key.isEmpty) {
        emptyKeyCount++;
        AppLogger.log(
            '⚠️ Video has empty key: id=${video.id}, videoUrl=${video.videoUrl}, videoName=${video.videoName}');
        continue;
      }

      // Only check for duplicates in current batch, not seen videos
      // Backend already filtered watched videos
      if (!uniqueVideos.containsKey(key)) {
        uniqueVideos[key] = video;
      } else {
        duplicateCount++;
        AppLogger.log(
            '⚠️ Duplicate video found: key=$key, videoName=${video.videoName}');
      }
    }

    // #region agent log
    _debugLog(
        'video_feed_advanced_data.dart:495',
        'Ranking results',
        {
          'emptyKeyCount': emptyKeyCount,
          'duplicateCount': duplicateCount,
          'uniqueVideosCount': uniqueVideos.length,
          'inputVideosCount': videos.length,
        },
        'A');
    // #endregion

    AppLogger.log('🔍 _rankVideosWithEngagement: Results:');
    AppLogger.log('   Empty keys: $emptyKeyCount');
    AppLogger.log('   Duplicates: $duplicateCount');
    AppLogger.log('   Unique videos: ${uniqueVideos.length}');

    if (uniqueVideos.isEmpty) {
      // #region agent log
      _debugLog(
          'video_feed_advanced_data.dart:503',
          'All videos filtered out',
          {
            'emptyKeyCount': emptyKeyCount,
            'duplicateCount': duplicateCount,
          },
          'A');
      // #endregion

      AppLogger.log(
          '⚠️ VideoFeedAdvanced: All videos are duplicates in this batch');
      return <VideoModel>[];
    }

    final uniqueList = uniqueVideos.values.toList();

    // **RANKING: Rank by engagement (backend already shuffles, but ranking helps)**
    final rankedVideos = VideoEngagementRanker.rankVideos(uniqueList);

    // **PRESERVE: Keep current video at the beginning if specified**
    if (preserveVideoKey != null) {
      final preserveIndex = rankedVideos.indexWhere(
        (video) => videoIdentityKey(video) == preserveVideoKey,
      );
      if (preserveIndex > 0) {
        final preservedVideo = rankedVideos.removeAt(preserveIndex);
        rankedVideos.insert(0, preservedVideo);
      }
    }

    AppLogger.log(
        '🎲 VideoFeedAdvanced: Processed ${rankedVideos.length} videos (backend already filtered watched videos and shuffled)');

    return rankedVideos;
  }

  List<VideoModel> _filterAndRankNewVideos(List<VideoModel> videos) {
    if (videos.isEmpty) return <VideoModel>[];

    final Map<String, VideoModel> uniqueNewVideos = {};
    final existingKeys = <String>{
      for (final existing in _videos) videoIdentityKey(existing),
    };

    for (final video in videos) {
      final key = videoIdentityKey(video);
      if (key.isEmpty) continue;
      // **FILTER: Skip seen videos completely**
      if (_seenVideoKeys.contains(key)) continue;
      // **FILTER: Skip already loaded videos**
      if (existingKeys.contains(key)) continue;
      // **FILTER: Skip duplicates in this batch**
      if (uniqueNewVideos.containsKey(key)) continue;
      uniqueNewVideos[key] = video;
    }

    if (uniqueNewVideos.isEmpty) return <VideoModel>[];

    // **RANKING: Rank by engagement first**
    final rankedVideos =
        VideoEngagementRanker.rankVideos(uniqueNewVideos.values.toList());
    // **SHUFFLE: Then shuffle to show random order**
    rankedVideos.shuffle();
    return rankedVideos;
  }

  /// **BACKEND-FIRST: Mark video as seen (in-memory cache only)**
  /// Backend handles persistent storage via WatchHistory
  void _markVideoAsSeen(VideoModel video) {
    final key = videoIdentityKey(video);
    if (key.isEmpty) return;
    if (_seenVideoKeys.add(key)) {
      AppLogger.log('👀 Marked video as seen: ${video.id} ($key)');
      // **BACKEND-FIRST: Backend tracks this via WatchHistory API**
      // No local storage needed - backend is source of truth
    }
  }

  void _markCurrentVideoAsSeen() {
    if (_currentIndex < 0 || _currentIndex >= _videos.length) return;
    _markVideoAsSeen(_videos[_currentIndex]);
  }

  /// **MEMORY MANAGEMENT: Cleanup old videos from list to prevent memory issues**
  /// Removes videos that are far from current index, keeping only a sliding window
  void _cleanupOldVideosFromList() {
    // Only cleanup if we have more videos than threshold
    if (_videos.length <= VideoFeedStateFieldsMixin._videosCleanupThreshold) {
      return; // No cleanup needed yet
    }

    final currentIndex = _currentIndex;
    final keepStart =
        (currentIndex - VideoFeedStateFieldsMixin._videosKeepRange)
            .clamp(0, _videos.length);
    final keepEnd = (currentIndex + VideoFeedStateFieldsMixin._videosKeepRange)
        .clamp(0, _videos.length);

    // Calculate how many videos to remove
    final videosToRemove =
        _videos.length - VideoFeedStateFieldsMixin._maxVideosInMemory;

    if (videosToRemove > 0) {
      // **STRATEGY: Remove videos from the beginning (oldest)**
      // Keep videos around current index, remove from start
      final removeCount =
          (keepStart > 0) ? keepStart.clamp(0, videosToRemove) : videosToRemove;

      if (removeCount > 0) {
        // Remove old videos from start
        _videos.removeRange(0, removeCount);

        // **CRITICAL: Adjust current index after removal**
        _currentIndex =
            (_currentIndex - removeCount).clamp(0, _videos.length - 1);

        // Also cleanup related state maps
        _cleanupVideoStateMaps(removeCount);

        AppLogger.log(
          '🧹 Memory cleanup: Removed $removeCount old videos, kept ${_videos.length} videos (current index: $_currentIndex)',
        );
      }
    }
  }

  /// **MEMORY MANAGEMENT: Cleanup state maps when videos are removed**
  void _cleanupVideoStateMaps(int removedCount) {
    // Shift all indices in state maps
    final keysToUpdate = <int, dynamic>{};
    final keysToRemove = <int>[];

    // Update controller pool indices
    for (final key in _controllerPool.keys.toList()) {
      if (key < removedCount) {
        // Dispose controllers for removed videos
        try {
          _controllerPool[key]?.dispose();
        } catch (_) {}
        keysToRemove.add(key);
      } else {
        // Shift index
        final newKey = key - removedCount;
        keysToUpdate[newKey] = _controllerPool[key];
        keysToRemove.add(key);
      }
    }

    // Apply updates
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

    // Add shifted entries
    _controllerPool.addAll(
        keysToUpdate.map((k, v) => MapEntry(k, v as VideoPlayerController)));

    // Also cleanup ValueNotifiers
    for (final key in keysToRemove) {
      _isBufferingVN[key]?.dispose();
      _isBufferingVN.remove(key);
      _firstFrameReady[key]?.dispose();
      _forceMountPlayer[key]?.dispose();
    }

    // Shift remaining ValueNotifiers
    final bufferingVNToUpdate = <int, ValueNotifier<bool>>{};
    final firstFrameToUpdate = <int, ValueNotifier<bool>>{};
    final forceMountToUpdate = <int, ValueNotifier<bool>>{};

    for (final entry in _isBufferingVN.entries) {
      if (entry.key >= removedCount) {
        bufferingVNToUpdate[entry.key - removedCount] = entry.value;
      }
    }
    for (final entry in _firstFrameReady.entries) {
      if (entry.key >= removedCount) {
        firstFrameToUpdate[entry.key - removedCount] = entry.value;
      }
    }
    for (final entry in _forceMountPlayer.entries) {
      if (entry.key >= removedCount) {
        forceMountToUpdate[entry.key - removedCount] = entry.value;
      }
    }

    _isBufferingVN.clear();
    _isBufferingVN.addAll(bufferingVNToUpdate);
    _firstFrameReady.clear();
    _firstFrameReady.addAll(firstFrameToUpdate);
    _forceMountPlayer.clear();
    _forceMountPlayer.addAll(forceMountToUpdate);

    AppLogger.log('🧹 Cleaned up state maps for $removedCount removed videos');
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

      await _cacheManager.initialize();
      await _cacheManager.invalidateVideoCache(
        videoType: widget.videoType,
      );

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

  /// Start over - reset to first video and reload feed from beginning
  /// This allows users to restart the feed after watching all videos
  Future<void> startOver() async {
    AppLogger.log(
        '🔄 VideoFeedAdvanced: _startOver() called - restarting from beginning');

    if (_isLoading || _isRefreshing) {
      AppLogger.log(
        '⚠️ VideoFeedAdvanced: Already refreshing/loading, ignoring duplicate call',
      );
      return;
    }

    AppLogger.log('🛑 Stopping all videos before starting over...');
    await _stopAllVideosAndClearControllers();

    _isRefreshing = true;

    try {
      if (mounted) {
        setState(() {
          _isLoading = true;
          _errorMessage = null;
          _currentIndex = 0; // Reset to first video
          _hasMore = true; // Reset hasMore flag
        });
      }

      await _cacheManager.initialize();
      await _cacheManager.invalidateVideoCache(
        videoType: widget.videoType,
      );

      _currentPage = 1;
      await _loadVideos(page: 1, append: false);

      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = null;
        });

        // Navigate to first video
        if (_pageController.hasClients) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _pageController.hasClients) {
              _pageController.jumpToPage(0);
              _currentIndex = 0;
            }
          });
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            if (_mainController?.currentIndex == 0) {
              _tryAutoplayCurrent();
            }
          }
        });
      }

      AppLogger.log(
          '✅ VideoFeedAdvanced: Started over successfully - reset to first video');
      _restoreRetainedControllersAfterRefresh();
      _loadActiveAds();

      AppLogger.log(
        '🔄 VideoFeedAdvanced: Reloading carousel ads after start over...',
      );
      _carouselAdManager.loadCarouselAds();

      if (mounted && _videos.isNotEmpty) {
        _preloadVideo(0); // Preload first video
        _preloadNearbyVideos();
        _precacheThumbnails();
      }
    } catch (e) {
      AppLogger.log('❌ VideoFeedAdvanced: Error starting over: $e');

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
                    'Failed to start over: ${_getUserFriendlyErrorMessage(e)}',
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
                startOver();
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
      await _cacheManager.initialize();
      await _cacheManager.invalidateVideoCache(
        videoType: widget.videoType,
      );
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

      if (widget.videoType == 'yog') {
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
