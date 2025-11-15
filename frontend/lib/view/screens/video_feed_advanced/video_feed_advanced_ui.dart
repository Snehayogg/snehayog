part of 'package:vayu/view/screens/video_feed_advanced.dart';

extension _VideoFeedUI on _VideoFeedAdvancedState {
  Widget _buildVideoFeed() {
    return RefreshIndicator(
      onRefresh: refreshVideos,
      child: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        physics: const ClampingScrollPhysics(),
        onPageChanged: _onPageChanged,
        allowImplicitScrolling: false,
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
        ],
      ),
    );
  }

  int _getTotalItemCount() {
    return _videos.length + (_isLoadingMore ? 1 : 0);
  }

  Widget _buildFeedItem(int index) {
    final totalVideos = _videos.length;
    final videoIndex = index;

    if (videoIndex >= totalVideos) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.video_library_outlined,
                size: 64,
                color: Colors.white54,
              ),
              SizedBox(height: 16),
              Text(
                'No more videos',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'You\'ve reached the end!',
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ],
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
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(child: _buildVideoThumbnail(video)),
          if (controller != null && controller.value.isInitialized)
            ValueListenableBuilder<bool>(
              valueListenable:
                  _firstFrameReady[index] ?? ValueNotifier<bool>(false),
              builder: (context, firstFrameReady, _) {
                if (firstFrameReady ||
                    _forceMountPlayer[index]?.value == true) {
                  return Positioned.fill(
                    child: _buildVideoPlayer(controller, isActive, index),
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
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
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
    if (_showHeartAnimation[index] == null) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<bool>(
      valueListenable: _showHeartAnimation[index]!,
      builder: (context, showAnimation, _) {
        if (!showAnimation) return const SizedBox.shrink();
        return Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: AnimatedOpacity(
                opacity: showAnimation ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: AnimatedScale(
                  scale: showAnimation ? 1.2 : 0.8,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                    child:
                        const Icon(Icons.favorite, color: Colors.red, size: 48),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
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
    Map<String, dynamic>? adData;

    if (_adsLoaded) {
      AppLogger.log(
        '🔍 _buildBannerAd: Video index=$index, Total banner ads=${_bannerAds.length}, Locked ads=${_lockedBannerAdByVideoId.length}',
      );
    }

    if (_lockedBannerAdByVideoId.containsKey(video.id)) {
      adData = _lockedBannerAdByVideoId[video.id];
      if (adData != null) {
        AppLogger.log(
          '🔒 Using locked ad for video ${video.videoName} (index $index): ${adData['title']} (ID: ${adData['id']})',
        );
      }
    } else if (_adsLoaded && _bannerAds.isNotEmpty) {
      final adIndex = index % _bannerAds.length;
      if (adIndex < _bannerAds.length) {
        adData = _bannerAds[adIndex];
        AppLogger.log(
          '🔄 Showing banner ad ${adIndex + 1}/${_bannerAds.length} for video ${video.videoName} (index $index): ${adData['title']} (ID: ${adData['id']})',
        );
        _lockedBannerAdByVideoId[video.id] = adData;
      } else {
        AppLogger.log(
          '⚠️ Invalid adIndex $adIndex for bannerAds length ${_bannerAds.length}',
        );
      }
    } else {
      return Positioned(
        top: 0,
        left: 0,
        right: 0,
        height: 60,
        child: Container(color: Colors.black),
      );
    }

    if (adData == null) {
      return Positioned(
        top: 0,
        left: 0,
        right: 0,
        height: 60,
        child: Container(color: Colors.black),
      );
    }

    final adDataNonNull = adData;

    // Use BannerAdSection which supports both Google AdMob and custom ads
    return BannerAdSection(
      adData: {
        ...adDataNonNull,
        'videoId': video.id,
      },
      onClick: () {
        AppLogger.log('🖱️ Banner ad clicked on video $index');
      },
      onImpression: () async {
        if (index < _videos.length) {
          final video = _videos[index];
          final adId = adDataNonNull['_id'] ?? adDataNonNull['id'];
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
      useGoogleAds: true, // Use Google AdMob if configured
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
  ) {
    return RepaintBoundary(
      child: Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        child: Center(child: _buildVideoWithCorrectAspectRatio(controller)),
      ),
    );
  }

  Widget _buildVideoWithCorrectAspectRatio(VideoPlayerController controller) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final screenHeight = constraints.maxHeight;

        final currentVideo = _videos[_currentIndex];
        final double modelAspectRatio = currentVideo.aspectRatio;

        final Size videoSize = controller.value.size;
        final int rotation = controller.value.rotationCorrection;

        AppLogger.log('🎬 MODEL aspect ratio: $modelAspectRatio');
        AppLogger.log(
            '🎬 Video dimensions: ${videoSize.width}x${videoSize.height}');
        AppLogger.log('🎬 Rotation: $rotation degrees');
        AppLogger.log('🎬 Using MODEL aspect ratio instead of detected ratio');

        _debugAspectRatio(controller);

        if (modelAspectRatio < 1.0) {
          return _buildPortraitVideoFromModel(
            controller,
            screenWidth,
            screenHeight,
            modelAspectRatio,
          );
        } else {
          return _buildLandscapeVideoFromModel(
            controller,
            screenWidth,
            screenHeight,
            modelAspectRatio,
          );
        }
      },
    );
  }

  bool _isPortraitVideo(double aspectRatio) {
    const double portraitThreshold = 0.7;
    return aspectRatio < portraitThreshold;
  }

  Widget _buildPortraitVideoFromModel(
    VideoPlayerController controller,
    double screenWidth,
    double screenHeight,
    double modelAspectRatio,
  ) {
    final Size videoSize = controller.value.size;
    final int rotation = controller.value.rotationCorrection;

    double videoWidth = videoSize.width;
    double videoHeight = videoSize.height;

    if (rotation == 90 || rotation == 270) {
      videoWidth = videoSize.height;
      videoHeight = videoSize.width;
    }

    AppLogger.log(
      '🎬 MODEL Portrait video - Original video size: ${videoWidth}x$videoHeight',
    );
    AppLogger.log(
        '🎬 MODEL Portrait video - Model aspect ratio: $modelAspectRatio');
    AppLogger.log(
      '🎬 MODEL Portrait video - Screen size: ${screenWidth}x$screenHeight',
    );

    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: videoWidth,
        height: videoHeight,
        child: VideoPlayer(controller),
      ),
    );
  }

  Widget _buildLandscapeVideoFromModel(
    VideoPlayerController controller,
    double screenWidth,
    double screenHeight,
    double modelAspectRatio,
  ) {
    final Size videoSize = controller.value.size;
    final int rotation = controller.value.rotationCorrection;

    double videoWidth = videoSize.width;
    double videoHeight = videoSize.height;

    if (rotation == 90 || rotation == 270) {
      videoWidth = videoSize.height;
      videoHeight = videoSize.width;
    }

    AppLogger.log(
      '🎬 MODEL Landscape video - Original video size: ${videoWidth}x$videoHeight',
    );
    AppLogger.log(
        '🎬 MODEL Landscape video - Model aspect ratio: $modelAspectRatio');
    AppLogger.log(
      '🎬 MODEL Landscape video - Screen size: ${screenWidth}x$screenHeight',
    );

    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: videoWidth,
        height: videoHeight,
        child: VideoPlayer(controller),
      ),
    );
  }

  void _debugAspectRatio(VideoPlayerController controller) {
    final Size videoSize = controller.value.size;
    final int rotation = controller.value.rotationCorrection;

    double videoWidth = videoSize.width;
    double videoHeight = videoSize.height;

    if (rotation == 90 || rotation == 270) {
      videoWidth = videoSize.height;
      videoHeight = videoSize.width;
    }

    final double aspectRatio = videoWidth / videoHeight;
    final bool isPortrait = aspectRatio < 1.0 || _isPortraitVideo(aspectRatio);

    final currentVideo = _videos[_currentIndex];
    final double modelAspectRatio = currentVideo.aspectRatio;

    AppLogger.log('🔍 ASPECT RATIO DEBUG:');
    AppLogger.log('🔍 MODEL aspect ratio: $modelAspectRatio');
    AppLogger.log('🔍 Raw size: ${videoSize.width}x${videoSize.height}');
    AppLogger.log('🔍 Rotation: $rotation degrees');
    AppLogger.log('🔍 Corrected size: ${videoWidth}x$videoHeight');
    AppLogger.log('🔍 DETECTED aspect ratio: $aspectRatio');
    AppLogger.log('🔍 Is portrait (detected): $isPortrait');
    AppLogger.log('🔍 Expected 9:16 ratio: ${9.0 / 16.0}');
    AppLogger.log(
      '🔍 Difference from 9:16 (detected): ${(aspectRatio - (9.0 / 16.0)).abs()}',
    );
    AppLogger.log(
      '🔍 Difference from 9:16 (model): ${(modelAspectRatio - (9.0 / 16.0)).abs()}',
    );
    AppLogger.log('🔍 Using MODEL aspect ratio for display');
  }

  Widget _buildVideoThumbnail(VideoModel video) {
    final aspectRatio = video.aspectRatio > 0 ? video.aspectRatio : 9 / 16;
    return RepaintBoundary(
      child: Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        child: video.thumbnailUrl.isNotEmpty
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
            : _buildFallbackThumbnail(),
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
    return FutureBuilder<double>(
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
    );
  }

  Widget _buildVideoOverlay(VideoModel video, int index) {
    return RepaintBoundary(
      child: Stack(
        children: [
          Positioned(
            top: 52,
            right: 8,
            child: _buildEarningsLabel(video),
          ),
          Positioned(
            bottom: 8,
            left: 0,
            right: 75,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
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
                                      placeholder: (context, url) => Container(
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
                                          ? video.uploader.name[0].toUpperCase()
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
          Positioned(
            right: 12,
            bottom: 12,
            child: Column(
              children: [
                _buildVerticalActionButton(
                  icon:
                      _isLiked(video) ? Icons.favorite : Icons.favorite_border,
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
}
