import 'package:flutter/material.dart';
import 'package:snehayog/model/carousel_ad_model.dart';
import 'package:snehayog/services/carousel_ad_service.dart';

/// **CarouselAdManager - Handles all carousel ad logic**
/// Separated from VideoScreen for better maintainability
class CarouselAdManager {
  final CarouselAdService _carouselAdService = CarouselAdService();

  // **State management**
  List<CarouselAdModel> _carouselAds = [];
  bool _isCarouselAdsLoaded = false;
  int _carouselAdIndex = 0;
  bool _showCarouselAd = false;

  // **Getters**
  List<CarouselAdModel> get carouselAds => List.unmodifiable(_carouselAds);
  bool get isCarouselAdsLoaded => _isCarouselAdsLoaded;
  int get carouselAdIndex => _carouselAdIndex;
  bool get showCarouselAd => _showCarouselAd;

  /// **Load carousel ads from backend or fallback to dummy**
  Future<void> loadCarouselAds() async {
    try {
      print('🎯 CarouselAdManager: Loading carousel ads...');

      // First try to load from backend
      final ads = await _carouselAdService.fetchCarouselAds();

      if (ads.isNotEmpty) {
        _carouselAds = ads;
        _isCarouselAdsLoaded = true;
        print(
            '✅ CarouselAdManager: Loaded ${ads.length} carousel ads from backend');
      } else {
        // Fallback to dummy ad for testing
        final dummyAd = _carouselAdService.getDummyCarouselAd();
        _carouselAds = [dummyAd];
        _isCarouselAdsLoaded = true;
        print('✅ CarouselAdManager: Using dummy carousel ad for testing');
      }
    } catch (error) {
      print('❌ CarouselAdManager: Error loading carousel ads: $error');
      // Fallback to dummy ad
      final dummyAd = _carouselAdService.getDummyCarouselAd();
      _carouselAds = [dummyAd];
      _isCarouselAdsLoaded = true;
      print('✅ CarouselAdManager: Using dummy carousel ad due to error');
    }
  }

  /// **Check if index should show carousel ad**
  bool shouldShowCarouselAd(int index) {
    if (!_isCarouselAdsLoaded || _carouselAds.isEmpty) return false;

    // Show carousel ad every 3 videos for better visibility
    return (index + 1) % 3 == 0;
  }

  /// **Get carousel ad for specific index**
  CarouselAdModel? getCarouselAdForIndex(int index) {
    if (!_isCarouselAdsLoaded || _carouselAds.isEmpty) return null;

    // **UPDATED: Use modulo to cycle through available ads for new 1:1 ratio**
    final adIndex = index % _carouselAds.length;
    return _carouselAds[adIndex];
  }

  /// **Get total number of carousel ads available**
  int getTotalCarouselAds() {
    return _carouselAds.length;
  }

  /// **Calculate total item count including carousel ads**
  int calculateTotalItemCount(int videoCount, bool hasMore) {
    int totalItems = videoCount;

    if (_isCarouselAdsLoaded && _carouselAds.isNotEmpty) {
      // Add carousel ads every 3 videos
      int adCount = (videoCount / 3).floor();
      totalItems += adCount;
    }

    // Add loading indicator if there are more videos
    if (hasMore) {
      totalItems += 1;
    }

    return totalItems;
  }

  /// **Get actual video index considering carousel ads**
  int getActualVideoIndex(int displayIndex) {
    if (!_isCarouselAdsLoaded || _carouselAds.isEmpty) {
      return displayIndex;
    }

    // Calculate actual video index by accounting for carousel ads
    int actualIndex = displayIndex;
    int adCount = 0;

    for (int i = 0; i < displayIndex; i++) {
      if (shouldShowCarouselAd(i)) {
        adCount++;
      }
    }

    actualIndex = displayIndex - adCount;

    // Ensure index is within bounds
    if (actualIndex < 0) actualIndex = 0;

    return actualIndex;
  }

  /// **Handle carousel ad closed**
  void onCarouselAdClosed(int index, PageController pageController) {
    print('🎯 CarouselAdManager: Carousel ad closed at index $index');
    // Skip to next video
    if (index < 1000) {
      // Arbitrary large number for safety
      pageController.animateToPage(
        index + 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  /// **Handle carousel ad clicked**
  void onCarouselAdClicked(CarouselAdModel carouselAd) {
    print('🎯 CarouselAdManager: Carousel ad clicked: ${carouselAd.id}');
    // Track click
    _carouselAdService.trackClick(carouselAd.id);
  }

  /// **Update carousel ad state**
  void updateCarouselAdState({
    bool? showCarouselAd,
    int? carouselAdIndex,
  }) {
    if (showCarouselAd != null) _showCarouselAd = showCarouselAd;
    if (carouselAdIndex != null) _carouselAdIndex = carouselAdIndex;
  }

  /// **Get carousel ad statistics**
  Map<String, dynamic> getCarouselAdStats() {
    return {
      'totalAds': _carouselAds.length,
      'isLoaded': _isCarouselAdsLoaded,
      'currentIndex': _carouselAdIndex,
      'showAd': _showCarouselAd,
      'adIds': _carouselAds.map((ad) => ad.id).toList(),
    };
  }

  /// **Clear carousel ad data**
  void clearCarouselAds() {
    _carouselAds.clear();
    _isCarouselAdsLoaded = false;
    _carouselAdIndex = 0;
    _showCarouselAd = false;
    print('🗑️ CarouselAdManager: Carousel ads cleared');
  }
}
