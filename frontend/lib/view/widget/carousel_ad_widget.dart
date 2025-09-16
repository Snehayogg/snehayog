import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:snehayog/model/carousel_ad_model.dart';

class CarouselAdWidget extends StatefulWidget {
  final CarouselAdModel carouselAd;
  final VoidCallback? onAdClosed;
  final VoidCallback? onAdClicked;

  const CarouselAdWidget({
    Key? key,
    required this.carouselAd,
    this.onAdClosed,
    this.onAdClicked,
  }) : super(key: key);

  @override
  State<CarouselAdWidget> createState() => _CarouselAdWidgetState();
}

class _CarouselAdWidgetState extends State<CarouselAdWidget> {
  late PageController _pageController;
  late VideoPlayerController? _videoController;
  int _currentSlideIndex = 0;
  bool _isVideoPlaying = false;
  bool _isVideoInitialized = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _initializeVideoController();
  }

  void _initializeVideoController() {
    if (widget.carouselAd.slides.isNotEmpty &&
        widget.carouselAd.slides[_currentSlideIndex].mediaType == 'video') {
      final slide = widget.carouselAd.slides[_currentSlideIndex];
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(slide.mediaUrl),
      );
      _videoController!.initialize().then((_) {
        if (mounted) {
          setState(() {
            _isVideoInitialized = true;
          });
          _videoController!.play();
          _videoController!.addListener(_onVideoStateChanged);
        }
      });
    }
  }

  void _onVideoStateChanged() {
    if (_videoController != null && mounted) {
      setState(() {
        _isVideoPlaying = _videoController!.value.isPlaying;
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  void _onSlideChanged(int index) {
    setState(() {
      _currentSlideIndex = index;
    });

    // Dispose previous video controller and initialize new one if needed
    _videoController?.dispose();
    _videoController = null;
    _isVideoInitialized = false;

    if (widget.carouselAd.slides[index].mediaType == 'video') {
      _initializeVideoController();
    }
  }

  void _onCallToActionTap() async {
    if (widget.onAdClicked != null) {
      widget.onAdClicked!();
    }

    try {
      final url = Uri.parse(widget.carouselAd.callToActionUrl);
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      print('Error launching URL: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: MediaQuery.of(context).size.height,
      color: Colors.black,
      child: Stack(
        children: [
          // Carousel content
          _buildCarouselContent(),

          // Top overlay with close button and ad indicator
          _buildTopOverlay(),

          // Bottom overlay with call to action
          _buildBottomOverlay(),

          // Slide indicators
          _buildSlideIndicators(),
        ],
      ),
    );
  }

  Widget _buildCarouselContent() {
    return PageView.builder(
      controller: _pageController,
      onPageChanged: _onSlideChanged,
      itemCount: widget.carouselAd.slides.length,
      itemBuilder: (context, index) {
        final slide = widget.carouselAd.slides[index];
        return _buildSlide(slide);
      },
    );
  }

  Widget _buildSlide(CarouselSlide slide) {
    if (slide.mediaType == 'video') {
      return _buildVideoSlide(slide);
    } else {
      return _buildImageSlide(slide);
    }
  }

  Widget _buildVideoSlide(CarouselSlide slide) {
    if (_videoController == null || !_isVideoInitialized) {
      return _buildVideoPlaceholder(slide);
    }

    return Stack(
      children: [
        // Video player
        Center(
          child: AspectRatio(
            aspectRatio: _videoController!.value.aspectRatio,
            child: VideoPlayer(_videoController!),
          ),
        ),

        // Play/Pause overlay
        if (_isVideoInitialized)
          GestureDetector(
            onTap: () {
              if (_videoController!.value.isPlaying) {
                _videoController!.pause();
              } else {
                _videoController!.play();
              }
            },
            child: Container(
              color: Colors.transparent,
              child: Center(
                child: AnimatedOpacity(
                  opacity: _isVideoPlaying ? 0.0 : 0.7,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Icon(
                      _isVideoPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildVideoPlaceholder(CarouselSlide slide) {
    return Container(
      color: Colors.grey[900],
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
            SizedBox(height: 16),
            Text(
              'Loading video...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageSlide(CarouselSlide slide) {
    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: CachedNetworkImage(
        imageUrl: slide.mediaUrl,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          color: Colors.grey[900],
          child: const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ),
        errorWidget: (context, url, error) => Container(
          color: Colors.grey[900],
          child: const Center(
            child: Icon(
              Icons.error,
              color: Colors.white,
              size: 48,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopOverlay() {
    return Positioned(
      top: 50,
      left: 16,
      right: 16,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Ad indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.orange,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.campaign, color: Colors.white, size: 16),
                SizedBox(width: 4),
                Text(
                  'Carousel Ad',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // Close button
          GestureDetector(
            onTap: widget.onAdClosed,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.close,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomOverlay() {
    return Positioned(
      bottom: 100,
      left: 16,
      right: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Advertiser info
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundImage:
                    widget.carouselAd.advertiserProfilePic.isNotEmpty
                        ? CachedNetworkImageProvider(
                            widget.carouselAd.advertiserProfilePic,
                          )
                        : null,
                child: widget.carouselAd.advertiserProfilePic.isEmpty
                    ? Text(
                        widget.carouselAd.advertiserName.isNotEmpty
                            ? widget.carouselAd.advertiserName[0].toUpperCase()
                            : 'A',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Text(
                widget.carouselAd.advertiserName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
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
          ),

          const SizedBox(height: 16),

          // Call to action button
          GestureDetector(
            onTap: _onCallToActionTap,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Colors.blue, Colors.purple],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.carouselAd.callToActionLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.arrow_forward,
                    color: Colors.white,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlideIndicators() {
    if (widget.carouselAd.slides.length <= 1) return const SizedBox.shrink();

    return Positioned(
      top: 120,
      left: 16,
      child: Column(
        children: List.generate(
          widget.carouselAd.slides.length,
          (index) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: index == _currentSlideIndex
                  ? Colors.white
                  : Colors.white.withOpacity(0.5),
            ),
          ),
        ),
      ),
    );
  }
}
