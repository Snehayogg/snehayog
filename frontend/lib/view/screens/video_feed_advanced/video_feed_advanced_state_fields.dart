part of 'package:vayu/view/screens/video_feed_advanced.dart';

mixin VideoFeedStateFieldsMixin on State<VideoFeedAdvanced> {
  // Core state
  List<VideoModel> _videos = [];
  bool _isLoading = true;
  String? _currentUserId;
  int _currentIndex = 0;
  final Set<String> _followingUsers = {};
  final Set<String> _seenVideoKeys = <String>{};
  String? _errorMessage;
  bool _isRefreshing = false;

  // Services
  late VideoService _videoService;
  late AuthService _authService;
  late CarouselAdManager _carouselAdManager;
  final VideoControllerManager _videoControllerManager =
      VideoControllerManager();

  // Cached providers & media query
  MainController? _mainController;
  double? _screenWidth;
  double? _screenHeight;

  // Decoder priming
  int get _decoderPrimeBudget => 2;
  int _primedStartIndex = -1;

  // Ad and analytics services
  final ActiveAdsService _activeAdsService = ActiveAdsService();
  final VideoViewTracker _viewTracker = VideoViewTracker();
  final AdRefreshNotifier _adRefreshNotifier = AdRefreshNotifier();
  final BackgroundProfilePreloader _profilePreloader =
      BackgroundProfilePreloader();
  final AdImpressionService _adImpressionService = AdImpressionService();
  StreamSubscription? _adRefreshSubscription;

  // Cache manager
  final SmartCacheManager _cacheManager = SmartCacheManager();

  // Cache status tracking
  final int _cacheHits = 0;
  final int _cacheMisses = 0;
  int _preloadHits = 0;
  final int _totalRequests = 0;

  // Ad state
  List<Map<String, dynamic>> _bannerAds = [];
  final Map<String, Map<String, dynamic>> _lockedBannerAdByVideoId = {};
  bool _adsLoaded = false;

  // Page controller
  late PageController _pageController;
  final bool _autoScrollEnabled = true;
  bool _isAnimatingPage = false;
  final Set<int> _autoAdvancedForIndex = {};

  // Controller pools
  final Map<int, VideoPlayerController> _controllerPool = {};
  final Map<int, bool> _controllerStates = {};
  final int _maxPoolSize = 7;
  final Map<int, bool> _userPaused = {};
  final Map<int, bool> _isBuffering = {};
  final Set<int> _togglingVideos = {};
  final Map<int, ValueNotifier<bool>> _isBufferingVN = {};

  // LRU tracking
  final Map<int, DateTime> _lastAccessedLocal = {};
  final Map<int, VoidCallback> _bufferingListeners = {};
  final Map<int, VoidCallback> _videoEndListeners = {};

  // Resume tracking
  final Map<int, bool> _wasPlayingBeforeNavigation = {};

  // Preloading state
  final Set<int> _preloadedVideos = {};
  final Set<int> _loadingVideos = {};
  final Set<int> _initializingVideos = {};
  int get _maxConcurrentInitializations => 2;
  final Map<int, int> _preloadRetryCount = {};
  int get _maxRetryAttempts => 2;
  Timer? _preloadTimer;
  Timer? _pageChangeTimer;
  Timer? _preloadDebounceTimer;

  // First-frame tracking
  final Map<int, ValueNotifier<bool>> _firstFrameReady = {};
  final Map<int, ValueNotifier<bool>> _forceMountPlayer = {};

  // Retained controllers for refresh
  final Map<String, VideoPlayerController> _retainedByVideoId = {};
  final Set<int> _retainedIndices = {};

  // Infinite scrolling
  // **OPTIMIZED: Increased to 15 for earlier loading - next batch loads when 15 videos from end**
  int get _infiniteScrollThreshold => 15;
  bool _isLoadingMore = false;
  int _currentPage = 1;
  // **OPTIMIZED: Load 4 videos on first page for instant loading, then 15 for subsequent pages**
  int get _videosPerPage {
    // First page: only 4 videos for instant display (reduces load time significantly)
    if (_currentPage == 1 && _videos.isEmpty) {
      return 4;
    }
    // Subsequent pages: 15 videos for seamless UX
    return 15;
  }

  bool _hasMore = true;
  int? _totalVideos;
  bool _isLoadingRemainingVideos =
      false; // Track background loading of remaining videos

  // **MEMORY MANAGEMENT: Limit videos in memory to prevent memory issues**
  // Keep max 300 videos (15 pages) - removes old videos automatically
  // Each VideoModel ~5-10KB, so 300 videos = ~1.5-3MB (safe)
  // For 5000+ videos, this prevents 50MB+ memory usage
  static const int _maxVideosInMemory =
      300; // **SCALABLE: Adjust based on device memory**
  static const int _videosCleanupThreshold =
      250; // Start cleanup when reaching this
  static const int _videosKeepRange = 100; // Keep current ± 100 videos

  // Carousel ads
  List<CarouselAdModel> _carouselAds = [];
  final Map<int, ValueNotifier<int>> _currentHorizontalPage = {};

  // Screen visibility
  bool _isScreenVisible =
      false; // **FIX: Start as false, only set true when Yug tab is actually visible**
  bool _lifecyclePaused = false;

  // Double tap animations
  final Map<int, ValueNotifier<bool>> _showHeartAnimation = {};

  // Earnings cache
  final Map<String, double> _earningsCache = {};

  // Persisted state keys
  String get _kSavedFeedIndexKey => 'video_feed_saved_index';
  String get _kSavedFeedTypeKey => 'video_feed_saved_type';
  String get _kSavedVideoIdKey => 'video_feed_saved_video_id';
  String get _kSavedPageKey => 'video_feed_saved_page';
  String get _kSavedStateTimestampKey => 'video_feed_saved_timestamp';
  String get _kSeenVideoKeysKey => 'video_feed_seen_video_keys';

  // Cold start tracking
  bool _isColdStart = true;

  // Screen wake lock
  bool _wakelockEnabled = false;
  bool _wasSignedIn = false;
  bool _pendingAutoplayAfterLogin = false;

  // **NEW: Track when screen was first opened to delay sign-in prompts**
  DateTime? _screenFirstOpenedAt;
  Duration get _signInPromptDelay => const Duration(minutes: 5);

  String videoIdentityKey(VideoModel video) {
    if (video.id.isNotEmpty) return video.id;
    if (video.videoUrl.isNotEmpty) return video.videoUrl;
    if (video.videoName.isNotEmpty) return video.videoName;
    return '${video.hashCode}';
  }
}
