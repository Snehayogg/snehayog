part of 'package:vayu/view/screens/video_feed_advanced.dart';

extension _VideoFeedUI on _VideoFeedAdvancedState {
  Widget _buildVideoFeed() {
    return RefreshIndicator(
      onRefresh: refreshVideos,
      child: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        // **CUSTOM PHYSICS: Enabled VayuScrollPhysics for better snap/velocity control**
        physics: const ScrollPhysics(),
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
        child: Center(
          child: Column(
             mainAxisAlignment: MainAxisAlignment.center,
             children: [
                if (_errorMessage != null && _errorMessage!.isNotEmpty) ...[
                  const Icon(Icons.cloud_off, size: 48, color: Colors.white24),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      _getUserFriendlyErrorMessage(_errorMessage!),
                      style: const TextStyle(color: Colors.white54, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () {
                      safeSetState(() {
                        _errorMessage = null;
                        _loadMoreVideos();
                      });
                    },
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text("Retry Loading"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white12,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                  ),
                ] else ...[
                  const SizedBox(
                     width: 30,
                     height: 30,
                     child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white24)
                  ),
                  const SizedBox(height: 16),
                  const Text("Loading more videos...", style: TextStyle(color: Colors.white24, fontSize: 13)),
                ],
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
            RepaintBoundary(child: Center(child: _buildGreenSpinner(size: 28))),
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
    // **ZOMBIE AUDIO FIX: Check if error is real or if controller recovered**
    bool showError = _videoErrors.containsKey(index);
    if (showError && controller != null && controller.value.isInitialized && !controller.value.hasError) {
       // If controller is playing or has buffered content, it's likely a stale error
       // (e.g. transient network error during load, but retry succeeded)
       if (controller.value.isPlaying || controller.value.buffered.isNotEmpty) {
          // It's working! Ignore the error and schedule cleanup
          showError = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
             if (mounted && _videoErrors.containsKey(index)) {
                // AppLogger.log('✅ UI: Auto-recovered from stale error for video $index (Controller is healthy)');
                safeSetState(() {
                   _videoErrors.remove(index);
                   // Reset buffering state to be safe
                   _isBuffering[index] = false;
                   _isBufferingVN[index]?.value = false;
                });
             }
          });
       }
    }

    if (showError) {
      // **FINAL SAFETY: Ensure controller is paused if we show error**
      if (controller != null && controller.value.isPlaying) {
         controller.pause();
      }
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
          // **NEW: Back Button for Profile/Vayu navigation**
          if (widget.isFullScreen)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 16,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_back,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
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
              // **OPTIMIZED: Use ValueListenableBuilder for granular updates - avoid setState**
              child: ValueListenableBuilder<bool>(
                valueListenable: _userPausedVN[index] ??= ValueNotifier<bool>(false),
                builder: (context, isUserPaused, _) {
                  return Opacity(
                    opacity: isUserPaused ? 1.0 : 0.0,
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
                  );
                },
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: ValueListenableBuilder<bool>(
                valueListenable: _isBufferingVN[index] ??=
                    ValueNotifier<bool>(false),
                builder: (context, isBuffering, _) {
                   // **OPTIMIZED: Listen to userPausedVN too for correct visibility**
                   return ValueListenableBuilder<bool>(
                      valueListenable: _userPausedVN[index] ??= ValueNotifier<bool>(false),
                      builder: (context, isUserPaused, _) {
                          final show = isBuffering && !isUserPaused;
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
                      }
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
          _buildTopGradientOverlay(),
          ValueListenableBuilder<bool>(
            valueListenable: _adsLoadedVN,
            builder: (context, adsLoaded, _) {
              return _buildBannerAd(video, index);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTopGradientOverlay() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: 200, // Top 20-25% approximately
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.4),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeartAnimation(int index) {
    final notifier = _showHeartAnimation[index];
    if (notifier == null) {
      return const SizedBox.shrink();
    }
    return RepaintBoundary(child: HeartAnimation(showNotifier: notifier));
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
    // **DEBUG: Track ad state**
    // AppLogger.log('📺 UI: _buildBannerAd calling for video $index. AdsLoaded: $_adsLoaded, BannerAds: ${_bannerAds.length}');

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





  Widget _buildVideoOverlay(VideoModel video, int index) {
    // **REELS/SHORTS STYLE: Position at absolute bottom with zero spacing**
    return Builder(
      builder: (context) {
        final mediaQuery = MediaQuery.of(context);
        // **ENHANCED: Unified bottom padding strategy**
        // 1. Always account for system navigation bar (SafeArea padding)
        // 2. Add extra 60px padding when opened as a full-screen route (e.g. from Profile/Vayu)
        // 3. **NEW: Ensure min padding (e.g., 20) to clear the 40px seek bar touch zone**
        final bottomPadding = (mediaQuery.padding.bottom > 20 ? mediaQuery.padding.bottom : 20.0) + (widget.isFullScreen ? 60 : 0);

        return RepaintBoundary(
          child: Stack(
            children: [
              // **NEW: Bottom soft gradient for text readability**
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 200, // Enough to cover caption and action buttons
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withOpacity(0.55),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
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
                                width: AppConstants.avatarRadius * 2,
                                height: AppConstants.avatarRadius * 2,
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
                                    fontSize: 14, // Increased from 12
                                    fontWeight: FontWeight.w600, // Bold
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            // **NEW: Subscribe Button**
                            GestureDetector(
                              onTap: () => _handleFollow(video),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _isFollowing(video.uploader.id) ? Colors.grey[700] : Colors.black,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _isFollowing(video.uploader.id) ? 'Subscribed' : 'Subscribe',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        video.videoName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12, // Slightly increased
                          fontWeight: FontWeight.w400, // Lighter
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
                    // **NEW: Episode Action Button**
                    if (video.episodes != null && video.episodes!.isNotEmpty)
                      Column(
                        children: [
                      _buildVerticalActionButton(
                            icon: Icons.playlist_play_rounded,
                            onTap: () => _showEpisodeList(context, video),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                  _buildLikeButton(video, index),
                  const SizedBox(height: 12),
                    // **NEW: Info Button for Video Details**
                    _buildVerticalActionButton(
                      icon: Icons.info_outline,
                      onTap: () => _showVideoDetailsBottomSheet(context, video),
                    ),
                    const SizedBox(height: 12),
                    _buildVerticalActionButton(
                      icon: Icons.share,
                      onTap: () => _handleShare(video),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () => _navigateToCarouselAd(index),
                      child: Column(
                        children: [
                          Container(
                            width: AppConstants.secondaryActionButtonContainerSize,
                            height: AppConstants.secondaryActionButtonContainerSize,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.55),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.arrow_forward_ios,
                              color: Colors.white,
                              size: AppConstants.secondaryActionButtonSize,
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

  ValueNotifier<bool> _getLikeNotifier(VideoModel video) {
    if (!_isLikedVN.containsKey(video.id)) {
      _isLikedVN[video.id] = ValueNotifier<bool>(video.isLiked);
    }
    return _isLikedVN[video.id]!;
  }

  ValueNotifier<int> _getLikeCountNotifier(VideoModel video) {
    if (!_likeCountVN.containsKey(video.id)) {
      _likeCountVN[video.id] = ValueNotifier<int>(video.likes);
    }
    return _likeCountVN[video.id]!;
  }

  Widget _buildLikeButton(VideoModel video, int index) {
    return ValueListenableBuilder<bool>(
      valueListenable: _getLikeNotifier(video),
      builder: (context, isLiked, _) {
        return ValueListenableBuilder<int>(
          valueListenable: _getLikeCountNotifier(video),
          builder: (context, likeCount, _) {
            // **NEW: Using LikeButton for burst animation**
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: AppConstants.primaryActionButtonContainerSize,
                  height: AppConstants.primaryActionButtonContainerSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: LikeButton(
                    padding: EdgeInsets.zero,
                    size: AppConstants.primaryActionButtonSize,
                    isLiked: isLiked,
                    circleColor: const CircleColor(
                      start: Color(0xff00ddff),
                      end: Color(0xff0099cc),
                    ),
                    bubblesColor: const BubblesColor(
                      dotPrimaryColor: Color(0xff33b5e5),
                      dotSecondaryColor: Color(0xff0099cc),
                    ),
                    likeBuilder: (bool isLiked) {
                      return Icon(
                        isLiked ? Icons.favorite : Icons.favorite_border,
                        color: isLiked ? Colors.red : Colors.white,
                        size: AppConstants.primaryActionButtonSize, // Match size
                        shadows: const [
                          Shadow(
                            color: Colors.black26,
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      );
                    },
                    onTap: (bool isLiked) async {
                      await _handleLike(video, index);
                      return !isLiked;
                    },
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatCount(likeCount),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9), // Subtle
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            );
          },
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
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: AppConstants.secondaryActionButtonContainerSize,
            height: AppConstants.secondaryActionButtonContainerSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.55),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              icon,
              color: color,
              size: AppConstants.secondaryActionButtonSize,
              shadows: const [
                Shadow(
                  color: Colors.black45,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
          if (count != null) ...[
            const SizedBox(height: 4),
            Text(
              _formatCount(count),
              style: TextStyle(
                color: Colors.white.withOpacity(0.9), // Subtle
                fontSize: 12,
                fontWeight: FontWeight.w500,
                shadows: const [
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

  void _showEpisodeList(BuildContext context, VideoModel video) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.8,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  // Handle bar
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Title
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.playlist_play, color: Colors.black),
                        const SizedBox(width: 8),
                        Text(
                          'More Episodes',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  // List
                  Expanded(
                    child: GridView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 0.7,
                      ),
                      itemCount: video.episodes!.length,
                      itemBuilder: (context, index) {
                        final episode = video.episodes![index];
                        // Placeholder thumbnail logic - use video thumbnail if episode doesn't have one
                        final String thumbnailUrl = episode['thumbnailUrl'] ?? video.thumbnailUrl;
                        final String sequenceNumber = (index + 1).toString();

                        return GestureDetector(
                          onTap: () {
                              Navigator.pop(context);
                              // Navigate to the selected episode
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => VideoFeedAdvanced(
                                    initialVideoId: episode['id'] ?? episode['_id'],
                                    videoType: 'yog', // Episodes are typically 'yog' type
                                    isFullScreen: true, // **NEW: Full-screen mode**
                                  ),
                                ),
                              );
                              AppLogger.log('Selected episode $sequenceNumber: ${episode['id'] ?? episode['_id']}');
                          },
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CachedNetworkImage(
                                  imageUrl: thumbnailUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(color: Colors.grey[300]),
                                  errorWidget: (context, url, error) => Container(
                                    color: Colors.grey[300],
                                    child: const Icon(Icons.error),
                                  ),
                                ),
                              ),
                              // Sequence Number Overlay
                              Positioned(
                                top: 4,
                                left: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.7),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    sequenceNumber,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                              // Play Icon Overlay
                              Center(
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.5),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.play_arrow,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatUploadDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 365) {
      return '${(difference.inDays / 365).floor()}y ago';
    } else if (difference.inDays > 30) {
      return '${(difference.inDays / 30).floor()}mo ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }


  /// **SHOW VIDEO DETAILS BOTTOM SHEET**
  void _showVideoDetailsBottomSheet(BuildContext context, VideoModel video) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Video Details',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 20, color: Colors.grey),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Published on',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                    Text(
                      _formatUploadDate(video.uploadedAt),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.remove_red_eye_outlined, size: 20, color: Colors.grey),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Total Views',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                    Text(
                      '${_formatCount(video.views)} views',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
