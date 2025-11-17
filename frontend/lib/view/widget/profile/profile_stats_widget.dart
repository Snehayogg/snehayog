import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayu/core/managers/profile_state_manager.dart';
import 'package:vayu/core/providers/user_provider.dart';
import 'package:vayu/core/services/profile_screen_logger.dart';
import 'package:vayu/services/earnings_service.dart';
import 'package:vayu/utils/app_logger.dart';

class ProfileStatsWidget extends StatefulWidget {
  final ProfileStateManager stateManager;
  final String? userId;
  final bool isVideosLoaded;
  final bool isFollowersLoaded;
  final VoidCallback? onFollowersTap;
  final VoidCallback? onEarningsTap;

  const ProfileStatsWidget({
    super.key,
    required this.stateManager,
    this.userId,
    required this.isVideosLoaded,
    required this.isFollowersLoaded,
    this.onFollowersTap,
    this.onEarningsTap,
  });

  @override
  State<ProfileStatsWidget> createState() => _ProfileStatsWidgetState();
}

class _ProfileStatsWidgetState extends State<ProfileStatsWidget> {
  double _earnings = 0.0;
  bool _isLoadingEarnings = true;
  int _lastVideoCount = -1;

  @override
  void initState() {
    super.initState();
    _attachStateManagerListener();
    // **NEW: Try to load cached earnings first, then calculate if needed**
    _loadEarningsFromCache();
    _loadEarnings();
  }

  /// **NEW: Load earnings from cache if available (non-blocking)**
  Future<void> _loadEarningsFromCache() async {
    final cacheKey = _getEarningsCacheKey();
    if (cacheKey == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedEarningsJson = prefs.getString('earnings_cache_$cacheKey');
      final cachedTimestamp =
          prefs.getInt('earnings_cache_timestamp_$cacheKey');

      if (cachedEarningsJson != null && cachedTimestamp != null) {
        final cacheTime = DateTime.fromMillisecondsSinceEpoch(cachedTimestamp);
        final age = DateTime.now().difference(cacheTime);

        // Use cache if it's less than 1 day old
        if (age.inDays < 1) {
          final cachedEarnings = double.tryParse(cachedEarningsJson) ?? 0.0;
          if (mounted) {
            setState(() {
              _earnings = cachedEarnings;
              _isLoadingEarnings = false;
            });
          }
          AppLogger.log(
            '💰 ProfileStatsWidget: Loaded cached earnings on init: ₹${cachedEarnings.toStringAsFixed(2)}',
          );
        }
      }
    } catch (e) {
      AppLogger.log(
          '⚠️ ProfileStatsWidget: Error loading cached earnings on init: $e');
    }
  }

  @override
  void didUpdateWidget(ProfileStatsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Rewire listener if stateManager instance changed
    if (oldWidget.stateManager != widget.stateManager) {
      oldWidget.stateManager.removeListener(_onStateManagerChanged);
      _attachStateManagerListener();
    }

    // Reload if parent indicates load state changed
    if (widget.isVideosLoaded != oldWidget.isVideosLoaded) {
      _loadEarnings();
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
      // **FIXED: Only recalculate if videos are actually loaded and count changed meaningfully**
      if (widget.isVideosLoaded && currentCount > 0) {
        _loadEarnings();
      }
    }
  }

  @override
  void dispose() {
    widget.stateManager.removeListener(_onStateManagerChanged);
    super.dispose();
  }

  /// **FIXED: Load earnings with caching - check cache first, then calculate if needed**
  /// **ENHANCED: Works for any creator's videos (own profile or other creators)**
  Future<void> _loadEarnings() async {
    // **FIXED: Don't show 0 if videos are still loading**
    if (!widget.isVideosLoaded) {
      // Keep loading state, don't set to 0 yet
      if (mounted) {
        setState(() {
          _isLoadingEarnings = true;
        });
      }
      return;
    }

    if (widget.stateManager.userVideos.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoadingEarnings = false;
          _earnings = 0.0;
        });
      }
      return;
    }

    // **NEW: Try to load from cache first**
    final cacheKey = _getEarningsCacheKey();
    if (cacheKey != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final cachedEarningsJson = prefs.getString('earnings_cache_$cacheKey');
        final cachedTimestamp =
            prefs.getInt('earnings_cache_timestamp_$cacheKey');

        if (cachedEarningsJson != null && cachedTimestamp != null) {
          final cacheTime =
              DateTime.fromMillisecondsSinceEpoch(cachedTimestamp);
          final age = DateTime.now().difference(cacheTime);

          // Use cache if it's less than 1 day old
          if (age.inDays < 1) {
            final cachedEarnings = double.tryParse(cachedEarningsJson) ?? 0.0;
            AppLogger.log(
              '💰 ProfileStatsWidget: Using cached earnings: ₹${cachedEarnings.toStringAsFixed(2)} (${age.inHours}h old)',
            );
            if (mounted) {
              setState(() {
                _earnings = cachedEarnings;
                _isLoadingEarnings = false;
              });
            }
            return; // Exit early with cached value
          }
        }
      } catch (e) {
        AppLogger.log(
            '⚠️ ProfileStatsWidget: Error loading cached earnings: $e');
      }
    }

    // Cache miss or expired - calculate earnings
    if (mounted) {
      setState(() {
        _isLoadingEarnings = true;
      });
    }

    try {
      final videoCount = widget.stateManager.userVideos.length;
      final viewingUserId = widget.userId ?? 'own profile';
      AppLogger.log(
        '💰 ProfileStatsWidget: Calculating earnings for $videoCount videos (viewing: $viewingUserId)',
      );

      final totalRevenue =
          await EarningsService.calculateCreatorTotalRevenueForVideos(
        widget.stateManager.userVideos,
      );

      AppLogger.log(
        '💰 ProfileStatsWidget: Earnings calculated: ₹${totalRevenue.toStringAsFixed(2)} for $viewingUserId',
      );

      // **NEW: Cache the calculated earnings**
      if (cacheKey != null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
              'earnings_cache_$cacheKey', totalRevenue.toString());
          await prefs.setInt(
            'earnings_cache_timestamp_$cacheKey',
            DateTime.now().millisecondsSinceEpoch,
          );
          AppLogger.log('✅ ProfileStatsWidget: Earnings cached for $cacheKey');
        } catch (e) {
          AppLogger.log('⚠️ ProfileStatsWidget: Error caching earnings: $e');
        }
      }

      if (mounted) {
        setState(() {
          _earnings = totalRevenue;
          _isLoadingEarnings = false;
        });
      }
    } catch (e, stackTrace) {
      AppLogger.log('❌ ProfileStatsWidget: Error calculating earnings: $e');
      AppLogger.log('Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _earnings = 0.0;
          _isLoadingEarnings = false; // Always set to false on error
        });
      }
    }
  }

  /// **NEW: Get cache key for earnings based on userId and video count**
  String? _getEarningsCacheKey() {
    final userId = widget.userId ??
        widget.stateManager.userData?['googleId'] ??
        widget.stateManager.userData?['id'];
    if (userId == null) return null;

    final videoCount = widget.stateManager.userVideos.length;
    // Include video count in cache key so cache invalidates when videos change
    return '${userId}_${videoCount}';
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
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatColumn(
                      'Videos',
                      widget.isVideosLoaded
                          ? stateManager.userVideos.length
                          : '...',
                      isLoading: !widget.isVideosLoaded,
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
