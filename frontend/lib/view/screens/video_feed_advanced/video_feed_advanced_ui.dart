part of 'package:vayu/view/screens/video_feed_advanced.dart';

extension _VideoFeedUI on _VideoFeedAdvancedState {
  Widget _buildVideoFeed() {
    return RefreshIndicator(
      onRefresh: refreshVideos,
      child: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        // **CUSTOM PHYSICS: Enabled VayuScrollPhysics for better snap/velocity control**
        physics: const VayuScrollPhysics(),
        // physics: const AlwaysScrollableScrollPhysics(),
        onPageChanged: _onPageChanged,
        allowImplicitScrolling: true, // **FIX: Enable to preload next widget and smooth out scroll start**
        itemCount: _getTotalItemCount(),
        itemBuilder: (context, index) {
          return _buildFeedItem(index);
        },
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          const Text(
            'Failed to load videos',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _getUserFriendlyErrorMessage(_errorMessage!),
                style: const TextStyle(color: Colors.white54, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: refreshVideos,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _testApiConnection,
            icon: const Icon(Icons.wifi_find),
            label: const Text('Test Connection'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  // **NEW: Individual Video Error State widget**
  Widget _buildVideoErrorState(int index, String error) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white54, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Playback Error',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
             const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                _getUserFriendlyErrorMessage(error),
                style: const TextStyle(color: Colors.white54, fontSize: 11),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                 // Retry logic: clear error and reload
                 safeSetState(() {
                    _videoErrors.remove(index);
                    _loadingVideos.add(index); // Show spinner
                    _isBuffering[index] = false; // Reset buffering state
                    _isBufferingVN[index]?.value = false;
                 });
                 // Force reload
                 _preloadVideo(index).then((_) {
                    if (mounted && index == _currentIndex) {
                       _tryAutoplayCurrentImmediate(index);
                    }
                 });
              },
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white24,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.video_library_outlined,
            size: 64,
            color: Colors.white54,
          ),
          const SizedBox(height: 16),
          const Text(
            'No videos available',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Try refreshing or check back later',
            style: TextStyle(color: Colors.white54, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: refreshVideos,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
          // **NEW: Add debug info button for troubleshooting**
          if (_errorMessage != null && _errorMessage!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Error: ${_errorMessage!.length > 100 ? "${_errorMessage!.substring(0, 100)}..." : _errorMessage!}',
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }

  int _getTotalItemCount() {
    // **FIXED: Always add THREE extra items (buffer) to allow scrolling past end**
    // This solves "Blocked Scrolling" issue when next video isn't ready.
    // User can drag into these placeholders, triggering the loader.
    return _videos.length + 3;
  }

  Widget _buildFeedItem(int index) {
    final totalVideos = _videos.length;
    final videoIndex = index;

    // **NEW: Pre-fetch Trigger (Buffer 6 videos - Aggressive for Fast Scroll)**
    // Trigger load more when user is within 6 videos of the end (approx 50% through batch)
    // This helps prevent hitting the "Loading more videos" screen even when scrolling fast
    if (mounted && totalVideos > 0 && index >= totalVideos - 6 && !_isLoadingMore && !_isRefreshing && _hasMore) {
       WidgetsBinding.instance.addPostFrameCallback((_) {
          _loadMoreVideos();
       });
    }

    if (videoIndex >= totalVideos) {
      // **SEAMLESS END-OF-FEED ITEM**
      // Show last video as placeholder while new videos load (invisible transition)
      // This creates seamless experience - user sees video, not loading state

      if (totalVideos > 0 && videoIndex == totalVideos) {
        // **Format: First extra item = Copy of Last Video (Seamless)**
        final lastVideoIndex = totalVideos - 1;
        final lastVideo = _videos[lastVideoIndex];
        final lastController = _getController(lastVideoIndex);

        // **IMMEDIATE TRIGGER: Load more videos immediately if not already loading**
        if (mounted && !_isRefreshing && !_isLoadingMore) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
             AppLogger.log('📡 UI: End-of-feed reached at index $index. Triggering _loadMoreVideos');
             _loadMoreVideos();
          });
        }

        // Return duplicate of last video for seamless feel
        return _buildVideoItem(
          lastVideo,
          lastController,
          false, // Not active
          lastVideoIndex,
        );
      }

      // **FALLBACK: Loading Skeleton for subsequent items (index > totalVideos)**
      // This gives visual feedback that "more is coming" if user scrolls deep
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black, // Black background
        child: const Center(
          child: Column(
             mainAxisAlignment: MainAxisAlignment.center,
             children: [
                SizedBox(
                   width: 30,
                   height: 30,
                   child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white24)
                ),
                SizedBox(height: 16),
                Text("Loading more videos...", style: TextStyle(color: Colors.white24, fontSize: 12)),
             ]
          ),
        ),
      );
    }

    final video = _videos[videoIndex];
    final controller = _getController(videoIndex);
    final isActive = videoIndex == _currentIndex;

    return _buildVideoItem(video, controller, isActive, videoIndex);
  }

  Widget _buildVideoItem(
    VideoModel video,
    VideoPlayerController? controller,
    bool isActive,
    int index,
  ) {
    if (!_currentHorizontalPage.containsKey(index)) {
      _currentHorizontalPage[index] = ValueNotifier<int>(0);
    }

    return Container(
      key: ValueKey('video_${video.id}'), // **FIX: Stable key to prevent player recreation on feed update**
      width: double.infinity,
      height: double.infinity,
      color: Colors.black,
      child: Stack(
        children: [
          ValueListenableBuilder<int>(
            valueListenable: _currentHorizontalPage[index]!,
            builder: (context, currentPage, child) {
              return IndexedStack(
                index: currentPage,
                children: [
                  _buildVideoPage(video, controller, isActive, index),
                  if (_carouselAds.isNotEmpty)
                    _buildCarouselAdPage(index)
                  else
                    const SizedBox.shrink(),
                ],
              );
            },
          ),
          if (_loadingVideos.contains(index))
            Center(child: _buildGreenSpinner(size: 28)),
        ],
      ),
    );
  }

  Widget _buildVideoPage(
    VideoModel video,
    VideoPlayerController? controller,
    bool isActive,
    int index,
  ) {
    // **NEW: Check for error state**
    if (_videoErrors.containsKey(index)) {
      return _buildVideoErrorState(index, _videoErrors[index]!);
    }

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black,
      child: Stack(
        children: [
          // **WEB FIX: Hide thumbnail when video is ready on web**
          ValueListenableBuilder<bool>(
            valueListenable:
                _firstFrameReady[index] ?? ValueNotifier<bool>(false),
            builder: (context, firstFrameReady, _) {
              final bool shouldShowOnWeb = kIsWeb &&
                  controller != null &&
                  controller.value.isInitialized;
              final bool shouldHideThumbnail = firstFrameReady ||
                  _forceMountPlayer[index]?.value == true ||
                  shouldShowOnWeb;

              return Positioned.fill(
                child: shouldHideThumbnail
                    ? const SizedBox.shrink()
                    : _buildVideoThumbnail(video),
              );
            },
          ),
          if (controller != null && controller.value.isInitialized)
            ValueListenableBuilder<bool>(
              valueListenable:
                  _firstFrameReady[index] ?? ValueNotifier<bool>(false),
              builder: (context, firstFrameReady, _) {
                // **WEB FIX: On web, always show video if controller is initialized**
                // Web video player doesn't always trigger firstFrameReady properly
                // So we force show video on web if controller is initialized
                // This ensures videos are visible even if firstFrameReady never triggers
                final bool shouldShowOnWeb =
                    kIsWeb && controller.value.isInitialized;

                final shouldShowVideo = firstFrameReady ||
                    _forceMountPlayer[index]?.value == true ||
                    shouldShowOnWeb;

                if (shouldShowVideo) {
                  return Positioned.fill(
                    child:
                        _buildVideoPlayer(controller, isActive, index, video),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => _togglePlayPause(index),
              onDoubleTap: () => _handleDoubleTapLike(video, index),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: _userPaused[index] == true ? 1.0 : 0.0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: ValueListenableBuilder<bool>(
                valueListenable: _isBufferingVN[index] ??=
                    ValueNotifier<bool>(false),
                builder: (context, isBuffering, _) {
                  final show = isBuffering && _userPaused[index] != true;
                  return Opacity(
                    opacity: show ? 1.0 : 0.0,
                    child: Stack(
                      children: [
                        const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                        // **NEW: Slow Internet message**
                        ValueListenableBuilder<bool>(
                          valueListenable: _isSlowConnectionVN[index] ??=
                              ValueNotifier<bool>(false),
                          builder: (context, isSlow, _) {
                            if (!isSlow) return const SizedBox.shrink();
                            return Positioned(
                              top: 100,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.7),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                       Icon(
                                        Icons.wifi_off_rounded,
                                        color: Colors.orange,
                                        size: 16,
                                      ),
                                       SizedBox(width: 8),
                                      Text(
                                        'Slow Internet Connection',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          if (controller != null && controller.value.isInitialized && isActive)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildVideoProgressBar(controller),
            ),
          _buildVideoOverlay(video, index),
          _buildReportIndicator(index),
          if (_showHeartAnimation[index]?.value == true)
            _buildHeartAnimation(index),
          _buildBannerAd(video, index),
        ],
      ),
    );
  }

  Widget _buildHeartAnimation(int index) {
    final notifier = _showHeartAnimation[index];
    if (notifier == null) {
      return const SizedBox.shrink();
    }
    return HeartAnimation(showNotifier: notifier);
  }

  Widget _buildReportIndicator(int index) {
    final String videoId =
        (index >= 0 && index < _videos.length) ? _videos[index].id : '';
    return Positioned(
      right: 16,
      top: (_screenHeight ?? 800) * 0.5 - 20,
      child: AnimatedOpacity(
        opacity: 0.7,
        duration: const Duration(milliseconds: 300),
        child: GestureDetector(
          onTap: () => _openReportDialog(videoId),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Report',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(width: 4),
                Icon(Icons.arrow_forward_ios, color: Colors.white, size: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBannerAd(VideoModel video, int index) {
    // **FIXED: Prepare custom ad data for fallback (even when AdMob is configured)**
    Map<String, dynamic>? adData;

    if (_lockedBannerAdByVideoId.containsKey(video.id)) {
      adData = _lockedBannerAdByVideoId[video.id];
    } else if (_adsLoaded && _bannerAds.isNotEmpty) {
      final adIndex = index % _bannerAds.length;
      if (adIndex < _bannerAds.length) {
        adData = _bannerAds[adIndex];
        _lockedBannerAdByVideoId[video.id] = adData;
      }
    }

    // Prepare ad data map with videoId if available
    Map<String, dynamic>? adDataWithVideoId;
    if (adData != null) {
      adDataWithVideoId = {
        ...adData,
        'videoId': video.id,
      };
    }

    // **FIXED: Always pass custom ad data to BannerAdSection for fallback**
    // BannerAdSection will try AdMob first, then fallback to custom ads
    return BannerAdSection(
      adData: adDataWithVideoId, // **FIXED: Pass custom ad data for fallback**
      onClick: () {
        AppLogger.log('🖱️ Banner ad clicked on video $index');
      },
      onImpression: () async {
        if (index < _videos.length && adData != null) {
          final video = _videos[index];
          final adId = adData['_id'] ?? adData['id'];
          final userData = await _authService.getUserData();

          AppLogger.log('📊 Banner Ad Impression Tracking:');
          AppLogger.log('   Video ID: ${video.id}');
          AppLogger.log('   Video Name: ${video.videoName}');
          AppLogger.log('   Ad ID: $adId');
          AppLogger.log('   User ID: ${userData?['id']}');

          if (adId != null && userData != null) {
            try {
              await _adImpressionService.trackBannerAdImpression(
                videoId: video.id,
                adId: adId.toString(),
                userId: userData['id'],
              );
            } catch (e) {
              AppLogger.log('❌ Error tracking banner ad impression: $e');
            }
          }
        }
      },
      useGoogleAds: AdMobConfig.isConfigured(), // **FIXED: Use AdMob if configured, fallback to custom ads**
    );
  }

  Widget _buildVideoProgressBar(VideoPlayerController controller) {
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final screenWidth = constraints.maxWidth;
          return _ThrottledProgressBar(
            controller: controller,
            screenWidth: screenWidth,
            onSeek: (details) => _seekToPosition(controller, details),
          );
        },
      ),
    );
  }

  Widget _buildGreenSpinner({double size = 24}) {
    return SizedBox(
      width: size,
      height: size,
      child: const CircularProgressIndicator(
        strokeWidth: 3,
        color: Colors.green,
      ),
    );
  }

  Widget _buildVideoPlayer(
    VideoPlayerController controller,
    bool isActive,
    int index,
    VideoModel video,
  ) {
    return RepaintBoundary(
      child: Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        // **WEB FIX: Ensure video player container is above other elements**
        child: Center(
          child: _buildVideoWithCorrectAspectRatio(
            controller,
            video,
          ),
        ),
      ),
    );
  }

  Widget _buildVideoWithCorrectAspectRatio(
    VideoPlayerController controller,
    VideoModel currentVideo,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final screenHeight = constraints.maxHeight;

        // **FIX: Use video's actual aspect ratio from controller if model doesn't have one**
        // This ensures ALL videos display in their original aspect ratio regardless of size, duration, etc.
        double modelAspectRatio = currentVideo.aspectRatio > 0
            ? currentVideo.aspectRatio
            : _getDetectedAspectRatio(
                controller); // Use detected ratio from video controller

        // final Size videoSize = controller.value.size; // Unused
        // final int rotation = controller.value.rotationCorrection; // Unused

        // _debugAspectRatio(controller); // Disabled for performance

        // **FIX: Use model aspect ratio to determine portrait vs landscape**
        // Portrait videos have aspect ratio < 1.0 (height > width)
        // Landscape videos have aspect ratio >= 1.0 (width >= height)
        if (modelAspectRatio < 1.0) {
          return _buildPortraitVideoFromModel(
            controller,
            screenWidth,
            screenHeight,
            modelAspectRatio,
            currentVideo,
          );
        } else {
          return _buildLandscapeVideoFromModel(
            controller,
            screenWidth,
            screenHeight,
            modelAspectRatio,
            currentVideo,
          );
        }
      },
    );
  }

  // _isPortraitVideo removed (unused)

  /// **Get detected aspect ratio from video controller**
  /// This ensures videos display in their original aspect ratio even if model doesn't have one
  double _getDetectedAspectRatio(VideoPlayerController controller) {
    try {
      final Size videoSize = controller.value.size;
      final int rotation = controller.value.rotationCorrection;

      double videoWidth = videoSize.width;
      double videoHeight = videoSize.height;

      if (rotation == 90 || rotation == 270) {
        videoWidth = videoSize.height;
        videoHeight = videoSize.width;
      }

      if (videoWidth > 0 && videoHeight > 0) {
        final double aspectRatio = videoWidth / videoHeight;
        return aspectRatio > 0
            ? aspectRatio
            : 9.0 / 16.0; // Fallback if invalid
      }
    } catch (e) {
      AppLogger.log('⚠️ Error detecting aspect ratio: $e');
    }
    return 9.0 / 16.0; // Final fallback
  }

  Widget _buildPortraitVideoFromModel(
    VideoPlayerController controller,
    double screenWidth,
    double screenHeight,
    double modelAspectRatio,
    VideoModel currentVideo,
  ) {
    AppLogger.log(
      '🎬 MODEL Portrait video - Aspect Ratio: $modelAspectRatio',
    );
    
    // **FIX: Simplified to use standard AspectRatio widget**
    // This removes usage of originalResolution logic which might be causing sizing issues
    // and relies on standard Flutter widgets to respect aspect ratio.
    return AspectRatio(
      aspectRatio: modelAspectRatio,
      child: VideoPlayer(controller),
    );
  }

  // _debugAspectRatio removed (unused)

  Widget _buildLandscapeVideoFromModel(
    VideoPlayerController controller,
    double screenWidth,
    double screenHeight,
    double modelAspectRatio,
    VideoModel currentVideo,
  ) {
    // Simplification for release build
    // AppLogger.log('🎬 MODEL Landscape video - Aspect Ratio: $modelAspectRatio');

    // **FIX: Simplified to use standard AspectRatio widget**
    // This ensures the video always fits the screen width while maintaining aspect ratio
    // without fragile manual calculations or originalResolution dependency.
    return AspectRatio(
      aspectRatio: modelAspectRatio,
      child: VideoPlayer(controller),
    );
  }

  /// **WEB FIX: Build video player widget with explicit sizing for web compatibility**


  // Debug logic removed for release build
  // void _debugAspectRatio(VideoPlayerController controller) { ... }

  Widget _buildVideoThumbnail(VideoModel video) {
    final index = _videos.indexOf(video);
    final aspectRatio = video.aspectRatio > 0 ? video.aspectRatio : 9 / 16;

    return RepaintBoundary(
      child: Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        child: ValueListenableBuilder<bool>(
          valueListenable:
              _firstFrameReady[index] ?? ValueNotifier<bool>(false),
          builder: (context, ready, _) {
            final child = video.thumbnailUrl.isNotEmpty
                ? AspectRatio(
                    aspectRatio: aspectRatio,
                    child: CachedNetworkImage(
                      imageUrl: video.thumbnailUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => _buildFallbackThumbnail(),
                      errorWidget: (context, url, error) =>
                          _buildFallbackThumbnail(),
                    ),
                  )
                : _buildFallbackThumbnail();

            // **NEW: Premium pulsing effect during priming**
            if (!ready && index == _currentIndex) {
              return TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.7, end: 1.0),
                duration: const Duration(milliseconds: 1000),
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: child,
                  );
                },
                onEnd: () {

                },
                child: child,
              );
              // Note: for a true looping animation we'd need an AnimationController,
              // but since this is inside a builder, a simple subtle pulse is fine.
            }
            return child;
          },
        ),
      ),
    );
  }

  Widget _buildFallbackThumbnail() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.play_circle_outline, size: 80, color: Colors.white54),
            SizedBox(height: 16),
            Text(
              'Tap to play video',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<double> _calculateEarningsFromAdViews(VideoModel video) async {
    if (_earningsCache.containsKey(video.id)) {
      return _earningsCache[video.id]!;
    }
    try {
      final totalEarnings =
          await EarningsService.calculateCreatorRevenueForVideo(video.id);
      _earningsCache[video.id] = totalEarnings;
      return totalEarnings;
    } catch (_) {
      return 0.0;
    }
  }

  Widget _buildEarningsLabel(VideoModel video) {
    return GestureDetector(
      onTap: () => _showEarningsBottomSheet(),
      child: FutureBuilder<double>(
        future: _calculateEarningsFromAdViews(video),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.green.withOpacity(0.6),
                  width: 1,
                ),
              ),
              child: const Text(
                '...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }

          final earnings = snapshot.data ?? 0.0;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.green.withOpacity(0.6),
                width: 1,
              ),
            ),
            child: Text(
              '₹${earnings.toStringAsFixed(2)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildVideoOverlay(VideoModel video, int index) {
    // **REELS/SHORTS STYLE: Position at absolute bottom with zero spacing**
    return Builder(
      builder: (context) {
        final mediaQuery = MediaQuery.of(context);
        // Only account for SafeArea bottom padding (system navigation bar)
        // No bottom navigation bar spacing - elements will be at absolute bottom
        final bottomPadding = mediaQuery.padding.bottom;

        return RepaintBoundary(
          child: Stack(
            children: [
              Positioned(
                top: 52,
                right: 8,
                child: _buildEarningsLabel(video),
              ),
              // **Video info at absolute bottom - Reels/Shorts style**
              Positioned(
                bottom:
                    bottomPadding, // Only SafeArea padding, no extra spacing
                left: 0,
                right: 75,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12,
                      8), // **FIX: Bottom padding for content spacing**
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _navigateToCreatorProfile(video),
                        child: Row(
                          children: [
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _navigateToCreatorProfile(video),
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.grey,
                                ),
                                child: video.uploader.profilePic.isNotEmpty
                                    ? ClipOval(
                                        child: CachedNetworkImage(
                                          imageUrl: video.uploader.profilePic,
                                          fit: BoxFit.cover,
                                          placeholder: (context, url) =>
                                              Container(
                                            color: Colors.grey[300],
                                            child: Center(
                                              child: Text(
                                                video.uploader.name.isNotEmpty
                                                    ? video.uploader.name[0]
                                                        .toUpperCase()
                                                    : 'U',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 10,
                                                ),
                                              ),
                                            ),
                                          ),
                                          errorWidget: (context, url, error) =>
                                              Container(
                                            color: Colors.grey[300],
                                            child: Center(
                                              child: Text(
                                                video.uploader.name.isNotEmpty
                                                    ? video.uploader.name[0]
                                                        .toUpperCase()
                                                    : 'U',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 10,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      )
                                    : Center(
                                        child: Text(
                                          video.uploader.name.isNotEmpty
                                              ? video.uploader.name[0]
                                                  .toUpperCase()
                                              : 'U',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => _navigateToCreatorProfile(video),
                                child: Text(
                                  video.uploader.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            _buildFollowTextButton(video),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        video.videoName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      if (video.link?.isNotEmpty == true)
                        GestureDetector(
                          onTap: () => _handleVisitNow(video),
                          child: Container(
                            width: (_screenWidth ?? 400) * 0.75,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.4),
                                  blurRadius: 12,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.open_in_new,
                                  color: Colors.white,
                                  size: 14,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Visit Now',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // **Action buttons at absolute bottom - Reels/Shorts style**
              Positioned(
                right: 12,
                bottom:
                    bottomPadding, // Only SafeArea padding, no extra spacing
                child: Column(
                  children: [
                    _buildVerticalActionButton(
                      icon: _isLiked(video)
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: _isLiked(video) ? Colors.red : Colors.white,
                      count: video.likes,
                      onTap: () => _handleLike(video, index),
                    ),
                    const SizedBox(height: 10),
                    _buildVerticalActionButton(
                      icon: Icons.chat_bubble_outline,
                      count: video.comments.length,
                      onTap: () => _handleComment(video),
                    ),
                    const SizedBox(height: 10),
                    _buildVerticalActionButton(
                      icon: Icons.share,
                      onTap: () => _handleShare(video),
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () => _navigateToCarouselAd(index),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.arrow_forward_ios,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Swipe',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVerticalActionButton({
    required IconData icon,
    required VoidCallback onTap,
    Color color = Colors.white,
    int? count,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          if (count != null) ...[
            const SizedBox(height: 4),
            Text(
              _formatCount(count),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                shadows: [
                  Shadow(
                    offset: Offset(0, 1),
                    blurRadius: 2,
                    color: Colors.black54,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatCount(int count) {
    if (count < 1000) {
      return count.toString();
    } else if (count < 1000000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    } else {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    }
  }

  Widget _buildCarouselAdPage(int videoIndex) {
    if (_carouselAds.isEmpty) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        child: const Center(
          child: Text(
            'No carousel ads available',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    final carouselAd = _carouselAds[0];

    String? videoId;
    if (videoIndex < _videos.length) {
      videoId = _videos[videoIndex].id;
    }

    return CarouselAdWidget(
      carouselAd: carouselAd,
      videoId: videoId,
      onAdClosed: () {
        if (_currentHorizontalPage.containsKey(videoIndex)) {
          _currentHorizontalPage[videoIndex]!.value = 0;
        }
      },
      autoPlay: true,
    );
  }

  /// **OFFLINE INDICATOR: Shows when device has no internet connection**
  Widget _buildOfflineIndicator() {
    return StreamBuilder<List<ConnectivityResult>>(
      stream: ConnectivityService.connectivityStream,
      initialData: ConnectivityService.lastKnownResult,
      builder: (context, snapshot) {
        final connectivityResults = snapshot.data ?? [ConnectivityResult.none];
        final isOffline = ConnectivityService.isOffline(connectivityResults);

        if (!isOffline) {
          return const SizedBox.shrink();
        }

        return Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.orange.shade700,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.wifi_off,
                    color: Colors.white,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'No internet connection',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// **NEW: Show Earnings Bottom Sheet with video details**
  Future<void> _showEarningsBottomSheet() async {
    // Show earnings only for the CURRENT video user is watching in Yug tab
    if (_currentIndex < 0 || _currentIndex >= _videos.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Current video not found'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final currentVideo = _videos[_currentIndex];

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        // Yug tab: compact bottom sheet for single-video earnings
        initialChildSize: 0.5, // 50% of screen height by default
        minChildSize: 0.3, // Can be dragged down to 30%
        maxChildSize: 0.9, // Can be expanded up to 90%
        builder: (context, scrollController) => EarningsBottomSheetContent(
          videos: [currentVideo],
          scrollController: scrollController,
        ),
      ),
    );
  }
}
