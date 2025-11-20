part of 'package:vayu/view/screens/video_feed_advanced.dart';

extension _VideoFeedInitialization on _VideoFeedAdvancedState {
  void _initializeServices() {
    AppConfig.resetCachedUrl();

    // **FIX: For deep links (initialVideoId without initialVideos),
    // we'll set initialPage after fetching the video**
    int initialPage = widget.initialIndex ?? 0;
    if (widget.initialVideoId != null && widget.initialVideos != null) {
      final videoIndex = widget.initialVideos!.indexWhere(
        (v) => v.id == widget.initialVideoId,
      );
      if (videoIndex != -1) {
        initialPage = videoIndex;
        _currentIndex = videoIndex;
      }
    }
    // **FIX: For deep links without initialVideos, start at 0 but we'll correct it after video fetch**
    // Don't set initialPage here for deep links - we'll set it after fetching the video

    _pageController = PageController(initialPage: initialPage);

    _videoService = VideoService();
    _authService = AuthService();
    _carouselAdManager = CarouselAdManager();

    _cacheManager.initialize();

    _adRefreshSubscription = _adRefreshNotifier.refreshStream.listen((_) {
      refreshAds();
    });

    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null; // Clear any previous error
      });

      if (widget.initialVideos != null && widget.initialVideos!.isNotEmpty) {
        _videos = List.from(widget.initialVideos!);
        String? preserveKey;
        if (widget.initialVideoId != null) {
          for (final video in _videos) {
            if (video.id == widget.initialVideoId) {
              preserveKey = videoIdentityKey(video);
              break;
            }
          }
        }
        preserveKey ??=
            _videos.isNotEmpty ? videoIdentityKey(_videos.first) : null;

        // **FIX: Rank videos and find correct index AFTER ranking**
        _videos = _rankVideosWithEngagement(
          _videos,
          preserveVideoKey: preserveKey,
        );

        if (mounted) {
          // **FIX: Find correct index AFTER ranking (videos may have been reordered)**
          int correctIndex = 0;
          if (widget.initialVideoId != null && _videos.isNotEmpty) {
            final foundIndex = _videos.indexWhere(
              (v) => v.id == widget.initialVideoId,
            );
            if (foundIndex != -1) {
              correctIndex = foundIndex;
            }
          }

          _currentIndex = correctIndex;

          // **FIX: Update PageController to correct index after ranking**
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _pageController.hasClients) {
              _pageController.jumpToPage(correctIndex);
              AppLogger.log(
                '🎯 VideoFeedAdvanced: Updated PageController to index $correctIndex after ranking',
              );
            }
          });

          // Use a single setState call to prevent excessive updates
          setState(() {
            _isLoading = false;
            _errorMessage = null; // Ensure error is cleared
          });

          AppLogger.log(
            '🚀 VideoFeedAdvanced: Progressive render with provided videos: ${_videos.length}, currentIndex: $_currentIndex (videoId: ${widget.initialVideoId})',
          );

          if (_videos.isNotEmpty) {
            _markCurrentVideoAsSeen();
            _startVideoPreloading();
          } else {
            AppLogger.log('⚠️ VideoFeedAdvanced: No videos after ranking');
          }
        }

        // Load background data asynchronously - don't block video display on errors
        _loadCurrentUserId().catchError((e) {
          AppLogger.log('⚠️ Error loading user ID (non-blocking): $e');
        });
        _loadActiveAds().catchError((e) {
          AppLogger.log('⚠️ Error loading ads (non-blocking): $e');
        });
        _loadFollowingUsers().catchError((e) {
          AppLogger.log('⚠️ Error loading following users (non-blocking): $e');
        });
        return;
      }

      // **FIX: If initialVideoId is provided (deep link), fetch that video first**
      if (widget.initialVideoId != null && widget.initialVideos == null) {
        try {
          final targetVideoId = widget.initialVideoId!.trim();
          AppLogger.log(
            '🔗 VideoFeedAdvanced: Deep link detected (cold start), fetching video: $targetVideoId',
          );

          // Fetch the target video first
          final targetVideo = await _videoService.getVideoById(targetVideoId);
          AppLogger.log(
            '✅ VideoFeedAdvanced: Fetched deep link video: ${targetVideo.videoName} (ID: ${targetVideo.id})',
          );

          // Load regular videos from API
          await _loadVideos(page: 1);

          if (mounted) {
            // **CRITICAL: Find video by ID after ranking (videos may have been reordered)**
            int correctIndex = 0;
            final foundIndex = _videos.indexWhere(
              (v) => v.id.trim() == targetVideoId || v.id == targetVideoId,
            );

            if (foundIndex == -1) {
              // Video not in list, insert it at the beginning
              AppLogger.log(
                '📌 VideoFeedAdvanced: Deep link video not in loaded list, inserting at index 0',
              );
              _videos.insert(0, targetVideo);
              correctIndex = 0;
            } else {
              // Video already in list, use its index
              correctIndex = foundIndex;
              AppLogger.log(
                '✅ VideoFeedAdvanced: Found deep link video at index $correctIndex',
              );
            }

            // **CRITICAL: Update currentIndex BEFORE PageController operations**
            _currentIndex = correctIndex;

            // **FIX: For cold start, we need to immediately update PageController**
            // The PageController was initialized with initialPage: 0, but we need to change it
            if (_pageController.hasClients) {
              // PageController is already attached, jump immediately
              _pageController.jumpToPage(correctIndex);
              AppLogger.log(
                '🎯 VideoFeedAdvanced: PageController jumped to index $correctIndex (cold start, immediate)',
              );
            } else {
              // PageController not ready yet, wait for it
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  // Try immediately
                  if (_pageController.hasClients) {
                    _pageController.jumpToPage(correctIndex);
                    AppLogger.log(
                      '🎯 VideoFeedAdvanced: PageController jumped to index $correctIndex (cold start, first callback)',
                    );
                  } else {
                    // If still not ready, wait a bit more
                    Future.delayed(const Duration(milliseconds: 150), () {
                      if (mounted && _pageController.hasClients) {
                        _pageController.jumpToPage(correctIndex);
                        AppLogger.log(
                          '🎯 VideoFeedAdvanced: PageController jumped to index $correctIndex (cold start, delayed)',
                        );
                      }
                    });
                  }
                }
              });
            }

            AppLogger.log(
              '✅ VideoFeedAdvanced: Deep link video ready at index $_currentIndex (ID: $targetVideoId, videoName: ${targetVideo.videoName})',
            );
          }
        } catch (e) {
          AppLogger.log(
            '⚠️ VideoFeedAdvanced: Error fetching deep link video: $e, falling back to regular load',
          );
          // Fallback to regular video load
          await _loadVideos(page: 1);
          if (mounted) {
            _verifyAndSetCorrectIndex();
          }
        }
      } else {
        // Regular video load (no deep link)
        // **FIX: Wait for videos to load before setting isLoading = false**
        await _loadVideos(page: 1);
        if (!mounted) return;
        _verifyAndSetCorrectIndex();
      }

      final userFuture = _loadCurrentUserId();
      final adsFuture = _loadActiveAds();

      if (mounted) {
        if (!_isColdStart) {
          await _restoreBackgroundStateIfAny();
        }

        // **FIX: Only set isLoading = false if videos are actually loaded**
        // If videos list is still empty, keep loading state or show error
        if (_videos.isEmpty && _errorMessage == null) {
          AppLogger.log(
            '⚠️ VideoFeedAdvanced: No videos loaded, retrying once...',
          );
          // No error but no videos - might be network issue, retry once
          try {
            await Future.delayed(const Duration(milliseconds: 500));
            await _loadVideos(page: 1, useCache: false);
            if (!mounted) return;
            _verifyAndSetCorrectIndex();
          } catch (retryError) {
            AppLogger.log('❌ VideoFeedAdvanced: Retry failed: $retryError');
            if (mounted) {
              setState(() {
                _isLoading = false;
                _errorMessage = retryError.toString();
              });
            }
            return;
          }
        }

        // Videos loaded successfully or error occurred
        if (mounted) {
          setState(() => _isLoading = false);
          if (_videos.isNotEmpty) {
            AppLogger.log(
              '🚀 VideoFeedAdvanced: Progressive render after videos loaded: ${_videos.length}',
            );
            _startVideoPreloading();
            _loadFollowingUsers();
          }
        }
      }

      try {
        await Future.wait([userFuture, adsFuture], eagerError: false);
      } catch (_) {}
    } catch (e) {
      AppLogger.log('❌ Error loading initial data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _verifyAndSetCorrectIndex() {
    if (widget.initialVideoId != null && _videos.isNotEmpty) {
      final targetVideoId = widget.initialVideoId!.trim();

      // Ensure currentIndex is valid before accessing
      if (_currentIndex >= _videos.length) {
        _currentIndex = 0;
      }

      if (_currentIndex < _videos.length) {
        final videoAtCurrentIndex = _videos[_currentIndex];
        // **FIX: Compare with trimmed IDs to handle whitespace issues**
        final currentVideoId = videoAtCurrentIndex.id.trim();

        if (currentVideoId != targetVideoId &&
            videoAtCurrentIndex.id != targetVideoId) {
          // Find the correct video by ID (try both trimmed and original)
          final correctIndex = _videos.indexWhere(
            (v) => v.id.trim() == targetVideoId || v.id == targetVideoId,
          );

          if (correctIndex != -1) {
            AppLogger.log(
              '🔧 VideoFeedAdvanced: Correcting index from $_currentIndex to $correctIndex for video ID: $targetVideoId',
            );
            _currentIndex = correctIndex;
            if (_pageController.hasClients) {
              _pageController.jumpToPage(correctIndex);
              AppLogger.log(
                '✅ VideoFeedAdvanced: PageController updated to index $correctIndex',
              );
            }
          } else {
            AppLogger.log(
              '⚠️ VideoFeedAdvanced: Video with ID $targetVideoId not found in list of ${_videos.length} videos',
            );
          }
        } else {
          AppLogger.log(
            '✅ VideoFeedAdvanced: Current video at index $_currentIndex matches target ID: $targetVideoId',
          );
        }
      }
    }
  }

  void _startVideoPreloading() {
    // **FIX: Ensure screen is visible when opened from ProfileScreen**
    final bool openedFromProfile =
        widget.initialVideos != null && widget.initialVideos!.isNotEmpty;
    if (openedFromProfile) {
      _isScreenVisible = true;
      _ensureWakelockForVisibility();
    }

    // **FIX: For deep links on cold start, verify we're preloading the correct video**
    if (widget.initialVideoId != null &&
        widget.initialVideos == null &&
        _videos.isNotEmpty) {
      final targetVideoId = widget.initialVideoId!.trim();
      if (_currentIndex < _videos.length) {
        final currentVideoId = _videos[_currentIndex].id.trim();
        if (currentVideoId != targetVideoId) {
          // Wrong video at current index, find correct one
          final correctIndex = _videos.indexWhere(
            (v) => v.id.trim() == targetVideoId || v.id == targetVideoId,
          );
          if (correctIndex != -1 && correctIndex != _currentIndex) {
            AppLogger.log(
              '🔧 VideoFeedAdvanced: Correcting index from $_currentIndex to $correctIndex before preload (deep link cold start)',
            );
            _currentIndex = correctIndex;
            if (_pageController.hasClients) {
              _pageController.jumpToPage(correctIndex);
            }
          }
        }
      }
    }

    if (_currentIndex < _videos.length) {
      AppLogger.log(
        '🎬 VideoFeedAdvanced: Starting preload for index $_currentIndex (video ID: ${_videos[_currentIndex].id}, name: ${_videos[_currentIndex].videoName})',
      );
      _preloadVideo(_currentIndex).then((_) {
        if (!mounted) return;

        // **FIX: Don't delay autoplay - let _preloadVideo handle it immediately**
        // The _preloadVideo method now triggers autoplay as soon as controller is ready
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _isColdStart = false;
          AppLogger.log(
            '�� VideoFeedAdvanced: Preload complete for index $_currentIndex',
          );

          // **FALLBACK: Only try autoplay if video still hasn't started playing**
          // Wait a bit to let immediate autoplay from _preloadVideo work first
          Future.delayed(const Duration(milliseconds: 250), () {
            if (mounted && _currentIndex < _videos.length) {
              final controller = _controllerPool[_currentIndex];
              if (controller != null &&
                  controller.value.isInitialized &&
                  !controller.value.isPlaying &&
                  _userPaused[_currentIndex] != true) {
                AppLogger.log(
                    '🔄 VideoFeedAdvanced: Fallback autoplay trigger after preload');
                _tryAutoplayCurrent();
              }
            }
          });
        });
      }).catchError((e) {
        AppLogger.log('❌ Error preloading initial video: $e');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _isColdStart = false;
          _tryAutoplayCurrent();
        });
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _isColdStart = false;
        _tryAutoplayCurrent();
      });
    }
  }

  void _precacheThumbnails() {
    Future(() async {
      for (final v in _videos.take(5)) {
        if (v.thumbnailUrl.isNotEmpty) {
          try {
            if (mounted) {
              await precacheImage(
                  CachedNetworkImageProvider(v.thumbnailUrl), context);
            }
          } catch (_) {}
        }
      }
    });
  }

  Future<void> _loadCurrentUserId() async {
    try {
      final authController =
          Provider.of<GoogleSignInController>(context, listen: false);
      if (authController.isSignedIn && authController.userData != null) {
        final userId = authController.userData!['id'] ??
            authController.userData!['googleId'];
        if (userId != null) {
          setState(() {
            _currentUserId = userId;
          });
          AppLogger.log(
              '✅ Loaded current user ID from auth controller: $_currentUserId');
          return;
        }
      }

      final userData = await _authService.getUserData();
      if (userData != null && userData['id'] != null) {
        setState(() {
          _currentUserId = userData['id'];
        });
        AppLogger.log(
            '✅ Loaded current user ID from auth service: $_currentUserId');
      }
    } catch (e) {
      AppLogger.log('❌ Error loading current user ID: $e');
    }
  }

  Future<void> _loadActiveAds() async {
    try {
      AppLogger.log(
          '🎯 VideoFeedAdvanced: Loading fallback ads in background...');

      final allAds = await _activeAdsService.fetchActiveAds();

      if (mounted) {
        setState(() {
          _bannerAds = allAds['banner'] ?? [];
          _adsLoaded = true;
        });

        AppLogger.log('✅ VideoFeedAdvanced: Fallback ads loaded:');
        AppLogger.log('   Banner ads: ${_bannerAds.length}');

        for (int i = 0; i < _bannerAds.length; i++) {
          final ad = _bannerAds[i];
          AppLogger.log(
            '   Banner Ad $i: ${ad['title']} (${ad['adType']}) - ID: ${ad['id']} - Active: ${ad['isActive']} - ImageUrl: ${ad['imageUrl']}',
          );
        }

        if (mounted) {
          setState(() {
            _lockedBannerAdByVideoId.clear();
            AppLogger.log(
                '🧹 Cleared locked banner ads to allow rotation with ${_bannerAds.length} ads');
          });
        }
      }

      if (mounted && (_bannerAds.isEmpty)) {
        AppLogger.log(
            '⚠️ VideoFeedAdvanced: No banner ads received, retrying in 3s...');
        Future.delayed(const Duration(seconds: 3), () async {
          if (!mounted) return;
          try {
            final retry = await _activeAdsService.fetchActiveAds();
            if (!mounted) return;
            if ((retry['banner'] ?? []).isNotEmpty) {
              setState(() {
                _bannerAds = retry['banner']!;
                _adsLoaded = true;
              });
              AppLogger.log(
                  '✅ VideoFeedAdvanced: Banner ads loaded on retry: ${_bannerAds.length}');
            }
          } catch (e) {
            AppLogger.log('❌ VideoFeedAdvanced: Retry load ads failed: $e');
          }
        });
      }

      await _carouselAdManager.loadCarouselAds();
      if (widget.videoType == 'yug' || widget.videoType == 'vayu') {
        await _loadCarouselAds();
      }
    } catch (e) {
      AppLogger.log('❌ Error loading fallback ads: $e');
      if (mounted) {
        setState(() {
          _adsLoaded = true;
        });
      }
    }
  }

  Future<void> _loadFollowingUsers() async {
    if (_currentUserId == null || _videos.isEmpty) return;

    try {
      final userService = UserService();
      final uniqueUploaders = _videos
          .map((video) => video.uploader.id)
          .toSet()
          .where((id) => id != _currentUserId)
          .toList();

      AppLogger.log(
        '🔍 Checking follow status for ${uniqueUploaders.length} unique uploaders',
      );

      for (final uploaderId in uniqueUploaders) {
        try {
          final isFollowing = await userService.isFollowingUser(uploaderId);
          if (isFollowing) {
            setState(() {
              _followingUsers.add(uploaderId);
            });
          }
        } catch (e) {
          AppLogger.log('❌ Error checking follow status for $uploaderId: $e');
        }
      }

      AppLogger.log(
          '✅ Loaded follow status for ${_followingUsers.length} users');
    } catch (e) {
      AppLogger.log('❌ Error loading following users: $e');
    }
  }
}
