import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:snehayog/utils/responsive_helper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snehayog/view/screens/creator_revenue_screen.dart';
import 'dart:convert';
import 'package:snehayog/config/app_config.dart';
import 'package:snehayog/core/managers/profile_state_manager.dart';
import 'package:provider/provider.dart';
import 'package:snehayog/core/providers/user_provider.dart';
import 'package:snehayog/model/usermodel.dart';
import 'package:snehayog/core/services/profile_screen_logger.dart';
import 'package:snehayog/services/background_profile_preloader.dart';
import 'dart:async';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:snehayog/view/widget/profile/profile_header_widget.dart';
import 'package:snehayog/view/widget/profile/profile_stats_widget.dart';
import 'package:snehayog/view/widget/profile/profile_videos_widget.dart';
import 'package:snehayog/view/widget/profile/profile_menu_widget.dart';
import 'package:snehayog/view/widget/profile/profile_dialogs_widget.dart';

class ProfileScreen extends StatefulWidget {
  final String? userId;
  const ProfileScreen({super.key, this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();

  static void refreshVideos(GlobalKey<State<ProfileScreen>> key) {
    final state = key.currentState;
    if (state != null) {
      (state as _ProfileScreenState)._stateManager.refreshVideosOnly();
    }
  }
}

class _ProfileScreenState extends State<ProfileScreen>
    with AutomaticKeepAliveClientMixin {
  late final ProfileStateManager _stateManager;
  final ImagePicker _imagePicker = ImagePicker();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Progressive loading states
  bool _isProfileDataLoaded = false;
  bool _isVideosLoaded = false;
  bool _isFollowersLoaded = false;
  bool _isLoading = true;
  String? _error;
  int _authRetryAttempts = 0;

  // Referral tracking
  int _invitedCount = 0;
  int _verifiedInstalled = 0;
  int _verifiedSignedUp = 0;

  // Progressive loading timers
  Timer? _progressiveLoadTimer;
  int _currentLoadStep = 0;

  @override
  void initState() {
    super.initState();
    ProfileScreenLogger.logProfileScreenInit();
    _stateManager = ProfileStateManager();
    _stateManager.setContext(context);

    // Ensure context is set early for providers that may be used during loads
    // It will be set again in didChangeDependencies
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _stateManager.setContext(context);
    });

    // **ENHANCED: Start loading with multiple fallback mechanisms**
    _startEnhancedLoading();
    // Load referral stats
    _loadReferralStats();
    _fetchVerifiedReferralStats();
  }

  /// **PUBLIC METHOD: Called when Profile tab is selected**
  /// Forces immediate data load if not already loaded
  void onProfileTabSelected() {
    print('🔄 ProfileScreen: Profile tab selected, ensuring data is loaded');

    // **ENHANCED: Better tab selection handling with multiple checks**
    if (!_isProfileDataLoaded || _stateManager.userData == null) {
      print('📡 ProfileScreen: Data not loaded, forcing immediate load');
      _forceImmediateLoad();
    } else {
      print('✅ ProfileScreen: Data already loaded, checking if refresh needed');

      // **ENHANCED: Check if data is stale and needs refresh**
      _checkAndRefreshStaleData();
    }
  }

  /// **NEW: Check if data is stale and needs refresh**
  Future<void> _checkAndRefreshStaleData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _getProfileCacheKey();
      final cacheTimestamp = prefs.getInt('profile_cache_timestamp_$cacheKey');

      if (cacheTimestamp != null) {
        final cacheAge = DateTime.now().millisecondsSinceEpoch - cacheTimestamp;
        const staleThreshold = 10 * 60 * 1000; // 10 minutes

        if (cacheAge > staleThreshold) {
          print('🔄 ProfileScreen: Data is stale, refreshing in background');
          // Trigger background refresh
          final preloader = BackgroundProfilePreloader();
          preloader.startBackgroundPreloading();
        } else {
          print('✅ ProfileScreen: Data is fresh, no refresh needed');
        }
      } else {
        print(
            '🔄 ProfileScreen: No cache timestamp, triggering background refresh');
        final preloader = BackgroundProfilePreloader();
        preloader.startBackgroundPreloading();
      }
    } catch (e) {
      print('❌ ProfileScreen: Error checking stale data: $e');
    }
  }

  /// **FORCE IMMEDIATE LOAD: Load data immediately without progressive loading**
  Future<void> _forceImmediateLoad() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      // Try to load from background preloader first
      final preloader = BackgroundProfilePreloader();
      final preloadedData = await preloader.getPreloadedProfileData();

      if (preloadedData != null) {
        print('⚡ ProfileScreen: Using preloaded data for immediate load');
        _stateManager.setUserData(preloadedData);

        setState(() {
          _isProfileDataLoaded = true;
          _isLoading = false;
        });

        // Load videos and followers in background
        _loadVideosProgressive();
        _loadFollowersProgressive();
        return;
      }

      // If no preloaded data, force load from server
      print('📡 ProfileScreen: Force loading from server');
      await _stateManager.loadUserData(widget.userId);

      if (_stateManager.userData != null) {
        setState(() {
          _isProfileDataLoaded = true;
          _isLoading = false;
        });

        // Cache the loaded data
        await _cacheProfileData(_stateManager.userData!);

        // Load videos and followers
        _loadVideosProgressive();
        _loadFollowersProgressive();
      }
    } catch (e) {
      print('❌ ProfileScreen: Error in force immediate load: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  /// **ENHANCED: Multi-layered loading approach with fallbacks**
  void _startEnhancedLoading() {
    print(
        '🚀 ProfileScreen: Starting enhanced loading with multiple fallbacks');

    // **LAYER 1: Immediate cache check (fastest)**
    _loadFromCacheFirst();

    // **LAYER 2: Progressive loading with improved reliability**
    _startProgressiveLoading();

    // **LAYER 3: Aggressive backup loading (if progressive fails)**
    Timer(const Duration(milliseconds: 1500), () {
      if (!_isProfileDataLoaded && mounted) {
        print(
            '⚠️ ProfileScreen: Progressive loading taking too long, starting aggressive backup load');
        _startAggressiveBackupLoading();
      }
    });

    // **LAYER 4: Final aggressive fallback (if everything else fails)**
    Timer(const Duration(seconds: 3), () {
      if (!_isProfileDataLoaded && mounted) {
        print(
            '🆘 ProfileScreen: All loading methods failed, starting final aggressive load');
        _startFinalAggressiveLoad();
      }
    });

    // **LAYER 5: Background continuous retry (silent)**
    Timer(const Duration(seconds: 5), () {
      if (!_isProfileDataLoaded && mounted) {
        print('🔄 ProfileScreen: Starting background continuous retry');
        _startBackgroundContinuousRetry();
      }
    });
  }

  /// **NEW: Load from cache first for instant response**
  Future<void> _loadFromCacheFirst() async {
    try {
      print('⚡ ProfileScreen: Checking cache first for instant load');

      // Check background preloaded data first
      final preloader = BackgroundProfilePreloader();
      final preloadedData = await preloader.getPreloadedProfileData();

      if (preloadedData != null) {
        print('⚡ ProfileScreen: Using preloaded data (instant!)');
        _stateManager.setUserData(preloadedData);
        setState(() {
          _isProfileDataLoaded = true;
          _isLoading = false;
        });

        // Load videos and followers in background
        _loadVideosProgressive();
        _loadFollowersProgressive();
        return;
      }

      // Check SharedPreferences cache
      final cachedData = await _loadCachedProfileData();
      if (cachedData != null) {
        print('⚡ ProfileScreen: Using cached data (instant!)');
        _stateManager.setUserData(cachedData);
        setState(() {
          _isProfileDataLoaded = true;
          _isLoading = false;
        });

        // Load videos and followers in background
        _loadVideosProgressive();
        _loadFollowersProgressive();
        return;
      }

      print('📡 ProfileScreen: No cache available, will load from server');
    } catch (e) {
      print('❌ ProfileScreen: Cache loading failed: $e');
    }
  }

  /// **NEW: Aggressive backup loading with multiple strategies**
  Future<void> _startAggressiveBackupLoading() async {
    try {
      print('🔥 ProfileScreen: Starting aggressive backup loading');

      // Strategy 1: Try direct server load with timeout
      try {
        await _stateManager.loadUserData(widget.userId).timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            print('⏰ ProfileScreen: Direct server load timed out');
            throw TimeoutException('Direct server load timeout');
          },
        );

        if (_stateManager.userData != null) {
          print('✅ ProfileScreen: Aggressive backup loading successful');
          setState(() {
            _isProfileDataLoaded = true;
            _isLoading = false;
          });
          return;
        }
      } catch (e) {
        print('❌ ProfileScreen: Aggressive backup loading failed: $e');
      }

      // Strategy 2: Try with different user ID combinations
      await _tryAlternativeUserIds();
    } catch (e) {
      print('❌ ProfileScreen: Aggressive backup loading completely failed: $e');
    }
  }

  /// **NEW: Final aggressive load with all possible methods**
  Future<void> _startFinalAggressiveLoad() async {
    try {
      print('🚀 ProfileScreen: Starting final aggressive load');

      // Clear all caches first
      await _clearProfileCache();

      // Try multiple loading strategies in parallel
      final futures = [
        _stateManager.loadUserData(widget.userId),
        _loadFromAlternativeSources(),
        _loadFromBackgroundPreloader(),
      ];

      // Wait for any one to succeed
      await Future.wait(
        futures.map((f) => f.catchError((e) => null)),
        eagerError: false,
      );

      // Check if any succeeded
      bool anySucceeded = _stateManager.userData != null;

      if (anySucceeded) {
        print('✅ ProfileScreen: Final aggressive load succeeded');
        setState(() {
          _isProfileDataLoaded = true;
          _isLoading = false;
        });
      } else {
        print('❌ ProfileScreen: Final aggressive load failed');
        setState(() {
          _error = 'Unable to load profile data. Please check your connection.';
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ ProfileScreen: Final aggressive load error: $e');
      setState(() {
        _error = 'Failed to load profile data: $e';
        _isLoading = false;
      });
    }
  }

  /// **NEW: Background continuous retry (silent)**
  void _startBackgroundContinuousRetry() {
    print('🔄 ProfileScreen: Starting background continuous retry');

    Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_isProfileDataLoaded) {
        print('✅ ProfileScreen: Data loaded, stopping background retry');
        timer.cancel();
        return;
      }

      print('🔄 ProfileScreen: Background retry attempt');
      _silentBackgroundLoad();
    });
  }

  /// **NEW: Silent background load (no UI changes)**
  Future<void> _silentBackgroundLoad() async {
    try {
      print('🔇 ProfileScreen: Silent background load attempt');

      // Try to load without affecting UI state
      await _stateManager.loadUserData(widget.userId);

      if (_stateManager.userData != null && mounted) {
        print('✅ ProfileScreen: Silent background load succeeded');
        setState(() {
          _isProfileDataLoaded = true;
          _isLoading = false;
        });

        // Load additional data
        _loadVideosProgressive();
        _loadFollowersProgressive();
      }
    } catch (e) {
      print('❌ ProfileScreen: Silent background load failed: $e');
    }
  }

  /// **NEW: Try alternative user ID combinations**
  Future<void> _tryAlternativeUserIds() async {
    try {
      print('🔄 ProfileScreen: Trying alternative user ID combinations');

      // Get current user data to try different ID formats
      final prefs = await SharedPreferences.getInstance();
      final fallbackUser = prefs.getString('fallback_user');

      if (fallbackUser != null) {
        final userData = jsonDecode(fallbackUser);
        final alternativeIds = [
          userData['id'],
          userData['googleId'],
          widget.userId,
        ].where((id) => id != null).toList();

        for (final altId in alternativeIds) {
          try {
            await _stateManager.loadUserData(altId);
            if (_stateManager.userData != null) {
              print('✅ ProfileScreen: Alternative ID $altId worked');
              setState(() {
                _isProfileDataLoaded = true;
                _isLoading = false;
              });
              return;
            }
          } catch (e) {
            print('❌ ProfileScreen: Alternative ID $altId failed: $e');
          }
        }
      }
    } catch (e) {
      print('❌ ProfileScreen: Alternative user ID strategy failed: $e');
    }
  }

  /// **NEW: Load from alternative sources**
  Future<void> _loadFromAlternativeSources() async {
    try {
      print('🔄 ProfileScreen: Loading from alternative sources');

      // Try to get user data from different sources
      final cachedData = await _loadCachedProfileData();

      if (cachedData != null) {
        _stateManager.setUserData(cachedData);
        print('✅ ProfileScreen: Loaded from alternative source (cache)');
        return;
      }

      // Try background preloader
      final preloader = BackgroundProfilePreloader();
      final preloadedData = await preloader.getPreloadedProfileData();

      if (preloadedData != null) {
        _stateManager.setUserData(preloadedData);
        print('✅ ProfileScreen: Loaded from alternative source (preloader)');
        return;
      }

      print('❌ ProfileScreen: No alternative sources available');
    } catch (e) {
      print('❌ ProfileScreen: Alternative source loading failed: $e');
    }
  }

  /// **NEW: Load from background preloader**
  Future<void> _loadFromBackgroundPreloader() async {
    try {
      print('🔄 ProfileScreen: Loading from background preloader');

      final preloader = BackgroundProfilePreloader();
      final preloadedData = await preloader.getPreloadedProfileData();

      if (preloadedData != null) {
        _stateManager.setUserData(preloadedData);
        print('✅ ProfileScreen: Loaded from background preloader');
      } else {
        print('❌ ProfileScreen: No preloaded data available');
      }
    } catch (e) {
      print('❌ ProfileScreen: Background preloader loading failed: $e');
    }
  }

  void _startProgressiveLoading() {
    // Step 1: Load basic profile data first (fastest)
    _loadBasicProfileData();

    // Step 2: Start progressive loading timer for other data
    _progressiveLoadTimer =
        Timer.periodic(const Duration(milliseconds: 300), (timer) {
      if (_currentLoadStep < 3) {
        _executeNextLoadStep();
      } else {
        timer.cancel();
      }
    });
  }

  void _executeNextLoadStep() {
    switch (_currentLoadStep) {
      case 0:
        // Step 1: Load videos (after profile data)
        if (_isProfileDataLoaded && !_isVideosLoaded) {
          _loadVideosProgressive();
        }
        break;
      case 1:
        // Step 2: Load followers data (do not depend on videos)
        if (_isProfileDataLoaded && !_isFollowersLoaded) {
          _loadFollowersProgressive();
        }
        break;
      case 2:
        // Step 3: Load additional user data
        if (_isFollowersLoaded) {
          _loadAdditionalUserData();
        }
        break;
    }
    _currentLoadStep++;
  }

  Future<void> _loadBasicProfileData() async {
    try {
      ProfileScreenLogger.logProfileLoad();

      // **ENHANCED: Improved authentication check with better retry logic**
      final prefs = await SharedPreferences.getInstance();
      final hasJwtToken = prefs.getString('jwt_token') != null;
      final hasFallbackUser = prefs.getString('fallback_user') != null;

      print(
          '🔐 ProfileScreen: Auth check - JWT: $hasJwtToken, Fallback: $hasFallbackUser');

      if (!hasJwtToken && !hasFallbackUser) {
        // **ENHANCED: Better retry mechanism with exponential backoff**
        if (_authRetryAttempts < 3) {
          _authRetryAttempts++;
          print(
              '🔄 ProfileScreen: No auth data found, retrying in $_authRetryAttempts seconds (attempt $_authRetryAttempts/3)');

          Future.delayed(Duration(seconds: _authRetryAttempts), () {
            if (mounted) _loadBasicProfileData();
          });
          return; // keep showing loading spinner
        } else {
          print('❌ ProfileScreen: Authentication retry limit reached');
          setState(() {
            _error = 'No authentication data found. Please sign in again.';
            _isLoading = false;
          });
          return;
        }
      }

      // **NEW: Check background preloaded data first (HIGHEST PRIORITY)**
      final preloader = BackgroundProfilePreloader();
      final preloadedProfileData = await preloader.getPreloadedProfileData();

      if (preloadedProfileData != null) {
        print('⚡ ProfileScreen: Using PRELOADED profile data (instant load!)');
        ProfileScreenLogger.logProfileLoadSuccess(userId: widget.userId);
        setState(() {
          _isProfileDataLoaded = true;
          _isLoading = false;
        });

        // Load from preloaded data instantly
        _stateManager.setUserData(preloadedProfileData);

        // Schedule background refresh if needed
        _scheduleBackgroundProfileRefresh();
        // Ensure payment setup flag is synced from backend/cache
        unawaited(_ensurePaymentSetupFlag());
        return;
      }

      // **ENHANCED: Check SharedPreferences cache first for instant loading**
      final cachedProfileData = await _loadCachedProfileData();
      if (cachedProfileData != null) {
        print('⚡ ProfileScreen: Using cached profile data');
        ProfileScreenLogger.logProfileLoadSuccess(userId: widget.userId);
        setState(() {
          _isProfileDataLoaded = true;
          _isLoading = false;
        });

        // Load from cache instantly, then refresh in background if needed
        _stateManager.setUserData(cachedProfileData);

        // Schedule background refresh if cache is stale
        _scheduleBackgroundProfileRefresh();
        // Ensure payment setup flag is synced from backend/cache
        unawaited(_ensurePaymentSetupFlag());
        return;
      }

      // Load basic profile data only if no cache available
      print('📡 ProfileScreen: Loading profile data from server...');
      await _stateManager.loadUserData(widget.userId);

      if (_stateManager.userData != null) {
        // **ENHANCED: Cache the loaded profile data**
        await _cacheProfileData(_stateManager.userData!);

        setState(() {
          _isProfileDataLoaded = true;
          _isLoading = false;
        });

        ProfileScreenLogger.logProfileLoadSuccess(userId: widget.userId);
        // Ensure payment setup flag is synced from backend
        unawaited(_ensurePaymentSetupFlag());
      }
    } catch (e) {
      ProfileScreenLogger.logProfileLoadError(e.toString());
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadVideosProgressive() async {
    if (_stateManager.userData == null) return;

    try {
      final currentUserId = _stateManager.userData!['googleId'] ??
          _stateManager.userData!['_id'] ??
          _stateManager.userData!['id'];
      if (currentUserId != null) {
        ProfileScreenLogger.logVideoLoad(userId: currentUserId);

        // **NEW: Check background preloaded videos first (HIGHEST PRIORITY)**
        final preloader = BackgroundProfilePreloader();
        final preloadedVideos = await preloader.getPreloadedUserVideos();

        if (preloadedVideos != null && preloadedVideos.isNotEmpty) {
          print(
              '⚡ ProfileScreen: Using PRELOADED videos (instant load!) - ${preloadedVideos.length} videos');
          _stateManager.setVideos(preloadedVideos);

          setState(() {
            _isVideosLoaded = true;
          });

          ProfileScreenLogger.logVideoLoadSuccess(
              count: preloadedVideos.length);
          return;
        }

        if (_stateManager.userVideos.isNotEmpty) {
          ProfileScreenLogger.logVideoLoadSuccess(
              count: _stateManager.userVideos.length);
          setState(() {
            _isVideosLoaded = true;
          });
          return;
        }

        print('📡 ProfileScreen: Loading videos from server...');
        await _stateManager.loadUserVideos(currentUserId);

        setState(() {
          _isVideosLoaded = true;
        });

        ProfileScreenLogger.logVideoLoadSuccess(
            count: _stateManager.userVideos.length);
      }
    } catch (e) {
      ProfileScreenLogger.logVideoLoadError(e.toString());
      setState(() {
        _isVideosLoaded = true;
      });
    }
  }

  Future<void> _loadFollowersProgressive() async {
    try {
      // Build candidate IDs: prefer googleId, then Mongo _id/id, then widget.userId
      final List<String> idsToTry = <String?>[
        _stateManager.userData?['googleId'],
        _stateManager.userData?['_id'] ?? _stateManager.userData?['id'],
        widget.userId,
      ]
          .where((e) => e != null && (e).isNotEmpty)
          .map((e) => e as String)
          .toList()
          .toSet()
          .toList();

      if (idsToTry.isEmpty) {
        ProfileScreenLogger.logWarning(
            'No user ID available for followers load');
        setState(() {
          _isFollowersLoaded = true;
        });
        return;
      }

      final userProvider = Provider.of<UserProvider>(context, listen: false);
      bool loadedAny = false;

      // **ENHANCED: Check cache first before making API calls**
      for (final candidateId in idsToTry) {
        final cachedUserData = userProvider.getUserData(candidateId);
        if (cachedUserData != null) {
          ProfileScreenLogger.logDebugInfo(
              'Using cached followers data for user: $candidateId');
          loadedAny = true;
          break;
        }
      }

      // Only make API calls if no cached data is available
      if (!loadedAny) {
        for (final candidateId in idsToTry) {
          try {
            ProfileScreenLogger.logDebugInfo(
                'Loading followers for user: $candidateId');
            await userProvider.getUserDataWithFollowers(candidateId);

            final model = userProvider.getUserData(candidateId);
            final followersCount = model?.followersCount ??
                (_stateManager.userData != null
                    ? (_stateManager.userData!['followers'] ??
                        _stateManager.userData!['followersCount'] ??
                        0)
                    : 0);
            if (model != null || followersCount > 0) {
              loadedAny = true;
              break;
            }
          } catch (e) {
            ProfileScreenLogger.logWarning(
                'Followers load failed for $candidateId: $e');
          }
        }
      }

      setState(() {
        _isFollowersLoaded = true;
      });

      if (!loadedAny) {
        ProfileScreenLogger.logWarning(
            'Followers data not found for any candidate ID');
      }
    } catch (e) {
      ProfileScreenLogger.logWarning('Followers load failed: $e');
      // Mark as loaded to avoid infinite loading
      setState(() {
        _isFollowersLoaded = true;
      });
    }
  }

  Future<void> _loadAdditionalUserData() async {
    try {
      if (widget.userId == null && _stateManager.userData != null) {
        final currentUserId =
            _stateManager.userData!['_id'] ?? _stateManager.userData!['id'];
        if (currentUserId != null) {
          final userProvider =
              Provider.of<UserProvider>(context, listen: false);
          await userProvider.getUserDataWithFollowers(currentUserId);
        }
      }
    } catch (e) {
      ProfileScreenLogger.logWarning('Additional user data load failed: $e');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stateManager.setContext(context);
  }

  @override
  void dispose() {
    _progressiveLoadTimer?.cancel();
    ProfileScreenLogger.logProfileScreenDispose();
    _stateManager.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  Future<void> _handleLogout() async {
    try {
      ProfileScreenLogger.logLogout();
      final prefs = await SharedPreferences.getInstance();

      // **FIX: Only remove session tokens, NOT payment data**
      await prefs.remove('jwt_token');
      await prefs.remove('fallback_user');

      // **DO NOT REMOVE payment data - it should persist across sessions**
      // await prefs.remove('has_payment_setup'); // REMOVED - keep this flag
      // await prefs.remove('payment_profile_cache'); // REMOVED - keep payment data

      // **ENHANCED: Clear profile cache on logout**
      await _clearProfileCache();

      await _stateManager.handleLogout();

      // **ENHANCED: Clear UserProvider cache**
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      userProvider.clearAllCaches();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Logged out successfully. Your payment details are saved.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
      ProfileScreenLogger.logLogoutSuccess();
    } catch (e) {
      ProfileScreenLogger.logLogoutError(e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error logging out: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    try {
      ProfileScreenLogger.logGoogleSignIn();
      final userData = await _stateManager.handleGoogleSignIn();
      if (userData != null) {
        _restartProgressiveLoading();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Signed in successfully!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
        ProfileScreenLogger.logGoogleSignInSuccess();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sign-in failed. Please try again.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      ProfileScreenLogger.logGoogleSignInError(e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error signing in: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _restartProgressiveLoading() {
    print('🔄 ProfileScreen: Restarting progressive loading (manual refresh)');

    setState(() {
      _isProfileDataLoaded = false;
      _isVideosLoaded = false;
      _isFollowersLoaded = false;
      _isLoading = true;
      _error = null;
      _currentLoadStep = 0;
      _authRetryAttempts = 0; // Reset auth retry attempts
    });

    // Clear all caches to force fresh data load
    _clearProfileCache();

    // **ENHANCED: Also trigger background preloading to refresh cache**
    final preloader = BackgroundProfilePreloader();
    preloader.clearCache(); // Clear old cache
    preloader.forcePreload(); // Trigger fresh preload

    _progressiveLoadTimer?.cancel();

    // **ENHANCED: Use the new enhanced loading approach**
    _startEnhancedLoading();
  }

  /// Share app referral message
  Future<void> _handleReferFriends() async {
    try {
      // Build a referral link with user code if available
      String base = 'https://snehayog.app';
      String referralCode = '';
      final userData = _stateManager.getUserData();
      final token = userData?['token'];
      if (token != null) {
        try {
          final uri = Uri.parse('${AppConfig.baseUrl}/api/referrals/code');
          final resp = await http.get(uri, headers: {
            'Authorization': 'Bearer $token',
          }).timeout(const Duration(seconds: 6));
          if (resp.statusCode == 200) {
            final data = json.decode(resp.body);
            referralCode = data['code'] ?? '';
          }
        } catch (_) {}
      }
      final String referralLink =
          referralCode.isNotEmpty ? '$base/?ref=$referralCode' : base;
      final String message =
          'I am using Snehayog! Refer 2 friends and get full access. Join now: $referralLink';
      await Share.share(
        message,
        subject: 'Snehayog – Refer 2 friends and get full access',
      );

      // Optimistically increment invite counter
      final prefs = await SharedPreferences.getInstance();
      _invitedCount = (prefs.getInt('referral_invite_count') ?? 0) + 1;
      await prefs.setInt('referral_invite_count', _invitedCount);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to share right now. Please try again.'),
          ),
        );
      }
    }
  }

  Future<void> _loadReferralStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _invitedCount = prefs.getInt('referral_invite_count') ?? 0;
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _fetchVerifiedReferralStats() async {
    try {
      final userData = _stateManager.getUserData();
      final token = userData?['token'];
      if (token == null) return;
      final uri = Uri.parse('${AppConfig.baseUrl}/api/referrals/stats');
      final resp = await http.get(uri, headers: {
        'Authorization': 'Bearer $token',
      }).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        _verifiedInstalled = data['installed'] ?? 0;
        _verifiedSignedUp = data['signedUp'] ?? 0;
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _handleEditProfile() async {
    ProfileScreenLogger.logProfileEditStart();
    _stateManager.startEditing();
  }

  Future<void> _handleSaveProfile() async {
    try {
      ProfileScreenLogger.logProfileEditSave();
      final newName = _stateManager.nameController.text.trim();
      if (newName.isEmpty) {
        throw 'Name cannot be empty';
      }

      await _stateManager.saveProfile();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
      ProfileScreenLogger.logProfileEditSaveSuccess();
    } catch (e) {
      ProfileScreenLogger.logProfileEditSaveError(e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleCancelEdit() async {
    ProfileScreenLogger.logProfileEditCancel();
    _stateManager.cancelEditing();
  }

  Future<void> _handleDeleteSelectedVideos() async {
    try {
      final initialCount = _stateManager.selectedVideoIds.length;
      ProfileScreenLogger.logVideoDeletion(count: initialCount);
      final shouldDelete = await _showDeleteConfirmationDialog();
      if (!shouldDelete) return;

      await _stateManager.deleteSelectedVideos();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$initialCount videos deleted successfully!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      ProfileScreenLogger.logVideoDeletionSuccess(count: initialCount);
    } catch (e) {
      ProfileScreenLogger.logVideoDeletionError(e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_stateManager.error ?? 'Failed to delete videos'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _handleDeleteSelectedVideos(),
            ),
          ),
        );
      }
    }
  }

  Future<bool> _showDeleteConfirmationDialog() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Icon with animated background
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.red.withOpacity(0.3),
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.delete_forever,
                        color: Colors.red,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Title
                    const Text(
                      'Delete Videos?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Description
                    Text(
                      'You are about to delete ${_stateManager.selectedVideoIds.length} video${_stateManager.selectedVideoIds.length == 1 ? '' : 's'}. This action cannot be undone.',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 16,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),

                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: Colors.grey.withOpacity(0.3),
                                ),
                              ),
                            ),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              elevation: 0,
                            ),
                            child: const Text(
                              'Delete',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ) ??
        false;
  }

  Future<void> _handleProfilePhotoChange() async {
    try {
      ProfileScreenLogger.logProfilePhotoChange();
      final XFile? image = await showDialog<XFile>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Change Profile Photo'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.camera_alt),
                  title: const Text('Take Photo'),
                  onTap: () async {
                    final XFile? photo = await _imagePicker.pickImage(
                        source: ImageSource.camera);
                    Navigator.pop(context, photo);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('Choose from Gallery'),
                  onTap: () async {
                    final XFile? photo = await _imagePicker.pickImage(
                        source: ImageSource.gallery);
                    Navigator.pop(context, photo);
                  },
                ),
              ],
            ),
          );
        },
      );

      if (image != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Uploading profile photo...'),
              duration: Duration(seconds: 1),
            ),
          );
        }

        await _stateManager.updateProfilePhoto(image.path);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile photo updated successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
        ProfileScreenLogger.logProfilePhotoChangeSuccess();
      }
    } catch (e) {
      ProfileScreenLogger.logProfilePhotoChangeError(e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error changing profile photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Show How to Earn guidance (same style as UploadScreen's What to Upload)
  void _showHowToEarnDialog() {
    ProfileDialogsWidget.showHowToEarnDialog(context);
  }

  Widget _buildSignInView() {
    return RepaintBoundary(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.account_circle,
                size: 100,
                color: Color(0xFF757575),
              ),
              const SizedBox(height: 20),
              const Text(
                'Sign in to view your profile',
                style: TextStyle(
                  fontSize: 20,
                  color: Color(0xFF424242),
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'You need to sign in with your Google account to access your profile, upload videos, and track your earnings.',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF757575),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _handleGoogleSignIn,
                icon: Image.network(
                  'https://www.google.com/favicon.ico',
                  height: 24,
                ),
                label: const Text('Sign in with Google'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[700],
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.grey[600]!),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ChangeNotifierProvider.value(
      value: _stateManager,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: _buildAppBar(),
        drawer: ProfileMenuWidget(
          stateManager: _stateManager,
          userId: widget.userId,
          onEditProfile: _handleEditProfile,
          onSaveProfile: _handleSaveProfile,
          onCancelEdit: _handleCancelEdit,
          onReportUser: () => _openReportDialog(
            targetType: 'user',
            targetId: widget.userId!,
          ),
          onShowFeedback: _showFeedbackDialog,
          onShowFAQ: _showFAQDialog,
          onEnterSelectionMode: () => _stateManager.enterSelectionMode(),
          onShowSettings: _showSettingsBottomSheet,
          onLogout: _handleLogout,
          onGoogleSignIn: _handleGoogleSignIn,
          onCheckPaymentSetupStatus: _checkPaymentSetupStatus,
        ),
        body: Consumer<UserProvider>(
          builder: (context, userProvider, child) {
            UserModel? userModel;
            if (widget.userId != null) {
              userModel = userProvider.getUserData(widget.userId!);
            }
            // Use the local _stateManager directly since it's not in Provider
            return _buildBody(userProvider, userModel);
          },
        ),
      ),
    );
  }

  Widget _buildBody(UserProvider userProvider, UserModel? userModel) {
    // Show loading indicator only for initial profile data
    if (_isLoading && !_isProfileDataLoaded) {
      return RepaintBoundary(
        child: _buildSkeletonLoading(),
      );
    }

    // Show error state
    if (_error != null) {
      if (_error == 'No authentication data found') {
        return _buildSignInView();
      }

      // Otherwise show error with retry
      return RepaintBoundary(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red[300],
                ),
                const SizedBox(height: 16),
                Text(
                  'Failed to load profile data',
                  style: TextStyle(
                    color: Colors.red[700],
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'You appear to be signed in, but we couldn\'t load your profile.',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // **AUTOMATIC: Auto-retry loading without manual buttons**
                TextButton.icon(
                  onPressed: _handleGoogleSignIn,
                  icon: const Icon(Icons.login),
                  label: const Text('Sign In Again'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.blue,
                  ),
                ),

                const SizedBox(height: 16),

                // **NEW: Debug information for troubleshooting**
                if (kDebugMode) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Debug Info:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text('Auth Retry Attempts: $_authRetryAttempts'),
                        Text('Profile Data Loaded: $_isProfileDataLoaded'),
                        Text('Videos Loaded: $_isVideosLoaded'),
                        Text('Followers Loaded: $_isFollowersLoaded'),
                        Text('Error: $_error'),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    // Check if we have user data
    if (_stateManager.userData == null) {
      return _buildSignInView();
    }

    // If we reach here, we have user data and can show the profile
    return RefreshIndicator(
      onRefresh: () async {
        _restartProgressiveLoading();
      },
      child: SingleChildScrollView(
        physics:
            const AlwaysScrollableScrollPhysics(), // Enable pull-to-refresh
        child: Column(
          children: [
            ProfileHeaderWidget(
              stateManager: _stateManager,
              userId: widget.userId,
              onEditProfile: _handleEditProfile,
              onSaveProfile: _handleSaveProfile,
              onCancelEdit: _handleCancelEdit,
              onProfilePhotoChange: _handleProfilePhotoChange,
              onShowHowToEarn: _showHowToEarnDialog,
            ),
            _buildProfileContent(userProvider, userModel),
            // Show loading indicators for progressive loading
            if (!_isVideosLoaded) _buildVideosLoadingIndicator(),
            if (!_isFollowersLoaded && _isVideosLoaded)
              _buildFollowersLoadingIndicator(),
          ],
        ),
      ),
    );
  }

  // **NEW: Skeleton loading for better UX**
  Widget _buildSkeletonLoading() {
    return RepaintBoundary(
      child: SingleChildScrollView(
        child: Column(
          children: [
            // Profile header skeleton
            RepaintBoundary(
              child: Container(
                padding: ResponsiveHelper.getAdaptivePadding(context),
                child: Column(
                  children: [
                    // Profile picture skeleton
                    Container(
                      width: ResponsiveHelper.isMobile(context) ? 100 : 150,
                      height: ResponsiveHelper.isMobile(context) ? 100 : 150,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Name skeleton
                    Container(
                      width: 200,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Edit button skeleton
                    Container(
                      width: 120,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Stats skeleton
            RepaintBoundary(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Color(0xFFE0E0E0)),
                    bottom: BorderSide(color: Color(0xFFE0E0E0)),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(
                      3,
                      (index) => Column(
                            children: [
                              Container(
                                width: 60,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.grey[300],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                width: 80,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: Colors.grey[300],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ],
                          )),
                ),
              ),
            ),

            // Videos section skeleton
            RepaintBoundary(
              child: Padding(
                padding: ResponsiveHelper.getAdaptivePadding(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title skeleton
                    Container(
                      width: 150,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Video grid skeleton
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount:
                            ResponsiveHelper.isMobile(context) ? 2 : 3,
                        crossAxisSpacing:
                            ResponsiveHelper.isMobile(context) ? 16 : 24,
                        mainAxisSpacing:
                            ResponsiveHelper.isMobile(context) ? 16 : 24,
                        childAspectRatio:
                            ResponsiveHelper.isMobile(context) ? 0.75 : 0.8,
                      ),
                      itemCount: 6,
                      itemBuilder: (context, index) => Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight + 10),
      child: Consumer<ProfileStateManager>(
        builder: (context, stateManager, child) {
          return AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            shadowColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            title: stateManager.isSelecting &&
                    stateManager.selectedVideoIds.isNotEmpty
                ? Text(
                    '${stateManager.selectedVideoIds.length} video${stateManager.selectedVideoIds.length == 1 ? '' : 's'} selected',
                    style: const TextStyle(
                      color: Color(0xFF1A1A1A),
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.5,
                    ),
                  )
                : Text(
                    stateManager.userData?['name'] ?? 'Profile',
                    style: const TextStyle(
                      color: Color(0xFF1A1A1A),
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
            leading: IconButton(
              icon: const Icon(Icons.menu, color: Color(0xFF1A1A1A), size: 24),
              tooltip: 'Menu',
              onPressed: () {
                _scaffoldKey.currentState?.openDrawer();
              },
            ),
            actions: [
              // Show delete icon when videos are selected
              if (stateManager.isSelecting &&
                  stateManager.selectedVideoIds.isNotEmpty) ...[
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.delete_forever,
                      color: Colors.red,
                      size: 24,
                    ),
                  ),
                  tooltip: 'Delete Selected Videos',
                  onPressed: _handleDeleteSelectedVideos,
                ),
                const SizedBox(width: 8),
              ],
              // Show cancel icon when in selection mode
              if (stateManager.isSelecting)
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.grey,
                      size: 24,
                    ),
                  ),
                  tooltip: 'Cancel Selection',
                  onPressed: () {
                    stateManager.exitSelectionMode();
                  },
                ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(
                height: 1,
                color: const Color(0xFFE5E7EB),
              ),
            ),
          );
        },
      ),
    );
  }

  /// **NEW: Professional Settings Bottom Sheet**
  void _showSettingsBottomSheet() {
    ProfileDialogsWidget.showSettingsBottomSheet(
      context,
      stateManager: _stateManager,
      checkPaymentSetupStatus: _checkPaymentSetupStatus,
    );
  }

  /// **NEW: Feedback Dialog**
  void _showFeedbackDialog() {
    ProfileDialogsWidget.showFeedbackDialog(context);
  }

  /// **NEW: Open Report Dialog**
  void _openReportDialog(
      {required String targetType, required String targetId}) {
    ProfileDialogsWidget.showReportDialog(
      context,
      targetType: targetType,
      targetId: targetId,
    );
  }

  /// **NEW: Show Professional FAQ Dialog**
  void _showFAQDialog() {
    ProfileDialogsWidget.showFAQDialog(context);
  }

  Widget _buildProfileContent(UserProvider userProvider, UserModel? userModel) {
    return RepaintBoundary(
      child: Column(
        children: [
          // Stats Section
          ProfileStatsWidget(
            stateManager: _stateManager,
            userId: widget.userId,
            isVideosLoaded: _isVideosLoaded,
            isFollowersLoaded: _isFollowersLoaded,
            onFollowersTap: () {
              // **NEW: Debug followers loading**
              ProfileScreenLogger.logDebugInfo('=== FOLLOWERS DEBUG ===');
              ProfileScreenLogger.logDebugInfo(
                  '_isFollowersLoaded: $_isFollowersLoaded');
              ProfileScreenLogger.logDebugInfo(
                  'widget.userId: ${widget.userId}');
              ProfileScreenLogger.logDebugInfo(
                  '_stateManager.userData: ${_stateManager.userData != null}');
              if (_stateManager.userData != null) {
                ProfileScreenLogger.logDebugInfo(
                    'Current user ID: ${_stateManager.userData!['_id'] ?? _stateManager.userData!['id']}');
              }

              // Show debug info
              if (mounted) {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Followers Debug Info'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Followers Loaded: $_isFollowersLoaded'),
                        Text('User ID: ${widget.userId ?? "Own Profile"}'),
                        Text('Followers Count: ${_getFollowersCount()}'),
                        Text(
                            'User Data Available: ${_stateManager.userData != null}'),
                        if (_stateManager.userData != null) ...[
                          Text(
                              'ObjectID: ${_stateManager.userData!['_id'] ?? "Not Set"}'),
                          Text(
                              'ID: ${_stateManager.userData!['id'] ?? "Not Set"}'),
                        ],
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          // Force reload followers
                          setState(() {
                            _isFollowersLoaded = false;
                          });
                          _loadFollowersProgressive();
                        },
                        child: const Text('Reload Followers'),
                      ),
                    ],
                  ),
                );
              }
            },
            onEarningsTap: () async {
              // Navigate directly to revenue screen
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CreatorRevenueScreen(),
                ),
              );
            },
          ),

          const SizedBox(height: 24),

          // Action Buttons Section
          RepaintBoundary(
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFF10B981), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: _handleReferFriends,
                      icon: const Icon(
                        Icons.share,
                        color: Color(0xFF10B981),
                        size: 20,
                      ),
                      label: const Text(
                        'Refer 2 friends and get full access',
                        style: TextStyle(
                          color: Color(0xFF10B981),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
                if (_invitedCount > 0 ||
                    _verifiedInstalled > 0 ||
                    _verifiedSignedUp > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Invited: $_invitedCount • Installed: $_verifiedInstalled • Signed up: $_verifiedSignedUp',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),

          // Videos Section
          ProfileVideosWidget(
            stateManager: _stateManager,
            isVideosLoaded: _isVideosLoaded,
          ),
        ],
      ),
    );
  }

  // **NEW: Helper method to get followers count using MongoDB ObjectID**
  int _getFollowersCount() {
    ProfileScreenLogger.logDebugInfo('=== GETTING FOLLOWERS COUNT ===');
    ProfileScreenLogger.logDebugInfo('widget.userId: ${widget.userId}');
    ProfileScreenLogger.logDebugInfo(
        '_stateManager.userData: ${_stateManager.userData != null}');

    // Build candidate IDs to query provider with
    final List<String> idsToTry = <String?>[
      widget.userId,
      _stateManager.userData?['googleId'],
      _stateManager.userData?['_id'] ?? _stateManager.userData?['id'],
    ]
        .where((e) => e != null && (e).isNotEmpty)
        .map((e) => e as String)
        .toList()
        .toSet()
        .toList();

    if (idsToTry.isNotEmpty) {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      for (final candidateId in idsToTry) {
        final userModel = userProvider.getUserData(candidateId);
        if (userModel?.followersCount != null) {
          ProfileScreenLogger.logDebugInfo(
              'Using followers count from UserProvider for $candidateId: ${userModel!.followersCount}');
          return userModel.followersCount;
        }
      }
    }

    // **NEW: Check if we're viewing own profile**
    if (widget.userId == null && _stateManager.userData != null) {
      ProfileScreenLogger.logDebugInfo('Viewing own profile');

      // Prefer counts available in userData
      final followersCount = _stateManager.userData!['followers'] ??
          _stateManager.userData!['followersCount'] ??
          0;
      if (followersCount != 0) {
        ProfileScreenLogger.logDebugInfo(
            'Using followers count from ProfileStateManager: $followersCount');
        return followersCount;
      }
    }

    // Fall back to ProfileStateManager data
    if (_stateManager.userData != null &&
        _stateManager.userData!['followersCount'] != null) {
      final followersCount = _stateManager.userData!['followersCount'];
      ProfileScreenLogger.logDebugInfo(
          'Using followers count from ProfileStateManager: $followersCount');
      return followersCount;
    }

    // Final fallback
    ProfileScreenLogger.logDebugInfo(
        'No followers count available, using default: 0');
    return 0;
  }

  Future<bool> _checkPaymentSetupStatus() async {
    try {
      // **FIX: Check user-specific flag first**
      ProfileScreenLogger.logPaymentSetupCheck();
      final prefs = await SharedPreferences.getInstance();

      // **FIX: Get user ID for user-specific check**
      final userData = _stateManager.getUserData();
      final userId = userData?['googleId'] ?? userData?['id'];

      // **FIX: Check user-specific flag first**
      if (userId != null) {
        final hasUserSpecificSetup =
            prefs.getBool('has_payment_setup_$userId') ?? false;
        if (hasUserSpecificSetup) {
          ProfileScreenLogger.logPaymentSetupFound();
          print('✅ User-specific payment setup found for user: $userId');
          return true;
        }
      }

      // **FALLBACK: Check global flag for backward compatibility**
      final hasPaymentSetup = prefs.getBool('has_payment_setup') ?? false;
      if (hasPaymentSetup) {
        ProfileScreenLogger.logPaymentSetupFound();
        print('✅ Global payment setup flag found');
        return true;
      }

      // **NEW: If no flag, try to load payment setup data from backend**
      if (_stateManager.userData != null &&
          _stateManager.userData!['_id'] != null) {
        ProfileScreenLogger.logDebugInfo(
            'No payment setup flag found, checking backend data...');
        final hasBackendSetup = await _checkBackendPaymentSetup();
        if (hasBackendSetup) {
          // **FIX: Set both user-specific and global flags**
          if (userId != null) {
            await prefs.setBool('has_payment_setup_$userId', true);
            print('✅ Set user-specific payment setup flag for user: $userId');
          }
          await prefs.setBool('has_payment_setup', true);
          ProfileScreenLogger.logPaymentSetupFound();
          return true;
        }
      }

      ProfileScreenLogger.logPaymentSetupNotFound();
      print('ℹ️ No payment setup found for user');
      return false;
    } catch (e) {
      ProfileScreenLogger.logPaymentSetupCheckError(e.toString());
      return false;
    }
  }

  /// **FIX: Sync user-specific payment setup flag from backend**
  Future<void> _ensurePaymentSetupFlag() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userData = _stateManager.getUserData();
      final userId = userData?['googleId'] ?? userData?['id'];

      // **FIX: Check user-specific flag**
      if (userId != null) {
        final already = prefs.getBool('has_payment_setup_$userId') ?? false;
        if (already) {
          print(
              '✅ User-specific payment setup flag already exists for user: $userId');
          return;
        }
      }

      if (_stateManager.userData != null &&
          _stateManager.userData!['_id'] != null) {
        final backendHas = await _checkBackendPaymentSetup();
        if (backendHas) {
          // **FIX: Set both user-specific and global flags**
          if (userId != null) {
            await prefs.setBool('has_payment_setup_$userId', true);
            print('✅ Set user-specific payment setup flag for user: $userId');
          }
          await prefs.setBool('has_payment_setup', true);
          ProfileScreenLogger.logPaymentSetupFound();
        }
      }
    } catch (e) {
      ProfileScreenLogger.logWarning('ensurePaymentSetupFlag failed: $e');
    }
  }

  // **NEW: Method to check payment setup from backend**
  Future<bool> _checkBackendPaymentSetup() async {
    try {
      ProfileScreenLogger.logDebugInfo(
          'Starting backend payment setup check...');
      final userData = _stateManager.getUserData();
      final token = userData?['token'];

      if (token == null) {
        ProfileScreenLogger.logError(
            'No token available for backend payment setup check');
        return false;
      }

      ProfileScreenLogger.logApiCall(
          endpoint: 'creator-payouts/profile', method: 'GET');
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/creator-payouts/profile'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      ProfileScreenLogger.logApiResponse(
        endpoint: 'creator-payouts/profile',
        statusCode: response.statusCode,
        body: response.body,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final paymentMethod = data['creator']?['preferredPaymentMethod'];
        final paymentDetails = data['paymentDetails'];

        ProfileScreenLogger.logDebugInfo('Payment method: $paymentMethod');
        ProfileScreenLogger.logDebugInfo('Payment details: $paymentDetails');

        // Check if user has completed payment setup
        if (paymentMethod != null &&
            paymentMethod.isNotEmpty &&
            paymentDetails != null) {
          ProfileScreenLogger.logPaymentSetupFound(method: paymentMethod);
          return true;
        } else {
          ProfileScreenLogger.logDebugWarning(
              'Payment setup incomplete - method: $paymentMethod, details: $paymentDetails');
        }
      } else {
        ProfileScreenLogger.logApiError(
          endpoint: 'creator-payouts/profile',
          error: 'API call failed with status ${response.statusCode}',
        );
      }

      return false;
    } catch (e) {
      ProfileScreenLogger.logApiError(
        endpoint: 'creator-payouts/profile',
        error: e.toString(),
      );
      return false;
    }
  }

  Widget _buildFollowersLoadingIndicator() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(
            'Loading followers data...',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideosLoadingIndicator() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(
            'Loading videos...',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  // **NEW: Enhanced caching methods for profile data**

  /// Load cached profile data from SharedPreferences
  Future<Map<String, dynamic>?> _loadCachedProfileData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _getProfileCacheKey();
      final cachedDataJson = prefs.getString('profile_cache_$cacheKey');
      final cacheTimestamp = prefs.getInt('profile_cache_timestamp_$cacheKey');

      if (cachedDataJson != null && cacheTimestamp != null) {
        final cacheAge = DateTime.now().millisecondsSinceEpoch - cacheTimestamp;
        const maxCacheAge = 30 * 60 * 1000; // 30 minutes in milliseconds

        if (cacheAge < maxCacheAge) {
          ProfileScreenLogger.logDebugInfo(
              'Loading profile from SharedPreferences cache');
          return Map<String, dynamic>.from(json.decode(cachedDataJson));
        } else {
          ProfileScreenLogger.logDebugInfo(
              'Profile cache expired, removing stale data');
          await _clearProfileCache();
        }
      }
    } catch (e) {
      ProfileScreenLogger.logWarning('Error loading cached profile data: $e');
    }
    return null;
  }

  /// Cache profile data to SharedPreferences
  Future<void> _cacheProfileData(Map<String, dynamic> profileData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _getProfileCacheKey();

      await prefs.setString(
          'profile_cache_$cacheKey', json.encode(profileData));
      await prefs.setInt('profile_cache_timestamp_$cacheKey',
          DateTime.now().millisecondsSinceEpoch);

      ProfileScreenLogger.logDebugInfo(
          'Profile data cached to SharedPreferences');
    } catch (e) {
      ProfileScreenLogger.logWarning('Error caching profile data: $e');
    }
  }

  /// Get cache key for current profile
  String _getProfileCacheKey() {
    if (widget.userId != null) {
      return widget.userId!;
    }
    // For own profile, use a consistent key
    return 'own_profile';
  }

  /// Clear profile cache
  Future<void> _clearProfileCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _getProfileCacheKey();

      await prefs.remove('profile_cache_$cacheKey');
      await prefs.remove('profile_cache_timestamp_$cacheKey');

      ProfileScreenLogger.logDebugInfo('Profile cache cleared');
    } catch (e) {
      ProfileScreenLogger.logWarning('Error clearing profile cache: $e');
    }
  }

  /// Schedule background refresh if cache is getting stale
  void _scheduleBackgroundProfileRefresh() {
    // Only refresh if cache is older than 15 minutes
    Timer(const Duration(seconds: 5), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final cacheKey = _getProfileCacheKey();
        final cacheTimestamp =
            prefs.getInt('profile_cache_timestamp_$cacheKey');

        if (cacheTimestamp != null) {
          final cacheAge =
              DateTime.now().millisecondsSinceEpoch - cacheTimestamp;
          const staleThreshold = 15 * 60 * 1000; // 15 minutes in milliseconds

          if (cacheAge > staleThreshold) {
            ProfileScreenLogger.logDebugInfo(
                'Background refreshing stale profile data');
            await _stateManager.loadUserData(widget.userId);

            if (_stateManager.userData != null) {
              await _cacheProfileData(_stateManager.userData!);
            }
          }
        }
      } catch (e) {
        ProfileScreenLogger.logWarning('Background profile refresh failed: $e');
      }
    });
  }
}
