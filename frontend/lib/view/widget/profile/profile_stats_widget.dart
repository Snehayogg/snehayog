import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vayu/core/managers/profile_state_manager.dart';
import 'package:vayu/core/providers/user_provider.dart';
import 'package:vayu/core/services/profile_screen_logger.dart';

import 'package:vayu/services/ad_service.dart';
import 'package:vayu/services/authservices.dart';
import 'package:vayu/utils/app_logger.dart';


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
  final AdService _adService = AdService();
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

      // **FIXED: Use backend API for ALL users (own profile AND other creators)**
      // Backend now supports fetching revenue for any user ID
      // If forceRefresh, we bypass cache
      
      // Determine target user ID
      String targetUserId;
      if (widget.userId != null) {
        targetUserId = widget.userId!;
      } else {
        // Own profile
        final userData = await _authService.getUserData();
        if (userData == null) {
           _finalEarningsUpdate(0.0);
           return;
        }
        targetUserId = userData['googleId'] ?? userData['id'];
      if (targetUserId.isEmpty) {
           _finalEarningsUpdate(0.0);
           return;
      }
      }

      final cacheKey = 'creator_earnings_$targetUserId';
      final now = DateTime.now();

      // **STEP 1: Check cache first (unless force refresh)**
      if (!forceRefresh) {
        final cachedEarnings = _creatorEarningsCache[cacheKey];
        final cacheTime = _creatorEarningsCacheTimestamp[cacheKey];

        if (cachedEarnings != null && cacheTime != null) {
          final cacheAge = now.difference(cacheTime);
          if (cacheAge < const Duration(hours: 1)) {
            if (mounted) {
              setState(() {
                _earnings = cachedEarnings;
                _isLoadingEarnings = false;
              });
            }
            // Fetch fresh in background
            _loadProfileEarnings(targetUserId, forceRefresh: true);
            return;
          }
        }
      }

      // **STEP 2: Fetch from BACKEND API**
      await _loadProfileEarnings(targetUserId, forceRefresh: forceRefresh);
  }

  void _finalEarningsUpdate(double value) {
    if (mounted) {
      setState(() {
        _earnings = value;
        _isLoadingEarnings = false;
      });
    }
  }




  // **Refactored: Load earnings from backend API for ANY user ID**
  Future<void> _loadProfileEarnings(String userId, {bool forceRefresh = false}) async {
    try {
      if (userId.isEmpty) {
         _finalEarningsUpdate(0.0);
         return;
      }
      
      // Use AdService to fetch earnings (wraps API + Cache)
      final response = await _adService.getCreatorRevenueSummary(
        userId: userId, 
        forceRefresh: forceRefresh
      );

      // Parse response
      if (response.isNotEmpty && response.containsKey('thisMonth')) {
        final thisMonthEarnings = (response['thisMonth'] as num?)?.toDouble() ?? 0.0;
        
        AppLogger.log(
            '💰 ProfileStatsWidget: Loaded backend earnings for $userId: ₹$thisMonthEarnings');

        if (mounted) {
          setState(() {
            _earnings = thisMonthEarnings;
            _isLoadingEarnings = false;
          });
          
          // Flash cache update
          final cacheKey = 'creator_earnings_$userId';
          _creatorEarningsCache[cacheKey] = thisMonthEarnings;
          _creatorEarningsCacheTimestamp[cacheKey] = DateTime.now();
        }
      } else {
        AppLogger.log('⚠️ ProfileStatsWidget: API returned empty or invalid data');
        _finalEarningsUpdate(0.0);
      }
    } catch (e) {
      AppLogger.log('❌ ProfileStatsWidget: Error loading earnings: $e');
      _finalEarningsUpdate(0.0);
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
