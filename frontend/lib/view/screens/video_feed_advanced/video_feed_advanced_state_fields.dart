part of 'package:vayu/view/screens/video_feed_advanced.dart';

mixin VideoFeedStateFieldsMixin on State<VideoFeedAdvanced> {
  // Core state - **OPTIMIZED: Using ValueNotifiers for granular updates**
  List<VideoModel> _videos = [];
  final ValueNotifier<bool> _isLoadingVN = ValueNotifier<bool>(true);
  bool get _isLoading => _isLoadingVN.value;
  set _isLoading(bool value) => _isLoadingVN.value = value;

  String? _currentUserId;
  int _previousIndex = 0;
  final ValueNotifier<int> _currentIndexVN = ValueNotifier<int>(0);
  int get _currentIndex => _currentIndexVN.value;
  set _currentIndex(int value) {
    _previousIndex = _currentIndexVN.value;
    _currentIndexVN.value = value;
  }
  int _currentPage = 1;

  final Set<String> _followingUsers = {};
  final Set<String> _seenVideoKeys = <String>{};
  final ValueNotifier<String?> _errorMessageVN = ValueNotifier<String?>(null);
  String? get _errorMessage => _errorMessageVN.value;
  set _errorMessage(String? value) => _errorMessageVN.value = value;

  final ValueNotifier<bool> _isRefreshingVN = ValueNotifier<bool>(false);
  bool get _isRefreshing => _isRefreshingVN.value;
  set _isRefreshing(bool value) => _isRefreshingVN.value = value;

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
  int get _decoderPrimeBudget => 3;
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

  // Ad state - **OPTIMIZED: Using ValueNotifiers for granular updates**
  final ValueNotifier<List<Map<String, dynamic>>> _bannerAdsVN =
      ValueNotifier<List<Map<String, dynamic>>>([]);
  List<Map<String, dynamic>> get _bannerAds => _bannerAdsVN.value;
  set _bannerAds(List<Map<String, dynamic>> value) =>
      _bannerAdsVN.value = value;

  final Map<String, Map<String, dynamic>> _lockedBannerAdByVideoId = {};
  final ValueNotifier<bool> _adsLoadedVN = ValueNotifier<bool>(false);
  bool get _adsLoaded => _adsLoadedVN.value;
  set _adsLoaded(bool value) => _adsLoadedVN.value = value;

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
  final Map<int, ValueNotifier<bool>> _isSlowConnectionVN = {};
  final Map<int, Timer> _bufferingTimers = {};

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
  // **OPTIMIZED: Reduced from 4 to 2 for "Sniper" pipeline loading**
  // Focus bandwidth on next 2 videos for max speed instead of spreading thin
  // **OPTIMIZED: Increased from 2 to 4 for faster scrolling**
  // Focus bandwidth on next 4 videos for better responsiveness
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

  // Infinite scrollingtrollers for refresh

  // Infinite scrolling
  // **OPTIMIZED: Increased to 20 for earlier loading - next batch loads when 20 videos from end**
  final ValueNotifier<bool> _isLoadingMoreVN = ValueNotifier<bool>(false);
  bool get _isLoadingMore => _isLoadingMoreVN.value;
  set _isLoadingMore(bool value) => _isLoadingMoreVN.value = value;

  // **OPTIMIZED: Constant 15 videos per page to prevent offset/skipping bugs**
  // Variable page size (5 then 15) caused backend to skip videos 5-15.
  int get _videosPerPage => 15;

  final ValueNotifier<bool> _hasMoreVN = ValueNotifier<bool>(true);
  bool get _hasMore => _hasMoreVN.value;
  set _hasMore(bool value) => _hasMoreVN.value = value;


  // **NEW: Video Error Tracking**
  // Stores error messages for videos that failed to load or play
  final Map<int, String> _videoErrors = {};

  // Playback StateMANAGEMENT: Limit videos in memory to prevent memory issues**
  // Keep max 300 videos (15 pages) - removes old videos automatically
  // Each VideoModel ~5-10KB, so 300 videos = ~1.5-3MB (safe)
  // For 5000+ videos, this prevents 50MB+ memory usage
  static const int _maxVideosInMemory =
      300; // **SCALABLE: Adjust based on device memory**
  static const int _videosCleanupThreshold =
      250; // Start cleanup when reaching this
  static const int _videosKeepRange = 100; // Keep current ± 100 videos

  // Carousel ads - **OPTIMIZED: Using ValueNotifiers for granular updates**
  final ValueNotifier<List<CarouselAdModel>> _carouselAdsVN =
      ValueNotifier<List<CarouselAdModel>>([]);
  List<CarouselAdModel> get _carouselAds => _carouselAdsVN.value;
  set _carouselAds(List<CarouselAdModel> value) => _carouselAdsVN.value = value;

  final Map<int, ValueNotifier<int>> _currentHorizontalPage = {};

  // Screen visibility
  bool _isScreenVisible =
      false; // **FIX: Start as false, only set true when Yug tab is actually visible**
  bool _lifecyclePaused = false;

  // Double tap animations
  final Map<int, ValueNotifier<bool>> _showHeartAnimation = {};

  // Earnings cache


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
  DateTime? _lastPausedAt;
  DateTime? _screenFirstOpenedAt;
  Duration get _signInPromptDelay => const Duration(minutes: 5);

  // Background page preload logic
  bool _hasStartedBackgroundPreload = false;

  String videoIdentityKey(VideoModel video) {
    if (video.id.isNotEmpty) return video.id;
    if (video.videoUrl.isNotEmpty) return video.videoUrl;
    if (video.videoName.isNotEmpty) return video.videoName;
    return '${video.hashCode}';
  }
}
