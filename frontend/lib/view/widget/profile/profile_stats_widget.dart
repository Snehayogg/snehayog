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

  /// **NEW: Calculate current month earnings from videos (same logic as CreatorRevenueScreen)**
  Future<double> _calculateCurrentMonthEarnings() async {
    try {
      final now = DateTime.now();
      final currentMonth = now.month - 1; // 0-indexed for backend
      final currentYear = now.year;

      AppLogger.log(
          '💰 ProfileStatsWidget: Calculating current month (${now.month}/$currentYear) earnings for ${widget.stateManager.userVideos.length} videos');

      double totalCreatorEarnings = 0.0;

      for (final video in widget.stateManager.userVideos) {
        final grossEarnings =
            await EarningsService.calculateVideoRevenueForMonth(
          video.id,
          currentMonth,
          currentYear,
        );
        final creatorEarnings =
            EarningsService.creatorShareFromGross(grossEarnings);
        totalCreatorEarnings += creatorEarnings;
      }

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

    // **FIX: Only load earnings for own profile (userId is null)**
    // For other creators, show 0 or use fallback calculation
    if (widget.userId != null) {
      // Viewing someone else's profile - use fallback calculation
      if (widget.stateManager.userVideos.isEmpty) {
        if (mounted) {
          setState(() {
            _isLoadingEarnings = false;
            _earnings = 0.0;
          });
        }
        return;
      }

      // Fallback: Calculate from videos (all-time for other creators)
      if (mounted) {
        setState(() {
          _isLoadingEarnings = true;
        });
      }

      try {
        final totalRevenue =
            await EarningsService.calculateCreatorTotalRevenueForVideos(
          widget.stateManager.userVideos,
        );

        if (mounted) {
          setState(() {
            _earnings = totalRevenue;
            _isLoadingEarnings = false;
          });
        }
      } catch (e) {
        AppLogger.log('❌ ProfileStatsWidget: Error calculating earnings: $e');
        if (mounted) {
          setState(() {
            _earnings = 0.0;
            _isLoadingEarnings = false;
          });
        }
      }
      return;
    }

    // **OWN PROFILE: Use backend API for monthly earnings**
    if (mounted) {
      setState(() {
        _isLoadingEarnings = true;
      });
    }

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
          AppLogger.log('⚠️ ProfileStatsWidget: Empty response body from API');
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
          '💰 ProfileStatsWidget: Monthly earnings loaded: ₹${thisMonthEarnings.toStringAsFixed(2)} (this month)',
        );

        if (mounted) {
          setState(() {
            _earnings = thisMonthEarnings;
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
      if (widget.stateManager.userVideos.isNotEmpty) {
        try {
          AppLogger.log(
              '🔄 ProfileStatsWidget: Attempting fallback calculation (CURRENT MONTH) from videos...');
          final currentMonthRevenue = await _calculateCurrentMonthEarnings();
          AppLogger.log(
              '💰 ProfileStatsWidget: Fallback calculation result (CURRENT MONTH): ₹${currentMonthRevenue.toStringAsFixed(2)}');
          if (mounted) {
            setState(() {
              _earnings = currentMonthRevenue;
              _isLoadingEarnings = false;
            });
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
