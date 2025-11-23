import 'package:flutter/material.dart';
import 'package:vayu/utils/responsive_helper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayu/view/screens/creator_revenue_screen.dart';
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
import 'package:vayu/controller/main_controller.dart';
import 'package:vayu/model/video_model.dart';
import 'package:vayu/core/managers/shared_video_controller_pool.dart';
import 'package:vayu/utils/app_logger.dart';
import 'package:vayu/controller/google_sign_in_controller.dart';
import 'package:vayu/services/logout_service.dart';
import 'package:url_launcher/url_launcher.dart';

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

  // **OPTIMIZED: Use ValueNotifiers for granular updates**
  final ValueNotifier<bool> _isLoading = ValueNotifier<bool>(true);
  final ValueNotifier<String?> _error = ValueNotifier<String?>(null);

  // Referral tracking
  final ValueNotifier<int> _invitedCount = ValueNotifier<int>(0);
  final ValueNotifier<int> _verifiedInstalled = ValueNotifier<int>(0);
  final ValueNotifier<int> _verifiedSignedUp = ValueNotifier<int>(0);

  // Local tab state for content section
  // 0 => Your Videos, 1 => My Recommendations
  final ValueNotifier<int> _activeProfileTabIndex = ValueNotifier<int>(0);
  final List<Map<String, dynamic>> _recommendations = [];

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

    // **SIMPLIFIED: Simple cache-first loading**
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

    // **ENHANCED: Use cache-first approach - only load if no data in memory**
    if (_stateManager.userData == null) {
      AppLogger.log(
          '📡 ProfileScreen: Data not loaded, loading from cache or server');
      _loadData(); // This will use cache if available, only fetch from server if no cache
    } else {
      AppLogger.log('✅ ProfileScreen: Data already loaded in memory');
    }
  }

  /// **ENHANCED: Instant cache-first loading - show cached data immediately, refresh in background**
  Future<void> _loadData({bool forceRefresh = false}) async {
    try {
      AppLogger.log(
          '🔄 ProfileScreen: Starting instant cache-first loading (forceRefresh: $forceRefresh)');

      // Step 1: Try cache first (unless forcing refresh)
      if (!forceRefresh) {
        final cachedData = await _loadCachedProfileData();
        if (cachedData != null) {
          AppLogger.log(
              '⚡ ProfileScreen: Using cached data (INSTANT - no server fetch)');

          // **INSTANT: Show cached data immediately (no loading state)**
          _stateManager.setUserData(cachedData);
          await _loadVideosFromCache(); // **FIXED: Wait for videos to load before hiding loading**
          _isLoading.value = false; // Hide loading after videos are loaded

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
                  await _loadVideos();
                  AppLogger.log(
                      '✅ ProfileScreen: Background refresh completed');
                }
              } catch (e) {
                AppLogger.log(
                    '⚠️ ProfileScreen: Background refresh failed: $e');
                // Don't show error - user already has cached data
              }
            });
          }

          return; // Exit early - user sees cached data instantly
        }
      }

      // Step 2: No cache or force refresh - load from server
      _isLoading.value = true;
      _error.value = null;

      AppLogger.log(
          '📡 ProfileScreen: ${forceRefresh ? "Force refreshing" : "No cache, loading"} from server');

      // **OPTIMIZATION: Load profile data first, then videos in background**
      try {
        // Start loading profile data
        await _stateManager.loadUserData(widget.userId);

        if (_stateManager.userData != null) {
          // Cache the loaded data
          await _cacheProfileData(_stateManager.userData!);

          // **OPTIMIZATION: Get user ID and start loading videos in parallel**
          final currentUserId = _stateManager.userData!['googleId'] ??
              _stateManager.userData!['_id'] ??
              _stateManager.userData!['id'];

          if (currentUserId != null) {
            // **OPTIMIZATION: Hide loading state as soon as profile data is ready**
            // Videos will continue loading in background and update UI when ready
            _isLoading.value = false;

            // **OPTIMIZATION: Load videos in background without blocking UI**
            _loadVideos(forceRefresh: forceRefresh).catchError((e) {
              AppLogger.log(
                  '⚠️ ProfileScreen: Error loading videos in background: $e');
              // Don't show error - profile is already shown
            });

            AppLogger.log(
                '✅ ProfileScreen: Profile data loaded, videos loading in background');
          } else {
            // If no user ID, wait for videos anyway (fallback)
            await _loadVideos(forceRefresh: forceRefresh);
            _isLoading.value = false;
          }
        } else {
          _error.value = 'Failed to load profile data';
          _isLoading.value = false;
        }
      } catch (e) {
        AppLogger.log('❌ ProfileScreen: Error loading data: $e');
        _error.value = e.toString();
        _isLoading.value = false;
      }
    } catch (e) {
      AppLogger.log('❌ ProfileScreen: Error loading data: $e');
      // **BATCHED UPDATE: Update error and loading together**
      _error.value = e.toString();
      _isLoading.value = false;
    }
  }

  /// **ENHANCED: Load videos from cache - use cache if exists, only fetch from server if no cache**
  Future<void> _loadVideosFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _getProfileCacheKey();
      final cachedVideosJson =
          prefs.getString('profile_videos_cache_$cacheKey');

      if (cachedVideosJson != null && cachedVideosJson.isNotEmpty) {
        final List<dynamic> cached = json.decode(cachedVideosJson) as List;
        if (cached.isNotEmpty) {
          final videos = cached.map((v) => VideoModel.fromJson(v)).toList();
          AppLogger.log(
              '⚡ ProfileScreen: Loaded ${videos.length} cached videos for $cacheKey (no server fetch)');

          final viewedUserId =
              widget.userId ?? _stateManager.userData?['googleId'];
          final cachedOwnerId =
              videos.isNotEmpty ? videos.first.uploader.id : null;

          if (viewedUserId != null &&
              cachedOwnerId != null &&
              cachedOwnerId.trim().isNotEmpty &&
              cachedOwnerId == viewedUserId) {
            _stateManager.setVideos(videos);
            AppLogger.log(
                '⚡ ProfileScreen: Using cached videos for $viewedUserId');
            return;
          }

          AppLogger.log(
              'ℹ️ ProfileScreen: Cached videos belong to $cachedOwnerId but viewing $viewedUserId. Fetching fresh data.');
        } else {
          AppLogger.log(
              'ℹ️ ProfileScreen: Cached videos empty; fetching from server');
        }
      } else {
        AppLogger.log(
            'ℹ️ ProfileScreen: No video cache found; fetching from server');
      }

      // No cache or cache mismatch → load from server
      await _loadVideos();
    } catch (e) {
      AppLogger.log('❌ ProfileScreen: Error loading videos from cache: $e');
      await _loadVideos();
    }
  }

  /// **OPTIMIZED: Load videos from server (can run in background)**
  Future<void> _loadVideos({bool forceRefresh = false}) async {
    try {
      if (_stateManager.userData == null) {
        // **OPTIMIZATION: Wait briefly for profile data if not ready yet**
        await Future.delayed(const Duration(milliseconds: 100));
        if (_stateManager.userData == null) {
          AppLogger.log(
              '⚠️ ProfileScreen: User data not ready, skipping video load');
          return;
        }
      }

      final currentUserId = _stateManager.userData!['googleId'] ??
          _stateManager.userData!['_id'] ??
          _stateManager.userData!['id'];

      if (currentUserId != null) {
        AppLogger.log(
            '📡 ProfileScreen: Loading videos from server for user: $currentUserId (forceRefresh: $forceRefresh)');

        // **FIX: If force refresh, clear video cache first**
        if (forceRefresh) {
          final prefs = await SharedPreferences.getInstance();
          final cacheKey = _getProfileCacheKey();
          await prefs.remove('profile_videos_cache_$cacheKey');
          await prefs.remove('profile_videos_cache_timestamp_$cacheKey');

          // Also clear smart cache
          final smartCache = SmartCacheManager();
          await smartCache.initialize();
          if (smartCache.isInitialized) {
            final videoCacheKey = 'video_profile_$currentUserId';
            await smartCache.clearCacheByPattern(videoCacheKey);
            AppLogger.log('🧹 ProfileScreen: Cleared video cache for refresh');
          }
        }

        await _stateManager.loadUserVideos(currentUserId);

        // Cache the videos
        await _cacheVideos();

        AppLogger.log(
            '✅ ProfileScreen: Loaded ${_stateManager.userVideos.length} videos');
      }
    } catch (e) {
      AppLogger.log('❌ ProfileScreen: Error loading videos: $e');
      // **OPTIMIZATION: Don't throw error - let videos load in background**
      // Profile is already shown, videos can fail silently
    }
  }

  /// **SIMPLIFIED: Cache videos to SharedPreferences**
  Future<void> _cacheVideos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _getProfileCacheKey();

      final videosJson =
          _stateManager.userVideos.map((v) => v.toJson()).toList();
      await prefs.setString(
          'profile_videos_cache_$cacheKey', json.encode(videosJson));
      await prefs.setInt('profile_videos_cache_timestamp_$cacheKey',
          DateTime.now().millisecondsSinceEpoch);

      AppLogger.log('✅ ProfileScreen: Videos cached successfully');
    } catch (e) {
      AppLogger.log('❌ ProfileScreen: Error caching videos: $e');
    }
  }

  /// **ENHANCED: Manual refresh - clear cache and fetch fresh data from server**
  Future<void> _refreshData() async {
    AppLogger.log(
        '🔄 ProfileScreen: Manual refresh - clearing cache and fetching from server');

    try {
      // Clear cache to force fresh load
      await _clearProfileCache();

      // **FIX: Force refresh both user data and videos**
      _isLoading.value = true;
      _error.value = null;

      // Reload user data with force refresh flag
      await _loadData(forceRefresh: true);

      // **FIX: Explicitly reload videos after user data is loaded**
      if (_stateManager.userData != null) {
        final currentUserId = _stateManager.userData!['googleId'] ??
            _stateManager.userData!['_id'] ??
            _stateManager.userData!['id'];

        if (currentUserId != null) {
          AppLogger.log(
              '🔄 ProfileScreen: Refreshing videos for user: $currentUserId');

          // **FIX: Force refresh videos (clear cache first)**
          await _loadVideos(forceRefresh: true);

          AppLogger.log(
              '✅ ProfileScreen: Refreshed ${_stateManager.userVideos.length} videos');
        }
      }

      _isLoading.value = false;
      AppLogger.log('✅ ProfileScreen: Manual refresh completed');
    } catch (e) {
      AppLogger.log('❌ ProfileScreen: Error during refresh: $e');
      _error.value = 'Failed to refresh: ${e.toString()}';
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

  /// **FIXED: Use GoogleSignInController Provider for unified auth state**
  Future<void> _handleGoogleSignIn() async {
    try {
      ProfileScreenLogger.logGoogleSignIn();
      final authController =
          Provider.of<GoogleSignInController>(context, listen: false);

      final userData = await authController.signIn();
      if (userData != null) {
        // Update ProfileStateManager with new auth data
        await _stateManager
            .loadUserData(userData['id'] ?? userData['googleId']);
        _refreshData();

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
            SnackBar(
              content: Text(
                  authController.error ?? 'Sign-in failed. Please try again.'),
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
            content: Text('Error signing in: $e'),
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

      // **ENHANCED: Update videos cache immediately after deletion (no server fetch needed)**
      await _cacheVideos();
      AppLogger.log(
          '✅ ProfileScreen: Updated videos cache immediately after deletion');

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
      // **FIX: Pause all video controllers to prevent audio leak**
      AppLogger.log(
          '🔇 ProfileScreen: Pausing all videos before profile photo change');
      _pauseAllVideoControllers();

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

        // **ENHANCED: Update cache immediately with new data (no server fetch needed)**
        if (_stateManager.userData != null) {
          await _cacheProfileData(_stateManager.userData!);
          AppLogger.log(
              '✅ ProfileScreen: Updated profile cache immediately after photo update');
        }

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
      child: Consumer<GoogleSignInController>(
        builder: (context, authController, _) {
          // **FIX: Only sync with logged in user if viewing own profile (widget.userId is null)**
          // If widget.userId is provided, we're viewing someone else's profile - don't override it
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (widget.userId == null ||
                (authController.isSignedIn &&
                    authController.userData != null)) {
              final loggedInUserId = authController.userData?['id'] ??
                  authController.userData?['googleId'];

              // If viewing own profile (widget.userId is null), sync with logged in user
              if (widget.userId == null && loggedInUserId != null) {
                final currentUserId = _stateManager.userData?['id'] ??
                    _stateManager.userData?['googleId'];
                if (currentUserId != loggedInUserId) {
                  AppLogger.log(
                      '🔄 ProfileScreen: Syncing with logged in user: $loggedInUserId');
                  _stateManager.loadUserData(null); // null = own profile
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
    // **FIXED: Check authentication status first - if viewing own profile and not signed in, show sign-in view**
    // If viewing someone else's profile (widget.userId != null), show their profile even if not signed in
    if (widget.userId == null && !authController.isSignedIn) {
      return _buildSignInView();
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

                          // **SIMPLIFIED: Simple retry button**
                          TextButton.icon(
                            onPressed: _loadData,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.blue,
                            ),
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
                            'Failed to load profile data',
                            style: TextStyle(
                              color: Colors.red[700],
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          TextButton.icon(
                            onPressed: _loadData,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.blue,
                            ),
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
                    stateManager.userData?['name'] ?? 'Profile',
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
      const SnackBar(
        content:
            Text('Unable to open WhatsApp right now. Please try again later.'),
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
          // Stats Section
          ProfileStatsWidget(
            stateManager: _stateManager,
            userId: widget.userId,
            isVideosLoaded: _stateManager.userVideos.isNotEmpty,
            isFollowersLoaded: true,
            onFollowersTap: () {
              // **SIMPLIFIED: Simple followers tap**
              AppLogger.log('🔄 ProfileScreen: Followers tapped');
            },
            onEarningsTap: isViewingOwnProfile
                ? () async {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CreatorRevenueScreen(),
                      ),
                    );
                  }
                : null,
          ),

          const SizedBox(height: 24),

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
                      label: const Text(
                        'Refer 2 friends and get full access',
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
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
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

  /// Simple Recommendations placeholder grid (creator suggested products)
  Widget _buildRecommendationsSection() {
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_recommendations.isEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(vertical: 32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: const Center(
                  child: Text(
                    'No Recommendations',
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.9,
                ),
                itemCount: _recommendations.length,
                itemBuilder: (context, index) {
                  final item = _recommendations[index];
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(12),
                              topRight: Radius.circular(12),
                            ),
                            child: Container(
                              color: const Color(0xFFF3F4F6),
                              child: const Center(
                                child: Icon(Icons.shopping_bag,
                                    color: Color(0xFF9CA3AF)),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          child: Text(
                            item['title'] ?? 'Recommended product',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF111827),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Padding(
                          padding:
                              EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          child: Text(
                            'Creator suggested',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  );
                },
              ),
          ],
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

  /// Clear profile cache (including earnings cache)
  Future<void> _clearProfileCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _getProfileCacheKey();

      await prefs.remove('profile_cache_$cacheKey');
      await prefs.remove('profile_cache_timestamp_$cacheKey');
      await prefs.remove('profile_videos_cache_$cacheKey');
      await prefs.remove('profile_videos_cache_timestamp_$cacheKey');

      // **NEW: Clear earnings cache for this user**
      // Clear all earnings cache entries that match this user's ID
      final userId = widget.userId ??
          _stateManager.userData?['googleId'] ??
          _stateManager.userData?['id'];
      if (userId != null) {
        // Get all keys and remove earnings cache entries for this user
        final allKeys = prefs.getKeys();
        for (final key in allKeys) {
          if (key.startsWith('earnings_cache_$userId')) {
            await prefs.remove(key);
            AppLogger.log('🧹 ProfileScreen: Cleared earnings cache: $key');
          }
        }
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
