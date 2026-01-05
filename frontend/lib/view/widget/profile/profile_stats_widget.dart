import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vayu/core/managers/profile_state_manager.dart';
import 'package:vayu/core/providers/user_provider.dart';
import 'package:vayu/core/services/profile_screen_logger.dart';
import 'package:vayu/services/earnings_service.dart';
import 'package:vayu/services/authservices.dart';
import 'package:vayu/config/app_config.dart';
import 'package:vayu/utils/app_logger.dart';
import 'dart:convert';
import 'package:vayu/core/services/http_client_service.dart';

class ProfileStatsWidget extends StatefulWidget {
  final ProfileStateManager stateManager;
  final String? userId;
  final bool isVideosLoaded;
  final bool isFollowersLoaded;
  final VoidCallback? onFollowersTap;
  final VoidCallback? onEarningsTap;
  final int? refreshKey; // **NEW: Key to force refresh when profile refreshes**

  const ProfileStatsWidget({
    super.key,
    required this.stateManager,
    this.userId,
    required this.isVideosLoaded,
    required this.isFollowersLoaded,
    this.onFollowersTap,
    this.onEarningsTap,
    this.refreshKey, // **NEW: Optional refresh key**
  });

  @override
  State<ProfileStatsWidget> createState() => _ProfileStatsWidgetState();
}

class _ProfileStatsWidgetState extends State<ProfileStatsWidget> {
  double _earnings = 0.0;
  bool _isLoadingEarnings = true;
  int _lastVideoCount = -1;
  final AuthService _authService = AuthService();

  // **NEW: Static cache for creator earnings (shared across all instances)**
  static final Map<String, double> _creatorEarningsCache = {};
  static final Map<String, DateTime> _creatorEarningsCacheTimestamp = {};

  @override
  void initState() {
    super.initState();
    _attachStateManagerListener();
    _loadEarnings();
  }

  @override
  void didUpdateWidget(ProfileStatsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Rewire listener if stateManager instance changed
    if (oldWidget.stateManager != widget.stateManager) {
      oldWidget.stateManager.removeListener(_onStateManagerChanged);
      _attachStateManagerListener();
    }

    // **NEW: Reload earnings if refresh key changed (profile was refreshed)**
    if (widget.refreshKey != null &&
        widget.refreshKey != oldWidget.refreshKey) {
      AppLogger.log(
          '🔄 ProfileStatsWidget: Refresh key changed, reloading earnings...');
      _loadEarnings(forceRefresh: true);
    }
  }

  void _attachStateManagerListener() {
    _lastVideoCount = widget.stateManager.userVideos.length;
    widget.stateManager.addListener(_onStateManagerChanged);
  }

  void _onStateManagerChanged() {
    final currentCount = widget.stateManager.userVideos.length;
    if (currentCount != _lastVideoCount) {
      _lastVideoCount = currentCount;
      // **FIXED: Only recalculate when videos finish loading (even if count is 0)**
      if (!widget.stateManager.isVideosLoading) {
        _loadEarnings();
      }
    }
  }

  @override
  void dispose() {
    widget.stateManager.removeListener(_onStateManagerChanged);
    super.dispose();
  }

  /// **OPTIMIZED: Calculate current month earnings from videos (parallel processing like CreatorRevenueScreen)**
  Future<double> _calculateCurrentMonthEarnings() async {
    try {
      if (widget.stateManager.userVideos.isEmpty) {
        return 0.0;
      }

      final now = DateTime.now();
      final currentMonth = now.month - 1; // 0-indexed for backend
      final currentYear = now.year;

      AppLogger.log(
          '💰 ProfileStatsWidget: Calculating current month (${now.month}/$currentYear) earnings for ${widget.stateManager.userVideos.length} videos');

      // **OPTIMIZED: Calculate all videos in parallel (like CreatorRevenueScreen)**
      final earningsFutures = widget.stateManager.userVideos.map((video) async {
        try {
          final grossEarnings =
              await EarningsService.calculateVideoRevenueForMonth(
            video.id,
            currentMonth,
            currentYear,
            timeout:
                const Duration(seconds: 2), // **OPTIMIZED: Faster timeout**
          );
          return EarningsService.creatorShareFromGross(grossEarnings);
        } catch (e) {
          AppLogger.log(
              '⚠️ ProfileStatsWidget: Error calculating earnings for video ${video.id}: $e');
          return 0.0;
        }
      }).toList();

      // **OPTIMIZED: Wait for all calculations in parallel**
      final earnings = await Future.wait(earningsFutures);
      final totalCreatorEarnings =
          earnings.fold<double>(0.0, (sum, earning) => sum + earning);

      AppLogger.log(
          '💰 ProfileStatsWidget: Current month earnings calculated: ₹${totalCreatorEarnings.toStringAsFixed(2)}');

      return totalCreatorEarnings;
    } catch (e) {
      AppLogger.log(
          '❌ ProfileStatsWidget: Error calculating current month earnings: $e');
      return 0.0;
    }
  }

  /// **FIXED: Load monthly earnings from backend API (not all-time)**
  /// **ENHANCED: Uses backend API which calculates current month earnings correctly**
  Future<void> _loadEarnings({bool forceRefresh = false}) async {
    // **FIXED: Don't show 0 if videos are still loading**
    if (widget.stateManager.isVideosLoading) {
      // Keep loading state, don't set to 0 yet
      if (mounted) {
        setState(() {
          _isLoadingEarnings = true;
        });
      }
      return;
    }

    // **OPTIMIZED: For other creators, show cached earnings immediately, load fresh in background**
    // This provides instant earnings display with fresh data update
    if (widget.userId != null) {
      final creatorId = widget.userId!;
      final cacheKey = 'creator_earnings_$creatorId';
      final now = DateTime.now();

      // **STEP 1: Check cache first - show immediately if available (unless force refresh)**
      // **CRITICAL: Manual refresh bypasses cache completely**
      double? cachedEarnings;
      DateTime? cacheTime;

      if (!forceRefresh) {
        cachedEarnings = _creatorEarningsCache[cacheKey];
        cacheTime = _creatorEarningsCacheTimestamp[cacheKey];

        if (cachedEarnings != null && cacheTime != null) {
          final cacheAge = now.difference(cacheTime);
          // **OPTIMIZED: Use 1-hour cache for other creators (balance between freshness and performance)**
          final cacheDuration = const Duration(hours: 1);
          if (cacheAge < cacheDuration) {
            AppLogger.log(
                '⚡ ProfileStatsWidget: Using cached earnings for creator $creatorId (${cacheAge.inMinutes}m old): ₹${cachedEarnings.toStringAsFixed(2)}');
            if (mounted) {
              setState(() {
                _earnings = cachedEarnings!;
                _isLoadingEarnings = false;
              });
            }
            // **OPTIMIZED: Still fetch fresh in background (non-blocking)**
            // This ensures cache is updated even if user doesn't manually refresh
            _fetchFreshEarningsInBackground(creatorId, cacheKey);
            return;
          } else {
            AppLogger.log(
                '🔄 ProfileStatsWidget: Cache expired for creator $creatorId (${cacheAge.inHours}h old), fetching fresh...');
          }
        }
      } else {
        AppLogger.log(
            '🔄 ProfileStatsWidget: Force refresh requested - bypassing cache for creator $creatorId');
      }

      // **STEP 2: No cache or cache expired or force refresh - calculate IMMEDIATELY (like CreatorRevenueScreen)**
      if (widget.stateManager.userVideos.isNotEmpty) {
        // **CRITICAL FIX: Calculate frontend earnings IMMEDIATELY (not in background)**
        // This ensures earnings show instantly, just like CreatorRevenueScreen
        try {
          AppLogger.log(
              '💰 ProfileStatsWidget: Calculating earnings IMMEDIATELY for creator profile (${forceRefresh ? "force refresh" : "no cache"})...');

          // **OPTIMIZED: Calculate earnings immediately using parallel processing**
          final totalRevenue =
              await EarningsService.calculateCreatorTotalRevenueForVideos(
            widget.stateManager.userVideos,
            timeout:
                const Duration(seconds: 2), // **OPTIMIZED: Faster timeout**
          );

          // **CACHE: Store earnings in cache**
          _creatorEarningsCache[cacheKey] = totalRevenue;
          _creatorEarningsCacheTimestamp[cacheKey] = now;

          if (mounted) {
            setState(() {
              _earnings = totalRevenue;
              _isLoadingEarnings = false;
            });
            AppLogger.log(
                '✅ ProfileStatsWidget: Earnings calculated and cached IMMEDIATELY: ₹${totalRevenue.toStringAsFixed(2)}');
          }
        } catch (e) {
          AppLogger.log(
              '⚠️ ProfileStatsWidget: Earnings calculation failed: $e');
          // **FALLBACK: Use cached value even if calculation fails**
          if (cachedEarnings != null && mounted) {
            setState(() {
              _earnings = cachedEarnings!;
              _isLoadingEarnings = false;
            });
          } else if (mounted) {
            setState(() {
              _earnings = 0.0;
              _isLoadingEarnings = false;
            });
          }
        }
      } else {
        // No videos - show 0 immediately
        if (mounted) {
          setState(() {
            _earnings = 0.0;
            _isLoadingEarnings = false;
          });
        }
        // Cache 0 earnings too
        _creatorEarningsCache[cacheKey] = 0.0;
        _creatorEarningsCacheTimestamp[cacheKey] = now;
      }
      return;
    }

    // **OWN PROFILE: Use backend API for monthly earnings**
    if (mounted) {
      setState(() {
        _isLoadingEarnings = true;
      });
    }

    // **OWN PROFILE: Load earnings from backend API**
    await _loadOwnProfileEarnings(forceRefresh: forceRefresh);
  }

  /// **NEW: Fetch fresh earnings in background (non-blocking) for creators**
  Future<void> _fetchFreshEarningsInBackground(
      String creatorId, String cacheKey) async {
    try {
      if (widget.stateManager.userVideos.isEmpty) {
        return;
      }

      AppLogger.log(
          '🔄 ProfileStatsWidget: Fetching fresh earnings in background for creator: $creatorId');

      // Calculate earnings from videos
      final earnings =
          await EarningsService.calculateCreatorTotalRevenueForVideos(
        widget.stateManager.userVideos,
        timeout: const Duration(seconds: 3),
      );

      // **UPDATE CACHE: Store fresh earnings**
      _creatorEarningsCache[cacheKey] = earnings;
      _creatorEarningsCacheTimestamp[cacheKey] = DateTime.now();

      // **UPDATE UI: Only update if value changed significantly (avoid flicker)**
      if (mounted && (_earnings - earnings).abs() > 0.01) {
        setState(() {
          _earnings = earnings;
        });
        AppLogger.log(
            '✅ ProfileStatsWidget: Background earnings updated for creator $creatorId: ₹${earnings.toStringAsFixed(2)}');
      } else {
        AppLogger.log(
            'ℹ️ ProfileStatsWidget: Background earnings unchanged for creator $creatorId: ₹${earnings.toStringAsFixed(2)}');
      }
    } catch (e) {
      // Silent fail - keep showing cached value
      AppLogger.log(
          '⚠️ ProfileStatsWidget: Background earnings fetch failed (non-critical): $e');
    }
  }

  // **OWN PROFILE: Continue with backend API call**
  Future<void> _loadOwnProfileEarnings({bool forceRefresh = false}) async {
    try {
      final userData = await _authService.getUserData();
      if (userData == null) {
        AppLogger.log(
            '⚠️ ProfileStatsWidget: No user data, showing 0 earnings');
        if (mounted) {
          setState(() {
            _earnings = 0.0;
            _isLoadingEarnings = false;
          });
        }
        return;
      }

      final userId = userData['googleId'] ?? userData['id'];
      if (userId == null) {
        AppLogger.log('⚠️ ProfileStatsWidget: No userId, showing 0 earnings');
        if (mounted) {
          setState(() {
            _earnings = 0.0;
            _isLoadingEarnings = false;
          });
        }
        return;
      }

      AppLogger.log(
          '💰 ProfileStatsWidget: Loading monthly earnings from backend API for user: $userId');

      // **FIX: Use backend API which returns current month earnings**
      final baseUrl = await AppConfig.getBaseUrlWithFallback();

      // **FIX: Add timestamp to prevent caching when force refresh**
      final uri = forceRefresh
          ? Uri.parse(
              '$baseUrl/api/ads/creator/revenue/$userId?_t=${DateTime.now().millisecondsSinceEpoch}')
          : Uri.parse('$baseUrl/api/ads/creator/revenue/$userId');

      AppLogger.log(
          '📡 ProfileStatsWidget: Fetching earnings from: $uri (forceRefresh: $forceRefresh)');

      final response = await httpClientService.get(
        uri,
        headers: {
          'Authorization': 'Bearer ${userData['token']}',
        },
        timeout: const Duration(seconds: 8),
      );

      if (response.statusCode == 200) {
        // **DEBUG: Log raw response to diagnose issues**
        AppLogger.log(
            '🔍 ProfileStatsWidget: API response body: ${response.body}');

        if (response.body.isEmpty) {
          AppLogger.log(
              '⚠️ ProfileStatsWidget: Empty response body from API - trying frontend calculation as fallback');
          // **FIX: Try frontend calculation before showing 0**
          if (widget.stateManager.userVideos.isNotEmpty) {
            try {
              final frontendCalculated = await _calculateCurrentMonthEarnings();
              if (frontendCalculated > 0.0) {
                AppLogger.log(
                  '✅ ProfileStatsWidget: Empty API response but frontend calculated ₹${frontendCalculated.toStringAsFixed(2)} - using frontend calculation',
                );
                if (mounted) {
                  setState(() {
                    _earnings = frontendCalculated;
                    _isLoadingEarnings = false;
                  });
                }
                return;
              }
            } catch (e) {
              AppLogger.log(
                '⚠️ ProfileStatsWidget: Frontend calculation fallback failed: $e',
              );
            }
          }
          // Only show 0 if frontend calculation also fails or no videos
          if (mounted) {
            setState(() {
              _earnings = 0.0;
              _isLoadingEarnings = false;
            });
          }
          return;
        }

        final data = json.decode(response.body) as Map<String, dynamic>;

        // **DEBUG: Log full response data**
        AppLogger.log(
          '🔍 ProfileStatsWidget: Full API response - thisMonth: ${data['thisMonth']}, lastMonth: ${data['lastMonth']}, totalRevenue: ${data['totalRevenue']}, adRevenue: ${data['adRevenue']}',
        );

        // **USE CURRENT MONTH EARNINGS (not all-time)**
        final thisMonthEarnings =
            (data['thisMonth'] as num?)?.toDouble() ?? 0.0;

        AppLogger.log(
          '💰 ProfileStatsWidget: Monthly earnings loaded from API: ₹${thisMonthEarnings.toStringAsFixed(2)} (this month)',
        );

        // **FIX: If API returns 0, ALWAYS try frontend calculation as fallback**
        double finalEarnings = thisMonthEarnings;
        if (thisMonthEarnings == 0.0) {
          // **ENHANCED: Always try frontend calculation if API returns 0, even if videos are loading**
          // Wait a bit for videos to load if they're still loading
          if (widget.stateManager.isVideosLoading) {
            AppLogger.log(
              '⏳ ProfileStatsWidget: Videos still loading, waiting for videos before frontend calculation...',
            );
            // Wait up to 3 seconds for videos to load
            for (int i = 0; i < 6; i++) {
              await Future.delayed(const Duration(milliseconds: 500));
              if (!widget.stateManager.isVideosLoading) {
                break;
              }
            }
          }

          if (widget.stateManager.userVideos.isNotEmpty) {
            try {
              final frontendCalculated = await _calculateCurrentMonthEarnings();
              if (frontendCalculated > 0.0) {
                AppLogger.log(
                  '✅ ProfileStatsWidget: API returned 0 but frontend calculated ₹${frontendCalculated.toStringAsFixed(2)} - using frontend calculation',
                );
                finalEarnings = frontendCalculated;
              } else {
                AppLogger.log(
                  '⚠️ ProfileStatsWidget: API returned 0 and frontend calculation also returned 0',
                );
              }
            } catch (e) {
              AppLogger.log(
                '⚠️ ProfileStatsWidget: Frontend calculation fallback failed: $e',
              );
            }
          } else {
            AppLogger.log(
              '⚠️ ProfileStatsWidget: API returned 0 but no videos available for frontend calculation',
            );
          }
        }

        if (mounted) {
          setState(() {
            _earnings = finalEarnings;
            _isLoadingEarnings = false;
          });
        }
      } else {
        AppLogger.log(
            '⚠️ ProfileStatsWidget: API returned status ${response.statusCode}, body: ${response.body}');
        // **FIXED: Fallback to CURRENT MONTH calculation (not all-time)**
        if (widget.stateManager.userVideos.isNotEmpty) {
          try {
            final currentMonthRevenue = await _calculateCurrentMonthEarnings();
            AppLogger.log(
                '💰 ProfileStatsWidget: Using fallback calculation (CURRENT MONTH): ₹${currentMonthRevenue.toStringAsFixed(2)}');
            if (mounted) {
              setState(() {
                _earnings = currentMonthRevenue;
                _isLoadingEarnings = false;
              });
            }
          } catch (e) {
            AppLogger.log(
                '❌ ProfileStatsWidget: Fallback calculation failed: $e');
            if (mounted) {
              setState(() {
                _earnings = 0.0;
                _isLoadingEarnings = false;
              });
            }
          }
        } else {
          // **FIX: Try frontend calculation even when videos list is empty (might be loading)**
          // Wait a bit for videos to load if they're still loading
          if (widget.stateManager.isVideosLoading) {
            AppLogger.log(
              '⏳ ProfileStatsWidget: Videos still loading, waiting before frontend calculation...',
            );
            // Wait up to 3 seconds for videos to load
            for (int i = 0; i < 6; i++) {
              await Future.delayed(const Duration(milliseconds: 500));
              if (!widget.stateManager.isVideosLoading) {
                break;
              }
            }
          }

          if (widget.stateManager.userVideos.isNotEmpty) {
            try {
              final currentMonthRevenue =
                  await _calculateCurrentMonthEarnings();
              if (currentMonthRevenue > 0.0) {
                AppLogger.log(
                  '✅ ProfileStatsWidget: API failed but frontend calculated ₹${currentMonthRevenue.toStringAsFixed(2)} - using frontend calculation',
                );
                if (mounted) {
                  setState(() {
                    _earnings = currentMonthRevenue;
                    _isLoadingEarnings = false;
                  });
                }
                return;
              }
            } catch (e) {
              AppLogger.log(
                '⚠️ ProfileStatsWidget: Frontend calculation failed: $e',
              );
            }
          }

          // Only show 0 if frontend calculation also fails or no videos
          if (mounted) {
            setState(() {
              _earnings = 0.0;
              _isLoadingEarnings = false;
            });
          }
        }
      }
    } catch (e, stackTrace) {
      AppLogger.log('❌ ProfileStatsWidget: Error loading earnings: $e');
      AppLogger.log('Stack trace: $stackTrace');

      // **DEBUG: Log more details about the error**
      if (e.toString().contains('timeout') ||
          e.toString().contains('TimeoutException')) {
        AppLogger.log(
            '⚠️ ProfileStatsWidget: Request timed out - API might be slow');
      } else if (e.toString().contains('SocketException') ||
          e.toString().contains('network')) {
        AppLogger.log(
            '⚠️ ProfileStatsWidget: Network error - check internet connection');
      } else if (e.toString().contains('FormatException') ||
          e.toString().contains('json')) {
        AppLogger.log(
            '⚠️ ProfileStatsWidget: JSON parsing error - API response might be malformed');
      }

      // **FIXED: Fallback to CURRENT MONTH calculation on error (not all-time)**
      // **ENHANCED: Wait for videos to load if they're still loading**
      if (widget.stateManager.isVideosLoading) {
        AppLogger.log(
          '⏳ ProfileStatsWidget: Videos still loading, waiting before fallback calculation...',
        );
        // Wait up to 3 seconds for videos to load
        for (int i = 0; i < 6; i++) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (!widget.stateManager.isVideosLoading) {
            break;
          }
        }
      }

      if (widget.stateManager.userVideos.isNotEmpty) {
        try {
          AppLogger.log(
              '🔄 ProfileStatsWidget: Attempting fallback calculation (CURRENT MONTH) from videos...');
          final currentMonthRevenue = await _calculateCurrentMonthEarnings();
          if (currentMonthRevenue > 0.0) {
            AppLogger.log(
                '✅ ProfileStatsWidget: Fallback calculation result (CURRENT MONTH): ₹${currentMonthRevenue.toStringAsFixed(2)}');
            if (mounted) {
              setState(() {
                _earnings = currentMonthRevenue;
                _isLoadingEarnings = false;
              });
            }
          } else {
            AppLogger.log(
                '⚠️ ProfileStatsWidget: Fallback calculation returned 0');
            if (mounted) {
              setState(() {
                _earnings = 0.0;
                _isLoadingEarnings = false;
              });
            }
          }
        } catch (fallbackError) {
          AppLogger.log(
              '❌ ProfileStatsWidget: Fallback calculation also failed: $fallbackError');
          if (mounted) {
            setState(() {
              _earnings = 0.0;
              _isLoadingEarnings = false;
            });
          }
        }
      } else {
        AppLogger.log(
            '⚠️ ProfileStatsWidget: No videos available for fallback calculation');
        if (mounted) {
          setState(() {
            _earnings = 0.0;
            _isLoadingEarnings = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Consumer<ProfileStateManager>(
          builder: (context, stateManager, child) {
            // **FIXED: Also listen to UserProvider to get real-time follower count updates**
            return Consumer<UserProvider>(
              builder: (context, userProvider, child) {
                final videosLoading = stateManager.isVideosLoading;
                final videoCountValue =
                    videosLoading ? '...' : stateManager.userVideos.length;

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatColumn(
                      'Videos',
                      videoCountValue,
                      isLoading: videosLoading,
                    ),
                    Container(
                        width: 1, height: 40, color: const Color(0xFFE5E7EB)),
                    _buildStatColumn(
                      'Followers',
                      widget.isFollowersLoaded
                          ? _getFollowersCount(context)
                          : '...',
                      isLoading: !widget.isFollowersLoaded,
                      onTap: widget.onFollowersTap,
                    ),
                    Container(
                        width: 1, height: 40, color: const Color(0xFFE5E7EB)),
                    _buildStatColumn(
                      'Earnings',
                      _isLoadingEarnings ? '...' : _earnings,
                      isEarnings: true,
                      isLoading: _isLoadingEarnings,
                      onTap: widget.onEarningsTap,
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatColumn(
    String label,
    dynamic value, {
    bool isEarnings = false,
    VoidCallback? onTap,
    bool isLoading = false,
  }) {
    return RepaintBoundary(
      child: Builder(
        builder: (context) => Column(
          children: [
            GestureDetector(
              onTap: onTap,
              child: MouseRegion(
                cursor: isEarnings && onTap != null
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
                child: Text(
                  isLoading
                      ? '...'
                      : (isEarnings
                          ? '₹${(value is double ? value : double.tryParse(value.toString()) ?? 0.0).toStringAsFixed(2)}'
                          : value.toString()),
                  style: const TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
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
      ),
    );
  }

  // Helper method to get followers count using MongoDB ObjectID
  int _getFollowersCount(BuildContext context) {
    ProfileScreenLogger.logDebugInfo('=== GETTING FOLLOWERS COUNT ===');
    ProfileScreenLogger.logDebugInfo('userId: ${widget.userId}');
    ProfileScreenLogger.logDebugInfo(
      'stateManager.userData: ${widget.stateManager.userData != null}',
    );

    // **FIXED: Prioritize ProfileStateManager.userData first (loaded immediately)**
    // This ensures follower count displays immediately when viewing another creator's profile
    if (widget.stateManager.userData != null) {
      // Try both field names for compatibility
      final followersCount = widget.stateManager.userData!['followersCount'] ??
          widget.stateManager.userData!['followers'];

      if (followersCount != null && followersCount != 0) {
        ProfileScreenLogger.logDebugInfo(
          '✅ Using followers count from ProfileStateManager: $followersCount',
        );
        return followersCount is int
            ? followersCount
            : (int.tryParse(followersCount.toString()) ?? 0);
      }
    }

    // **FALLBACK: Check UserProvider cache (populated asynchronously)**
    final List<String> idsToTry = <String?>[
      widget.userId,
      widget.stateManager.userData?['googleId'],
      widget.stateManager.userData?['_id'] ??
          widget.stateManager.userData?['id'],
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
        if (userModel?.followersCount != null &&
            userModel!.followersCount > 0) {
          ProfileScreenLogger.logDebugInfo(
            '✅ Using followers count from UserProvider for $candidateId: ${userModel.followersCount}',
          );
          return userModel.followersCount;
        }
      }
    }

    // Final fallback
    ProfileScreenLogger.logDebugInfo(
      '⚠️ No followers count available, using default: 0',
    );
    return 0;
  }
}
