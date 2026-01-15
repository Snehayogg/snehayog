import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:vayu/model/carousel_ad_model.dart';
import 'package:vayu/services/carousel_ad_service.dart';
import 'package:vayu/services/ad_impression_service.dart';
import 'package:vayu/services/authservices.dart';
import 'package:vayu/services/video_service.dart';
import 'package:vayu/view/widget/comments_sheet_widget.dart';
import 'package:vayu/services/comments/ad_comments_data_source.dart';
import 'package:vayu/services/ad_comment_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vayu/view/widget/custom_share_widget.dart';
import 'package:vayu/utils/app_logger.dart';
import 'package:vayu/core/constants/app_constants.dart';

/// **Professional Carousel Ad Widget**
class CarouselAdWidget extends StatefulWidget {
  final CarouselAdModel carouselAd;
  final VoidCallback? onAdClosed;
  final bool autoPlay;
  final String?
      videoId; // **NEW: Track which video context this ad was shown in**

  const CarouselAdWidget({
    Key? key,
    required this.carouselAd,
    this.onAdClosed,
    this.autoPlay = true,
    this.videoId, // **NEW: Optional videoId for view tracking**
  }) : super(key: key);

  @override
  State<CarouselAdWidget> createState() => _CarouselAdWidgetState();
}

class _CarouselAdWidgetState extends State<CarouselAdWidget>
    with TickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _progressController;

  int _currentSlideIndex = 0;
  bool _hasTrackedImpression = false;
  bool _hasTrackedClick = false;
  bool _hasTrackedView = false; // **NEW: Prevent duplicate view tracking**
  bool _isLiked = false;
  bool _initiallyLiked = false;
  String? _currentUserId;
  DateTime? _viewStartTime; // **NEW: Track when ad became visible**
  Timer? _viewTrackingTimer; // **NEW: Timer to check view duration**
  bool _isVisible = false; // **NEW: Track if ad is actually visible on screen**

  final CarouselAdService _carouselAdService = CarouselAdService();
  final AdImpressionService _adImpressionService = AdImpressionService();
  final AuthService _authService = AuthService();


  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _progressController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _loadUserData();
    _trackImpression();
    _startProgressAnimation();
    // **FIX: Don't start view tracking in initState - wait for visibility**
    // View tracking will start when ad becomes visible (detected by VisibilityDetector)
  }

  Future<void> _loadUserData() async {
    try {
      final userData = await _authService.getUserData();
      if (userData != null) {
        setState(() {
          // **FIX: Prioritize googleId over id to match backend likedBy array**
          _currentUserId = userData['googleId'] ?? userData['id'];
          _isLiked = _currentUserId != null &&
              widget.carouselAd.likedBy.contains(_currentUserId);
          _initiallyLiked = _isLiked;
        });
      }
    } catch (e) {
      AppLogger.log('❌ Error loading user data: $e');
    }
  }

  @override
  void dispose() {
    _stopViewTracking();
    _pageController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  /// **NEW: Track ad view duration (minimum 2 seconds)**
  /// **FIX: Only start tracking when ad is actually visible**
  void _startViewTracking() {
    if (_hasTrackedView || _isVisible) {
      // Already tracking or already tracked
      return;
    }

    _isVisible = true;
    _viewStartTime = DateTime.now();
    AppLogger.log(
        '✅ CarouselAdWidget: Ad became visible, starting view tracking');

    // Track view after minimum duration (4 seconds for ads)
    _viewTrackingTimer = Timer(AppConstants.adViewCountThreshold, () async {
      if (!_hasTrackedView && mounted && _isVisible) {
        await _trackAdView();
      }
    });
  }

  /// **NEW: Stop view tracking when ad becomes invisible**
  void _stopViewTracking() {
    if (!_isVisible) return;

    _isVisible = false;
    _viewTrackingTimer?.cancel();
    _viewTrackingTimer = null;
    _viewStartTime = null;
    AppLogger.log(
        '⏸️ CarouselAdWidget: Ad became invisible, stopped view tracking');
  }

  /// **NEW: Track carousel ad view (minimum 4 seconds visible)**
  Future<void> _trackAdView() async {
    if (_hasTrackedView || _viewStartTime == null) return;

    // Need videoId to track views properly
    if (widget.videoId == null || widget.videoId!.isEmpty) {
      AppLogger.log(
          '⚠️ CarouselAdWidget: No videoId provided, skipping view tracking');
      return;
    }

    try {
      final viewDuration =
          DateTime.now().difference(_viewStartTime!).inMilliseconds / 1000.0;

      // Minimum view duration for ads (4 seconds)
      final minSeconds = AppConstants.adViewCountThreshold.inSeconds;
      if (viewDuration < minSeconds) {
        AppLogger.log(
            '⚠️ CarouselAdWidget: View duration too short ($viewDuration s), not tracking (min: ${minSeconds}s)');
        return;
      }

      final userData = await _authService.getUserData();
      if (userData == null) {
        AppLogger.log(
            '⚠️ CarouselAdWidget: No user data, skipping view tracking');
        return;
      }

      final videoId = widget.videoId!;
      final adId = widget.carouselAd.id;
      // **FIX: Prioritize googleId over id to match backend likedBy array**
      final userId = userData['googleId'] ?? userData['id'] ?? '';

      if (videoId.isEmpty || adId.isEmpty) {
        AppLogger.log(
            '⚠️ CarouselAdWidget: Missing videoId or adId, skipping view tracking');
        return;
      }

      await _adImpressionService.trackCarouselAdView(
        videoId: videoId,
        adId: adId,
        userId: userId,
        viewDuration: viewDuration,
      );

      _hasTrackedView = true;
      AppLogger.log(
          '✅ CarouselAdWidget: Ad view tracked (${viewDuration.toStringAsFixed(2)}s)');
    } catch (e) {
      AppLogger.log('❌ CarouselAdWidget: Error tracking ad view: $e');
    }
  }

  void _trackImpression() async {
    if (_hasTrackedImpression) return;

    try {
      await _carouselAdService.trackImpression(widget.carouselAd.id);
      _hasTrackedImpression = true;
    } catch (e) {
      AppLogger.log('❌ Error tracking carousel ad impression: $e');
    }
  }

  void _trackClick() async {
    if (_hasTrackedClick) return;

    try {
      await _carouselAdService.trackClick(widget.carouselAd.id);
      _hasTrackedClick = true;
    } catch (e) {
      AppLogger.log('❌ Error tracking carousel ad click: $e');
    }
  }

  void _startProgressAnimation() {
    if (widget.autoPlay && widget.carouselAd.slides.length > 1) {
      _progressController.repeat();
    }
  }

  void _onSlideChanged(int index) {
    setState(() {
      _currentSlideIndex = index;
    });
  }

  void _onAdTap() async {
    _trackClick();

    // Launch CTA URL if available
    final ctaUrl = widget.carouselAd.callToActionUrl;
    if (ctaUrl.isNotEmpty) {
      try {
        final uri = Uri.parse(ctaUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } catch (e) {
        AppLogger.log('❌ Error launching carousel ad URL: $e');
      }
    }

    widget.onAdClosed?.call();
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key('carousel_ad_${widget.carouselAd.id}'),
      onVisibilityChanged: (VisibilityInfo info) {
        // **FIX: Only track views when ad is actually visible (at least 50% visible)**
        final visibleFraction = info.visibleFraction;
        if (visibleFraction >= 0.5 && !_isVisible) {
          // Ad became visible - start tracking
          _startViewTracking();
        } else if (visibleFraction < 0.5 && _isVisible) {
          // Ad became invisible - stop tracking
          _stopViewTracking();
        }
      },
      child: RepaintBoundary(
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.black,
            child: Stack(
              children: [
                // **Sponsored Text at Top Corner**
                _buildSponsoredText(),

                // **Main Content Area - Dynamic Ad Section**
                Positioned.fill(
                  child: _buildMainContentArea(),
                ),

                // **Progress Indicators** (for multiple slides)
                if (widget.carouselAd.slides.length > 1)
                  _buildCarouselCounter(),

                // **Right-Side Vertical Action Bar**
                _buildRightActionBar(),

                // **Bottom Ad Metadata Section**
                _buildBottomAdMetadata(),

                // **Back Button** (bottom corner
                Positioned(
                  right: 16,
                  bottom: 20, // Aligned with action buttons
                  child: _buildBackButton(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCarouselContent() {
    if (widget.carouselAd.slides.isEmpty) {
      return _buildFallbackContent();
    }

    return PageView.builder(
      controller: _pageController,
      onPageChanged: _onSlideChanged,
      itemCount: widget.carouselAd.slides.length,
      // Enable smooth swipe transitions
      physics: const BouncingScrollPhysics(),
      itemBuilder: (context, index) {
        final slide = widget.carouselAd.slides[index];
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: _buildSlideContent(slide),
        );
      },
    );
  }

  Widget _buildSlideContent(CarouselSlide slide) {
    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: slide.mediaType == 'video'
          ? _buildVideoContent(slide)
          : _buildImageContent(slide),
    );
  }

  Widget _buildImageContent(CarouselSlide slide) {
    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: CachedNetworkImage(
        imageUrl: slide.mediaUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        placeholder: (context, url) => _buildLoadingPlaceholder(),
        errorWidget: (context, url, error) => _buildErrorPlaceholder(),
      ),
    );
  }

  Widget _buildVideoContent(CarouselSlide slide) {
    // For now, show image placeholder for videos
    // TODO: Implement video player for carousel videos
    return Container(
      color: Colors.grey[900],
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.play_circle_outline,
              color: Colors.white,
              size: 80,
            ),
            SizedBox(height: 16),
            Text(
              'Video Ad',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackContent() {
    return Container(
      color: Colors.grey[900],
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.campaign,
              color: Colors.white,
              size: 80,
            ),
            SizedBox(height: 16),
            Text(
              'Advertisement',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCarouselCounter() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.85),
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: Colors.white.withOpacity(0.7), width: 0.7),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.6),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Text(
              '${_currentSlideIndex + 1}/${widget.carouselAd.slides.length}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// **BUILD BACK BUTTON: Bottom corner back button**
  Widget _buildBackButton() {
    return GestureDetector(
      onTap: widget.onAdClosed,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.arrow_back_ios,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildLoadingPlaceholder() {
    return Container(
      color: Colors.grey[800],
      child: const Center(
        child: CircularProgressIndicator(
          color: Colors.blue,
        ),
      ),
    );
  }

  Widget _buildErrorPlaceholder() {
    return Container(
      color: Colors.grey[800],
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.white, size: 48),
            SizedBox(height: 8),
            Text(
              'Ad Image',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  String _getAdTitle() {
    if (widget.carouselAd.slides.isNotEmpty) {
      final currentSlide = widget.carouselAd.slides[_currentSlideIndex];
      return currentSlide.title ?? 'Advertisement';
    }
    return 'Advertisement';
  }

  String _getAdDescription() {
    if (widget.carouselAd.slides.isNotEmpty) {
      final currentSlide = widget.carouselAd.slides[_currentSlideIndex];
      return currentSlide.description ?? '';
    }
    return '';
  }

  /// **BUILD SPONSORED TEXT: Top-right corner sponsored label**
  Widget _buildSponsoredText() {
    return Positioned(
      right: 16,
      top: 0,
      child: SafeArea(
        child: Material(
          color: Colors.transparent,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.85),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: Colors.white.withOpacity(0.7), width: 0.7),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.6),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.campaign, size: 14, color: Colors.white),
                  SizedBox(width: 6),
                  Text(
                    'Sponsored',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// **BUILD MAIN CONTENT AREA: Full screen ad creatives (not clickable)**
  Widget _buildMainContentArea() {
    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child:
          _buildCarouselContent(), // Removed GestureDetector - no whole screen tap
    );
  }

  /// **BUILD RIGHT ACTION BAR: Vertical action buttons aligned with back button**
  Widget _buildRightActionBar() {
    return Positioned(
      right: 16,
      bottom: 80, // Aligned with back button at bottom
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Heart icon
          _buildActionButton(
            icon: _isLiked ? Icons.favorite : Icons.favorite_border,
            onTap: _onHeartTap,
            count: _displayLikes(),
          ),
          const SizedBox(height: 20),

          // Comment icon
          _buildActionButton(
            icon: Icons.chat_bubble_outline,
            onTap: _onCommentTap,
            count: widget.carouselAd.comments,
          ),
          const SizedBox(height: 20),

          // Share icon
          _buildActionButton(
            icon: Icons.send,
            onTap: _onShareTap,
            count: widget.carouselAd.shares,
          ),
          const SizedBox(height: 20), // Spacing before back button
        ],
      ),
    );
  }

  /// **BUILD BOTTOM AD METADATA: Instagram-style bottom section**
  Widget _buildBottomAdMetadata() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 80, // Leave space for action bar
      child: Container(
        padding: const EdgeInsets.all(16),
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Advertiser profile and info
            Row(
              children: [
                // Small circular profile image
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.grey[300],
                  backgroundImage:
                      widget.carouselAd.advertiserProfilePic.isNotEmpty
                          ? CachedNetworkImageProvider(
                              widget.carouselAd.advertiserProfilePic)
                          : null,
                  child: widget.carouselAd.advertiserProfilePic.isEmpty
                      ? Icon(Icons.business, size: 16, color: Colors.grey[600])
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.carouselAd.advertiserName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Ad caption
            Text(
              _getAdTitle(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
                shadows: [
                  Shadow(
                    color: Colors.black54,
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
            if (_getAdDescription().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                _getAdDescription(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  shadows: [
                    Shadow(
                      color: Colors.black45,
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),

            // CTA Button - Same as "Visit Now" button
            GestureDetector(
              onTap: _onAdTap,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  widget.carouselAd.callToActionLabel,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// **BUILD ACTION BUTTON: Individual action button**
  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onTap,
    int? count,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 24,
            ),
          ),
          if (count != null) ...[
            const SizedBox(height: 4),
            Text(
              _formatCount(count),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
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

  /// **ACTION HANDLERS: Handle user interactions**
  Future<void> _onHeartTap() async {
    if (_currentUserId == null) {
      // Silently ignore or you can navigate to login if required
      return;
    }

    // Store original state for rollback
    final wasLiked = _isLiked;

    try {
      // Optimistic UI update
      setState(() {
        _isLiked = !_isLiked;
      });

      // Make API call
      if (_isLiked) {
        await _carouselAdService.likeAd(widget.carouselAd.id, _currentUserId!);
      } else {
        await _carouselAdService.unlikeAd(
            widget.carouselAd.id, _currentUserId!);
      }
    } catch (e) {
      AppLogger.log('❌ Error handling like: $e');

      // Revert optimistic update on error
      setState(() {
        _isLiked = wasLiked;
      });

      // Avoid showing snackbar per requirement
    }
  }

  int _displayLikes() {
    // Derive display likes without mutating model
    final base = widget.carouselAd.likes;
    if (_initiallyLiked) {
      // If initially liked and now unliked, subtract one
      return _isLiked ? base : (base - 1).clamp(0, 1 << 31);
    } else {
      // If initially not liked and now liked, add one
      return _isLiked ? base + 1 : base;
    }
  }

  void _onCommentTap() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => CommentsSheetWidget(
        dataSource: AdCommentsDataSource(
          adId: widget.carouselAd.id,
          adCommentService: AdCommentService(),
        ),
      ),
    );
  }

  void _onShareTap() {
    // Create a mock VideoModel for the ad to use existing CustomShareWidget
    final mockVideo = _createMockVideoFromAd();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CustomShareWidget(video: mockVideo),
    );
  }

  /// Create a mock VideoModel from the carousel ad for compatibility
  dynamic _createMockVideoFromAd() {
    // Return a simple object with the required fields for the widgets
    return {
      'id': widget.carouselAd.id,
      'videoName': _getAdTitle(),
      'description': _getAdDescription(),
      'uploader': {
        'id': widget.carouselAd.campaignId,
        'name': widget.carouselAd.advertiserName,
        'profilePic': widget.carouselAd.advertiserProfilePic,
      },
      'likes': widget.carouselAd.likes,
      'comments': [], // Empty for now
      'shares': widget.carouselAd.shares,
      'likedBy': widget.carouselAd.likedBy,
      'link': widget.carouselAd.callToActionUrl,
    };
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
