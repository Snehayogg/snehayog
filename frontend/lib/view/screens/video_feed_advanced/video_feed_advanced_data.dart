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
      _printCacheStatus();



    // **NEW: Check for Pre-fetched Vital Content (Stage 2)**
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
          
          // Clear it so we don't reuse it on manual refresh
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

    // **CHANGED: SKIP Standard Cache Load here**
    // We want to avoid "Proxy Miss" (Old video buffering).
    // If Instant Splash failed, go straight to API.
    
    // **AGGRESSIVE CACHING: Try loading stale videos FIRST (0ms)**
    // **EXPERIMENT: DISABLED to remove Startup Jank/Lag**
    /*
    if (page == 1 && !append) {
      AppLogger.log('🚀 Aggressive Caching: Checking for stale/offline videos... (0ms target)');
      try {
        final feedLocalDataSource = FeedLocalDataSource();
        var cachedVideos =
            await feedLocalDataSource.getCachedFeed(page, widget.videoType);

        // **FALLBACK: Check VideoLocalDataSource (used by Splash Prefetch & VideoService)**
        if (cachedVideos == null || cachedVideos.isEmpty) {
           try {
             final videoLocalDataSource = VideoLocalDataSource();
             // Map null videoType to 'yog' or 'vayu' default
             final typeKey = widget.videoType ?? 'yog';
             cachedVideos = await videoLocalDataSource.getCachedVideoFeed(typeKey);
             if (cachedVideos != null && cachedVideos.isNotEmpty) {
                AppLogger.log('✅ Aggressive Caching: Loaded ${cachedVideos.length} videos from Global Cache (Splash Prefetch)');
             }
           } catch (_) {}
        }

        if (cachedVideos != null && cachedVideos.isEmpty) {
             cachedVideos = null; // Normalize empty list to null for check below
        }

        if (cachedVideos != null) {
          AppLogger.log(
              '✅ Aggressive Caching: Loaded ${cachedVideos.length} stale videos immediately');
          if (mounted) {
            safeSetState(() {
              _videos = cachedVideos!; // Force non-null
              _currentIndex = 0;
              // Don't set isLoading=false yet, keep spinner if needed, 
              // or set it false to show videos immediately? User said "show those stale videos immediately".
              // So let's show them.
              _isLoading = false; 
              _errorMessage = null; 
            });
            // Try to autoplay first one safely
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _videos.isNotEmpty) {
                 _preloadVideo(0);
                 _tryAutoplayCurrent();
              }
            });
          }
        }
      } catch (e) {
         AppLogger.log('⚠️ Aggressive Caching failed: $e');
      }
    }
    */

    // **Load from API directly**
    // This will fetch FRESH videos in background and update the list (replacing stale ones)
    // **OPTIMIZED: If we have cached videos, DELAY the API call to let UI render smoothly**
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

    // **OFFLINE FALLBACK: DISABLED per user request**
    // We want FRESH content every time. Backend is fast enough.
    /*
    if (_videos.isEmpty && !append && page == 1) {
      AppLogger.log(
          '⚠️ API failed or returned empty. Attempting Offline Fallback via Hive Cache...');
      final feedLocalDataSource = FeedLocalDataSource();
      final cachedVideos =
          await feedLocalDataSource.getCachedFeed(page, widget.videoType);

      if (cachedVideos != null && cachedVideos.isNotEmpty) {
        AppLogger.log(
            '✅ OFFLINE FALLBACK: Loaded ${cachedVideos.length} videos from Hive cache');
        if (mounted) {
          safeSetState(() {
            _videos = cachedVideos;
            _currentIndex = 0;
            _isLoading = false;
            _errorMessage = null; // Clear API error since we have cache
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _videos.isNotEmpty) {
              _preloadVideo(0);
              _tryAutoplayCurrent();
            }
          });
        }
      }
    }
    */
    } catch (e) {
      AppLogger.log('❌ Error loading videos: $e');
      if (mounted) {
        _isLoading = false;
        _errorMessage = e.toString();
      }
    }
  }

  /// **NEW: Load videos from API (separate method for background refresh)**
  Future<void> _loadVideosFromAPI(
      {int page = 1,
      bool append = false,
      bool clearSession = false}) async {
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
          // **OPTIMIZED: Use ValueNotifier for granular update**
          _isLoading = false;
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

      // **OPTIMIZED: Load 4 videos on first page for instant loading, then 15 for subsequent pages**
      final limit = _videosPerPage;
      AppLogger.log(
          '   - limit: $limit (first page: 4 videos for instant load, subsequent: 15 videos)');
      AppLogger.log('   - videoType: ${widget.videoType}');
      AppLogger.log('   - clearSession: $clearSession');

      final response = await _videoService.getVideos(
        page: page,
        limit: limit,
        videoType: widget.videoType,
        clearSession: clearSession,
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
          AppLogger.log(
              '🔍 VideoFeedAdvanced: videosList is List, length: ${videosList.length}');
          
          if (videosList.isNotEmpty) {
             // **PERFORMANCE OPTIMIZATION: Parse in background Isolate**
             // Parsing large JSON lists frames on the UI thread. We offload this to a separate thread.
             
             // First, ensure the list is List<dynamic> or List<Map<String, dynamic>>
             // We pass the raw list to the isolate
             try {
                // Must act as List<dynamic> for the isolate, but we might need to cast elements if they are not raw standard types
                final rawList = videosList; 
                
                // Using compute to run parseVideos in a background isolate
                newVideos = await compute(_parseVideosInIsolate, rawList);
                
                AppLogger.log(
                  '✅ VideoFeedAdvanced: Parsed ${newVideos.length} videos in background isolate',
                );
             } catch (isolateError) {
                AppLogger.log('❌ VideoFeedAdvanced: Isolate parsing failed: $isolateError. Falling back to main thread.');
                // Fallback to main thread parsing if isolate fails (e.g. if objects are not transferable)
                 newVideos = videosList
                  .map((item) {
                    if (item is VideoModel) return item;
                    if (item is Map<String, dynamic>) {
                        try {
                          return VideoModel.fromJson(item);
                        } catch (_) { return null; }
                    }
                    return null;
                  })
                  .whereType<VideoModel>()
                  .toList();
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

      // **REMOVED: Hive Caching as per user request**
      // if (newVideos.isNotEmpty && !clearSession) {
      //   try {
      //     final feedLocalDataSource = FeedLocalDataSource();
      //    feedLocalDataSource.cacheFeed(...)
      //   } catch (e) {}
      // }

      // **SIMPLIFIED: No Deduplication**
      // Trust backend to return unique videos
      // seenIds/uniqueNewVideos logic removed


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
                  final rankedFallbackVideos = await _rankVideosWithEngagement(
                    fallbackVideos,
                    preserveVideoKey: existingCurrentKey,
                  );
                  // **OPTIMIZED: Use ValueNotifiers for granular updates**
                  _videos = rankedFallbackVideos;
                  _currentIndex = 0;
                  _currentPage =
                      fallbackResponse['currentPage'] as int? ?? page;
                  _hasMore = fallbackResponse['hasMore'] as bool? ?? false;

                  // **CRITICAL FIX: Clear error message when videos are successfully loaded**
                  _errorMessage = null;
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
              final rankedRetryVideos = await _rankVideosWithEngagement(
                retryVideos,
                preserveVideoKey: existingCurrentKey,
              );
              // **OPTIMIZED: Use ValueNotifiers for granular updates**
              _videos = rankedRetryVideos;
              _currentIndex = 0;
              _currentPage = retryResponse['currentPage'] as int? ?? page;
              _hasMore = retryResponse['hasMore'] as bool? ?? false;

              // **CRITICAL FIX: Clear error message when videos are successfully loaded**
              _errorMessage = null;
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
        // **SIMPLIFIED: Direct append (Backend is source of truth)**
        // **SIMPLIFIED: Direct Append without deduplication**
        final validNewVideos = newVideos;

          
        if (mounted) {
          safeSetState(() {
            if (validNewVideos.isNotEmpty) {
               _videos.addAll(validNewVideos);
               
               // **MEMORY MANAGEMENT: Cleanup old videos**
               _cleanupOldVideosFromList();
            } else if (_hasMore && newVideos.isNotEmpty) {
               // **CRITICAL: If backend sent videos but ALL were duplicates, fetch next page immediately**
               // This prevents "End of Feed" false positive
               AppLogger.log('⚠️ VideoFeedAdvanced: All appended videos were duplicates. Fetching next page...');
               Future.microtask(() => _loadMoreVideos());
            }
            
            _errorMessage = null; 
            _currentPage = currentPage;
            _hasMore = hasMore;

            
            _markCurrentVideoAsSeen();
          });
        }
      } else {
        // **SEAMLESS MERGE STRATEGY (User Request):**
        // Instead of replacing cached videos ("Swap"), we APPEND fresh videos to the end.
        // This ensures the user continues watching cached content smoothly, and can scroll down to new content.
        
        final videosToUse = newVideos;
        
        if (videosToUse.isEmpty) {
           AppLogger.log('⚠️ VideoFeedAdvanced: API returned empty list on refresh');
        }

        if (mounted) {
          // Check if we have cached videos currently shown
          final hasCachedVideos = _videos.isNotEmpty;
          
          if (hasCachedVideos) {
             // **SCENARIO 1: Cache exists -> MERGE (Append)**
             // **CHANGED: Removed Session Deduplication Logic per user request**
             // Simply append all new videos to the end.
             
             if (videosToUse.isNotEmpty) {
                // **APPEND** to the end
                _videos.addAll(videosToUse);  
                
                AppLogger.log(
                   '✅ VideoFeedAdvanced: SEAMLESS MERGE - Appended ${videosToUse.length} fresh videos to existing ${_videos.length - videosToUse.length} cached videos.',
                );
             }
             
             // Ensure UI state matches
             _errorMessage = null;
             _currentPage = currentPage; 
             _hasMore = hasMore || videosToUse.isNotEmpty; 
             
          } else {
             // **SCENARIO 2: No Cache (Cold Start) -> REPLACE**
             // Standard behavior
             _videos = videosToUse;
             _currentIndex = 0;
             
             if (_pageController.hasClients) {
                _pageController.jumpToPage(0);
             }
             
             AppLogger.log(
               '✅ VideoFeedAdvanced: Fresh Load - Replaced empty list with ${videosToUse.length} videos.',
             );
          }

          // **DEBUG: Log final state**
          AppLogger.log('✅ VideoFeedAdvanced: State updated:');
          AppLogger.log('   _videos.length: ${_videos.length}');
          AppLogger.log('   _errorMessage: $_errorMessage');
          AppLogger.log('   _isLoading: $_isLoading');
          AppLogger.log('   _currentIndex: $_currentIndex');
          
          // Clear error if success
          _errorMessage = null;
          
          // **PRIORITY LOGIC: Preload Page 2 IMMEDIATELY**
          // Since we just "appended" Page 1 to Cache, we might have a long list now.
          // But logically we should still prepare the *next* batch from backend (Page 2)
          if (page == 1 && videosToUse.isNotEmpty) {
             Future.microtask(() {
                if (mounted && _hasMore) {
                   AppLogger.log('🚀 PRIORITY: Preloading Page 2 immediately for seamless scrolling...');
                   _loadVideosFromAPI(
                     page: 2, 
                     append: true, 
                     clearSession: false
                   );
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
          // **OPTIMIZED: Use ValueNotifier for granular update**
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
          // **FALLBACK: Only try autoplay if video still hasn't started**
          // Use nested callback instead of delay for faster check
          WidgetsBinding.instance.addPostFrameCallback((_) {
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
          // **OPTIMIZED: Use ValueNotifier for granular update**
          _isLoading = false;
        } else {
          final errorMsg = _getUserFriendlyErrorMessage(e);
          // **OPTIMIZED: Use ValueNotifiers for granular updates**
          _errorMessage = errorMsg;
          _hasMore = false;
          _isLoading = false;
        }
      }
    }
  }

  /// **OPTIMIZED: Async ranking with isolate for heavy computation**
  /// Moves heavy VideoEngagementRanker.rankVideos() to isolate to prevent UI freezes
  Future<List<VideoModel>> _rankVideosWithEngagement(
    List<VideoModel> videos, {
    String? preserveVideoKey,
  }) async {
    // **SIMPLIFIED: Trust Backend Order**
    // We removed _rankVideosInIsolate to prevent conflicts with backend logic.
    // The backend now handles diversity and ranking (FeedQueueService).
    return videos;
  }



  /// **BACKEND-FIRST: Mark video as seen (in-memory cache only)**
  /// Backend handles persistent storage via WatchHistory
  void _markVideoAsSeen(VideoModel video) {
    final key = videoIdentityKey(video);
    if (key.isEmpty) return;
    if (_seenVideoKeys.add(key)) {
      AppLogger.log('👀 Marked video as seen: ${video.id} ($key)');
      // **BACKEND-FIRST + LOCAL CACHE: Backend stores WatchHistory, local set avoids cached repeats**
      // Persist seen keys so that cached first-page data after app reopen doesn't re-show watched videos
      _saveSeenVideoKeysToStorage();
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
        // **OPTIMIZED: Use ValueNotifiers for granular updates**
        _isLoading = true;
        _errorMessage = null;
      }

      await _cacheManager.initialize();
      await _cacheManager.invalidateVideoCache(
        videoType: widget.videoType,
      );

      _currentPage = 1;
      await _loadVideos(page: 1, append: false, clearSession: false);

      if (mounted) {
        // **OPTIMIZED: Use ValueNotifiers for granular updates**
        _isLoading = false;
        _errorMessage = null;

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
        // **OPTIMIZED: Use ValueNotifiers for granular updates**
        _isLoading = false;
        _errorMessage = e.toString();
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

  Future<void> startOver() async {
    if (_isRefreshing) {
      AppLogger.log(
        '⚠️ VideoFeedAdvanced: Already refreshing/loading, ignoring duplicate call',
      );
      return;
    }

    AppLogger.log('🛑 Stopping all videos before starting over...');
    await _stopAllVideosAndClearControllers();

    _isRefreshing = true;

    try {
      // **SEAMLESS RESTART: Don't clear videos list immediately to avoid grey screen**
      // Keep last video visible while new videos load in background
      if (mounted) {
        // **OPTIMIZED: Use ValueNotifiers for granular updates**
        // Don't set _isLoading = true to avoid grey screen
        _errorMessage = null;
        _hasMore = true; // Reset hasMore flag
      }

      await _cacheManager.initialize();
      await _cacheManager.invalidateVideoCache(
        videoType: widget.videoType,
      );

      _currentPage = 1;

      // **SEAMLESS: Load videos with clearSession=true AND append=true initially**
      // This ensures:
      // 1. Backend session state is cleared (fresh videos)
      // 2. Videos are appended to existing list (no grey screen)
      // 3. After load, we'll replace the list seamlessly
      final currentVideosCount = _videos.length;
      await _loadVideos(page: 1, append: true, clearSession: true);

      // **SEAMLESS: After videos load, replace old videos with new ones**
      if (mounted && _videos.length > currentVideosCount) {
        // **OPTIMIZED: Use ValueNotifiers for granular updates**
        // Remove old videos and keep only new ones (seamless transition)
        _videos = _videos.sublist(currentVideosCount);
        _currentIndex = 0; // Reset to first video of new list

        // Navigate to first video
        if (_pageController.hasClients) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _pageController.hasClients) {
              _pageController.jumpToPage(0);
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
      } else if (mounted && _videos.isEmpty) {
        // Fallback: If no videos loaded, clear list and show loading
        // **OPTIMIZED: Use ValueNotifier for granular update**
        _isLoading = true;
        // Retry without append
        await _loadVideos(page: 1, append: false, clearSession: true);
        if (mounted) {
          // **OPTIMIZED: Use ValueNotifiers for granular updates**
          _isLoading = false;
          _currentIndex = 0;
        }

        // Navigate to first video
        if (_pageController.hasClients) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _pageController.hasClients) {
              _pageController.jumpToPage(0);
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

      if (mounted) {
        // **OPTIMIZED: Use ValueNotifier for granular update**
        _errorMessage = null;
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
        // **OPTIMIZED: Use ValueNotifiers for granular updates**
        _isLoading = false;
        _errorMessage = e.toString();
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
      // **OPTIMIZED: Use ValueNotifier for granular update**
      _currentIndex = 0;
      AppLogger.log('🔄 Reset current index to 0');
    }

    AppLogger.log('✅ _stopAllVideosAndClearControllers: Cleanup complete');
  }

  Future<void> refreshAds() async {
    AppLogger.log('🔄 VideoFeedAdvanced: refreshAds() called');

    try {
      await _activeAdsService.clearAdsCache();

      if (mounted) {
        // **OPTIMIZED: No setState needed - just clear the map**
        _lockedBannerAdByVideoId.clear();
        AppLogger.log(
            '🧹 Cleared locked banner ads to allow new ads to display');
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
        // **OPTIMIZED: Use ValueNotifier for granular update**
        _carouselAds = carouselAds;
        AppLogger.log(
          '✅ VideoFeedAdvanced: Loaded ${_carouselAds.length} carousel ads',
        );
      }
    } catch (e) {
      AppLogger.log('❌ Error loading carousel ads: $e');
    }
  }



  Future<void> _loadMoreVideos() async {
    if (!_hasMore) {
      AppLogger.log('✅ All fresh videos loaded (hasMore: false). Switching to LRU/History mode...');
      AppLogger.log('🔄 Calling _loadVideos(page: 1, append: true, clearSession: true) to fetch fallback content');
      // **LRU FALLBACK logic**:
      // If backend says "No more new videos", we trigger a fetch with clearSession=true
      // This tells backend: "Okay, filter is too strict, give me anything (LRU/Random)"
      // We do this by calling _loadVideos(..., clearSession: true)
      // But we must be careful not to create an infinite loop of clearing sessions.
      // So we only do this if we haven't already switched to a "History" mode concept, 
      // or simply rely on the fact that clearSession=true will return videos, and next time hasMore might be true.
      
      // For now, let's keep it simple: If feed end reached, load next page with clearSession=true to get recycle content
      // But we append it.
      await _loadVideos(page: 1, append: true, clearSession: true);
      return;
    }

    if (_isLoadingMore) {
      AppLogger.log('⏳ Already loading more videos');
      return;
    }

    AppLogger.log('📡 Loading more videos: Page ${_currentPage + 1}');

    // **OPTIMIZED: Silent loading - no setState to prevent UI updates**
    // This ensures seamless experience without visible loading state
    _isLoadingMore = true; // Just update flag, no setState (no UI rebuild)

    try {
      final videosCountBefore = _videos.length;
      await _loadVideos(page: _currentPage + 1, append: true);
      
      // **RECURSIVE FETCH FIX: If we loaded a page but it resulted in 0 NEW videos (due to deduplication),**
      // **we must IMMEDIATELY try the next page, otherwise the user sees a loading spinner that never finishes.**
      if (mounted && _videos.length == videosCountBefore && _hasMore && _errorMessage == null) {
         AppLogger.log('⚠️ Page ${_currentPage} resulted in 0 new videos (all duplicates). Recursively fetching next page...');
         _isLoadingMore = false; // Reset before recursive call
         await _loadMoreVideos(); 
         return; // Return early after recursion
      }

      AppLogger.log('✅ Loaded more videos successfully');
      _errorMessage = null; // Clear error on success

      // **CRITICAL: Immediately preload newly loaded videos for seamless playback**
      if (mounted && _videos.length > videosCountBefore) {
        final newVideosStartIndex = videosCountBefore;
        final newVideosEndIndex = _videos.length;
        final newVideosCount = newVideosEndIndex - newVideosStartIndex;

        AppLogger.log(
          '🚀 ${_videosPerPage} videos requested, $newVideosCount videos added to feed.',
        );

        // ... rest of preloading logic ...
        for (int i = newVideosStartIndex; i < newVideosEndIndex; i++) {
          if (i >= 0 &&
              !_preloadedVideos.contains(i) &&
              !_loadingVideos.contains(i)) {
            _preloadVideo(i);
          }
        }
        _preloadNearbyVideos();
      }
    } catch (e) {
      AppLogger.log('❌ Error loading more videos: $e');
      if (mounted) {
        safeSetState(() {
          _errorMessage = e.toString();
        });
      }
    } finally {
      _isLoadingMore = false; 
    }
  }
}


/// **Top-Level Function for Isolate Parsing**
/// Must be outside any class to be usable by compute()
List<VideoModel> _parseVideosInIsolate(dynamic rawList) {
  if (rawList is! List) return [];
  
  return rawList.map((item) {
    // If it's already a VideoModel (not likely across isolate boundary, but good safety)
    if (item is VideoModel) {
      return item;
    }
    // Standard case: it's a Map
    if (item is Map) {
       // Convert Map<dynamic, dynamic> to Map<String, dynamic> if needed
       // JSON decoding usually produces Map<String, dynamic>, but sometimes Map<dynamic, dynamic>
       try {
         final Map<String, dynamic> typedMap = Map<String, dynamic>.from(item);
         return VideoModel.fromJson(typedMap);
       } catch (e) {
         // Silently fail for one bad item
         return null; 
       }
    }
    return null;
  }).whereType<VideoModel>().toList();
}
