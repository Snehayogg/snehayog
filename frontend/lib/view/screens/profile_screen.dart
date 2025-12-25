import 'package:flutter/material.dart';
import 'package:vayu/utils/responsive_helper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:vayu/config/app_config.dart';
import 'package:vayu/core/managers/profile_state_manager.dart';
import 'package:vayu/core/managers/smart_cache_manager.dart';
import 'package:provider/provider.dart';
import 'package:vayu/core/providers/user_provider.dart';
import 'package:vayu/model/usermodel.dart';
import 'package:vayu/core/services/profile_screen_logger.dart';
import 'dart:async';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:vayu/view/widget/profile/profile_header_widget.dart';
import 'package:vayu/view/widget/profile/profile_stats_widget.dart';
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
import 'package:vayu/services/earnings_service.dart';
import 'package:vayu/model/video_model.dart';
import 'package:vayu/view/screens/creator_revenue_screen.dart';
import 'package:vayu/utils/app_text.dart';
import 'package:vayu/view/widget/ads/google_admob_banner_widget.dart';

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

  // **NEW: Refresh counter to force ProfileStatsWidget to reload earnings**
  int _earningsRefreshCounter = 0;

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
  }

  /// **PUBLIC METHOD: Called when Profile tab is selected**
  /// Uses cache if available, only loads from server if no cache exists
  void onProfileTabSelected() {
    AppLogger.log(
        '🔄 ProfileScreen: Profile tab selected, ensuring data is loaded');

    // **ENHANCED: Always ensure data is loaded, even if cached**
    // This fixes the issue where data doesn't show after coming back to profile tab
    if (_stateManager.userData == null || _stateManager.userVideos.isEmpty) {
      AppLogger.log(
          '📡 ProfileScreen: Data not loaded or videos missing, loading from cache or server');
      _loadData(); // This will use cache if available, only fetch from server if no cache
    } else {
      AppLogger.log('✅ ProfileScreen: Data already loaded in memory');
      // **FIX: Even if data exists, ensure videos are loaded**
      if (_stateManager.userVideos.isEmpty && !_stateManager.isVideosLoading) {
        AppLogger.log(
            '🔄 ProfileScreen: Data exists but videos missing, loading videos...');
        _loadVideos().catchError((e) {
          AppLogger.log('⚠️ ProfileScreen: Error loading videos: $e');
        });
      }
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
              '⚡ ProfileScreen: Using cached data (INSTANT - no server fetch)');

          // **INSTANT: Show cached data immediately (no loading state)**
          _stateManager.setUserData(cachedData);
          await _loadVideosFromCache(); // **FIXED: Wait for videos to load before hiding loading**
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

          // **OPTIMIZATION: Different cache refresh times for own profile vs other users**
          final prefs = await SharedPreferences.getInstance();
          final cacheKey = _getProfileCacheKey();
          final cachedTimestamp =
              prefs.getInt('profile_cache_timestamp_$cacheKey');

          bool shouldRefresh = true;
          if (cachedTimestamp != null) {
            final cacheTime =
                DateTime.fromMillisecondsSinceEpoch(cachedTimestamp);
            final age = DateTime.now().difference(cacheTime);

            // **OPTIMIZATION: Shorter cache time for other users (5 minutes) vs own profile (1 day)**
            final isOtherUser = widget.userId != null;
            final maxCacheAge = isOtherUser
                ? const Duration(
                    minutes: 5) // 5 minutes for other users (fresher data)
                : const Duration(days: 1); // 1 day for own profile

            if (age < maxCacheAge) {
              shouldRefresh = false;
              AppLogger.log(
                '⚡ ProfileScreen: Cache is fresh (${age.inMinutes}m old for ${isOtherUser ? "other user" : "own profile"}), skipping background refresh',
              );
            } else {
              AppLogger.log(
                '🔄 ProfileScreen: Cache is stale (${age.inMinutes}m old), will refresh in background',
              );
            }
          }

          if (shouldRefresh) {
            // **BACKGROUND: Refresh in background (non-blocking)**
            Future.microtask(() async {
              try {
                AppLogger.log('🔄 ProfileScreen: Background refresh started');
                await _stateManager.loadUserData(widget.userId);

                if (_stateManager.userData != null) {
                  await _cacheProfileData(_stateManager.userData!);
                  // **FIXED: Load videos for creator profiles using widget.userId**
                  final videoUserId = widget.userId ??
                      _stateManager.userData!['googleId'] ??
                      _stateManager.userData!['_id'] ??
                      _stateManager.userData!['id'];
                  if (videoUserId != null) {
                    await _loadVideos();
                  }

                  // **NEW: Refresh earnings data in background (only for own profile)**
                  await _refreshEarningsData();

                  AppLogger.log(
                      '✅ ProfileScreen: Background refresh completed');
                } else {
                  // **FIX: If refresh fails, show error but keep cached data visible**
                  AppLogger.log(
                      '⚠️ ProfileScreen: Background refresh returned null data');
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          AppText.get('error_refresh_cache'),
                        ),
                        backgroundColor: Colors.orange,
                        duration: const Duration(seconds: 3),
                        action: SnackBarAction(
                          label: AppText.get('btn_retry', fallback: 'Retry'),
                          textColor: Colors.white,
                          onPressed: () => _loadData(forceRefresh: true),
                        ),
                      ),
                    );
                  }
                }
              } catch (e) {
                AppLogger.log(
                    '⚠️ ProfileScreen: Background refresh failed: $e');
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
            await _loadVideos(forceRefresh: forceRefresh);
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
  Future<void> _loadVideos({bool forceRefresh = false}) async {
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
            '📡 ProfileScreen: Loading videos for user: $userIdForVideos (forceRefresh: $forceRefresh, viewing creator: ${widget.userId != null})');

        // Respect the incoming forceRefresh flag:
        // - forceRefresh=true  → bypass SmartCache for videos (manual pull‑to‑refresh, delete, etc.)
        // - forceRefresh=false → allow SmartCache/video caching to work for faster loads
        await _stateManager
            .loadUserVideos(userIdForVideos, forceRefresh: forceRefresh)
            .timeout(
          const Duration(seconds: 20),
          onTimeout: () {
            throw Exception('Video loading timed out');
          },
        );

        AppLogger.log(
            '✅ ProfileScreen: Loaded ${_stateManager.userVideos.length} videos${forceRefresh ? " (fresh from server, not cache)" : ""}');
      }
    } catch (e) {
      AppLogger.log('❌ ProfileScreen: Error loading videos: $e');
      // **FIX: Re-throw error so it can be caught and shown to user**
      rethrow;
    }
  }

  /// **ENHANCED: Manual refresh - clear cache and fetch fresh data from server**
  /// **CRITICAL: When user manually refreshes, ALWAYS show latest data from server, NEVER use cache**
  Future<void> _refreshData() async {
    AppLogger.log(
        '🔄 ProfileScreen: Manual refresh - clearing ALL caches and fetching fresh data from server (NO CACHE WILL BE USED)');

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

      // **NEW: Increment refresh counter to force ProfileStatsWidget to reload earnings**
      setState(() {
        _earningsRefreshCounter++;
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
      final uri = Uri.parse('${AppConfig.baseUrl}/api/referrals/stats');
      final resp = await http.get(uri, headers: {
        'Authorization': 'Bearer $token',
      }).timeout(const Duration(seconds: 6));
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

      await _stateManager.deleteSelectedVideos();

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

  /// Show How to Earn guidance (same style as UploadScreen's What to Upload)
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
                    onShowSettings: _showSettingsBottomSheet,
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
              if (error == 'No authentication data found' ||
                  error.contains('authentication') ||
                  error.contains('Unauthorized')) {
                // If viewing own profile and authentication error, show sign-in view
                if (widget.userId == null) {
                  return _buildSignInView();
                }
              }

              // Otherwise show error with retry (only if signed in)
              if (authController.isSignedIn) {
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
                            error.isNotEmpty
                                ? error
                                : 'You appear to be signed in, but we couldn\'t load your profile.',
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
              } else {
                // Not signed in and error occurred - show sign-in view
                return _buildSignInView();
              }
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
            final loggedInUserId = authController.userData?['id']?.toString() ??
                authController.userData?['googleId']?.toString();
            final displayedUserId = widget.userId ??
                _stateManager.userData?['googleId']?.toString() ??
                _stateManager.userData?['id']?.toString();
            final bool isViewingOwnProfile = loggedInUserId != null &&
                loggedInUserId.isNotEmpty &&
                loggedInUserId == displayedUserId;

            // If we reach here, we have user data and can show the profile
            return RefreshIndicator(
              onRefresh: _refreshData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    // Google AdMob Banner Ad at the top
                    GoogleAdMobBannerWidget(
                      adUnitId: 'ca-app-pub-2359959043864469/8166031130',
                    ),
                    ProfileHeaderWidget(
                      stateManager: _stateManager,
                      userId: widget.userId,
                      onEditProfile: _handleEditProfile,
                      onSaveProfile: _handleSaveProfile,
                      onCancelEdit: _handleCancelEdit,
                      onProfilePhotoChange: _handleProfilePhotoChange,
                      onShowHowToEarn:
                          isViewingOwnProfile ? _showHowToEarnDialog : null,
                    ),
                    _buildProfileContent(userProvider, userModel),
                  ],
                ),
              ),
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

                    // Video grid skeleton (Instagram-like 3-column, tighter spacing)
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
                : Text(
                    stateManager.userData?['name'] ??
                        AppText.get('profile_title'),
                    style: const TextStyle(
                      color: Color(0xFF1A1A1A),
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
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

  Widget _buildProfileContent(UserProvider userProvider, UserModel? userModel) {
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

    return RepaintBoundary(
      child: Column(
        children: [
          // UPI ID Notice Banner (only for own profile without UPI ID)
          // Shown near the top, more compact for better use of vertical space.
          if (isViewingOwnProfile)
            ValueListenableBuilder<bool>(
              valueListenable: _isCheckingUpiId,
              builder: (context, isChecking, child) {
                if (isChecking) {
                  return const SizedBox.shrink(); // Don't show while checking
                }
                return ValueListenableBuilder<bool>(
                  valueListenable: _hasUpiId,
                  builder: (context, hasUpi, child) {
                    if (hasUpi) {
                      return const SizedBox
                          .shrink(); // Don't show if UPI ID is set
                    }
                    return _buildUpiIdNoticeBanner();
                  },
                );
              },
            ),
          // Stats Section (kept tight under banner for compact layout)
          ProfileStatsWidget(
            stateManager: _stateManager,
            userId: widget.userId,
            isVideosLoaded: _stateManager.userVideos.isNotEmpty,
            isFollowersLoaded: true,
            refreshKey:
                _earningsRefreshCounter, // **NEW: Pass refresh key to force reload**
            onFollowersTap: () {
              // **SIMPLIFIED: Simple followers tap**
              AppLogger.log('🔄 ProfileScreen: Followers tapped');
            },
            // **FIXED: Navigate to CreatorRevenueScreen when earnings is tapped (only for own profile)**
            onEarningsTap: isViewingOwnProfile ? _handleEarningsTap : null,
          ),

          const SizedBox(height: 16),

          // Action Buttons Section
          RepaintBoundary(
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    height: 29,
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
                        size: 12,
                      ),
                      label: Text(
                        AppText.get('profile_refer_friends'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Color(0xFF10B981),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.1,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 0),
                        minimumSize: const Size.fromHeight(29),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Content Tabs: Your Videos | My Recommendations (icon-based)
          ValueListenableBuilder<int>(
            valueListenable: _activeProfileTabIndex,
            builder: (context, activeIndex, child) {
              return _ProfileTabs(
                activeIndex: activeIndex,
                onSelect: (i) => _activeProfileTabIndex.value = i,
              );
            },
          ),

          // Videos Section
          // Swipe horizontally across content area to switch tabs
          ValueListenableBuilder<int>(
            valueListenable: _activeProfileTabIndex,
            builder: (context, activeIndex, child) {
              return GestureDetector(
                onHorizontalDragEnd: (details) {
                  final velocity = details.primaryVelocity ?? 0;
                  if (velocity < 0 && activeIndex == 0) {
                    _activeProfileTabIndex.value = 1;
                  } else if (velocity > 0 && activeIndex == 1) {
                    _activeProfileTabIndex.value = 0;
                  }
                },
                child: activeIndex == 0
                    ? ProfileVideosWidget(
                        stateManager: _stateManager,
                        showHeader: false,
                      )
                    : _buildRecommendationsSection(),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Compact icon-only tabs
  Widget _ProfileTabs(
      {required int activeIndex, required ValueChanged<int> onSelect}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => onSelect(0),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color:
                      activeIndex == 0 ? const Color(0xFF111827) : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Icon(
                  Icons.video_library,
                  size: 18,
                  color:
                      activeIndex == 0 ? Colors.white : const Color(0xFF111827),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: () => onSelect(1),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color:
                      activeIndex == 1 ? const Color(0xFF111827) : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Icon(
                  Icons.shopping_bag,
                  size: 18,
                  color:
                      activeIndex == 1 ? Colors.white : const Color(0xFF111827),
                ),
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
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/creator-payouts/profile'),
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

  /// **ENHANCED: Load cached profile data - use cache if exists (no expiry check)**
  /// Only fetches from server if no cache exists or manual refresh
  Future<Map<String, dynamic>?> _loadCachedProfileData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _getProfileCacheKey();
      final cachedDataJson = prefs.getString('profile_cache_$cacheKey');

      if (cachedDataJson != null && cachedDataJson.isNotEmpty) {
        ProfileScreenLogger.logDebugInfo(
            '⚡ Loading profile from SharedPreferences cache (no expiry check - cache persists until manual refresh)');
        return Map<String, dynamic>.from(json.decode(cachedDataJson));
      } else {
        ProfileScreenLogger.logDebugInfo(
            'ℹ️ No profile cache found - will fetch from server');
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

  /// Clear profile cache (including earnings cache)
  Future<void> _clearProfileCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _getProfileCacheKey();

      await prefs.remove('profile_cache_$cacheKey');
      await prefs.remove('profile_cache_timestamp_$cacheKey');
      await prefs.remove('profile_videos_cache_$cacheKey');
      await prefs.remove('profile_videos_cache_timestamp_$cacheKey');

      // **SIMPLIFIED: Clear earnings cache**
      final userId = widget.userId ??
          _stateManager.userData?['googleId'] ??
          _stateManager.userData?['id'];
      if (userId != null) {
        await prefs.remove('earnings_cache_$userId');
        await prefs.remove('earnings_cache_timestamp_$userId');
      }

      ProfileScreenLogger.logDebugInfo(
          'Profile cache cleared (including earnings)');

      final smartCache = SmartCacheManager();
      await smartCache.initialize();
      if (smartCache.isInitialized) {
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

        if (idsToClear.isEmpty) {
          idsToClear.add('self');
        }

        for (final id in idsToClear) {
          final pattern = 'user_profile_$id';
          await smartCache.clearCacheByPattern(pattern);
          AppLogger.log(
              '🧹 ProfileScreen: Cleared SmartCache entry pattern $pattern');
        }
      }
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
      // Always limit the number of concurrent requests so UI doesn't feel stuck
      final now = DateTime.now();
      final currentMonth = now.month - 1; // 0-indexed for backend
      final currentYear = now.year;

      // To keep loading time reasonable, cap the number of videos we query
      final videosToLoad = widget.videos.take(50).toList();

      await Future.wait(
        videosToLoad.map((video) async {
          try {
            final grossEarnings =
                await EarningsService.calculateVideoRevenueForMonth(
              video.id,
              currentMonth,
              currentYear,
            );
            final creatorEarnings =
                EarningsService.creatorShareFromGross(grossEarnings);
            _videoEarnings[video.id] = creatorEarnings;
          } catch (e) {
            _videoEarnings[video.id] = 0.0;
          }
        }),
      );
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
