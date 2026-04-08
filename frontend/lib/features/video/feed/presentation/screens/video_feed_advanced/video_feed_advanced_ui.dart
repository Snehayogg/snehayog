part of '../video_feed_advanced.dart';

extension _VideoFeedUI on _VideoFeedAdvancedState {
  double get _primaryActionHitTargetSize {
    const minTouchTarget = AppSpacing.minTouchTarget;
    const primaryContainer = AppConstants.primaryActionButtonContainerSize;
    return minTouchTarget > primaryContainer
        ? minTouchTarget
        : primaryContainer;
  }

  double get _secondaryActionHitTargetSize {
    const minTouchTarget = AppSpacing.minTouchTarget;
    const secondaryContainer = AppConstants.secondaryActionButtonContainerSize;
    return minTouchTarget > secondaryContainer
        ? minTouchTarget
        : secondaryContainer;
  }

  Widget _buildVideoFeed() {
    return VisibilityDetector(
      key: const Key('yug_feed_visibility'),
      onVisibilityChanged: (visibilityInfo) {
        final double visibleFraction = visibilityInfo.visibleFraction;
        // Determine if screen is truly visible to the user
        final bool isCurrentlyVisible = visibleFraction > 0;
        _handleVisibilityChange(isCurrentlyVisible);
      },
      child: RefreshIndicator(
        onRefresh: refreshVideos,
        child: PageView.builder(
          controller: _pageController,
          scrollDirection: Axis.vertical,
          onPageChanged: _onPageChanged,
          itemCount: _getTotalItemCount(),
          itemBuilder: (context, index) {
            return _buildFeedItem(index);
          },
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: AppColors.error),
          AppSpacing.vSpace16,
          Text(
            'Failed to load videos',
            style: TextStyle(
              color: AppColors.white,
              fontSize: AppTypography.fontSizeXL,
              fontWeight: AppTypography.weightBold,
            ),
          ),
          if (_errorMessage != null) ...[
            AppSpacing.vSpace8,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _getUserFriendlyErrorMessage(_errorMessage!),
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: AppTypography.fontSizeBase),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          AppSpacing.vSpace24,
          AppButton(
            onPressed: refreshVideos,
            icon: const Icon(Icons.refresh),
            label: 'Retry',
            variant: AppButtonVariant.primary,
          ),
          AppSpacing.vSpace12,
          AppButton(
            onPressed: _testApiConnection,
            icon: const Icon(Icons.wifi_find),
            label: 'Test Connection',
            variant: AppButtonVariant.secondary,
          ),
        ],
      ),
    );
  }

  // **NEW: Individual Video Error State widget**
  Widget _buildVideoErrorState(int index, String error) {
    final String videoId = index < _videos.length ? _videos[index].id : '';
    return Container(
      color: AppColors.backgroundPrimary,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: AppColors.textSecondary, size: 48),
            AppSpacing.vSpace12,
            const Text(
              'Playback Error',
              style: TextStyle(
                  color: AppColors.white, fontWeight: AppTypography.weightBold),
            ),
            AppSpacing.vSpace4,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                _getUserFriendlyErrorMessage(error),
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: AppTypography.fontSizeSM),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            AppSpacing.vSpace16,
            AppButton(
              onPressed: () {
                // Retry logic: clear error and reload
                safeSetState(() {
                  _videoErrors.remove(videoId);
                  _loadingVideos.add(videoId); // Show spinner
                  _isBuffering[videoId] = false; // Reset buffering state
                  _isBufferingVN[videoId]?.value = false;
                });
                // Force reload (Use fallback for manual retry to ensure success)
                _preloadVideo(index, bypassProxy: true).then((_) {
                  if (mounted && index == _currentIndex) {
                    _tryAutoplayCurrentImmediate(index);
                  }
                });
              },
              icon: const Icon(Icons.refresh, size: 16),
              label: 'Retry',
              variant: AppButtonVariant.secondary,
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
            color: AppColors.textSecondary,
          ),
          AppSpacing.vSpace16,
          Text(
            'No videos available',
            style: TextStyle(
              color: AppColors.white,
              fontSize: AppTypography.fontSizeXL,
              fontWeight: AppTypography.weightBold,
            ),
          ),
          AppSpacing.vSpace8,
          Text(
            'Try refreshing or check back later',
            style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: AppTypography.fontSizeBase),
            textAlign: TextAlign.center,
          ),
          AppSpacing.vSpace24,
          AppButton(
            onPressed: refreshVideos,
            icon: const Icon(Icons.refresh),
            label: 'Refresh',
            variant: AppButtonVariant.primary,
          ),
          // **NEW: Add debug info button for troubleshooting**
          if (_errorMessage != null && _errorMessage!.isNotEmpty) ...[
            AppSpacing.vSpace12,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Error: ${_errorMessage!.length > 100 ? "${_errorMessage!.substring(0, 100)}..." : _errorMessage!}',
                style: TextStyle(
                  color: AppColors.error,
                  fontSize: AppTypography.fontSizeSM,
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

    // **NEW: Pre-fetch Trigger (Buffer 12 videos - Ultra Aggressive for Fast Scroll)**
    // Trigger load more when user is within 12 videos of the end (approx 80% through batch)
    // This provides a much larger safety buffer for slow backend refills or fast scrolling.

    // **OPTIMIZATION: Adjust trigger for Low-RAM devices**
    final int prefetchThreshold = _isLowEndDevice ? 3 : 12;

    if (mounted &&
        totalVideos > 0 &&
        index >= totalVideos - prefetchThreshold &&
        !_isLoadingMore &&
        !_isRefreshing &&
        _hasMore) {
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
            AppLogger.log(
                '📡 UI: End-of-feed reached at index $index. Triggering _loadMoreVideos');
            _loadMoreVideos();
          });
        }

        // Return duplicate of last video for seamless feel
        return _buildVideoItem(
          lastVideo,
          lastController,
          videoIndex == _currentIndex, // **FIX: Allow buffer item to be active**
          lastVideoIndex,
        );
      }

      // **FALLBACK: Loading Skeleton for subsequent items (index > totalVideos)**
      // This gives visual feedback that "more is coming" if user scrolls deep
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: AppColors.backgroundPrimary, // Black background
        child: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (_errorMessage != null && _errorMessage!.isNotEmpty) ...[
              const Icon(Icons.cloud_off,
                  size: 48, color: AppColors.textTertiary),
              AppSpacing.vSpace16,
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  _getUserFriendlyErrorMessage(_errorMessage!),
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: AppTypography.fontSizeSM),
                  textAlign: TextAlign.center,
                ),
              ),
              AppSpacing.vSpace24,
              AppButton(
                onPressed: () {
                  safeSetState(() {
                    _errorMessage = null;
                    _loadMoreVideos();
                  });
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: "Retry Loading",
                variant: AppButtonVariant.secondary,
              ),
            ] else ...[
              const SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary)),
              AppSpacing.vSpace16,
              Text("Loading more videos...",
                  style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: AppTypography.fontSizeSM)),
              // **NEW: Safety Trigger: If we land on this screen, force a reload if not already loading**
              if (mounted && !_isLoadingMore && !_isRefreshing && _hasMore) ...[
                AppSpacing.vSpace8,
                Builder(builder: (_) {
                  WidgetsBinding.instance.addPostFrameCallback((__) {
                    if (!_isLoadingMore) _loadMoreVideos();
                  });
                  return const SizedBox.shrink();
                }),
              ],
            ],
          ]),
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
    final String videoId = video.id;
    _getOrCreateNotifier<int>(_currentHorizontalPage, videoId, 0);

    return Container(
      key: ValueKey(
          'video_${video.id}'), // **FIX: Stable key to prevent player recreation on feed update**
      width: double.infinity,
      height: double.infinity,
      color: AppColors.backgroundPrimary,
      child: Stack(
        children: [
          PageView(
            controller: _horizontalControllers.putIfAbsent(videoId, () => PageController(initialPage: _currentHorizontalPage[videoId]!.value)),
            onPageChanged: (page) {
              _currentHorizontalPage[videoId]!.value = page;
              if (page == 1) {
                // Pause video when swiping to ad
                _pauseCurrentVideo();
              } else if (page == 0 && isActive) {
                // Resume video when swiping back (if it's the active one)
                _tryAutoplayCurrent();
              }
            },
            physics: const BouncingScrollPhysics(),
            children: [
              _buildVideoPage(video, controller, isActive, index),
              if (_carouselAdManager.shouldShowCarouselAd(index))
                _buildCarouselAdPage(index)
              else
                const SizedBox.shrink(),
            ],
          ),
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
    return _buildVideoPageContent(video, controller, isActive, index);
  }

  Widget _buildVideoPageContent(
    VideoModel video,
    VideoPlayerController? controller,
    bool isActive,
    int index,
  ) {
    final String videoId = video.id;
    bool controllerUsable = false;
    // **RE-INITIALIZATION TRIGGER: If controller is disposed, restart it immediately**
    bool isDisposed = false;
    try {
      if (controller == null) {
        isDisposed = true;
      } else {
        isDisposed = SharedVideoControllerPool().isControllerDisposed(controller);
      }
    } catch (_) {
      isDisposed = true;
    }

    if (isDisposed) {
      controllerUsable = false;
      controller = null;
      // Trigger re-initialization in next frame to avoid state mutation during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          AppLogger.log('🔄 UI: Detected disposed controller for video $index. Re-initializing...');
          _preloadVideo(index);
        }
      });
    } else {
      try {
        controllerUsable = controller!.value.isInitialized;
      } catch (_) {
        controllerUsable = false;
      }
    }

    // **NEW: Check for error state**
    // **ZOMBIE AUDIO FIX: Check if error is real or if controller recovered**
    bool showError = _videoErrors.containsKey(videoId);
    if (showError &&
        controllerUsable &&
        controller != null &&
        !controller.value.hasError) {
      // If controller is playing or has buffered content, it's likely a stale error
      // (e.g. transient network error during load, but retry succeeded)
      if (controller.value.isPlaying || controller.value.buffered.isNotEmpty) {
        // It's working! Ignore the error and schedule cleanup
        showError = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _videoErrors.containsKey(videoId)) {
            // AppLogger.log('✅ UI: Auto-recovered from stale error for video $videoId (Controller is healthy)');
            safeSetState(() {
              _videoErrors.remove(videoId);
              // Reset buffering state to be safe
              _isBuffering[videoId] = false;
              _isBufferingVN[videoId]?.value = false;
            });
          }
        });
      }
    }

    if (showError) {
      // **FINAL SAFETY: Ensure controller is paused if we show error**
      try {
        if (controller != null && controllerUsable && controller.value.isPlaying) {
          controller.pause();
        }
      } catch (_) {}
      return _buildVideoErrorState(index, _videoErrors[videoId]!);
    }

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: AppColors.backgroundPrimary,
      child: RepaintBoundary(
        child: Stack(
          children: [
            Align(
              alignment: Alignment.bottomCenter,
              child: AspectRatio(
                aspectRatio: video.aspectRatio,
                child: _buildVideoThumbnail(video),
              ),
            ),

            // **FEEDBACK: Show spinner while loading, identical to Vayu player**
            if (controller == null || !controllerUsable)
              Align(
                alignment: Alignment.bottomCenter,
                child: AspectRatio(
                  aspectRatio: video.aspectRatio,
                  child: const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primary,
                      strokeWidth: 2,
                    ),
                  ),
                ),
              ),

            // **SIMPLIFIED: Mount VideoPlayer directly when controller is ready.**

            if (controller != null && controllerUsable)
              Positioned.fill(
                child: _buildVideoPlayer(controller, isActive, index, video),
              ),

            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => _togglePlayPause(index),
                onDoubleTap: () => _handleDoubleTapLike(video),
                onLongPress: () => _showLongPressAd(index),
                child: const SizedBox.expand(),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                // **OPTIMIZED: Use ValueListenableBuilder for granular updates - avoid setState**
                child: ValueListenableBuilder<bool>(
                  valueListenable:
                      _getOrCreateNotifier<bool>(_userPausedVN, videoId, false),
                  builder: (context, isUserPaused, _) {
                    return Opacity(
                      opacity: isUserPaused ? 1.0 : 0.0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.backgroundSecondary
                                .withValues(alpha: 0.7),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: AppColors.white.withValues(alpha: 0.5),
                                width: 2),
                          ),
                          child: const Icon(
                            Icons.play_arrow,
                            color: AppColors.white,
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
                  valueListenable: _getOrCreateNotifier<bool>(
                      _isBufferingVN, videoId, false),
                  builder: (context, isBuffering, _) {
                    // **OPTIMIZED: Listen to userPausedVN too for correct visibility**
                    return ValueListenableBuilder<bool>(
                        valueListenable: _getOrCreateNotifier<bool>(
                            _userPausedVN, videoId, false),
                        builder: (context, isUserPaused, _) {
                          final show = isBuffering && !isUserPaused;
                          return Opacity(
                            opacity: show ? 1.0 : 0.0,
                            child: Stack(
                              children: [
                                const Center(
                                  child: CircularProgressIndicator(
                                      color: AppColors.primary,
                                      strokeWidth: 2),
                                ),
                                // **NEW: Slow Internet message**
                                ValueListenableBuilder<bool>(
                                  valueListenable: _getOrCreateNotifier<bool>(
                                      _isSlowConnectionVN, videoId, false),
                                  builder: (context, isSlow, _) {
                                    if (!isSlow) return const SizedBox.shrink();
                                    return Positioned(
                                      top: 100,
                                      left: 0,
                                      right: 0,
                                      child: Center(
                                        child: GestureDetector(
                                          onTap: () {
                                            // **MANUAL RELOAD: User requested immediate fix**
                                            AppLogger.log(
                                                '🔄 User manually reloaded video $videoId');
                                            // Reset states
                                            _isSlowConnectionVN[videoId]
                                                ?.value = false;
                                            _isBufferingVN[videoId]?.value =
                                                false;
                                            _videoErrors.remove(videoId);
                                            // Trigger reload
                                            _preloadVideo(index);
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors
                                                  .backgroundSecondary
                                                  .withValues(alpha: 0.8),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      AppRadius.xl),
                                              border: Border.all(
                                                  color: AppColors.white
                                                      .withValues(alpha: 0.1)),
                                            ),
                                            child: index < _videos.length
                                                ? Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      const Icon(
                                                        Icons.refresh_rounded,
                                                        color: AppColors.white,
                                                        size: 18,
                                                      ),
                                                      AppSpacing.hSpace8,
                                                      Text(
                                                        'Trouble playing? Tap to Reload',
                                                        style: TextStyle(
                                                          color: AppColors.white
                                                              .withValues(
                                                                  alpha: 0.9),
                                                          fontSize:
                                                              AppTypography
                                                                  .fontSizeSM,
                                                          fontWeight:
                                                              AppTypography
                                                                  .weightSemiBold,
                                                        ),
                                                      ),
                                                    ],
                                                  )
                                                : const SizedBox.shrink(),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          );
                        });
                  },
                ),
              ),
            ),
            _buildVideoOverlay(video, index, controller),
            if (controller != null &&
                isActive &&
                (() {
                  try {
                    return controller?.value.isInitialized ?? false;
                  } catch (_) {
                    return false;
                  }
                }()))
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildVideoProgressBar(controller),
              ),
            if (_showHeartAnimation[videoId]?.value == true)
              _buildHeartAnimation(index),
            _buildTopGradientOverlay(),
            ValueListenableBuilder<List<Map<String, dynamic>>>(
              valueListenable: _bannerAdsVN,
              builder: (context, bannerAds, _) {
                return Positioned(
                  top: MediaQuery.of(context).padding.top + 4,
                  left: 8,
                  child: _buildBannerAd(video, index),
                );
              },
            ),
            // **Long-press carousel ad preview overlay**
            ValueListenableBuilder<bool>(
              valueListenable: _showLongPressAdOverlayVN,
              builder: (context, showOverlay, _) {
                if (!showOverlay || index != _currentIndex) {
                  return const SizedBox.shrink();
                }
                return _buildLongPressAdOverlay(index);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopGradientOverlay() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: 200, // Top 20-25% approximately
      child: RepaintBoundary(
        child: IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.backgroundPrimary.withValues(alpha: 0.4),
                  Colors.transparent,
                ],
              ),
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
    return RepaintBoundary(
      child: AnimatedOpacity(
        opacity: 0.8,
        duration: const Duration(milliseconds: 300),
        child: GestureDetector(
          onTap: () => _openReportDialog(videoId),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.backgroundSecondary.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                  color: AppColors.white.withValues(alpha: 0.1), width: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Report',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: AppTypography.fontSizeSM,
                    fontWeight: AppTypography.weightSemiBold,
                  ),
                ),
                AppSpacing.hSpace4,
                const Icon(Icons.arrow_forward_ios,
                    color: AppColors.white, size: 10),
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
      // **ROAS IMPROVEMENT: Contextual Ad Matching**
      // Attempt to match ad keywords with video title/description
      Map<String, dynamic>? matchedAd;

      try {
        final videoTitle = video.videoName.toLowerCase();
        final videoDesc = (video.description ?? '').toLowerCase();

        // 1. Search for matching ad
        for (final ad in _bannerAds) {
          final keywords = ad['targetKeywords'];
          if (keywords != null) {
            final List<String> targetWords = (keywords is List)
                ? keywords.map((e) => e.toString().toLowerCase()).toList()
                : keywords
                    .toString()
                    .split(',')
                    .map((e) => e.trim().toLowerCase())
                    .toList();

            for (final word in targetWords) {
              if (word.isNotEmpty &&
                  (videoTitle.contains(word) || videoDesc.contains(word))) {
                matchedAd = ad;
                break;
              }
            }
          }
          if (matchedAd != null) break;
        }
      } catch (e) {
        // AppLogger.log('⚠️ Error in contextual ad matching: $e');
      }

      // 2. Fallback to Round-Robin if no match found
      if (matchedAd == null) {
        final adIndex = index % _bannerAds.length;
        if (adIndex < _bannerAds.length) {
          matchedAd = _bannerAds[adIndex];
        }
      }

      // 3. Lock the selected ad for consistency
      if (matchedAd != null) {
        adData = matchedAd;
        _lockedBannerAdByVideoId[video.id] = adData;
      }
    } else if (_adsLoaded && _bannerAds.isEmpty) {
      // **FIX: If ads are confirmed loaded but empty, hide the section entirely**
      // This avoids showing a "Sponsored" placeholder when no ads exist.
      return const SizedBox.shrink();
    }

    // Prepare ad data map with videoId if available
    Map<String, dynamic>? adDataWithVideoId;
    if (adData != null) {
      adDataWithVideoId = {
        ...adData,
        'videoId': video.id,
        'creatorId': video.uploader.id, // **NEW: Pass creatorId for checking**
      };
    }

    // **FIXED: Always pass custom ad data to BannerAdSection for fallback**
    // BannerAdSection will try AdMob first, then fallback to custom ads
    return BannerAdSection(
      adData: adDataWithVideoId, // **FIXED: Pass custom ad data for fallback**
      onVideoPause: () {
        // Pause the currently playing video while the browser is open
        final videoId = index < _videos.length ? _videos[index].id : null;
        if (videoId != null && _controllerPool.containsKey(videoId)) {
          _controllerPool[videoId]!.pause();
        }
      },
      onVideoResume: () {
        // Resume the video when the browser is closed (if still active)
        final videoId = index < _videos.length ? _videos[index].id : null;
        if (videoId != null && _controllerPool.containsKey(videoId)) {
          if (!_shouldAutoplayForContext('ad resume')) return;
          _controllerPool[videoId]!.play();
        }
      },
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
            // **NEW: Check if viewer is the creator**
            if (userData['id'] == video.uploader.id) {
              AppLogger.log('🚫 UI: Self-impression prevented (video owner)');
              return;
            }

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
    );
  }

  Widget _buildVideoProgressBar(VideoPlayerController controller) {
    // **CRASH-PROOF: Check disposal before passing to progress bar**
    if (SharedVideoControllerPool().isControllerDisposed(controller)) {
      return const SizedBox.shrink();
    }

    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final screenWidth = constraints.maxWidth;
          return ThrottledProgressBar(
            key: ValueKey('progress_${controller.hashCode}'),
            controller: controller,
            screenWidth: screenWidth,
            onSeek: (details) => _seekToPosition(controller, details),
          );
        },
      ),
    );
  }

  Widget _buildVideoPlayer(
    VideoPlayerController controller,
    bool isActive,
    int index,
    VideoModel video,
  ) {
    // **CRASH-PROOF: Final check before building the player widget**
    final sharedPool = SharedVideoControllerPool();
    if (sharedPool.isControllerDisposed(controller)) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
          strokeWidth: 2,
        ),
      );
    }

    try {
      if (!controller.value.isInitialized) {
        return const Center(
          child: CircularProgressIndicator(
          color: AppColors.primary,
          strokeWidth: 2,
        ),
        );
      }
    } catch (_) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
          strokeWidth: 2,
        ),
      );
    }

    final String langCode = _selectedAudioLanguage[video.id] ?? 'default';
    
    return RepaintBoundary(
      key: ValueKey('player_${video.id}_${langCode}_${controller.hashCode}'),
      child: Center(
        child: Hero(
          tag: 'video_player_${video.id}_$langCode',
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

    // **CRASH-PROOF: Final check before VideoPlayer widget hits the tree**
    if (SharedVideoControllerPool().isControllerDisposed(controller)) {
      return const SizedBox.shrink();
    }

    return Align(
      alignment: Alignment.bottomCenter,
      child: AspectRatio(
        aspectRatio: modelAspectRatio,
        child: VideoPlayer(controller),
      ),
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

    // **CRASH-PROOF: Final check before VideoPlayer widget hits the tree**
    if (SharedVideoControllerPool().isControllerDisposed(controller)) {
      return const SizedBox.shrink();
    }

    return Align(
      alignment:
          Alignment.center, // **FIX: Center horizontal videos vertically**
      child: AspectRatio(
        aspectRatio: modelAspectRatio,
        child: VideoPlayer(controller),
      ),
    );
  }

  /// **WEB FIX: Build video player widget with explicit sizing for web compatibility**

  // Debug logic removed for release build
  // void _debugAspectRatio(VideoPlayerController controller) { ... }

  Widget _buildVideoThumbnail(VideoModel video) {
    if (video.thumbnailUrl.isEmpty) {
      return Container(color: AppColors.backgroundPrimary);
    }

    return CachedNetworkImage(
      imageUrl: video.thumbnailUrl,
      fit: BoxFit.cover,
      fadeInDuration: Duration.zero, // **ZERO-BLINK: Remove fade-in delay**
      fadeOutDuration: Duration.zero,
      placeholder: (context, url) => Container(color: AppColors.backgroundPrimary),
      errorWidget: (context, url, error) => Container(
        color: AppColors.backgroundPrimary,
        child: const Icon(
          Icons.video_camera_back_outlined,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildVideoOverlay(
      VideoModel video, int index, VideoPlayerController? controller) {
    // **REELS/SHORTS STYLE: Position at absolute bottom with zero spacing**
    return Builder(
      builder: (context) {
        final mediaQuery = MediaQuery.of(context);
        // **ENHANCED: Standardized bottom padding**
        // Ensure UI stays at a safe distance from the bottom edge.
        final double systemBottomPadding = mediaQuery.padding.bottom;
        final double bottomPadding = systemBottomPadding > 14
            ? systemBottomPadding + 5 // Reduced from 15
            : 14.0; // Reduced from 30

        Widget overlayContent = RepaintBoundary(
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
                          AppColors.backgroundPrimary.withValues(alpha: 0.55),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                // **FIX: Adjust bottom padding if Visit Now button is present (approx 55px height)**
                bottom: (video.link?.isNotEmpty == true)
                    ? bottomPadding + 65
                    : bottomPadding,
                left: 0,
                // **FIX: Reserve dynamic space for right-side action column**
                // Prevents "Right overflowed by X pixels" on some devices.
                right: _secondaryActionHitTargetSize + 40,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(
                      12, 8, 12, 4), // **FIX: Tighter bottom padding**
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
                                  color: AppColors.textSecondary,
                                ),
                                child: video.uploader.profilePic.isNotEmpty
                                    ? ClipOval(
                                        child: CachedNetworkImage(
                                          imageUrl: video.uploader.profilePic,
                                          fit: BoxFit.cover,
                                          placeholder: (context, url) =>
                                              Container(
                                            color: AppColors.borderPrimary,
                                            child: Center(
                                              child: Text(
                                                video.uploader.name.isNotEmpty
                                                    ? video.uploader.name[0]
                                                        .toUpperCase()
                                                    : 'U',
                                                style: TextStyle(
                                                  color: AppColors.white,
                                                  fontWeight:
                                                      AppTypography.weightBold,
                                                  fontSize:
                                                      AppTypography.fontSizeXS,
                                                ),
                                              ),
                                            ),
                                          ),
                                          errorWidget: (context, url, error) =>
                                              Container(
                                            color: AppColors.borderPrimary,
                                            child: Center(
                                              child: Text(
                                                video.uploader.name.isNotEmpty
                                                    ? video.uploader.name[0]
                                                        .toUpperCase()
                                                    : 'U',
                                                style: TextStyle(
                                                  color: AppColors.white,
                                                  fontWeight:
                                                      AppTypography.weightBold,
                                                  fontSize:
                                                      AppTypography.fontSizeXS,
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
                                          style: TextStyle(
                                            color: AppColors.white,
                                            fontWeight:
                                                AppTypography.weightBold,
                                            fontSize: AppTypography.fontSizeXS,
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                            AppSpacing.hSpace4 /* closest */,
                            Flexible(
                              fit: FlexFit.tight,
                              child: GestureDetector(
                                onTap: () => _navigateToCreatorProfile(video),
                                child: Text(
                                  video.uploader.name,
                                  style: TextStyle(
                                    color: AppColors.white,
                                    fontSize: AppTypography
                                        .fontSizeBase, // Increased from 12
                                    fontWeight:
                                        AppTypography.weightSemiBold, // Bold
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            AppSpacing.hSpace4 /* closest */,
                            Consumer(
                              builder: (context, ref, _) {
                                final bool isFollowing = ref.watch(userProvider)
                                    .isFollowingUser(video.uploader.id);
                                return ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 110),
                                  child: GestureDetector(
                                    onTap: () => _handleFollow(video),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: isFollowing
                                            ? AppColors.backgroundTertiary
                                            : AppColors.backgroundSecondary
                                                .withValues(alpha: 0.7),
                                        borderRadius: BorderRadius.circular(
                                            AppRadius.pill),
                                      ),
                                      child: Text(
                                        isFollowing ? 'Subscribed' : 'Subscribe',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: AppColors.white,
                                          fontSize: AppTypography.fontSizeSM,
                                          fontWeight: AppTypography.weightBold,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _showVideoDetailsBottomSheet(context, video),
                        child: Text(
                          video.videoName,
                          style: TextStyle(
                            color: AppColors.white,
                            fontSize:
                                AppTypography.fontSizeSM, // Slightly increased
                            fontWeight: AppTypography.weightRegular, // Lighter
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      AppSpacing.vSpace4,
                      // Visit Now moved to Positioned stack for visibility control
                    ],
                  ),
                ),
              ),
              Positioned(
                right: 12,
                bottom:
                    bottomPadding, // Only SafeArea padding, no extra spacing
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildReportIndicator(index),
                    AppSpacing.vSpace16,
                    _buildLikeButton(video, index),
                    AppSpacing.vSpace12,
                    _buildAudioDubbingButton(video, index),
                    AppSpacing.vSpace12,
                    _buildVerticalActionButton(
                      icon: Icons.share,
                      onTap: () => _handleShare(video),
                    ),
                    AppSpacing.vSpace12,
                    if (video.episodes != null && video.episodes!.isNotEmpty)
                      _buildVerticalActionButton(
                        icon: Icons.playlist_play_rounded,
                        onTap: () => _showEpisodeList(context, video),
                        labelOverride: 'Episode',
                        isPrimary: true, // **Match Like button size**
                      ),
                  ],
                ),
              ),
            ],
          ),
        );

        // **VISIT NOW PROTECTION: Always show button if it exists, even if overlay hides**
        final visitNowButton = (video.link?.isNotEmpty == true)
            ? Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  bottom: bottomPadding + 16,
                ),
                child: SizedBox(
                  width: (_screenWidth ?? MediaQuery.of(context).size.width) * 0.75,
                  child: AppButton(
                    label: 'Visit Now',
                    onPressed: () => _handleVisitNow(video),
                    icon: const Icon(Icons.open_in_new, size: 14, color: AppColors.white),
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.small,
                  ),
                ),
              )
            : const SizedBox.shrink();

        final bool isYugTab = widget.videoType == 'yog';
        if (!isYugTab || controller == null) {
          return Stack(
            children: [
              overlayContent,
              Positioned(left: 0, bottom: 0, child: visitNowButton),
            ],
          );
        }

        // Get or create the force-show notifier for this video
        final forceShowNotifier = _forceShowOverlayVN[video.id] ??= ValueNotifier<bool>(false);

        // **CRASH-PROOF: Don't listen to disposed controllers. If disposed, trigger a re-fetch.**
        if (SharedVideoControllerPool().isControllerDisposed(controller)) {
          // Trigger a re-fetch for the next frame
          Future.microtask(() {
            if (mounted) {
              _getController(index);
              safeSetState(() {});
            }
          });
          return overlayContent;
        }

        return Stack(
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: forceShowNotifier,
              builder: (context, forceShow, _) {
                // **CRASH-PROOF: Defensive check inside the inner builder**
                // Even if it was alive 1ms ago, check again before building the next layer.
                if (SharedVideoControllerPool().isControllerDisposed(controller)) {
                  // Trigger re-fetch and return fallback
                  Future.microtask(() {
                    if (mounted) {
                      _getController(index);
                      safeSetState(() {});
                    }
                  });
                  return overlayContent;
                }

                return ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: controller,
                  builder: (context, value, child) {
                    bool isPlaying = false;
                    try {
                      isPlaying = value.isPlaying;
                    } catch (_) {
                      // **SAFETY VALVE**: If value access fails here, it means it was disposed mid-build.
                      // We silently return the content and trigger a recovery link.
                      return child!;
                    }
                    // Show overlay if force-showing (double-tap like) OR if paused
                    final bool shouldShow = forceShow || !isPlaying;
                    return AnimatedOpacity(
                      opacity: shouldShow ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      child: IgnorePointer(
                        ignoring: !shouldShow,
                        child: child,
                      ),
                    );
                  },
                  child: overlayContent,
                );
              },
            ),
            // **Visit Now button remains visible outside AnimatedOpacity**
            Positioned(left: 0, bottom: 0, child: visitNowButton),
          ],
        );
      },
    );
  }

  ValueNotifier<bool> _getLikeNotifier(VideoModel video) {
    return _getOrCreateNotifier<bool>(_isLikedVN, video.id, video.isLiked);
  }

  ValueNotifier<int> _getLikeCountNotifier(VideoModel video) {
    return _getOrCreateNotifier<int>(_likeCountVN, video.id, video.likes);
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
                SizedBox(
                  width: _primaryActionHitTargetSize,
                  height: _primaryActionHitTargetSize,
                  child: LikeButton(
                    padding: EdgeInsets.zero,
                    size: _primaryActionHitTargetSize,
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
                      return Center(
                        child: Container(
                          width: AppConstants.primaryActionButtonContainerSize,
                          height: AppConstants.primaryActionButtonContainerSize,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.backgroundSecondary
                                .withValues(alpha: 0.7),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.shadowSecondary
                                    .withValues(alpha: 0.2),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            isLiked ? Icons.favorite : Icons.favorite_border,
                            color: isLiked ? AppColors.error : AppColors.white,
                            size: AppConstants.primaryActionButtonSize,
                            shadows: const [
                              Shadow(
                                color: AppColors.overlayMedium,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    onTap: (bool isLiked) async {
                      await _handleLike(video);
                      return !isLiked;
                    },
                  ),
                ),
                AppSpacing.vSpace4,
                Text(
                  _formatCount(likeCount),
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: AppTypography.fontSizeSM,
                    fontWeight: AppTypography.weightMedium,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildAudioDubbingButton(VideoModel video, int index) {
    final videoId = video.id;
    final resultVN = _getOrCreateNotifier<DubbingResult>(
      _dubbingResultsVN,
      videoId,
      const DubbingResult(status: DubbingStatus.idle),
    );

    return ValueListenableBuilder<DubbingResult>(
      valueListenable: resultVN,
      builder: (context, result, _) {
        final bool isDubbed = result.isDone && result.dubbedUrl != null;
        final bool isProcessing = result.status != DubbingStatus.idle && !result.isDone;

        IconData icon = Icons.multitrack_audio_rounded;
        Color iconColor = AppColors.white;
        String label = AppConstants.audioButtonLabel;

        if (isProcessing) {
          icon = Icons.hourglass_empty_rounded;
          iconColor = AppColors.primary;
          label = '${result.progress}%';
        } else if (isDubbed) {
          icon = Icons.volume_up_rounded;
          iconColor = AppColors.primary;
        }

        return _buildVerticalActionButton(
          icon: icon,
          onTap: () => _onAudioDubTap(video),
          color: iconColor,
          labelOverride: label,
        );
      },
    );
  }

  Widget _buildVerticalActionButton({
    required IconData icon,
    required VoidCallback onTap,
    Color color = AppColors.white,
    int? count,
    String? labelOverride,
    bool isPrimary = false,
  }) {
    final containerSize = isPrimary
        ? AppConstants.primaryActionButtonContainerSize
        : AppConstants.secondaryActionButtonContainerSize;
    final iconSize = isPrimary
        ? AppConstants.primaryActionButtonSize
        : AppConstants.secondaryActionButtonSize;
    final hitTargetSize = isPrimary
        ? _primaryActionHitTargetSize
        : _secondaryActionHitTargetSize;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: hitTargetSize,
            height: hitTargetSize,
            child: Center(
              child: Container(
                width: containerSize,
                height: containerSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.backgroundSecondary.withValues(alpha: 0.7),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.shadowSecondary.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: iconSize,
                  shadows: const [
                    Shadow(
                      color: AppColors.overlayDark,
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (count != null || labelOverride != null) ...[
            AppSpacing.vSpace4,
            Text(
              labelOverride ?? _formatCount(count!),
              style: TextStyle(
                color: AppColors.white,
                fontSize: AppTypography.fontSizeXS,
                fontWeight: AppTypography.weightSemiBold,
                shadows: const [
                  Shadow(
                    offset: Offset(0, 1),
                    blurRadius: 2,
                    color: AppColors.overlayDark,
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
    final carouselAd = _carouselAdManager.getCarouselAdForIndex(videoIndex);
    if (carouselAd == null) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: AppColors.backgroundPrimary,
        child: const Center(
          child: Text(
            'No carousel ads available',
            style: TextStyle(color: AppColors.white),
          ),
        ),
      );
    }

    String? videoId;
    if (videoIndex < _videos.length) {
      videoId = _videos[videoIndex].id;
    }

    return CarouselAdWidget(
      carouselAd: carouselAd,
      videoId: videoId,
      onVideoPause: () {
        // Pause the currently playing video while the browser is open
        if (videoId != null && _controllerPool.containsKey(videoId)) {
          _controllerPool[videoId]!.pause();
        }
      },
      onVideoResume: () {
        // Resume the video when the browser is closed (if still active)
        if (videoId != null && _controllerPool.containsKey(videoId)) {
          if (!_shouldAutoplayForContext('carousel ad resume')) return;
          _controllerPool[videoId]!.play();
        }
      },
      onAdClosed: () {
        if (videoId != null && _currentHorizontalPage.containsKey(videoId)) {
          _currentHorizontalPage[videoId]!.value = 0;
        }
      },
      autoPlay: true,
    );
  }

  /// **LONG-PRESS AD OVERLAY: Show carousel ad image on long press**
  void _showLongPressAd(int index) {
    final carouselAd = _carouselAdManager.getCarouselAdForIndex(index);
    if (carouselAd == null || carouselAd.slides.isEmpty) return;

    _showLongPressAdOverlayVN.value = true;

    // Auto-hide after 3 seconds
    _longPressAdAutoHideTimer?.cancel();
    _longPressAdAutoHideTimer = Timer(const Duration(seconds: 3), () {
      _hideLongPressAdOverlay();
    });
  }

  void _hideLongPressAdOverlay() {
    _showLongPressAdOverlayVN.value = false;
    _longPressAdAutoHideTimer?.cancel();
    _longPressAdAutoHideTimer = null;
  }

  Widget _buildLongPressAdOverlay(int index) {
    final carouselAd = _carouselAdManager.getCarouselAdForIndex(index);
    if (carouselAd == null || carouselAd.slides.isEmpty) {
      return const SizedBox.shrink();
    }

    final slide = carouselAd.slides.first;
    final imageUrl = slide.thumbnailUrl ?? slide.mediaUrl;

    return Positioned.fill(
      child: Stack(
        children: [
          // Transparent background - dismiss on tap outside
          Positioned.fill(
            child: GestureDetector(
              onTap: () => _hideLongPressAdOverlay(),
              child: Container(color: Colors.transparent),
            ),
          ),
          // Circular ad image - slightly left, vertically centered, with popup animation
          Positioned(
            left: 40,
            top: 0,
            bottom: 0,
            child: Align(
              alignment: Alignment.centerLeft,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 350),
                curve: Curves.elasticOut,
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: Opacity(
                      opacity: value.clamp(0.0, 1.0),
                      child: child,
                    ),
                  );
                },
                child: GestureDetector(
                  onTap: () {
                    _hideLongPressAdOverlay();

                    // Prioritize external navigation if URL is available
                    if (carouselAd.callToActionUrl.isNotEmpty) {
                      AppLogger.log(
                          '🔗 LongPressOverlay: Launching URL: ${carouselAd.callToActionUrl}');
                      _launchExternalUrl(carouselAd.callToActionUrl);
                      return;
                    }

                    // Fallback: Transition to carousel ad page (Existing logic)
                    if (_videos.isNotEmpty && index < _videos.length) {
                      final videoId = _videos[index].id;
                      AppLogger.log(
                          '🖱️ LongPressOverlay: Tapped for video $videoId (Fallback to feed)');

                      if (_carouselAdManager.getTotalCarouselAds() > 0) {
                        if (_currentHorizontalPage.containsKey(videoId)) {
                          _currentHorizontalPage[videoId]!.value = 1;
                        }
                      }
                    }
                  },
                  child: Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.backgroundPrimary
                              .withValues(alpha: 0.5),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image.network(
                        imageUrl,
                        width: 70,
                        height: 70,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: AppColors.borderPrimary,
                            child: const Icon(Icons.ad_units,
                                color: AppColors.white, size: 30),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// **OFFLINE INDICATOR: Shows when device has no internet connection**
  Widget _buildOfflineIndicator() {
    return ValueListenableBuilder<bool>(
      valueListenable: _showOfflineBannerVN,
      builder: (context, show, _) {
        if (!show) {
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.wifi_off,
                    color: AppColors.white,
                    size: 20,
                  ),
                  AppSpacing.hSpace8,
                  Text(
                    'No internet connection',
                    style: TextStyle(
                      color: AppColors.white,
                      fontSize: AppTypography.fontSizeBase,
                      fontWeight: AppTypography.weightSemiBold,
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
    if (video.episodes == null || video.episodes!.isEmpty) return;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.backgroundPrimary,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
          padding: EdgeInsets.symmetric(vertical: AppSpacing.spacing4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.spacing4, vertical: AppSpacing.spacing2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Episodes', style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.bold, color: AppColors.white)),
                    IconButton(icon: const Icon(Icons.close_rounded, color: AppColors.white), onPressed: () => Navigator.pop(context)),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.divider),
              AppSpacing.vSpace8,
              Flexible(
                child: _buildShortsEpisodeGrid(video),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildShortsEpisodeGrid(VideoModel video) {
    return GridView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.spacing4),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: AppSpacing.spacing3,
        mainAxisSpacing: AppSpacing.spacing3,
        childAspectRatio: 9 / 16,
      ),
      itemCount: video.episodes!.length,
      itemBuilder: (context, index) {
        final ep = video.episodes![index];
        final isCurrent = ep['id'] == video.id || ep['_id'] == video.id;
        
        return GestureDetector(
          onTap: () {
            Navigator.pop(context);
            if (!isCurrent) {
               final epId = ep['id'] ?? ep['_id'];
               if (epId != null) {
                 final targetIndex = _videos.indexWhere((v) => v.id == epId);
                 if (targetIndex != -1) {
                   _pageController.animateToPage(
                     targetIndex,
                     duration: const Duration(milliseconds: 300),
                     curve: Curves.easeInOut,
                   );
                 } else {
                   // Optional: If not in feed, we could potentiall fetch and insert it
                   // or just show a snackbar. Since it's a feed, jump-if-present is safest.
                   _showSnackBar('Episode is not in current feed. Scrolling to find it...');
                 }
               }
            }
          },
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: AppColors.backgroundSecondary,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (ep['thumbnailUrl'] != null)
                  CachedNetworkImage(imageUrl: ep['thumbnailUrl'], fit: BoxFit.cover),
                
                // Blur Overlay with numbers
                Positioned.fill(
                  child: ClipRRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 1, sigmaY: 1),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.3),
                        alignment: Alignment.center,
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 48, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                ),
                
                // Active Border
                if (isCurrent)
                  Container(decoration: BoxDecoration(border: Border.all(color: AppColors.primary, width: 2), borderRadius: BorderRadius.circular(12))),

                // Title at bottom
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Container(
                    padding: EdgeInsets.all(AppSpacing.spacing2),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent]),
                    ),
                    child: Text(ep['videoName'] ?? 'Ep ${index + 1}', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTypography.bodySmall.copyWith(color: AppColors.white, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
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
    VayuBottomSheet.show(
      context: context,
      title: 'Video Details',
      actions: [
        if (_currentUserId != null &&
            (video.uploader.googleId == _currentUserId ||
                video.uploader.id == _currentUserId))
          SizedBox(
            width: 80,
            child: AppButton(
              size: AppButtonSize.small,
              variant: AppButtonVariant.secondary,
              onPressed: () async {
                Navigator.of(context).pop();
                final result = await Navigator.of(context).push<Map<String, dynamic>>(
                  MaterialPageRoute(
                    builder: (context) => EditVideoDetails(video: video),
                  ),
                );

                if (result != null) {
                  safeSetState(() {
                    final index = _videos.indexWhere((v) => v.id == video.id);
                    if (index != -1) {
                      _videos[index] = _videos[index].copyWith(
                        videoName: result['videoName'],
                        link: result['link'],
                        tags: result['tags'],
                        seriesId: result['seriesId'],
                        episodes: result['episodes'] != null 
                          ? List<Map<String, dynamic>>.from(result['episodes']) 
                          : null,
                      );
                    }
                  });
                }
              },
              icon: const Icon(Icons.edit_outlined, size: 14),
              label: 'Edit',
            ),
          ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (video.tags != null && video.tags!.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: video.tags!.map((tag) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: Text(
                  '#$tag',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: AppTypography.fontSizeXS,
                    fontWeight: AppTypography.weightMedium,
                  ),
                ),
              )).toList(),
            ),
            AppSpacing.vSpace16,
            const Divider(),
            AppSpacing.vSpace16,
          ],
          Row(
            children: [
              const Icon(Icons.calendar_today,
                  size: 20, color: AppColors.textSecondary),
              AppSpacing.hSpace12,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Published on',
                    style: TextStyle(
                      fontSize: AppTypography.fontSizeSM,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    _formatUploadDate(video.uploadedAt),
                    style: TextStyle(
                      fontSize: AppTypography.fontSizeLG,
                      fontWeight: AppTypography.weightMedium,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          AppSpacing.vSpace16,
          const Divider(),
          AppSpacing.vSpace16,
          Row(
            children: [
              const Icon(Icons.remove_red_eye_outlined,
                  size: 20, color: AppColors.textSecondary),
              AppSpacing.hSpace12,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Views',
                    style: TextStyle(
                      fontSize: AppTypography.fontSizeSM,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    '${_formatCount(video.views)} views',
                    style: TextStyle(
                      fontSize: AppTypography.fontSizeLG,
                      fontWeight: AppTypography.weightMedium,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          AppSpacing.vSpace16,
        ],
      ),
    );
  }
}

