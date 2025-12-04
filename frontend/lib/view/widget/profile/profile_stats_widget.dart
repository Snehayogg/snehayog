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
  Future<void> _loadEarnings() async {
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
      final response = await httpClientService.get(
        Uri.parse('$baseUrl/api/ads/creator/revenue/$userId'),
        headers: {
          'Authorization': 'Bearer ${userData['token']}',
        },
        timeout: const Duration(seconds: 8),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
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
            '⚠️ ProfileStatsWidget: API returned status ${response.statusCode}');
        // Fallback to local calculation
        if (widget.stateManager.userVideos.isNotEmpty) {
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
      // Fallback to local calculation on error
      if (widget.stateManager.userVideos.isNotEmpty) {
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
