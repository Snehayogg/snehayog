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

      // **NEW: Load persisted seen video keys so cache doesn't re-show watched videos**
      await _loadSeenVideoKeysFromStorage();

      // **BACKEND-FIRST: Backend handles all filtering via WatchHistory**
      // No need to load from local storage - backend is source of truth
      // Backend filters watched videos for ALL users (authenticated + anonymous via deviceId)
      // Even after app reinstall, backend will filter watched videos correctly
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
        final rankedVideos = _rankVideosWithEngagement(
          _videos,
          preserveVideoKey: preserveKey,
        );

        // **CRITICAL FIX: If all videos were filtered out, use original videos as fallback**
        final videosToUse =
            rankedVideos.isEmpty && _videos.isNotEmpty ? _videos : rankedVideos;

        if (rankedVideos.isEmpty && _videos.isNotEmpty) {
          AppLogger.log(
              '⚠️ VideoFeedAdvanced: All ${_videos.length} initial videos were filtered out! Using original videos as fallback.');
        }

        _videos = videosToUse;

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
            // **FIX: For shared/deep link videos, ALWAYS put target video at index 0**
            // This ensures the correct video plays regardless of where it appears in the feed
            final normalizedTargetId = targetVideoId.trim().toLowerCase();

            // Remove video from list if it exists (to avoid duplicates)
            _videos.removeWhere((v) {
              final normalizedVideoId = v.id.trim().toLowerCase();
              return normalizedVideoId == normalizedTargetId ||
                  v.id.trim() == targetVideoId ||
                  v.id == targetVideoId;
            });

            // **CRITICAL: Always insert shared video at index 0 BEFORE any ranking**
            _videos.insert(0, targetVideo);

            // **CRITICAL: Re-rank videos but preserve deep link video at index 0**
            // Use preserveVideoKey to ensure deep link video stays at position 0
            final deepLinkVideoKey = videoIdentityKey(targetVideo);
            final rankedVideos = _rankVideosWithEngagement(
              _videos,
              preserveVideoKey: deepLinkVideoKey.isNotEmpty
                  ? deepLinkVideoKey
                  : targetVideoId,
            );

            // **CRITICAL FIX: If all videos were filtered out, use original videos as fallback**
            _videos = rankedVideos.isEmpty && _videos.isNotEmpty
                ? _videos
                : rankedVideos;

            if (rankedVideos.isEmpty && _videos.isNotEmpty) {
              AppLogger.log(
                  '⚠️ VideoFeedAdvanced: All videos were filtered out after deep link! Using original videos as fallback.');
            }

            // **VERIFY: Ensure deep link video is still at index 0 after ranking**
            final verifyIndex = _videos.indexWhere((v) {
              final normalizedId = v.id.trim().toLowerCase();
              final normalizedTargetId = targetVideoId.trim().toLowerCase();
              return normalizedId == normalizedTargetId ||
                  v.id.trim() == targetVideoId ||
                  v.id == targetVideoId ||
                  videoIdentityKey(v) == deepLinkVideoKey;
            });

            // **FIX: Always ensure deep link video is at index 0**
            final correctIndex = verifyIndex != -1 ? verifyIndex : 0;

            // If ranking moved the video, move it back to index 0
            if (correctIndex != 0 && correctIndex < _videos.length) {
              final videoToMove = _videos.removeAt(correctIndex);
              _videos.insert(0, videoToMove);
              AppLogger.log(
                '🔧 VideoFeedAdvanced: Moved deep link video back to index 0 after ranking (was at index $correctIndex)',
              );
            }

            // **CRITICAL FIX: Always set currentIndex to 0 for deep link videos**
            // Since we've ensured the video is at index 0, _currentIndex must be 0
            _currentIndex = 0;

            // **DOUBLE VERIFY: Ensure video at index 0 is actually the target video**
            if (_videos.isNotEmpty) {
              final videoAtZero = _videos[0];
              final videoAtZeroId = videoAtZero.id.trim().toLowerCase();
              final targetIdLower = targetVideoId.trim().toLowerCase();
              if (videoAtZeroId != targetIdLower &&
                  videoAtZero.id.trim() != targetVideoId &&
                  videoAtZero.id != targetVideoId) {
                AppLogger.log(
                  '⚠️ VideoFeedAdvanced: Video at index 0 does not match target! Expected: $targetVideoId, Got: ${videoAtZero.id}',
                );
                // Last resort: find and move the correct video to index 0
                final correctVideoIndex = _videos.indexWhere((v) {
                  final normalizedId = v.id.trim().toLowerCase();
                  return normalizedId == targetIdLower ||
                      v.id.trim() == targetVideoId ||
                      v.id == targetVideoId;
                });
                if (correctVideoIndex != -1 && correctVideoIndex != 0) {
                  final correctVideo = _videos.removeAt(correctVideoIndex);
                  _videos.insert(0, correctVideo);
                  AppLogger.log(
                    '🔧 VideoFeedAdvanced: Corrected deep link video position (found at index $correctVideoIndex, moved to 0)',
                  );
                }
              } else {
                AppLogger.log(
                  '✅ VideoFeedAdvanced: Verified deep link video is at index 0 (ID: $targetVideoId, Name: ${videoAtZero.videoName})',
                );
              }
            }

            AppLogger.log(
              '📊 VideoFeedAdvanced: Total videos after insertion and ranking: ${_videos.length}',
            );

            // **FIX: For cold start, we need to immediately update PageController**
            // The PageController was initialized with initialPage: 0, but we need to ensure it's at 0
            // Since we've verified the video is at index 0, jump to 0 (or stay at 0)
            if (_pageController.hasClients) {
              // PageController is already attached, jump to index 0
              _pageController.jumpToPage(0);
              AppLogger.log(
                '🎯 VideoFeedAdvanced: PageController jumped to index 0 (cold start, immediate)',
              );
            } else {
              // PageController not ready yet, wait for it
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  // Try immediately
                  if (_pageController.hasClients) {
                    _pageController.jumpToPage(0);
                    AppLogger.log(
                      '🎯 VideoFeedAdvanced: PageController jumped to index 0 (cold start, first callback)',
                    );
                  } else {
                    // If still not ready, wait a bit more
                    Future.delayed(const Duration(milliseconds: 150), () {
                      if (mounted && _pageController.hasClients) {
                        _pageController.jumpToPage(0);
                        AppLogger.log(
                          '🎯 VideoFeedAdvanced: PageController jumped to index 0 (cold start, delayed)',
                        );
                      }
                    });
                  }
                }
              });
            }

            AppLogger.log(
              '✅ VideoFeedAdvanced: Deep link video ready at index 0 (ID: $targetVideoId, videoName: ${targetVideo.videoName})',
            );

            // **CRITICAL: Set loading to false and ensure video autoplays after positioning**
            setState(() {
              _isLoading = false;
              _errorMessage = null;
            });

            // **CRITICAL: Ensure video preloading and autoplay for deep link video**
            // Deep link video is always at index 0
            if (_videos.isNotEmpty && _currentIndex < _videos.length) {
              // **CRITICAL: Mark screen as visible for deep link videos (they should autoplay)**
              _isScreenVisible = true;
              _ensureWakelockForVisibility();

              // Mark current video as seen
              _markCurrentVideoAsSeen();

              // Start video preloading (will include the deep link video)
              _startVideoPreloading();

              // **CRITICAL: Force autoplay of deep link video after positioning**
              // Use WidgetsBinding callback to ensure UI is ready
              // Deep link video is always at index 0
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _currentIndex == 0 && _videos.isNotEmpty) {
                  // First attempt: immediate autoplay
                  Future.delayed(const Duration(milliseconds: 100), () {
                    if (mounted && _currentIndex == 0 && _videos.isNotEmpty) {
                      AppLogger.log(
                        '🎬 VideoFeedAdvanced: Attempting autoplay for deep link video at index 0 (ID: ${_videos[0].id}, Name: ${_videos[0].videoName})',
                      );
                      _tryAutoplayCurrent();
                    }
                  });

                  // Second attempt: after video preloads (more reliable)
                  Future.delayed(const Duration(milliseconds: 500), () {
                    if (mounted && _currentIndex == 0 && _videos.isNotEmpty) {
                      AppLogger.log(
                        '🎬 VideoFeedAdvanced: Second autoplay attempt for deep link video',
                      );
                      _tryAutoplayCurrent();

                      // **FORCE PLAY: If video still not playing, force it**
                      // Deep link video is always at index 0
                      if (_controllerPool.containsKey(0)) {
                        final controller = _controllerPool[0];
                        if (controller != null &&
                            controller.value.isInitialized &&
                            !controller.value.isPlaying) {
                          AppLogger.log(
                            '🎬 VideoFeedAdvanced: Forcing play for deep link video at index 0 (controller ready but not playing)',
                          );
                          _pauseAllOtherVideos(0);
                          try {
                            controller.setVolume(1.0);
                            controller.play();
                            _controllerStates[0] = true;
                            _userPaused[0] = false;
                            AppLogger.log(
                              '✅ VideoFeedAdvanced: Deep link video force play successful',
                            );
                          } catch (e) {
                            AppLogger.log(
                              '❌ VideoFeedAdvanced: Error forcing play: $e',
                            );
                          }
                        }
                      }
                    }
                  });
                }
              });
            }
          }
        } catch (e) {
          AppLogger.log(
            '⚠️ VideoFeedAdvanced: Error fetching deep link video: $e, falling back to regular load',
          );

          // **ENHANCED: Show user-friendly error message**
          if (mounted) {
            setState(() {
              _errorMessage = 'Video not found. Loading feed instead...';
            });
          }

          // **FALLBACK: Load regular videos and try to find the video in the feed**
          await _loadVideos(page: 1);
          if (mounted) {
            // Clear error message
            setState(() {
              _errorMessage = null;
            });

            // **ENHANCED: Try to verify and set correct index after loading**
            _verifyAndSetCorrectIndex();

            // **IF VIDEO NOT FOUND: Show error to user**
            if (widget.initialVideoId != null && _videos.isNotEmpty) {
              final targetVideoId = widget.initialVideoId!.trim();
              final videoFound = _videos.any(
                (v) => v.id.trim() == targetVideoId || v.id == targetVideoId,
              );

              if (!videoFound && mounted) {
                AppLogger.log(
                  '❌ VideoFeedAdvanced: Video $targetVideoId not found in feed',
                );
                // Show snackbar to user
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Video not found. Showing feed instead.'),
                    backgroundColor: Colors.orange,
                    duration: Duration(seconds: 3),
                  ),
                );
              }
            }
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

            // **CRITICAL FIX: Set _isScreenVisible = true when videos are loaded for Yug tab**
            // This ensures autoplay works when Yug tab is first loaded
            if (!_openedFromProfile &&
                _mainController?.currentIndex == 0 &&
                !_isScreenVisible) {
              _isScreenVisible = true;
              _ensureWakelockForVisibility();
              AppLogger.log(
                '✅ VideoFeedAdvanced: Yug tab videos loaded - setting _isScreenVisible = true',
              );
            }

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
      final targetVideoIdLower = targetVideoId.toLowerCase();

      // Ensure currentIndex is valid before accessing
      if (_currentIndex >= _videos.length) {
        _currentIndex = 0;
      }

      if (_currentIndex < _videos.length) {
        final videoAtCurrentIndex = _videos[_currentIndex];
        // **FIX: Compare with trimmed and case-insensitive IDs to handle matching issues**
        final currentVideoId = videoAtCurrentIndex.id.trim();
        final currentVideoIdLower = currentVideoId.toLowerCase();

        // Check if current video matches target (with multiple matching strategies)
        final currentMatches = currentVideoIdLower == targetVideoIdLower ||
            currentVideoId == targetVideoId ||
            videoAtCurrentIndex.id == targetVideoId;

        if (!currentMatches) {
          // Find the correct video by ID (try multiple matching strategies)
          final correctIndex = _videos.indexWhere((v) {
            final vId = v.id.trim();
            final vIdLower = vId.toLowerCase();
            return vIdLower == targetVideoIdLower ||
                vId == targetVideoId ||
                v.id == targetVideoId;
          });

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
            // Log all video IDs for debugging
            AppLogger.log(
              '📋 VideoFeedAdvanced: Available video IDs: ${_videos.map((v) => v.id).join(", ")}',
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
      if (widget.videoType == 'yog' || widget.videoType == 'vayu') {
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
