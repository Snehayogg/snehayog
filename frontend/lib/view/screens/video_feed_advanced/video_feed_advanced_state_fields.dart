part of 'package:vayu/view/screens/video_feed_advanced.dart';

mixin VideoFeedStateFieldsMixin on State<VideoFeedAdvanced> {
  // Core state
  List<VideoModel> _videos = [];
  bool _isLoading = true;
  String? _currentUserId;
  int _currentIndex = 0;
  final Set<String> _followingUsers = {};
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
  int get _infiniteScrollThreshold => 4;
  bool _isLoadingMore = false;
  int _currentPage = 1;
  int get _videosPerPage => 5;
  bool _hasMore = true;
  int? _totalVideos;

  // Carousel ads
  List<CarouselAdModel> _carouselAds = [];
  final Map<int, ValueNotifier<int>> _currentHorizontalPage = {};

  // Screen visibility
  bool _isScreenVisible = true;
  bool _lifecyclePaused = false;

  // Double tap animations
  final Map<int, ValueNotifier<bool>> _showHeartAnimation = {};

  // Earnings cache
  final Map<String, double> _earningsCache = {};

  // Persisted state keys
  String get _kSavedFeedIndexKey => 'video_feed_saved_index';
  String get _kSavedFeedTypeKey => 'video_feed_saved_type';

  // Cold start tracking
  bool _isColdStart = true;

  // Screen wake lock
  bool _wakelockEnabled = false;
  bool _wasSignedIn = false;
  bool _pendingAutoplayAfterLogin = false;
}
