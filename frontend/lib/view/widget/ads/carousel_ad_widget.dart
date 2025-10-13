import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:snehayog/model/carousel_ad_model.dart';
import 'package:snehayog/services/carousel_ad_service.dart';
import 'package:url_launcher/url_launcher.dart';

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

  final CarouselAdService _carouselAdService = CarouselAdService();

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _progressController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _trackImpression();
    _startProgressAnimation();
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
    return Container(
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

  /// **BUILD MAIN CONTENT AREA: Full screen ad creatives (not clickable)**
  Widget _buildMainContentArea() {
    return Container(
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
            icon: Icons.favorite_border,
            onTap: _onHeartTap,
          ),
          const SizedBox(height: 20),

          // Comment icon
          _buildActionButton(
            icon: Icons.chat_bubble_outline,
            onTap: _onCommentTap,
          ),
          const SizedBox(height: 20),

          // Share icon
          _buildActionButton(
            icon: Icons.send,
            onTap: _onShareTap,
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
                      const SizedBox(height: 2),
                      const Text(
                        'Sponsored',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
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
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
    );
  }

  /// **ACTION HANDLERS: Handle user interactions**
  void _onHeartTap() {
    // Handle heart/like action
    print('❤️ Heart tapped');
  }

  void _onCommentTap() {
    // Handle comment action
    print('💬 Comment tapped');
  }

  void _onShareTap() {
    // Handle share action
    print('📤 Share tapped');
  }
}
