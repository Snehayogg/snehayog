import 'package:flutter/material.dart';
import 'package:vayu/utils/responsive_helper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io'; // Added for File
import 'package:vayu/config/app_config.dart';
import 'package:vayu/core/managers/profile_state_manager.dart';
import 'package:vayu/core/managers/smart_cache_manager.dart';
import 'package:provider/provider.dart';
import 'package:vayu/core/providers/user_provider.dart';
import 'package:vayu/model/usermodel.dart';
import 'package:vayu/core/services/profile_screen_logger.dart';
import 'dart:async';
import 'package:share_plus/share_plus.dart';
import 'package:vayu/features/profile/data/datasources/profile_local_datasource.dart';
import 'package:vayu/core/services/http_client_service.dart';
// Removed ProfileHeaderWidget and ProfileStatsWidget imports
import 'package:vayu/view/widget/profile/profile_videos_widget.dart';
import 'package:vayu/view/widget/profile/profile_menu_widget.dart';
import 'package:vayu/view/widget/profile/profile_dialogs_widget.dart';
import 'package:vayu/view/widget/profile/top_earners_grid.dart';
import 'package:vayu/controller/main_controller.dart';
import 'package:vayu/core/managers/shared_video_controller_pool.dart';
import 'package:vayu/utils/app_logger.dart';
import 'package:vayu/controller/google_sign_in_controller.dart';
import 'package:vayu/services/logout_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vayu/services/ad_service.dart';
import 'package:vayu/services/authservices.dart';
import 'package:vayu/view/search/video_creator_search_delegate.dart';
import 'package:vayu/model/video_model.dart';
import 'package:vayu/view/screens/creator_revenue_screen.dart';
import 'package:vayu/utils/app_text.dart';
import 'package:vayu/view/widget/ads/google_admob_banner_widget.dart';
import 'package:vayu/services/video_cache_proxy_service.dart';

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
  static final Uri _whatsAppGroupUri =
      Uri.parse('https://chat.whatsapp.com/H7eU5xnwm3r2dfpvi7hCJC');

  late final ProfileStateManager _stateManager;
  final ImagePicker _imagePicker = ImagePicker();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AdService _adService = AdService();
  final AuthService _authService = AuthService();

  // **OPTIMIZED: Use ValueNotifiers for granular updates**
  final ValueNotifier<bool> _isLoading = ValueNotifier<bool>(true);
  final ValueNotifier<String?> _error = ValueNotifier<String?>(null);

  // Referral tracking
  final ValueNotifier<int> _invitedCount = ValueNotifier<int>(0);
  final ValueNotifier<int> _verifiedInstalled = ValueNotifier<int>(0);
  final ValueNotifier<int> _verifiedSignedUp = ValueNotifier<int>(0);

  // Local tab state for content section
  // 0 => Your Videos, 1 => Top Earners / Recommendations
  final ValueNotifier<int> _activeProfileTabIndex = ValueNotifier<int>(0);

  // UPI ID status tracking
  final ValueNotifier<bool> _hasUpiId = ValueNotifier<bool>(
      false); // Default to false - show notice until confirmed
  final ValueNotifier<bool> _isCheckingUpiId = ValueNotifier<bool>(false);

  // Removed _earningsRefreshCounter as it is unused

  // **NEW: Track if videos have been loaded/checked for this profile session**
  // This prevents reloading when creator has no videos
  bool _videosLoadAttempted = false;
  String? _lastLoadedUserId; // Track which user's videos we've loaded

  @override

  void initState() {
    super.initState();
    ProfileScreenLogger.logProfileScreenInit();
    _stateManager = ProfileStateManager();
    _stateManager.setContext(context);

    // Ensure context is set early for providers that may be used during loads
    // It will be set again in didChangeDependencies
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _stateManager.setContext(context);
        // **FIX: Ensure data loads on first attempt even if cache fails**
        // Call _loadData() in postFrameCallback to ensure context is ready
        if (_stateManager.userData == null) {
          _loadData();
        }
      }
    });

    // **FIX: Always attempt initial load, even if cache exists**
    // This ensures data loads on first attempt
    _loadData();
    // Load referral stats
    _loadReferralStats();
    _fetchVerifiedReferralStats();

    // **NEW: Rebuild profile slivers when tab changes**
    _activeProfileTabIndex.addListener(() {
      if (mounted) setState(() {});
    });
  }

  /// **PUBLIC METHOD: Called when Profile tab is selected**
  /// **OPTIMIZED: Only load if data is missing - don't reload on every tab switch**
  /// **FIXED: Don't reload if creator has no videos - only load once per session**
  void onProfileTabSelected() {
    AppLogger.log(
        '🔄 ProfileScreen: Profile tab selected, checking if data needs loading');

    // Get current user ID
    final currentUserId = widget.userId ??
        _stateManager.userData?['googleId'] ??
        _stateManager.userData?['id'];

    // **FIXED: Reset load attempt flag if user changed**
    if (currentUserId != null && currentUserId != _lastLoadedUserId) {
      _videosLoadAttempted = false;
      _lastLoadedUserId = currentUserId;
      AppLogger.log(
          '🔄 ProfileScreen: User changed, resetting videos load attempt flag');
    }

    // **OPTIMIZED: Only load if data is completely missing - don't reload if already loaded**
    if (_stateManager.userData == null) {
      AppLogger.log(
          '📡 ProfileScreen: No user data found, loading from cache or server');
      _loadData(); // This will use cache if available, only fetch from server if no cache
    } else if (!_videosLoadAttempted &&
        _stateManager.userVideos.isEmpty &&
        !_stateManager.isVideosLoading) {
      // **FIXED: Only load videos if we haven't attempted before**
      // This prevents reloading when creator has no videos
      AppLogger.log(
          '🔄 ProfileScreen: User data exists but videos not loaded yet, loading videos once...');
      _videosLoadAttempted = true; // Mark as attempted
      _loadVideos().catchError((e) {
        AppLogger.log('⚠️ ProfileScreen: Error loading videos: $e');
        _videosLoadAttempted = false; // Reset on error so we can retry
      });
    } else {
      AppLogger.log(
          '✅ ProfileScreen: Data already loaded - no reload needed (using cache/memory)');
      if (_videosLoadAttempted && _stateManager.userVideos.isEmpty) {
        AppLogger.log(
            'ℹ️ ProfileScreen: Videos already checked - creator has no videos (not reloading)');
      }
      // **OPTIMIZED: Don't reload if data is already available - just use cached data**
    }
  }

  /// **ENHANCED: Instant cache-first loading - show cached data immediately, refresh in background**
  /// **CRITICAL: When forceRefresh=true, COMPLETELY bypass cache and fetch fresh data from server**
  Future<void> _loadData({bool forceRefresh = false}) async {
    try {
      AppLogger.log(
          '🔄 ProfileScreen: Starting data loading (forceRefresh: $forceRefresh)');

      // **CRITICAL: If forceRefresh=true, SKIP ALL cache checks and go directly to server**
      // This ensures manual refresh ALWAYS shows latest data, never cached data
      if (forceRefresh) {
        AppLogger.log(
            '🔄 ProfileScreen: FORCE REFRESH - bypassing ALL cache, fetching fresh data from server');
        // Skip to Step 2 - load directly from server
      } else {
        // Step 1: Try cache first (only when NOT forcing refresh)
        final cachedData = await _loadCachedProfileData();
        if (cachedData != null) {
          AppLogger.log(
              '⚡ ProfileScreen: Using cached data (INSTANT - no server fetch, cache persists when user navigates back)');

          // **INSTANT: Show cached data immediately (no loading state)**
          _stateManager.setUserData(cachedData);

          // **OPTIMIZATION: Also load cached videos immediately**
          await _loadVideosFromCache(); // This will load from SmartCacheManager via ProfileStateManager
          _isLoading.value = false; // Hide loading after videos are loaded

          // **NEW: Check UPI ID status after cached data is loaded (only for own profile)**
          if (widget.userId == null) {
            _checkUpiIdStatus();
          }

          // **FIXED: If no videos in cache for creator profiles, load from server**
          if (widget.userId != null && _stateManager.userVideos.isEmpty) {
            AppLogger.log(
                '🔄 ProfileScreen: No cached videos for creator profile, loading from server');
            _loadVideos().catchError((e) {
              AppLogger.log(
                  '⚠️ ProfileScreen: Error loading videos for creator profile: $e');
            });
          }

          // **OPTIMIZATION: Always refresh in background for fresh data**
          // SmartCacheManager handles cache expiry, so we refresh to ensure fresh data
          bool shouldRefresh = true;
          AppLogger.log(
              '🔄 ProfileScreen: Will refresh in background to ensure fresh data (cache already shown)');

          if (shouldRefresh) {
            // **BACKGROUND: Refresh in background (non-blocking)**
            Future.microtask(() async {
              try {
                AppLogger.log('🔄 ProfileScreen: Background refresh started');
                // Determine userId to use
                final userIdForRefresh = widget.userId;

                // 1. Refresh user profile data (force refresh, silent)
                await _stateManager.loadUserData(
                  userIdForRefresh,
                  forceRefresh: true,
                  silent: true,
                );

                // 2. Refresh videos (force refresh, silent)
                if (mounted) {
                  await _loadVideos(forceRefresh: true, silent: true);
                }

                // 3. Refresh earnings
                if (mounted) {
                  await _refreshEarningsData(forceRefresh: true);
                }
                AppLogger.log(
                    '✅ ProfileScreen: Background refresh completed');
              } catch (e) {
                AppLogger.log('⚠️ ProfileScreen: Background refresh failed: $e');
                // **FIX: Show error to user with retry option**
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${AppText.get('error_refresh')}: ${_getUserFriendlyError(e)}',
                      ),
                      backgroundColor: Colors.orange,
                      duration: const Duration(seconds: 4),
                      action: SnackBarAction(
                        label: AppText.get('btn_retry', fallback: 'Retry'),
                        textColor: Colors.white,
                        onPressed: () => _loadData(forceRefresh: true),
                      ),
                    ),
                  );
                }
              }
            });
          }

          return; // Exit early - user sees cached data instantly
        }
      }

      // Step 2: No cache or force refresh - load from server with retry
      // **CRITICAL: When forceRefresh=true, we ALWAYS reach here and fetch from server**
      _isLoading.value = true;
      _error.value = null;

      AppLogger.log(
          '📡 ProfileScreen: ${forceRefresh ? "FORCE REFRESH - fetching fresh data from server (NO CACHE)" : "No cache, loading from server"}');

      // **FIX: Load with retry mechanism**
      await _loadDataWithRetry(forceRefresh: forceRefresh);
    } catch (e) {
      AppLogger.log('❌ ProfileScreen: Error loading data: $e');
      // **BATCHED UPDATE: Update error and loading together**
      _error.value = e.toString();
      _isLoading.value = false;
    }
  }

  /// **NEW: Load data with retry mechanism**
  /// **CRITICAL: When forceRefresh=true, NEVER use cache, ALWAYS fetch from server**
  Future<void> _loadDataWithRetry(
      {bool forceRefresh = false, int maxRetries = 3}) async {
    int retryCount = 0;

    while (retryCount <= maxRetries) {
      try {
        AppLogger.log(
            '📡 ProfileScreen: Loading data (attempt ${retryCount + 1}/${maxRetries + 1}) for ${widget.userId != null ? "creator" : "own"} profile (forceRefresh: $forceRefresh)');

        // **CRITICAL: When forceRefresh=true, loadUserData MUST bypass cache internally**
        // Start loading profile data with timeout
        // **FIXED: Longer timeout for creator profiles (20s) vs own profile (15s)**
        final timeoutDuration = widget.userId != null
            ? const Duration(seconds: 20)
            : const Duration(seconds: 15);

        await _stateManager
            .loadUserData(widget.userId, forceRefresh: forceRefresh)
            .timeout(
          timeoutDuration,
          onTimeout: () {
            throw Exception('Request timed out. Please check your connection.');
          },
        );

        if (_stateManager.userData != null) {
          // **CRITICAL: NEVER cache during force refresh - we want fresh data shown immediately**
          // Only cache after displaying fresh data (see line 344-348)
          if (!forceRefresh) {
            await _cacheProfileData(_stateManager.userData!);
          }

          // **FIXED: For creator profiles, use widget.userId directly; for own profile, extract from userData**
          final currentUserId = widget.userId ??
              _stateManager.userData!['googleId'] ??
              _stateManager.userData!['_id'] ??
              _stateManager.userData!['id'];

          if (currentUserId != null) {
            // **CRITICAL: When forceRefresh=true, videos MUST also bypass cache**
            // Load videos with forceRefresh flag to ensure fresh data from server
            if (forceRefresh) {
              // **CRITICAL: During force refresh, wait for videos to load before hiding loading state**
              // This ensures user sees complete fresh data, not partial cached data
              await _loadVideos(forceRefresh: true);
              // **FIX: Hide loading only after videos are loaded during force refresh**
              _isLoading.value = false;
            } else {
              // **OPTIMIZATION: Hide loading state as soon as profile data is ready**
              // Videos will continue loading in background and update UI when ready
              _isLoading.value = false;

              // **OPTIMIZATION: Load videos in background without blocking UI (normal load)**
              _loadVideos(forceRefresh: false).catchError((e) {
                AppLogger.log(
                    '⚠️ ProfileScreen: Error loading videos in background: $e');
                // **FIX: Show error for video loading failures**
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          '${AppText.get('error_videos_load')}: ${_getUserFriendlyError(e)}'),
                      backgroundColor: Colors.orange,
                      duration: const Duration(seconds: 3),
                      action: SnackBarAction(
                        label: AppText.get('btn_retry', fallback: 'Retry'),
                        textColor: Colors.white,
                        onPressed: () => _loadVideos(forceRefresh: true),
                      ),
                    ),
                  );
                }
              });
            }

            // **NEW: Check UPI ID status after user data is loaded (only for own profile)**
            if (widget.userId == null) {
              _checkUpiIdStatus();
            }

            // **FAST: Load earnings in parallel (non-blocking)**
            _refreshEarningsData(forceRefresh: forceRefresh).catchError((e) {
              // Silent fail - earnings are optional
            });

            // **CRITICAL: After successful force refresh, cache the fresh data for next time**
            // This caches AFTER displaying fresh data to user, so next load can use cache
            if (forceRefresh) {
              await _cacheProfileData(_stateManager.userData!);
              AppLogger.log(
                  '✅ ProfileScreen: Fresh profile data cached after force refresh (data already shown to user)');
            }

            AppLogger.log(
                '✅ ProfileScreen: Profile data loaded, videos and earnings loading in background');
            return; // Success - exit retry loop
          } else {
            // If no user ID, wait for videos anyway (fallback)
            try {
              await _loadVideos(forceRefresh: forceRefresh);
            } catch (e) {
              AppLogger.log(
                  '⚠️ ProfileScreen: Error loading videos during retry sequence: $e');
              // Don't fail the whole profile load if only videos fail
              // The user will see the profile header and can retry loading videos
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        '${AppText.get('error_videos_load')}: ${_getUserFriendlyError(e)}'),
                    backgroundColor: Colors.orange,
                    duration: const Duration(seconds: 3),
                    action: SnackBarAction(
                      label: AppText.get('btn_retry', fallback: 'Retry'),
                      textColor: Colors.white,
                      onPressed: () => _loadVideos(forceRefresh: true),
                    ),
                  ),
                );
              }
            }
            _isLoading.value = false;
            return; // Success - exit retry loop
          }
        } else {
          // **FIX: Better error message for null data**
          throw Exception('Server returned empty profile data');
        }
      } catch (e) {
        retryCount++;
        AppLogger.log(
            '❌ ProfileScreen: Error loading data (attempt $retryCount): $e');

        if (retryCount > maxRetries) {
          // Max retries reached - show error
          _error.value = _getUserFriendlyError(e);
          _isLoading.value = false;
          AppLogger.log('❌ ProfileScreen: Max retries reached, showing error');
        } else {
          // **FIXED: Exponential backoff for retries (1s, 2s, 4s)**
          final delaySeconds = retryCount; // 1, 2, 4 seconds
          AppLogger.log(
              '🔄 ProfileScreen: Retrying in $delaySeconds second(s)...');
          await Future.delayed(Duration(seconds: delaySeconds));
        }
      }
    }
  }

  /// **NEW: Get user-friendly error message**
  String _getUserFriendlyError(dynamic error) {
    final errorString = error.toString().toLowerCase();

    if (errorString.contains('timeout') || errorString.contains('timed out')) {
      return 'Request timed out. Please check your connection and try again.';
    } else if (errorString.contains('network') ||
        errorString.contains('socket')) {
      return 'Network error. Please check your internet connection.';
    } else if (errorString.contains('unauthorized') ||
        errorString.contains('401')) {
      return AppText.get('error_sign_in_again');
    } else if (errorString.contains('not found') ||
        errorString.contains('404')) {
      return AppText.get('error_profile_not_found');
    } else if (errorString.contains('server') || errorString.contains('500')) {
      return AppText.get('error_server');
    } else {
      return AppText.get('error_load_profile_generic');
    }
  }

  /// **ENHANCED: Load videos from cache - use cache if exists, only fetch from server if no cache**
  Future<void> _loadVideosFromCache() async {
    // **SIMPLIFIED: Always load videos via ProfileStateManager logic**
    // Local SharedPreferences video cache is no longer used.
    AppLogger.log(
        'ℹ️ ProfileScreen: _loadVideosFromCache -> delegating to _loadVideos()');
    await _loadVideos();
  }

  /// **OPTIMIZED: Load videos from server (can run in background)**
  /// **CRITICAL: When forceRefresh=true, COMPLETELY bypass cache and fetch fresh data from server**
  Future<void> _loadVideos(
      {bool forceRefresh = false, bool silent = false}) async {
    try {
      // **FIX: Better handling of null userData with retry**
      if (_stateManager.userData == null) {
        AppLogger.log('⚠️ ProfileScreen: User data not ready, waiting...');
        // Wait with exponential backoff
        for (int i = 0; i < 5; i++) {
          await Future.delayed(Duration(milliseconds: 200 * (i + 1)));
          if (_stateManager.userData != null) {
            break;
          }
        }

        if (_stateManager.userData == null) {
          AppLogger.log(
              '⚠️ ProfileScreen: User data still not ready after waiting, skipping video load');
          // **FIX: Show error instead of silently failing**
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppText.get('error_load_videos')),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 3),
              ),
            );
          }
          return;
        }
      }

      // **FIXED: Prioritize googleId, then id (which contains googleId from backend), then fallback**
      // When viewing another creator, ensure we use the correct googleId for the video endpoint
      final currentUserId = _stateManager.userData!['googleId'] ??
          _stateManager.userData!['id'] ?? // Backend returns id: user.googleId
          _stateManager.userData!['_id'];

      // **FIX: If viewing another creator and widget.userId is provided, use it as fallback**
      // This ensures we use the correct ID format when userData might not have googleId set correctly
      final userIdForVideos = currentUserId ?? widget.userId;

      if (userIdForVideos != null) {
        AppLogger.log(
            '🔄 ProfileScreen: Loading videos for $userIdForVideos (force: $forceRefresh, silent: $silent)');
        await _stateManager
            .loadUserVideos(userIdForVideos,
                forceRefresh: forceRefresh, silent: silent)
            .timeout(const Duration(seconds: 30));

        // **FIXED: Mark videos as loaded/attempted after successful load**
        // This prevents reloading when creator has no videos
        _videosLoadAttempted = true;
        if (userIdForVideos != null) {
          _lastLoadedUserId = userIdForVideos;
        }

        AppLogger.log(
            '✅ ProfileScreen: Loaded ${_stateManager.userVideos.length} videos${forceRefresh ? " (fresh from server, not cache)" : ""}');
            
        // **NEW: AGGRESSIVE BACKGROUND LOAD - Load all remaining videos**
        // This ensures the user sees a complete grid quickly without manually scrolling/waiting.
        if (_stateManager.hasMoreVideos && !_stateManager.isFetchingMore) {
           AppLogger.log('🚀 ProfileScreen: Triggering AGGRESSIVE background load for ALL remaining videos...');
           _stateManager.loadAllVideosInBackground(userIdForVideos).catchError((e) {
             AppLogger.log('⚠️ ProfileScreen: Background load all failed: $e');
           });
        }
      }
    } catch (e) {
      AppLogger.log('❌ ProfileScreen: Error loading videos: $e');
      // **FIXED: Reset load attempt flag on error so we can retry**
      _videosLoadAttempted = false;
      // **FIX: Re-throw error so it can be caught and shown to user**
      rethrow;
    }
  }

  /// **ENHANCED: Manual refresh - clear cache and fetch fresh data from server**
  /// **CRITICAL: When user manually refreshes, ALWAYS show latest data from server, NEVER use cache**
  Future<void> _refreshData() async {
    AppLogger.log(
        '🔄 ProfileScreen: Manual refresh - clearing ALL caches and fetching fresh data from server (NO CACHE WILL BE USED)');

    // **FIXED: Reset videos load attempt flag on manual refresh**
    // This allows videos to be reloaded even if they were empty before
    _videosLoadAttempted = false;
    AppLogger.log(
        '🔄 ProfileScreen: Manual refresh - resetting videos load attempt flag');

    try {
      // **CRITICAL: Clear ALL caches first - profile cache, video cache, and SmartCache**
      // This ensures no cached data can leak through during manual refresh
      await _clearProfileCache();

      // **NEW: Clear SmartCache for videos before refresh**
      try {
        final smartCache = SmartCacheManager();
        await smartCache.initialize();
        if (smartCache.isInitialized) {
          // Clear video cache for current user
          final currentUserId = widget.userId ??
              _stateManager.userData?['googleId'] ??
              _stateManager.userData?['id'];

          if (currentUserId != null) {
            final videoCacheKey = 'video_profile_$currentUserId';
            await smartCache.clearCacheByPattern(videoCacheKey);
            AppLogger.log(
                '🧹 ProfileScreen: Cleared SmartCache video cache: $videoCacheKey');
          }

          // Also clear profile cache from SmartCache
          if (currentUserId != null) {
            final profileCacheKey = 'user_profile_$currentUserId';
            await smartCache.clearCacheByPattern(profileCacheKey);
            AppLogger.log(
                '🧹 ProfileScreen: Cleared SmartCache profile cache: $profileCacheKey');
          }
        }
      } catch (e) {
        AppLogger.log(
            '⚠️ ProfileScreen: Error clearing SmartCache during refresh: $e');
        // Continue with refresh even if SmartCache clearing fails
      }

      // **CRITICAL: Set loading state BEFORE fetching - user should see loading indicator**
      _isLoading.value = true;
      _error.value = null;

      // **CRITICAL: Force refresh user data - this COMPLETELY bypasses cache**
      // forceRefresh: true ensures _loadData() skips ALL cache checks
      await _loadData(forceRefresh: true);

      // **CRITICAL: Explicitly reload videos with forceRefresh AFTER user data is loaded**
      // This ensures videos are also fetched fresh from server, not from cache
      if (_stateManager.userData != null) {
        final currentUserId = _stateManager.userData!['googleId'] ??
            _stateManager.userData!['_id'] ??
            _stateManager.userData!['id'];

        if (currentUserId != null) {
          AppLogger.log(
              '🔄 ProfileScreen: Force refreshing videos for user: $currentUserId (bypassing ALL caches - fetching from server)');

          // **CRITICAL: Force refresh videos - this bypasses cache and fetches fresh data**
          await _loadVideos(forceRefresh: true);

          AppLogger.log(
              '✅ ProfileScreen: Refreshed ${_stateManager.userVideos.length} videos from server (fresh data, not cache)');
        }
      }

      // **FAST: Refresh earnings after manual refresh**
      _refreshEarningsData(forceRefresh: true).catchError((e) {
        // Silent fail
      });

      _isLoading.value = false;
      AppLogger.log(
          '✅ ProfileScreen: Manual refresh completed - ALL data fetched fresh from server (NO CACHE USED)');
    } catch (e) {
      AppLogger.log('❌ ProfileScreen: Error during refresh: $e');
      _error.value = '${AppText.get('error_refresh')}: ${e.toString()}';
      _isLoading.value = false;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stateManager.setContext(context);

    // **DISABLED: Preload profile videos to prevent video playback conflicts**
    // _preloadProfileVideos();
  }

  /// **DISABLED: Preload profile videos to prevent video playback conflicts**
  // Future<void> _preloadProfileVideos() async {
  //   // Only preload if videos are loaded and not already preloading
  //   if (_stateManager.userVideos.isEmpty) {
  //     return;
  //   }

  //   // Get shared pool
  //   final sharedPool = SharedVideoControllerPool();

  //   // Check which videos are already loaded
  //   final videosToPreload = <VideoModel>[];
  //   for (final video in _stateManager.userVideos.take(3)) {
  //     if (!sharedPool.isVideoLoaded(video.id)) {
  //       videosToPreload.add(video);
  //     }
  //   }

  //   if (videosToPreload.isEmpty) {
  //     print('✅ ProfileScreen: All profile videos already preloaded');
  //     return;
  //   }

  //   print(
  //       '🚀 ProfileScreen: Preloading ${videosToPreload.length} profile videos in background...');

  //   // Preload videos in background
  //   Future.microtask(() async {
  //     for (final video in videosToPreload) {
  //       try {
  //         await _preloadVideo(video);
  //         print('✅ ProfileScreen: Preloaded video: ${video.videoName}');
  //       } catch (e) {
  //         print(
  //             '⚠️ ProfileScreen: Failed to preload video ${video.videoName}: $e');
  //       }
  //     }

  //     print('✅ ProfileScreen: Profile video preloading completed');
  //     sharedPool.printStatus();
  //   });
  // }

  /// **DISABLED: PRELOAD SINGLE VIDEO: Helper method to preload a video**
  // Future<void> _preloadVideo(VideoModel video) async {
  //   try {
  //     // **CHECK: Skip if video is already loaded in shared pool**
  //     final sharedPool = SharedVideoControllerPool();
  //     if (sharedPool.isVideoLoaded(video.id)) {
  //       print(
  //           '✅ ProfileScreen: Video already loaded, skipping: ${video.videoName}');
  //       return;
  //     }

  //     // Get video URL
  //     String? videoUrl;

  //     // Resolve playable URL
  //     if (video.hlsPlaylistUrl?.isNotEmpty == true) {
  //       videoUrl = video.hlsPlaylistUrl;
  //     } else if (video.videoUrl.contains('.m3u8') ||
  //         video.videoUrl.contains('.mp4')) {
  //       videoUrl = video.videoUrl;
  //     } else {
  //       // Skip if URL is not valid
  //       print('⚠️ ProfileScreen: Invalid video URL for ${video.videoName}');
  //       return;
  //     }

  //     if (videoUrl == null || videoUrl.isEmpty) {
  //       print('⚠️ ProfileScreen: Empty video URL for ${video.videoName}');
  //       return;
  //     }

  //     print(
  //         '🎬 ProfileScreen: Initializing controller for video: ${video.videoName}');

  //     // **HLS SUPPORT: Configure headers for HLS videos**
  //     final Map<String, String> headers = videoUrl.contains('.m3u8')
  //         ? const {
  //             'Accept': 'application/vnd.apple.mpegurl,application/x-mpegURL',
  //           }
  //         : const {};

  //     // Create controller
  //     final controller = VideoPlayerController.networkUrl(
  //       Uri.parse(videoUrl),
  //       videoPlayerOptions: VideoPlayerOptions(
  //         mixWithOthers: true,
  //         allowBackgroundPlayback: false,
  //       ),
  //       httpHeaders: headers,
  //     );

  //     // Initialize controller
  //     if (videoUrl.contains('.m3u8')) {
  //       await controller.initialize().timeout(
  //         const Duration(seconds: 30),
  //         onTimeout: () {
  //           throw Exception('HLS video initialization timeout');
  //         },
  //       );
  //     } else {
  //       await controller.initialize().timeout(
  //         const Duration(seconds: 10),
  //         onTimeout: () {
  //           throw Exception('Video initialization timeout');
  //         },
  //       );
  //     }

  //     // Add to shared pool
  //     sharedPool.addController(video.id, controller);

  //     print(
  //         '✅ ProfileScreen: Successfully preloaded video: ${video.videoName}');
  //   } catch (e) {
  //     print('❌ ProfileScreen: Error preloading video ${video.videoName}: $e');
  //   }
  // }

  @override
  void dispose() {
    ProfileScreenLogger.logProfileScreenDispose();
    
    // **NEW: Stop all background downloads immediately on exit**
    try {
      AppLogger.log('🛑 ProfileScreen: Exiting profile, stopping all background downloads...');
      final videoCacheProxy = VideoCacheProxyService();
      // Passing empty list cancels EVERYTHING
      videoCacheProxy.cancelAllStreamingExcept([]); 
      videoCacheProxy.cancelAllPrefetches();
    } catch (e) {
       AppLogger.log('⚠️ ProfileScreen: Error stopping downloads: $e');
    }

    // **OPTIMIZED: Dispose ValueNotifiers**
    _isLoading.dispose();
    _error.dispose();
    _invitedCount.dispose();
    _verifiedInstalled.dispose();
    _verifiedSignedUp.dispose();
    _activeProfileTabIndex.dispose();
    _hasUpiId.dispose();
    _isCheckingUpiId.dispose();
    _stateManager.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  Future<void> _handleLogout() async {
    try {
      ProfileScreenLogger.logLogout();

      // **FIXED: Use centralized LogoutService for unified logout across entire app**
      await LogoutService.performCompleteLogout(context);

      // Ensure local state is cleared immediately so login prompt appears
      _stateManager.clearData();

      // **FIX: Only remove session tokens, NOT payment data**
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('jwt_token');
      await prefs.remove('fallback_user');

      // **DO NOT REMOVE payment data - it should persist across sessions**
      // await prefs.remove('has_payment_setup'); // REMOVED - keep this flag
      // await prefs.remove('payment_profile_cache'); // REMOVED - keep payment data

      // **ENHANCED: Clear profile cache on logout**
      await _clearProfileCache();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppText.get('profile_logout_success')),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      ProfileScreenLogger.logLogoutSuccess();
    } catch (e) {
      ProfileScreenLogger.logLogoutError(e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppText.get('error_logout')}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// **FIXED: Use GoogleSignInController Provider for unified auth state**
  Future<void> _handleGoogleSignIn() async {
    try {
      ProfileScreenLogger.logGoogleSignIn();
      final authController =
          Provider.of<GoogleSignInController>(context, listen: false);

      final userData = await authController.signIn();
      if (userData != null) {
        // **FIX: Pass null to loadUserData to load own profile (not userId)**
        // When null is passed, ProfileStateManager uses logged-in user from AuthService
        AppLogger.log(
            '🔄 ProfileScreen: Sign-in successful, loading own profile data...');
        // Force refresh to get latest data from server
        await _loadData(forceRefresh: true);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppText.get('profile_sign_in_success')),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
        ProfileScreenLogger.logGoogleSignInSuccess();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text(authController.error ?? AppText.get('error_sign_in')),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      ProfileScreenLogger.logGoogleSignInError(e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppText.get('error_sign_in')}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Share app referral message
  Future<void> _handleReferFriends() async {
    try {
      // Build a referral link with user code if available
      String base = 'https://snehayog.site';
      String referralCode = '';
      final userData = _stateManager.getUserData();
      final token = userData?['token'];
      if (token != null) {
        try {
          final uri = Uri.parse('${NetworkHelper.apiBaseUrl}/referrals/code');
          final resp = await httpClientService.get(
            uri,
            headers: {'Authorization': 'Bearer $token'},
            timeout: const Duration(seconds: 6),
          );
          if (resp.statusCode == 200) {
            final data = json.decode(resp.body);
            referralCode = data['code'] ?? '';
          }
        } catch (_) {}
      }
      final String referralLink =
          referralCode.isNotEmpty ? '$base/?ref=$referralCode' : base;
      final String message =
          'I am using Vayug! Refer 2 friends and get full access. Join now: $referralLink';
      await Share.share(
        message,
        subject: 'Vayug – Refer 2 friends and get full access',
      );

      // Optimistically increment invite counter
      final prefs = await SharedPreferences.getInstance();
      _invitedCount.value = (prefs.getInt('referral_invite_count') ?? 0) + 1;
      await prefs.setInt('referral_invite_count', _invitedCount.value);
      // **REMOVED: No setState needed, ValueNotifier automatically updates listeners**
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppText.get('error_share')),
          ),
        );
      }
    }
  }

  Future<void> _loadReferralStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _invitedCount.value = prefs.getInt('referral_invite_count') ?? 0;
      // **REMOVED: No setState needed, ValueNotifier automatically updates listeners**
    } catch (_) {}
  }

  Future<void> _fetchVerifiedReferralStats() async {
    try {
      final userData = _stateManager.getUserData();
      final token = userData?['token'];
      if (token == null) return;
      final uri = Uri.parse('${NetworkHelper.apiBaseUrl}/referrals/stats');
      final resp = await httpClientService.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
        timeout: const Duration(seconds: 6),
      );
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        // **BATCHED UPDATE: Update both values**
        _verifiedInstalled.value = data['installed'] ?? 0;
        _verifiedSignedUp.value = data['signedUp'] ?? 0;
        // **REMOVED: No setState needed, ValueNotifier automatically updates listeners**
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

      // **ENHANCED: Update cache immediately with new data (no server fetch needed)**
      if (_stateManager.userData != null) {
        await _cacheProfileData(_stateManager.userData!);
        AppLogger.log(
            '✅ ProfileScreen: Updated profile cache immediately after name update');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppText.get('profile_updated_success')),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      ProfileScreenLogger.logProfileEditSaveSuccess();
    } catch (e) {
      ProfileScreenLogger.logProfileEditSaveError(e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppText.get('error_update_profile')}: $e'),
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

      // Show loading indicator
      _showLoadingDialog();

      try {
        await _stateManager.deleteSelectedVideos();

        // Hide loading indicator
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppText.get('profile_videos_deleted')
                  .replaceAll('{count}', '$initialCount')),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        ProfileScreenLogger.logVideoDeletionSuccess(count: initialCount);
      } catch (e) {
        // Hide loading indicator on error
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
        rethrow;
      }
    } catch (e) {
      ProfileScreenLogger.logVideoDeletionError(e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(_stateManager.error ?? AppText.get('error_delete_videos')),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: AppText.get('btn_retry', fallback: 'Retry'),
              textColor: Colors.white,
              onPressed: () => _handleDeleteSelectedVideos(),
            ),
          ),
        );
      }
    }
  }

  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const CircularProgressIndicator(),
          ),
        );
      },
    );
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
                    Text(
                      AppText.get('profile_delete_videos_title'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Description
                    Text(
                      AppText.get('profile_delete_videos_desc').replaceAll(
                          '{count}',
                          '${_stateManager.selectedVideoIds.length}'),
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
                            child: Text(
                              AppText.get('btn_cancel'),
                              style: const TextStyle(
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
                            child: Text(
                              AppText.get('btn_delete', fallback: 'Delete'),
                              style: const TextStyle(
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
      // **FIX: Pause all video controllers to prevent audio leak**
      AppLogger.log(
          '🔇 ProfileScreen: Pausing all videos before profile photo change');
      _pauseAllVideoControllers();

      ProfileScreenLogger.logProfilePhotoChange();
      final XFile? image = await showDialog<XFile>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(AppText.get('profile_change_photo')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.camera_alt),
                  title: Text(AppText.get('profile_take_photo')),
                  onTap: () async {
                    final XFile? photo = await _imagePicker.pickImage(
                        source: ImageSource.camera);
                    Navigator.pop(context, photo);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: Text(AppText.get('profile_choose_gallery')),
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
            SnackBar(
              content: Text(AppText.get('profile_photo_uploading')),
              duration: const Duration(seconds: 1),
            ),
          );
        }

        await _stateManager.updateProfilePhoto(image.path);

        // **ENHANCED: Update cache immediately with new data (no server fetch needed)**
        if (_stateManager.userData != null) {
          await _cacheProfileData(_stateManager.userData!);
          AppLogger.log(
              '✅ ProfileScreen: Updated profile cache immediately after photo update');
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppText.get('profile_photo_updated')),
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
            content: Text('${AppText.get('error_change_photo')}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// **IMPROVED: Pause all video controllers to prevent audio leak (better UX)**
  void _pauseAllVideoControllers() {
    try {
      // Get the main controller from the app
      final mainController =
          Provider.of<MainController>(context, listen: false);
      AppLogger.log('🔇 ProfileScreen: Pausing all videos via MainController');
      mainController.forcePauseVideos();

      // **IMPROVED: Also pause shared pool controllers**
      final sharedPool = SharedVideoControllerPool();
      sharedPool.pauseAllControllers();

      AppLogger.log(
          '🔇 ProfileScreen: All video controllers paused (kept in memory)');
    } catch (e) {
      AppLogger.log('⚠️ ProfileScreen: Error pausing videos: $e');
    }
  }





  /// Show How to Earn guidance
  void _showHowToEarnDialog() {
    ProfileDialogsWidget.showHowToEarnDialog(
      context,
      stateManager: _stateManager,
    );
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
              Text(
                AppText.get('profile_sign_in_title'),
                style: const TextStyle(
                  fontSize: 20,
                  color: Color(0xFF424242),
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                AppText.get('profile_sign_in_desc'),
                style: const TextStyle(
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
                label: Text(AppText.get('profile_sign_in_button')),
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
      child: Consumer<GoogleSignInController>(
        builder: (context, authController, _) {
          // **FIXED: Wait for auth initialization before rendering body**
          if (authController.isLoading) {
            return Scaffold(
              key: _scaffoldKey,
              backgroundColor: const Color(0xFFF8F9FA),
              appBar: _buildAppBar(false),
              body: RepaintBoundary(
                child: _buildSkeletonLoading(),
              ),
            );
          }

          // **FIX: Only sync with logged in user if viewing own profile (widget.userId is null)**
          // If widget.userId is provided, we're viewing someone else's profile - don't override it
          WidgetsBinding.instance.addPostFrameCallback((_) {
            // **FIX: Only sync for own profile (widget.userId is null) when signed in**
            if (widget.userId == null &&
                authController.isSignedIn &&
                authController.userData != null) {
              final loggedInUserId = authController.userData?['id'] ??
                  authController.userData?['googleId'];

              // **FIX: Load profile if userData is null OR if userId doesn't match**
              if (loggedInUserId != null) {
                final currentUserId = _stateManager.userData?['id'] ??
                    _stateManager.userData?['googleId'];
                // Compare as strings to avoid type mismatch issues
                final currentUserIdStr = currentUserId?.toString();
                final loggedInUserIdStr = loggedInUserId.toString();

                if (_stateManager.userData == null ||
                    currentUserIdStr == null ||
                    currentUserIdStr != loggedInUserIdStr) {
                  AppLogger.log(
                      '🔄 ProfileScreen: Syncing with logged in user: $loggedInUserIdStr (currentUserId: $currentUserIdStr, hasUserData: ${_stateManager.userData != null})');
                  // Use _loadData with forceRefresh to ensure fresh data after sign-in
                  _loadData(forceRefresh: true).catchError((e) {
                    AppLogger.log(
                        '⚠️ ProfileScreen: Error loading profile after sync: $e');
                  });
                }
              }
              // If viewing someone else's profile (widget.userId is provided),
              // only sync if the logged in user matches the viewed profile
              else if (widget.userId != null && loggedInUserId != null) {
                // Check if we're viewing the logged in user's profile
                if (widget.userId == loggedInUserId) {
                  final currentUserId = _stateManager.userData?['id'] ??
                      _stateManager.userData?['googleId'];
                  if (currentUserId != loggedInUserId) {
                    AppLogger.log(
                        '🔄 ProfileScreen: Syncing with logged in user (viewing own profile): $loggedInUserId');
                    _stateManager.loadUserData(widget.userId);
                  }
                }
                // If viewing someone else's profile, don't sync - keep the requested profile
              }
            } else if (!authController.isSignedIn &&
                _stateManager.userData != null &&
                widget.userId == null) {
              // User signed out and was viewing own profile - clear data
              _stateManager.clearData();
            }
          });

          // Determine if viewing own profile (use authController from Consumer builder)
          final loggedInUserId = authController.userData?['id']?.toString() ??
              authController.userData?['googleId']?.toString();
          final displayedUserId = widget.userId ??
              _stateManager.userData?['googleId']?.toString() ??
              _stateManager.userData?['id']?.toString();
          final bool isViewingOwnProfile = loggedInUserId != null &&
              loggedInUserId.isNotEmpty &&
              loggedInUserId == displayedUserId;

          return Scaffold(
            key: _scaffoldKey,
            backgroundColor: const Color(0xFFF8F9FA),
            appBar: _buildAppBar(isViewingOwnProfile),
            drawer: isViewingOwnProfile
                ? ProfileMenuWidget(
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
                    onEnterSelectionMode: () =>
                        _stateManager.enterSelectionMode(),
                    onLogout: _handleLogout,
                    onGoogleSignIn: _handleGoogleSignIn,
                    onCheckPaymentSetupStatus: _checkPaymentSetupStatus,
                  )
                : null,
            body: Consumer<UserProvider>(
              builder: (context, userProvider, child) {
                UserModel? userModel;
                if (widget.userId != null) {
                  userModel = userProvider.getUserData(widget.userId!);
                }
                // Use the local _stateManager directly since it's not in Provider
                // Pass authController to check authentication status
                return _buildBody(userProvider, userModel, authController);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(UserProvider userProvider, UserModel? userModel,
      GoogleSignInController authController) {
    // **FIXED: If auth is still loading, show skeleton instead of sign-in UI**
    if (authController.isLoading) {
      return RepaintBoundary(
        child: _buildSkeletonLoading(),
      );
    }

    // **FIXED: Check authentication status first - if viewing own profile and not signed in, show sign-in view**
    // If viewing someone else's profile (widget.userId != null), show their profile even if not signed in
    if (widget.userId == null && !authController.isSignedIn) {
      return _buildSignInView();
    }

    // **FIXED: For creator profiles, ensure videos are loaded after profile data loads**
    if (widget.userId != null &&
        _stateManager.userData != null &&
        _stateManager.userVideos.isEmpty &&
        !_stateManager.isVideosLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            widget.userId != null &&
            _stateManager.userData != null &&
            _stateManager.userVideos.isEmpty &&
            !_stateManager.isVideosLoading) {
          AppLogger.log(
              '🔄 ProfileScreen: Profile data loaded but videos missing, loading videos for creator: ${widget.userId}');
          _loadVideos().catchError((e) {
            AppLogger.log(
                '⚠️ ProfileScreen: Error loading videos for creator profile: $e');
          });
        }
      });
    }

    // **FIX: Ensure videos are loaded for own profile too if missing**
    if (widget.userId == null &&
        _stateManager.userData != null &&
        _stateManager.userVideos.isEmpty &&
        !_stateManager.isVideosLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            widget.userId == null &&
            _stateManager.userData != null &&
            _stateManager.userVideos.isEmpty &&
            !_stateManager.isVideosLoading) {
          AppLogger.log(
              '🔄 ProfileScreen: Profile data loaded but videos missing for own profile, loading videos...');
          _loadVideos().catchError((e) {
            AppLogger.log(
                '⚠️ ProfileScreen: Error loading videos for own profile: $e');
          });
        }
      });
    }

    // **OPTIMIZED: Use ValueListenableBuilder for granular updates**
    return ValueListenableBuilder<bool>(
      valueListenable: _isLoading,
      builder: (context, isLoading, child) {
        if (isLoading) {
          return RepaintBoundary(
            child: _buildSkeletonLoading(),
          );
        }

        // **OPTIMIZED: Nested ValueListenableBuilder for error state**
        return ValueListenableBuilder<String?>(
          valueListenable: _error,
          builder: (context, error, child) {
            // **FIXED: Check authentication status - if not signed in and viewing own profile, show sign-in view**
            if (widget.userId == null && !authController.isSignedIn) {
              return _buildSignInView();
            }

            // Show error state
            if (error != null) {
              final bool isAuthError = error == 'No authentication data found' ||
                  error.contains('authentication') ||
                  error.contains('Unauthorized');

              // If viewing own profile and auth error, show sign-in
              if (widget.userId == null && isAuthError) {
                return _buildSignInView();
              }
              
              // **FIX: Allow viewing other profiles even if not signed in**
              // If not signed in and viewing own profile -> Sign In
              if (widget.userId == null && !authController.isSignedIn) {
                 return _buildSignInView();
              }

              // Otherwise show error with retry (for both signed-in users and public profiles)
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
                          AppText.get('error_load_profile'),
                          style: TextStyle(
                            color: Colors.red[700],
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          error,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),

                        // **ENHANCED: Retry button with loading state**
                        ValueListenableBuilder<bool>(
                          valueListenable: _isLoading,
                          builder: (context, isLoading, child) {
                            return ElevatedButton.icon(
                              onPressed: isLoading
                                  ? null
                                  : () => _loadData(forceRefresh: true),
                              icon: isLoading
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.refresh),
                              label: Text(isLoading
                                  ? AppText.get('btn_loading',
                                      fallback: 'Loading...')
                                  : AppText.get('btn_retry',
                                      fallback: 'Retry')),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            // Check if we have user data - if viewing own profile and no data, show sign-in view
            if (_stateManager.userData == null) {
              if (widget.userId == null && !authController.isSignedIn) {
                return _buildSignInView();
              }
              // If viewing someone else's profile, we might not have data yet - show loading or error
              if (widget.userId != null) {
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
                            AppText.get('error_load_profile'),
                            style: TextStyle(
                              color: Colors.red[700],
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (error != null && error.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              error,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                          const SizedBox(height: 24),
                          // **ENHANCED: Retry button with loading state**
                          ValueListenableBuilder<bool>(
                            valueListenable: _isLoading,
                            builder: (context, isLoading, child) {
                              return ElevatedButton.icon(
                                onPressed: isLoading
                                    ? null
                                    : () => _loadData(forceRefresh: true),
                                icon: isLoading
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Icon(Icons.refresh),
                                label: Text(isLoading
                                    ? AppText.get('btn_loading',
                                        fallback: 'Loading...')
                                    : AppText.get('btn_retry',
                                        fallback: 'Retry')),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 12,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              return _buildSignInView();
            }

            // Determine if viewing own profile (authController already passed as parameter)

            // If we reach here, we have user data and can show the profile
            // If we reach here, we have user data and can show the profile
            return Stack(
              children: [
                RefreshIndicator(
                  onRefresh: _refreshData,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (ScrollNotification scrollInfo) {
                      // **SMART PAGINATION: Trigger only when close to bottom**
                      if (scrollInfo.metrics.pixels >=
                              scrollInfo.metrics.maxScrollExtent - 300 && 
                          !_stateManager.isFetchingMore &&
                          _stateManager.hasMoreVideos) {
                        _stateManager.loadMoreVideos();
                      }
                      return false;
                    },
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        // Google AdMob Banner Ad at the top
                        const SliverToBoxAdapter(
                          child: GoogleAdMobBannerWidget(
                            adUnitId: 'ca-app-pub-2359959043864469/8166031130',
                          ),
                        ),

                        ..._buildProfileSlivers(userProvider, userModel),
                        
                        // **SMART SPINNER: Pagination loader at the bottom of the grid**
                        SliverToBoxAdapter(
                          child: Consumer<ProfileStateManager>(
                            builder: (context, manager, _) {
                              if (manager.isFetchingMore) {
                                return Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 20),
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.green.shade500),
                                      ),
                                    ),
                                  ),
                                );
                              }
                              return const SizedBox(height: 80); // Final padding
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              ],
            );
          },
        );
      },
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

            // Videos section skeleton (Instagram-like 3-column, tighter spacing)
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
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 1,
                        mainAxisSpacing: 1,
                        childAspectRatio: 0.5,
                      ),
                      itemCount: 6,
                      itemBuilder: (context, index) => Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.zero,
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

  PreferredSizeWidget _buildAppBar(bool isViewingOwnProfile) {
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
                : (stateManager.isEditing
                    ? TextField(
                        controller: stateManager.nameController,
                        style: const TextStyle(
                          color: Color(0xFF1A1A1A),
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                        decoration: const InputDecoration(
                          border: UnderlineInputBorder(),
                          hintText: 'Enter your name',
                        ),
                        autofocus: true,
                      )
                    : Text(
                        stateManager.userData?['name'] ??
                            AppText.get('profile_title'),
                        style: const TextStyle(
                          color: Color(0xFF1A1A1A),
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                      )),
            leading: isViewingOwnProfile
                ? IconButton(
                    icon: const Icon(Icons.menu,
                        color: Color(0xFF1A1A1A), size: 24),
                    tooltip: 'Menu',
                    onPressed: () {
                      _scaffoldKey.currentState?.openDrawer();
                    },
                  )
                : IconButton(
                    icon: const Icon(Icons.arrow_back,
                        color: Color(0xFF1A1A1A), size: 24),
                    tooltip: 'Back',
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                  ),
            actions: _buildAppBarActions(stateManager),
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

  List<Widget> _buildAppBarActions(ProfileStateManager stateManager) {
    final actions = <Widget>[
      IconButton(
        icon: const Icon(
          Icons.search,
          color: Color(0xFF1A1A1A),
        ),
        tooltip: 'Search videos & creators',
        onPressed: () {
          showSearch(
            context: context,
            delegate: VideoCreatorSearchDelegate(),
          );
        },
      ),
      _buildChatSupportAction(),
    ];

    if (stateManager.isSelecting && stateManager.selectedVideoIds.isNotEmpty) {
      actions.add(
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
      );
      actions.add(const SizedBox(width: 8));
    }

    if (stateManager.isSelecting) {
      actions.add(
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
          onPressed: stateManager.exitSelectionMode,
        ),
      );
    }

    return actions;
  }

  Widget _buildChatSupportAction() {
    return IconButton(
      icon: const Icon(
        Icons.headset_mic_outlined,
        color: Color(0xFF10B981),
      ),
      tooltip: 'Chat with us on WhatsApp',
      onPressed: _openWhatsAppGroupChat,
    );
  }

  Future<void> _openWhatsAppGroupChat() async {
    try {
      final launched = await launchUrl(
        _whatsAppGroupUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        _showChatSupportError();
      }
    } catch (e) {
      AppLogger.log('❌ ProfileScreen: Error opening WhatsApp group: $e');
      if (mounted) {
        _showChatSupportError();
      }
    }
  }

  void _showChatSupportError() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppText.get('error_whatsapp')),
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

  /// **NEW: Navigate to Creator Revenue Screen when earnings is tapped**
  void _handleEarningsTap() {
    AppLogger.log(
        '💰 ProfileScreen: Earnings tapped - navigating to CreatorRevenueScreen');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CreatorRevenueScreen(),
      ),
    );
  }

  List<Widget> _buildProfileSlivers(UserProvider userProvider, UserModel? userModel) {
    // Determine if viewing own profile
    final authController =
        Provider.of<GoogleSignInController>(context, listen: false);
    final loggedInUserId = authController.userData?['id']?.toString() ??
        authController.userData?['googleId']?.toString();
    final displayedUserId = widget.userId ??
        _stateManager.userData?['googleId']?.toString() ??
        _stateManager.userData?['id']?.toString();
    final bool isViewingOwnProfile =
        loggedInUserId != null && loggedInUserId.isNotEmpty
            ? loggedInUserId == displayedUserId
            : widget.userId == null;

    final List<Widget> slivers = [];

    // 1. UPI ID Notice Banner (only for own profile without UPI ID)
    if (isViewingOwnProfile) {
      slivers.add(
        SliverToBoxAdapter(
          child: ValueListenableBuilder<bool>(
            valueListenable: _isCheckingUpiId,
            builder: (context, isChecking, child) {
              if (isChecking) {
                return const SizedBox.shrink();
              }
              return ValueListenableBuilder<bool>(
                valueListenable: _hasUpiId,
                builder: (context, hasUpi, child) {
                  if (hasUpi) {
                    return const SizedBox.shrink();
                  }
                  return _buildUpiIdNoticeBanner();
                },
              );
            },
          ),
        ),
      );
    }

    // 2. Compact Profile Header
    slivers.add(
      SliverToBoxAdapter(
        child: Consumer<ProfileStateManager>(
          builder: (context, stateManager, child) {
            AppLogger.log('🎨 ProfileScreen: Rebuilding Profile Header (Videos: ${stateManager.totalVideoCount})');
            return Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _buildCompactAvatar(),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: _buildCompactStatItem(
                                label: 'Followers',
                                valueBuilder: (context) => _getFollowersCountString(context),
                              ),
                            ),
                            Container(
                              height: 24,
                              width: 1,
                              color: Colors.grey[300],
                            ),
                            Expanded(
                              child: _buildCompactStatItem(
                                label: 'Videos',
                                valueBuilder: (context) => stateManager.totalVideoCount.toString(),
                              ),
                            ),
                            Container(
                              height: 24,
                              width: 1,
                              color: Colors.grey[300],
                            ),
                            Expanded(
                              child: _buildCompactStatItem(
                                 label: 'Earnings',
                                 isHighlighted: true,
                                 valueBuilder: (context) => (stateManager.isEarningsLoading || stateManager.isVideosLoading)
                                   ? 'Loading...' 
                                   : '₹${stateManager.cachedEarnings.toStringAsFixed(2)}',
                                 onTap: isViewingOwnProfile ? _handleEarningsTap : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    stateManager.userData?['bio'] ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF4B5563),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (isViewingOwnProfile)
                        Expanded(
                          child: stateManager.isEditing
                              ? Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: _handleCancelEdit,
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.red,
                                          side: const BorderSide(color: Colors.red),
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ),
                                        child: const Text('Cancel'),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: _handleSaveProfile,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ),
                                        child: const Text('Save'),
                                      ),
                                    ),
                                  ],
                                )
                              : ElevatedButton.icon(
                                  onPressed: _showHowToEarnDialog,
                                  icon: const Icon(Icons.workspace_premium, size: 18),
                                  label: const Text('How to Earn'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF10B981),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    elevation: 0,
                                  ),
                                ),
                        ),
                      if (isViewingOwnProfile && !stateManager.isEditing) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _handleReferFriends,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3B82F6),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text('Refer Friends'),
                          ),
                        ),
                      ]
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 8)));

    // 3. Content Tabs
    slivers.add(
      SliverToBoxAdapter(
        child: ValueListenableBuilder<int>(
          valueListenable: _activeProfileTabIndex,
          builder: (context, activeIndex, child) {
            return _ProfileTabs(
              activeIndex: activeIndex,
              onSelect: (i) => _activeProfileTabIndex.value = i,
            );
          },
        ),
      ),
    );

    // 4. Videos or Recommendations Section
    if (_activeProfileTabIndex.value == 0) {
      slivers.add(
        ProfileVideosWidget(
          stateManager: _stateManager,
          showHeader: false,
          isSliver: true, // **ENABLE VIRTUALIZATION**
        ),
      );
    } else {
      slivers.add(
        SliverToBoxAdapter(
          child: _buildRecommendationsSection(),
        ),
      );
    }

    return slivers;
  }

  // **NEW: Helper to build compact avatar**
  Widget _buildCompactAvatar() {
    return GestureDetector(
      onTap: _stateManager.isEditing ? _handleProfilePhotoChange : null,
      child: Stack(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFE5E7EB),
                width: 2,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(40),
              child: Consumer<ProfileStateManager>(
                builder: (context, stateManager, child) {
                  final profilePic = stateManager.userData?['profilePic'];
                  if (profilePic != null && profilePic.isNotEmpty) {
                    if (profilePic.startsWith('http')) {
                      return Image.network(profilePic, fit: BoxFit.cover);
                    } else {
                      return Image.file(File(profilePic), fit: BoxFit.cover);
                    }
                  }
                  return Container(
                    color: Colors.grey[200],
                    child: const Icon(Icons.person, color: Colors.grey, size: 40),
                  );
                },
              ),
            ),
          ),
          if (_stateManager.isEditing)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.4),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.camera_alt,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // **NEW: Helper for compact stats**
  Widget _buildCompactStatItem({
    required String label,
    required String Function(BuildContext) valueBuilder,
    bool isHighlighted = false,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Builder(builder: (context) {
             final value = valueBuilder(context);
             final bool isLoadingText = value.contains('Loading');
             return Text(
               value,
               style: TextStyle(
                 color: isHighlighted ? const Color(0xFF2563EB) : const Color(0xFF111827),
                 fontSize: isLoadingText ? 10 : 18,
                 fontWeight: isLoadingText ? FontWeight.w600 : FontWeight.w700,
               ),
             );
          }),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _getFollowersCountString(BuildContext context) {
    // 1. Try getting from ProfileStateManager first (immediate)
    if (_stateManager.userData != null) {
      final followersCount = _stateManager.userData!['followersCount'] ??
          _stateManager.userData!['followers'];

      if (followersCount != null) {
        final count = followersCount is int
            ? followersCount
            : (int.tryParse(followersCount.toString()) ?? 0);
        if (count > 0) return count.toString();
      }
    }

    // 2. Fallback to UserProvider (async loaded)
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
      try {
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        for (final candidateId in idsToTry) {
          final userModel = userProvider.getUserData(candidateId);
          if (userModel?.followersCount != null &&
              userModel!.followersCount > 0) {
            return userModel.followersCount.toString();
          }
        }
      } catch (e) {
        // Ignore provider errors if context is unstable
      }
    }

    return '0';
  }

  /// Compact tabs: Videos | Recommendations
  Widget _ProfileTabs(
      {required int activeIndex, required ValueChanged<int> onSelect}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => onSelect(0),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: activeIndex == 0 ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: activeIndex == 0 ? [
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2, offset: const Offset(0, 1))
                  ] : [],
                ),
                child: Center(child: Text('Videos', style: TextStyle(fontWeight: FontWeight.w600, color: activeIndex == 0 ? Colors.black : Colors.grey))),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => onSelect(1),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                   color: activeIndex == 1 ? Colors.white : Colors.transparent,
                   borderRadius: BorderRadius.circular(8),
                    boxShadow: activeIndex == 1 ? [
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2, offset: const Offset(0, 1))
                  ] : [],
                ),
                 child: Center(child: Text('Top Earner', style: TextStyle(fontWeight: FontWeight.w600, color: activeIndex == 1 ? Colors.black : Colors.grey))),

              ),
            ),
          ),
        ],
      ),
    );
  }


  /// Recommendations tab – shows Top Earners from following (3-column grid)
  Widget _buildRecommendationsSection() {
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text(
              AppText.get('profile_top_earners'),
              style: const TextStyle(
                color: Color(0xFF111827),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const TopEarnersGrid(),
          ],
        ),
      ),
    );
  }

  /// **NEW: Build UPI ID Notice Banner**
  Widget _buildUpiIdNoticeBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3CD), // Light yellow background
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFFC107), // Yellow border
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          AppText.get('profile_upi_notice'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[900],
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
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
          AppLogger.log(
              '✅ User-specific payment setup found for user: $userId');
          return true;
        }
      }

      // **FALLBACK: Check global flag for backward compatibility**
      final hasPaymentSetup = prefs.getBool('has_payment_setup') ?? false;
      if (hasPaymentSetup) {
        ProfileScreenLogger.logPaymentSetupFound();
        AppLogger.log('✅ Global payment setup flag found');
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
            AppLogger.log(
                '✅ Set user-specific payment setup flag for user: $userId');
          }
          await prefs.setBool('has_payment_setup', true);
          ProfileScreenLogger.logPaymentSetupFound();
          return true;
        }
      }

      ProfileScreenLogger.logPaymentSetupNotFound();
      AppLogger.log('ℹ️ No payment setup found for user');
      return false;
    } catch (e) {
      ProfileScreenLogger.logPaymentSetupCheckError(e.toString());
      return false;
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
      final response = await httpClientService.get(
        Uri.parse('${NetworkHelper.apiBaseUrl}/creator-payouts/profile'),
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

  // **NEW: Check UPI ID status for notice**
  Future<void> _checkUpiIdStatus() async {
    try {
      // Only check for own profile
      if (widget.userId != null) {
        _hasUpiId.value = true; // Don't show notice for other users
        return;
      }

      _isCheckingUpiId.value = true;

      // **NEW: If payment setup is already completed (any method), don't show UPI banner**
      try {
        final hasPaymentSetup = await _checkPaymentSetupStatus();
        if (hasPaymentSetup) {
          _hasUpiId.value = true;
          _isCheckingUpiId.value = false;
          AppLogger.log(
              '✅ ProfileScreen: Payment setup already completed, hiding UPI notice');
          return;
        }
      } catch (e) {
        AppLogger.log(
            '⚠️ ProfileScreen: Error checking payment setup status for UPI notice: $e');
        // Fall through to detailed UPI check
      }

      // **FIX: First check local state (ProfileStateManager) for UPI ID**
      // This ensures immediate update after saving UPI ID
      final userData = _stateManager.getUserData();
      if (userData != null) {
        final paymentDetails = userData['paymentDetails'];
        final paymentMethod = userData['preferredPaymentMethod'];

        // Check if UPI ID exists in local state
        if (paymentMethod == 'upi' && paymentDetails != null) {
          final upiId = paymentDetails['upiId'];
          final hasUpiLocal =
              upiId != null && upiId.toString().trim().isNotEmpty;

          if (hasUpiLocal) {
            // UPI ID found in local state - set immediately and skip API call
            _hasUpiId.value = true;
            AppLogger.log(
                '✅ ProfileScreen: UPI ID found in local state - hiding notice');
            _isCheckingUpiId.value = false;
            return;
          }
        }
      }

      final token = userData?['token'];

      if (token == null) {
        AppLogger.log('⚠️ ProfileScreen: No token available for UPI ID check');
        _hasUpiId.value =
            false; // Show notice if not signed in (they need to sign in first)
        _isCheckingUpiId.value = false;
        return;
      }

      // If not found in local state, verify with API
      AppLogger.log(
          '🔍 ProfileScreen: UPI ID not in local state, checking API...');
      final response = await httpClientService.get(
        Uri.parse('${NetworkHelper.apiBaseUrl}/creator-payouts/profile'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final paymentDetails = data['paymentDetails'];
        final paymentMethod = data['creator']?['preferredPaymentMethod'];

        AppLogger.log('🔍 ProfileScreen: Payment method: $paymentMethod');
        AppLogger.log('🔍 ProfileScreen: Payment details: $paymentDetails');

        // Check if UPI ID is set
        if (paymentMethod == 'upi' && paymentDetails != null) {
          final upiId = paymentDetails['upiId'];
          final hasUpi = upiId != null && upiId.toString().trim().isNotEmpty;
          _hasUpiId.value = hasUpi;
          AppLogger.log(
              '🔍 ProfileScreen: UPI ID status from API: ${hasUpi ? "SET" : "NOT SET"}');
        } else {
          // If payment method is not UPI or payment details don't exist, show notice
          _hasUpiId.value = false;
          AppLogger.log(
              '🔍 ProfileScreen: No UPI payment method found - showing notice');
        }
      } else {
        // If API fails, check local state as fallback
        final hasUpiLocal = _stateManager.hasUpiId;
        _hasUpiId.value = hasUpiLocal;
        AppLogger.log(
            '⚠️ ProfileScreen: API returned status ${response.statusCode} - using local state: ${hasUpiLocal ? "HAS UPI" : "NO UPI"}');
      }
    } catch (e) {
      AppLogger.log('⚠️ ProfileScreen: Error checking UPI ID status: $e');
      // On error, check local state as fallback
      final hasUpiLocal = _stateManager.hasUpiId;
      _hasUpiId.value = hasUpiLocal;
      AppLogger.log(
          '⚠️ ProfileScreen: Using local state fallback: ${hasUpiLocal ? "HAS UPI" : "NO UPI"}');
    } finally {
      _isCheckingUpiId.value = false;
    }
  }

  // **NEW: Enhanced caching methods for profile data**

  /// **OPTIMIZED: Load cached profile data from SmartCacheManager**
  /// **ENHANCED: Uses unified SmartCacheManager (same as ProfileStateManager)**
  /// Shows cached data instantly when user navigates back to same profile
  Future<Map<String, dynamic>?> _loadCachedProfileData() async {
    try {
      // **OPTIMIZATION: Use ProfileLocalDataSource (Hive) for instant load**
      final loggedInUser = await _authService.getUserData();
      final loggedInUserId = loggedInUser?['googleId'] ?? loggedInUser?['id'];
      
      // Determine the correct user ID to fetch
      final String? targetUserId = widget.userId ?? loggedInUserId;

      if (targetUserId == null) {
        ProfileScreenLogger.logDebugInfo(
            'ℹ️ No user ID found for cache lookup');
        return null;
      }

      final dataSource = ProfileLocalDataSource();
      Map<String, dynamic>? cachedProfile =
          await dataSource.getCachedUserData(targetUserId);

      if (cachedProfile != null) {
        ProfileScreenLogger.logDebugInfo(
            '⚡ Loading profile from Hive Cache (INSTANT - cache persists when user navigates back)');
        return cachedProfile;
      }

      // **NEW: Check SmartCacheManager (Memory Cache) if Hive is empty**
      // This is crucial because ProfilePreloader caches to SmartCacheManager
      final smartCache = SmartCacheManager();
      await smartCache.initialize();
      if (smartCache.isInitialized) {
        final cacheKey = 'user_profile_$targetUserId';
        final smartCachedProfile = await smartCache.peek<Map<String, dynamic>>(
          cacheKey,
          cacheType: 'user_profile',
          allowStale: true,
        );

        if (smartCachedProfile != null) {
          ProfileScreenLogger.logDebugInfo(
              '⚡ Loading profile from SmartCache (INSTANT - preloaded or previously visited)');
          return smartCachedProfile;
        }
      }

      ProfileScreenLogger.logDebugInfo(
          'ℹ️ No profile cache found for $targetUserId - will fetch from server');
    } catch (e) {
      ProfileScreenLogger.logWarning('Error loading cached profile data: $e');
    }
    return null;
  }

  /// **OPTIMIZED: Cache profile data to SmartCacheManager**
  /// **ENHANCED: Uses unified SmartCacheManager (same as ProfileStateManager)**
  /// Cache persists when user navigates back to same profile
  Future<void> _cacheProfileData(Map<String, dynamic> profileData) async {
    try {
      // **OPTIMIZATION: Cache to Hive via ProfileLocalDataSource**
      final loggedInUser = await _authService.getUserData();
      final loggedInUserId = loggedInUser?['googleId'] ?? loggedInUser?['id'];
      
      final String? targetUserId = widget.userId ?? loggedInUserId;

      if (targetUserId == null) {
        ProfileScreenLogger.logDebugInfo(
            '⚠️ No user ID found, skipping Hive cache');
        return;
      }

      final dataSource = ProfileLocalDataSource();
      await dataSource.cacheUserData(targetUserId, profileData);

      ProfileScreenLogger.logDebugInfo(
          '✅ Profile data cached to Hive (persists when user navigates back)');
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

  /// **SIMPLIFIED: Cache earnings - simple timestamp only**
  Future<void> _cacheEarningsData(Map<String, dynamic> earningsData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = widget.userId ??
          _stateManager.userData?['googleId'] ??
          _stateManager.userData?['id'];

      if (userId == null) {
        return;
      }

      final cacheKey = 'earnings_cache_$userId';
      final timestampKey = 'earnings_cache_timestamp_$userId';

      await prefs.setString(cacheKey, json.encode(earningsData));
      await prefs.setInt(timestampKey, DateTime.now().millisecondsSinceEpoch);

      AppLogger.log('✅ ProfileScreen: Earnings cached');
    } catch (e) {
      AppLogger.log('❌ ProfileScreen: Error caching earnings: $e');
    }
  }

  /// **SIMPLIFIED: Fast earnings cache - simple 5-minute check**
  Future<Map<String, dynamic>?> _loadCachedEarningsData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = widget.userId ??
          _stateManager.userData?['googleId'] ??
          _stateManager.userData?['id'];

      if (userId == null) {
        return null;
      }

      final cacheKey = 'earnings_cache_$userId';
      final timestampKey = 'earnings_cache_timestamp_$userId';
      final oldMonthKey =
          'earnings_cache_month_$userId'; // **OLD KEY - clean up if exists**

      final cachedDataJson = prefs.getString(cacheKey);
      final cachedTimestamp = prefs.getInt(timestampKey);

      // **CLEANUP: Remove old month key if it exists (from previous code version)**
      if (prefs.containsKey(oldMonthKey)) {
        await prefs.remove(oldMonthKey);
        AppLogger.log('🧹 ProfileScreen: Removed old month key');
      }

      if (cachedTimestamp != null && cachedDataJson != null) {
        final cacheTime = DateTime.fromMillisecondsSinceEpoch(cachedTimestamp);
        final now = DateTime.now();
        final age = now.difference(cacheTime);

        // **MONTH CHECK: If cache is from different month, invalidate it**
        if (cacheTime.month != now.month || cacheTime.year != now.year) {
          AppLogger.log(
              '🔄 ProfileScreen: Earnings cache is from different month (${cacheTime.month}/${cacheTime.year} vs ${now.month}/${now.year}) - invalidating');
          await prefs.remove(cacheKey);
          await prefs.remove(timestampKey);
          return null;
        }

        // **SIMPLE: Check if cache is fresh (5 minutes)**
        if (age < const Duration(minutes: 5)) {
          // Cache is fresh and from current month - use it
          return Map<String, dynamic>.from(json.decode(cachedDataJson));
        } else {
          // Cache is stale - clear it
          await prefs.remove(cacheKey);
          await prefs.remove(timestampKey);
        }
      }
    } catch (e) {
      AppLogger.log('❌ ProfileScreen: Error loading cached earnings: $e');
    }
    return null;
  }

  /// **FIXED: Fast earnings refresh with month reset detection**
  Future<void> _refreshEarningsData({bool forceRefresh = false}) async {
    try {
      // Only refresh earnings for own profile
      if (widget.userId != null) {
        return;
      }

      final userData = await _authService.getUserData();
      if (userData == null) {
        return;
      }

      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      final userId = widget.userId ??
          _stateManager.userData?['googleId'] ??
          _stateManager.userData?['id'];

      // **MONTH RESET: Check if cache is from different month - always force refresh**
      if (userId != null) {
        final timestampKey = 'earnings_cache_timestamp_$userId';
        final cachedTimestamp = prefs.getInt(timestampKey);

        if (cachedTimestamp != null) {
          final cacheTime =
              DateTime.fromMillisecondsSinceEpoch(cachedTimestamp);
          // **FIX: Force refresh if month changed (not just day 1)**
          if (cacheTime.month != now.month || cacheTime.year != now.year) {
            AppLogger.log(
                '🔄 ProfileScreen: Month changed - forcing fresh earnings calculation');
            forceRefresh = true;
            // Clear earnings cache when month changes
            await prefs.remove('earnings_cache_$userId');
            await prefs.remove(timestampKey);
            AppLogger.log(
                '🧹 ProfileScreen: Cleared earnings cache (month changed)');
          }
        }
      }

      // **MONTH RESET: Also check if it's the 1st of the month - always force refresh**
      if (now.day == 1) {
        AppLogger.log(
            '🔄 ProfileScreen: Month start detected - forcing fresh earnings calculation');
        forceRefresh = true;
        if (userId != null) {
          await prefs.remove('earnings_cache_$userId');
          await prefs.remove('earnings_cache_timestamp_$userId');
          AppLogger.log(
              '🧹 ProfileScreen: Cleared earnings cache at month start');
        }
      }

      // **SIMPLE CACHE: Check if cache is fresh (5 minutes) - but skip if month start**
      if (!forceRefresh) {
        final cachedEarnings = await _loadCachedEarningsData();
        if (cachedEarnings != null) {
          AppLogger.log('⚡ ProfileScreen: Using cached earnings (fast)');
          return; // Cache is fresh, skip API call
        }
      }

      // **FAST: Load earnings in parallel (non-blocking)**
      AppLogger.log('💰 ProfileScreen: Loading fresh earnings...');
      Future.microtask(() async {
        try {
          final earningsData = await _adService.getCreatorRevenueSummary();
          await _cacheEarningsData(earningsData);
          AppLogger.log('✅ ProfileScreen: Earnings loaded (fresh data)');
        } catch (e) {
          AppLogger.log('⚠️ ProfileScreen: Earnings load failed: $e');
          // Silent fail - earnings are optional
        }
      });
    } catch (e) {
      AppLogger.log('⚠️ ProfileScreen: Earnings refresh error: $e');
    }
  }

  Future<void> _clearProfileCache() async {
    try {
      // 1. Clear Legacy SharedPreferences Cache (Earnings & Old Profile Data)
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _getProfileCacheKey();

      // Clear old profile keys (safe to keep for cleanup)
      await prefs.remove('profile_cache_$cacheKey');
      await prefs.remove('profile_cache_timestamp_$cacheKey');
      await prefs.remove('profile_videos_cache_$cacheKey');
      await prefs.remove('profile_videos_cache_timestamp_$cacheKey');

      // Clear Earnings Cache (Still in SharedPreferences)
      final userId = widget.userId ??
          _stateManager.userData?['googleId'] ??
          _stateManager.userData?['id'];
          
      if (userId != null) {
        await prefs.remove('earnings_cache_$userId');
        await prefs.remove('earnings_cache_timestamp_$userId');
      }

      // 2. Clear Hive Cache (New Profile & Video Data)
      final dataSource = ProfileLocalDataSource();
      
      final idsToClear = <String>{
        if (widget.userId != null && widget.userId!.isNotEmpty)
          widget.userId!,
        if (_stateManager.userData?['googleId'] != null &&
            _stateManager.userData!['googleId'].toString().isNotEmpty)
          _stateManager.userData!['googleId'].toString(),
         if (_stateManager.userData?['id'] != null &&
            _stateManager.userData!['id'].toString().isNotEmpty)
          _stateManager.userData!['id'].toString(),
      };

      // Also clear "self" if logged in
      final loggedInUser = await _authService.getUserData();
       if (loggedInUser != null) {
          if (loggedInUser['id'] != null) idsToClear.add(loggedInUser['id']);
          if (loggedInUser['googleId'] != null) idsToClear.add(loggedInUser['googleId']);
       }

      for (final id in idsToClear) {
        await dataSource.clearUserCache(id);
        ProfileScreenLogger.logDebugInfo(
            '🧹 ProfileScreen: Cleared Hive cache for user $id');
      }
      
      AppLogger.log('🧹 ProfileScreen: Profile cache cleared successfully');
    } catch (e) {
      ProfileScreenLogger.logWarning('Error clearing profile cache: $e');
    }
  }
}

/// **NEW: Earnings Bottom Sheet Content Widget**
class EarningsBottomSheetContent extends StatefulWidget {
  final List<VideoModel> videos;
  final ScrollController scrollController;

  const EarningsBottomSheetContent({
    super.key,
    required this.videos,
    required this.scrollController,
  });

  @override
  State<EarningsBottomSheetContent> createState() =>
      _EarningsBottomSheetContentState();
}

class _EarningsBottomSheetContentState
    extends State<EarningsBottomSheetContent> {
  final Map<String, double> _videoEarnings = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEarnings();
  }

  Future<void> _loadEarnings() async {
    setState(() => _isLoading = true);
    try {
      final authService = AuthService();
      final userData = await authService.getUserData();
      final userId = userData?['googleId'] ?? userData?['id'];

      if (userId == null) {
        setState(() => _isLoading = false);
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'earnings_cache_$userId';
      final cachedDataJson = prefs.getString(cacheKey);

      if (cachedDataJson != null) {
        final Map<String, dynamic> revenueData = json.decode(cachedDataJson);
        if (revenueData.containsKey('videos')) {
           final List<dynamic> videoStatsList = revenueData['videos'] ?? [];
           
           for (var stat in videoStatsList) {
             final String videoId = stat['videoId']?.toString() ?? '';
             final double creatorRevenue = (stat['creatorRevenue'] as num?)?.toDouble() ?? 0.0;
             if (videoId.isNotEmpty) {
               _videoEarnings[videoId] = creatorRevenue;
             }
           }
        }
      }
    } catch (e) {
      AppLogger.log('⚠️ Error loading earnings for bottom sheet: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '$weeks week${weeks > 1 ? 's' : ''} ago';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return '$months month${months > 1 ? 's' : ''} ago';
    } else {
      final years = (difference.inDays / 365).floor();
      return '$years year${years > 1 ? 's' : ''} ago';
    }
  }

  @override
  Widget build(BuildContext context) {
    double totalEarnings = 0.0;
    for (var earnings in _videoEarnings.values) {
      totalEarnings += earnings;
    }

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(20),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.account_balance_wallet,
                  color: Colors.black87, size: 24),
              const SizedBox(width: 12),
              Text(
                AppText.get('profile_video_earnings'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const Spacer(),
              Text(
                '₹${totalEarnings.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF10B981),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.black54),
              ),
            ],
          ),
        ),
        Divider(color: Colors.grey[300], height: 1),

        // Content
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : widget.videos.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Text(
                          AppText.get('profile_no_videos'),
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: widget.scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: widget.videos.length,
                      itemBuilder: (context, index) {
                        final video = widget.videos[index];
                        final earnings = _videoEarnings[video.id] ?? 0.0;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.grey.shade200, width: 1),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Video name
                              Text(
                                video.videoName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 12),

                              // Stats row
                              Row(
                                children: [
                                  // Views
                                  Expanded(
                                    child: _buildStatItem(
                                      icon: Icons.visibility,
                                      label: 'Views',
                                      value: '${video.views}',
                                      color: Colors.blue,
                                    ),
                                  ),

                                  // Upload date
                                  Expanded(
                                    child: _buildStatItem(
                                      icon: Icons.calendar_today,
                                      label: 'Uploaded',
                                      value: _formatDate(video.uploadedAt),
                                      color: Colors.orange,
                                    ),
                                  ),

                                  // Earnings
                                  Expanded(
                                    child: _buildStatItem(
                                      icon: Icons.account_balance_wallet,
                                      label: 'Earnings',
                                      value: '₹${earnings.toStringAsFixed(2)}',
                                      color: const Color(0xFF10B981),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}
