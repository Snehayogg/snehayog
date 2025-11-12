part of 'package:vayu/view/screens/video_feed_advanced.dart';

extension _VideoFeedInitialization on _VideoFeedAdvancedState {
  void _initializeServices() {
    AppConfig.resetCachedUrl();

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
      setState(() => _isLoading = true);

      if (widget.initialVideos != null && widget.initialVideos!.isNotEmpty) {
        _videos = List.from(widget.initialVideos!);

        if (mounted) {
          _verifyAndSetCorrectIndex();
          setState(() => _isLoading = false);
          AppLogger.log(
            '🚀 VideoFeedAdvanced: Progressive render with provided videos: ${_videos.length}',
          );
          _startVideoPreloading();
        }

        _loadCurrentUserId();
        _loadActiveAds();
        _loadFollowingUsers();
        return;
      }

      final videosFuture = _loadVideos(page: 1);
      final userFuture = _loadCurrentUserId();
      final adsFuture = _loadActiveAds();

      videosFuture.then((_) async {
        if (!mounted) return;
        _verifyAndSetCorrectIndex();

        if (!_isColdStart) {
          await _restoreBackgroundStateIfAny();
        }

        setState(() => _isLoading = false);
        AppLogger.log(
          '🚀 VideoFeedAdvanced: Progressive render after videos loaded: ${_videos.length}',
        );
        _startVideoPreloading();
        _loadFollowingUsers();
      }).catchError((e) {
        AppLogger.log('❌ Error loading videos: $e');
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = e.toString();
          });
        }
      });

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
      final videoAtCurrentIndex = _videos[_currentIndex];
      if (videoAtCurrentIndex.id != widget.initialVideoId) {
        final correctIndex = _videos.indexWhere(
          (v) => v.id == widget.initialVideoId,
        );
        if (correctIndex != -1) {
          _currentIndex = correctIndex;
          _pageController.jumpToPage(correctIndex);
        }
      }
    }
  }

  void _startVideoPreloading() {
    if (_currentIndex < _videos.length) {
      _preloadVideo(_currentIndex).then((_) {
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _isColdStart = false;
          AppLogger.log(
            '🚀 VideoFeedAdvanced: Triggering autoplay after video preload at index $_currentIndex',
          );
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted) {
              _tryAutoplayCurrent();
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
