import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:snehayog/model/carousel_ad_model.dart';
import 'package:snehayog/services/carousel_ad_service.dart';
import 'package:snehayog/services/authservices.dart';
import 'package:snehayog/services/video_service.dart';
import 'package:snehayog/view/widget/comments_sheet_widget.dart';
import 'package:snehayog/services/comments/ad_comments_data_source.dart';
import 'package:snehayog/services/ad_comment_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:snehayog/view/widget/custom_share_widget.dart';

/// **Professional Carousel Ad Widget**
class CarouselAdWidget extends StatefulWidget {
  final CarouselAdModel carouselAd;
  final VoidCallback? onAdClosed;
  final bool autoPlay;

  const CarouselAdWidget({
    Key? key,
    required this.carouselAd,
    this.onAdClosed,
    this.autoPlay = true,
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
  bool _isLiked = false;
  bool _initiallyLiked = false;
  String? _currentUserId;

  final CarouselAdService _carouselAdService = CarouselAdService();
  final AuthService _authService = AuthService();
  final VideoService _videoService = VideoService();

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
  }

  Future<void> _loadUserData() async {
    try {
      final userData = await _authService.getUserData();
      if (userData != null) {
        setState(() {
          _currentUserId = userData['id'] ?? userData['googleId'];
          _isLiked = _currentUserId != null &&
              widget.carouselAd.likedBy.contains(_currentUserId);
          _initiallyLiked = _isLiked;
        });
      }
    } catch (e) {
      print('❌ Error loading user data: $e');
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  void _trackImpression() async {
    if (_hasTrackedImpression) return;

    try {
      await _carouselAdService.trackImpression(widget.carouselAd.id);
      _hasTrackedImpression = true;
      print('✅ Carousel ad impression tracked: ${widget.carouselAd.id}');
    } catch (e) {
      print('❌ Error tracking carousel ad impression: $e');
    }
  }

  void _trackClick() async {
    if (_hasTrackedClick) return;

    try {
      await _carouselAdService.trackClick(widget.carouselAd.id);
      _hasTrackedClick = true;
      print('✅ Carousel ad click tracked: ${widget.carouselAd.id}');
    } catch (e) {
      print('❌ Error tracking carousel ad click: $e');
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
          print('✅ Opened carousel ad link: $ctaUrl');
        }
      } catch (e) {
        print('❌ Error launching carousel ad URL: $e');
      }
    }

    widget.onAdClosed?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        child: Stack(
          children: [
            // **Top Bar with Yog Title**
            _buildTopBar(),

            // **Sponsored Text at Top Corner**
            _buildSponsoredText(),

            // **Main Content Area - Dynamic Ad Section**
            Positioned.fill(
              child: _buildMainContentArea(),
            ),

            // **Progress Indicators** (for multiple slides)
            if (widget.carouselAd.slides.length > 1) _buildProgressIndicators(),

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

  Widget _buildProgressIndicators() {
    return Positioned(
      top: 100,
      left: 16,
      right: 80,
      child: Row(
        children: List.generate(widget.carouselAd.slides.length, (index) {
          final isActive = index == _currentSlideIndex;
          return Expanded(
            child: Container(
              height: 3,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: isActive ? Colors.white : Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
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

  /// **BUILD TOP BAR: Left-aligned "Yog" title**
  Widget _buildTopBar() {
    return Positioned(
      top: 60,
      left: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: const Text(
          'Yog',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  /// **BUILD SPONSORED TEXT: Top-right corner sponsored label**
  Widget _buildSponsoredText() {
    return Positioned(
      right: 16,
      top: 0,
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.8),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white70, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.campaign, size: 14, color: Colors.white70),
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
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withOpacity(0.8),
              Colors.transparent,
            ],
          ),
        ),
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
              ),
            ),
            if (_getAdDescription().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                _getAdDescription(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ],
            const SizedBox(height: 16),

            // CTA Button - Same as "Visit Now" button
            GestureDetector(
              onTap: _onAdTap,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(25),
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
                    fontSize: 16,
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
    final originalLikes = widget.carouselAd.likes;
    final originalLikedBy = List<String>.from(widget.carouselAd.likedBy);

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

      print('✅ Successfully toggled like for ad ${widget.carouselAd.id}');
    } catch (e) {
      print('❌ Error handling like: $e');

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
