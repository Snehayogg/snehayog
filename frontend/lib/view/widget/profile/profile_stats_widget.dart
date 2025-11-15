import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vayu/core/managers/profile_state_manager.dart';
import 'package:vayu/core/providers/user_provider.dart';
import 'package:vayu/core/services/profile_screen_logger.dart';
// import 'package:vayu/services/ad_impression_service.dart';
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
      _loadEarnings();
    }
  }

  @override
  void dispose() {
    widget.stateManager.removeListener(_onStateManagerChanged);
    super.dispose();
  }

  /// **FIXED: Load earnings using centralized EarningsService (single source of truth)**
  /// **ENHANCED: Works for any creator's videos (own profile or other creators)**
  Future<void> _loadEarnings() async {
    if (!widget.isVideosLoaded || widget.stateManager.userVideos.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoadingEarnings = false; // Don't show loading if no videos
          _earnings = 0.0;
        });
      }
      return;
    }

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
                Container(width: 1, height: 40, color: const Color(0xFFE5E7EB)),
                _buildStatColumn(
                  'Followers',
                  widget.isFollowersLoaded
                      ? _getFollowersCount(context)
                      : '...',
                  isLoading: !widget.isFollowersLoaded,
                  onTap: widget.onFollowersTap,
                ),
                Container(width: 1, height: 40, color: const Color(0xFFE5E7EB)),
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

    // Build candidate IDs to query provider with
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
        if (userModel?.followersCount != null) {
          ProfileScreenLogger.logDebugInfo(
            'Using followers count from UserProvider for $candidateId: ${userModel!.followersCount}',
          );
          return userModel.followersCount;
        }
      }
    }

    // Check if we're viewing own profile
    if (widget.userId == null && widget.stateManager.userData != null) {
      ProfileScreenLogger.logDebugInfo('Viewing own profile');

      // Prefer counts available in userData
      final followersCount = widget.stateManager.userData!['followers'] ??
          widget.stateManager.userData!['followersCount'] ??
          0;
      if (followersCount != 0) {
        ProfileScreenLogger.logDebugInfo(
          'Using followers count from ProfileStateManager: $followersCount',
        );
        return followersCount;
      }
    }

    // Fall back to ProfileStateManager data
    if (widget.stateManager.userData != null &&
        widget.stateManager.userData!['followersCount'] != null) {
      final followersCount = widget.stateManager.userData!['followersCount'];
      ProfileScreenLogger.logDebugInfo(
        'Using followers count from ProfileStateManager: $followersCount',
      );
      return followersCount;
    }

    // Final fallback
    ProfileScreenLogger.logDebugInfo(
      'No followers count available, using default: 0',
    );
    return 0;
  }
}
