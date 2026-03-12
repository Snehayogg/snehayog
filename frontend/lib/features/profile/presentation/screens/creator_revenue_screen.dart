import 'package:flutter/material.dart';
import 'package:vayu/core/design/spacing.dart';
import 'package:vayu/core/design/radius.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayu/core/providers/auth_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayu/core/design/colors.dart';
import 'package:vayu/core/design/typography.dart';

import 'package:vayu/shared/config/app_config.dart';
import 'package:vayu/features/ads/data/services/ad_service.dart';
import 'package:vayu/features/auth/data/services/authservices.dart';
import 'package:vayu/features/video/data/services/video_service.dart';
import 'package:vayu/features/video/video_model.dart';
import 'package:vayu/features/auth/data/services/logout_service.dart';
import 'package:vayu/shared/utils/app_logger.dart';
import 'package:vayu/shared/utils/app_text.dart';
import 'package:vayu/features/profile/data/datasources/profile_local_datasource.dart'; // Added for cache fallback
import 'package:vayu/shared/widgets/app_button.dart';

// Lightweight holder for per-video stats used in the breakdown list
class _VideoStats {
  final double earnings;
  final int adViews;
  const _VideoStats(this.earnings, this.adViews);
}

class CreatorRevenueScreen extends ConsumerStatefulWidget {
  const CreatorRevenueScreen({super.key});

  @override
  ConsumerState<CreatorRevenueScreen> createState() => _CreatorRevenueScreenState();
}

class _CreatorRevenueScreenState extends ConsumerState<CreatorRevenueScreen> {
  final AdService _adService = AdService();
  final AuthService _authService = AuthService();
  final VideoService _videoService = VideoService();
  Map<String, dynamic>? _revenueData;
  List<VideoModel> _userVideos = [];
  final Map<String, double> _videoRevenueMap = {};
  final Map<String, _VideoStats> _videoStatsMap = {};
  // Removed _totalRevenue and _grossRevenue
  bool _isLoading = true;
  String? _errorMessage;
  int _currentMonthViews = 0;
  int _allTimeViews = 0;
  DateTime? _currentViewCycleStart;
  DateTime? _nextViewResetDate;
  bool _isMonthlyViewsLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRevenueData();
  }

  Future<void> _loadRevenueData({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final userData = await _authService.getUserData();
      if (userData case final Map<String, dynamic> rawUserMap) {
        final userMap = Map<String, dynamic>.from(rawUserMap);
        // **FIXED: Use googleId instead of id - backend expects googleId**
        final userId = (userMap['googleId'] ?? userMap['id'] ?? '').toString();

        if (userId.isEmpty) {
          throw Exception('User ID not found. Please sign in again.');
        }

        AppLogger.log(
            '🔍 CreatorRevenueScreen: Loading fresh data for userId: $userId');

        // **PARALLEL EXECUTION: Load Revenue and Videos independently**
        // This ensures video load failure doesn't block revenue display
        await Future.wait([
          _fetchRevenueData(userId, true).catchError((e) {
            AppLogger.log('⚠️ CreatorRevenueScreen: Revenue load failed: $e');
          }),
          _fetchVideosAndCalculateStats(userId, userMap, true).catchError((e) {
            AppLogger.log('⚠️ CreatorRevenueScreen: Video load failed: $e');
          }),
        ]);

        if (mounted) {
          // **FALLBACK LOGIC: If revenue is 0, try to get from video uploader stats**
          // This matches ProfileStatsWidget logic to ensure consistency
          final thisMonth =
              (_revenueData?['thisMonth'] as num?)?.toDouble() ?? 0.0;

          if (thisMonth == 0 && _userVideos.isNotEmpty) {
            double fallbackEarnings = 0.0;
            bool foundFallback = false;

            // 1. Try uploader.earnings from first video (Backend Profile Summary)
            final uploaderEarnings = _userVideos.first.uploader.earnings;
            if (uploaderEarnings != null && uploaderEarnings > 0) {
              fallbackEarnings = uploaderEarnings;
              foundFallback = true;
              AppLogger.log(
                  '💰 CreatorRevenueScreen: Using uploader.earnings fallback: $fallbackEarnings');
            }

            // 2. If still 0, Aggregate from individual video earnings (Client-side Sum)
            if (!foundFallback) {
              double aggregated = 0.0;
              for (var video in _userVideos) {
                aggregated += video.earnings;
              }
              if (aggregated > 0) {
                fallbackEarnings = aggregated;
                foundFallback = true;
                AppLogger.log(
                    '💰 CreatorRevenueScreen: Aggregated earnings from video list: $fallbackEarnings');
              }
            }

            if (foundFallback) {
              AppLogger.log(
                  '💰 CreatorRevenueScreen: Revenue API returned 0, using fallback earnings: $fallbackEarnings');
              setState(() {
                if (_revenueData == null) {
                  _revenueData = {
                    'thisMonth': fallbackEarnings,
                    'lastMonth': 0.0,
                  };
                } else {
                  // Create a new map to ensure state update triggers
                  final newData = Map<String, dynamic>.from(_revenueData!);
                  newData['thisMonth'] = fallbackEarnings;
                  _revenueData = newData;
                }
              });
            }
          }

          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      AppLogger.log('❌ CreatorRevenueScreen: Error loading data: $e');
      _handleLoadError(e);
    }
  }

  Future<void> _fetchRevenueData(String userId, bool forceRefresh) async {
    try {
      AppLogger.log(
          '🔄 CreatorRevenueScreen: Fetching fresh revenue from backend...');

      // **NO CACHE: Always request fresh data from server**
      final freshRevenueData =
          await _adService.getCreatorRevenueSummary(forceRefresh: true);

      if (mounted) {
        setState(() {
          _revenueData = freshRevenueData;
        });
      }
      final thisMonth =
          (freshRevenueData['thisMonth'] as num?)?.toDouble() ?? 0.0;
      AppLogger.log(
          '💰 Revenue Display: Month: ${DateTime.now().month} | Source: Backend API | Amount: $thisMonth');
      AppLogger.log('✅ CreatorRevenueScreen: Revenue updated from backend');
    } catch (e) {
      AppLogger.log(
          '⚠️ CreatorRevenueScreen: Backend revenue fetch failed: $e');
      // Set default UI to avoid null errors, but don't overwrite if we have partial data
      if (_revenueData == null && mounted) {
        setState(() {
          _revenueData = {
            'thisMonth': 0.0,
            'lastMonth': 0.0,
          };
        });
      }
      rethrow;
    }
  }

  /// **OPTIMIZED: Parse per-video revenue from backend response**
  Future<void> _fetchVideosAndCalculateStats(
    String userId,
    Map<String, dynamic> userMap,
    bool forceRefresh,
  ) async {
    try {
      AppLogger.log('🔍 CreatorRevenueScreen: Loading videos...');
      List<VideoModel> videos = [];

      try {
        // Try network load first
        videos = await _videoService.getUserVideos(userId);
      } catch (e) {
        AppLogger.log('⚠️ CreatorRevenueScreen: Network video load failed: $e');
      }

      // **FALLBACK: Try Hive Cache if network failed or returned empty**
      if (videos.isEmpty) {
        try {
          AppLogger.log(
              '🔍 CreatorRevenueScreen: Trying Hive cache for videos...');
          final cachedVideos =
              await ProfileLocalDataSource().getCachedUserVideos(userId);
          if (cachedVideos != null && cachedVideos.isNotEmpty) {
            videos = cachedVideos;
            AppLogger.log(
                '✅ CreatorRevenueScreen: Loaded ${videos.length} videos from Hive cache');
          }
        } catch (e) {
          AppLogger.log('⚠️ CreatorRevenueScreen: Hive cache load failed: $e');
        }
      }

      if (mounted) {
        setState(() {
          _userVideos = videos;
        });
      }

      // **NEW: Parse per-video revenue from Backend API response**
      if (_revenueData != null && _revenueData!.containsKey('videos')) {
        final List<dynamic> videoStatsList = _revenueData!['videos'] ?? [];

        _videoRevenueMap.clear();
        _videoStatsMap.clear();

        for (var stat in videoStatsList) {
          final String videoId = stat['videoId']?.toString() ?? '';
          final double creatorRevenue =
              (stat['creatorRevenue'] as num?)?.toDouble() ?? 0.0;
          final int views = (stat['views'] as num?)?.toInt() ?? 0;
          // We can also get ad impressions from backend if needed
          final int adImpressions =
              (stat['totalAdImpressions'] as num?)?.toInt() ?? 0;

          if (videoId.isNotEmpty) {
            _videoRevenueMap[videoId] = creatorRevenue;
            _videoStatsMap[videoId] = _VideoStats(
                creatorRevenue, adImpressions > 0 ? adImpressions : views);
          }
        }

        AppLogger.log(
            '✅ CreatorRevenueScreen: Parsed revenue for ${_videoRevenueMap.length} videos from backend');
      } else {
        AppLogger.log(
            '⚠️ CreatorRevenueScreen: No video revenue details in backend response');
      }

      // **OPTIMIZED: Calculate monthly views in background (non-blocking)**
      Future.microtask(() => _calculateMonthlyViews(userMap));
    } catch (e) {
      AppLogger.log('❌ CreatorRevenueScreen: Failed to fetch videos: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to load video details.'),
            backgroundColor: AppColors.warning,
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _handleLoadError(dynamic e) {
    String errorMessage = AppText.get('error_load_revenue',
            fallback: 'Error loading revenue data: {error}')
        .replaceAll('{error}', e.toString());
    if (e.toString().contains('401') || e.toString().contains('Unauthorized')) {
      errorMessage = AppText.get('error_revenue_sign_in');
    } else if (e.toString().contains('Authentication token not found') ||
        e.toString().contains('token not found')) {
      errorMessage = AppText.get('error_revenue_token');
    }

    if (mounted) {
      setState(() {
        _errorMessage = errorMessage;
        _isLoading = false;
      });
    }
  }

  Future<void> _calculateMonthlyViews(Map<String, dynamic> userData) async {
    final totalViews =
        _userVideos.fold<int>(0, (sum, video) => sum + (video.views));
    final now = DateTime.now();
    final cycleStart = DateTime(now.year, now.month, 1);
    final nextReset = DateTime(
      now.month == 12 ? now.year + 1 : now.year,
      now.month == 12 ? 1 : now.month + 1,
      1,
    );

    try {
      setState(() {
        _isMonthlyViewsLoading = true;
      });

      final userId = userData['id']?.toString() ??
          userData['googleId']?.toString() ??
          'anonymous';

      final prefs = await SharedPreferences.getInstance();
      final baselineKey = 'creator_monthly_view_baseline_$userId';
      final resetKey = 'creator_monthly_view_last_reset_$userId';
      final currentMonthKey =
          '${now.year}-${now.month.toString().padLeft(2, '0')}';

      String? storedResetMonth = prefs.getString(resetKey);
      int baseline = prefs.getInt(baselineKey) ?? -1;

      if (baseline < 0) {
        baseline = 0;
        await prefs.setInt(baselineKey, baseline);
      }

      if (storedResetMonth == null) {
        storedResetMonth = currentMonthKey;
        await prefs.setString(resetKey, currentMonthKey);
      }

      if (storedResetMonth != currentMonthKey) {
        baseline = totalViews;
        await prefs.setInt(baselineKey, baseline);
        await prefs.setString(resetKey, currentMonthKey);
      }

      final monthlyViews = totalViews - baseline;

      if (!mounted) return;
      setState(() {
        _allTimeViews = totalViews;
        _currentMonthViews = monthlyViews < 0 ? 0 : monthlyViews;
        _currentViewCycleStart = cycleStart;
        _nextViewResetDate = nextReset;
        _isMonthlyViewsLoading = false;
      });
    } catch (e) {
      AppLogger.log(
          '❌ CreatorRevenueScreen: Error calculating monthly views: $e');
      if (!mounted) return;
      setState(() {
        _allTimeViews = totalViews;
        _currentMonthViews = 0;
        _currentViewCycleStart = cycleStart;
        _nextViewResetDate = nextReset;
        _isMonthlyViewsLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppText.get('revenue_title')),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () => _loadRevenueData(forceRefresh: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _authService.getUserData(),
        builder: (context, snapshot) {
          final isSignedIn = snapshot.hasData && snapshot.data != null;

          if (!isSignedIn) {
            return _buildLoginPrompt();
          }

          return _buildRevenueContent();
        },
      ),
    );
  }

  Widget _buildLoginPrompt() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.lock_outline,
            size: 64,
            color: AppColors.textSecondary,
          ),
          AppSpacing.vSpace16,
          Text(
            AppText.get('revenue_sign_in_to_view'),
            style:
                const TextStyle(fontSize: 18, color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          AppSpacing.vSpace24,
          AppButton(
            isFullWidth: true,
            onPressed: () async {
              final authController = ref.read(googleSignInProvider);
              final user = await authController.signIn();
              if (user != null) {
                await LogoutService.refreshAllState(ref);
                if (mounted) {
                  setState(() {});
                }
              }
            },
            label: AppText.get('btn_sign_in_google'),
            variant: AppButtonVariant.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.error),
            AppSpacing.vSpace16,
            Text(
              _errorMessage!,
              style: const TextStyle(color: AppColors.error),
              textAlign: TextAlign.center,
            ),
            AppSpacing.vSpace16,
            AppButton(
              onPressed: () => _loadRevenueData(forceRefresh: true),
              label: AppText.get('btn_retry'),
              variant: AppButtonVariant.primary,
            ),
          ],
        ),
      );
    }

    if (_revenueData == null) {
      return Center(
        child: Text(AppText.get('error_load_profile_generic')),
      );
    }

    return RefreshIndicator(
        onRefresh: () async => await _loadRevenueData(forceRefresh: true),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(AppSpacing.spacing4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // **NEW: Revenue Overview Card**
              _buildRevenueOverviewCard(),

              AppSpacing.vSpace16,

              // **NEW: Monthly Views Card**
              _buildMonthlyViewsCard(),

              AppSpacing.vSpace24,

              // **NEW: Revenue Analytics Card**
              _buildRevenueAnalyticsCard(),

              AppSpacing.vSpace24,

              // **NEW: Revenue Breakdown**
              _buildRevenueBreakdownCard(),
              AppSpacing.vSpace24,
            ],
          ),
        ));
  }

  Widget _buildRevenueOverviewCard() {
    final thisMonth = (_revenueData?['thisMonth'] as num?)?.toDouble() ?? 0.0;
    final lastMonth = (_revenueData?['lastMonth'] as num?)?.toDouble() ?? 0.0;
    final creatorRevenue = thisMonth;
    final grossRevenue =
        thisMonth > 0 ? thisMonth / AppConfig.creatorRevenueShare : 0.0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.borderPrimary, width: 1),
      ),
      color: AppColors.backgroundPrimary,
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.spacing5),
        child: Column(
          children: [
            Text(
              AppText.get('revenue_creator_earnings'),
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.textSecondary,
              ),
            ),
            AppSpacing.vSpace8,
            Text(
              creatorRevenue.toStringAsFixed(2),
              style: AppTypography.displaySmall.copyWith(
                color:
                    AppColors.success, // Use success color for positive rewards
              ),
            ),
            AppSpacing.vSpace24,
            Row(
              children: [
                Expanded(
                  child: _buildRevenueStat(
                    AppText.get('revenue_gross_revenue'),
                    grossRevenue.toStringAsFixed(2),
                    Icons.receipt_long,
                    AppColors.textPrimary,
                  ),
                ),
                Expanded(
                  child: _buildRevenueStat(
                    AppText.get('revenue_last_month'),
                    lastMonth.toStringAsFixed(2),
                    Icons.history,
                    AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRevenueStat(
      String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        SizedBox(height: AppSpacing.spacing1),
        Text(
          value,
          style: AppTypography.titleLarge.copyWith(
            fontWeight: AppTypography.weightBold,
            color: color,
          ),
        ),
        Text(
          label,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textTertiary,
          ),
        ),
      ],
    );
  }

  Widget _buildMonthlyViewsCard() {
    final cycleStart = _currentViewCycleStart;
    final nextReset = _nextViewResetDate;
    final cycleEnd = nextReset?.subtract(const Duration(days: 1));

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.borderPrimary, width: 1),
      ),
      color: AppColors.backgroundPrimary,
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.spacing5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AppText.get('revenue_view_cycle'),
                  style: AppTypography.headlineSmall.copyWith(
                    fontWeight: AppTypography.weightBold,
                  ),
                ),
                const Icon(
                  Icons.visibility,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
            AppSpacing.vSpace16,
            if (_isMonthlyViewsLoading)
              const Center(child: CircularProgressIndicator())
            else ...[
              Text(
                AppText.get('revenue_current_cycle_views'),
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              AppSpacing.vSpace4,
              Text(
                _currentMonthViews.toString(),
                style: AppTypography.displaySmall.copyWith(
                  color: AppColors.success,
                ),
              ),
              AppSpacing.vSpace24,
              _buildAnalyticsRow(
                AppText.get('revenue_all_time_views'),
                _allTimeViews.toString(),
              ),
              _buildAnalyticsRow(
                AppText.get('revenue_cycle_period'),
                '${_formatDate(cycleStart)} → ${_formatDate(cycleEnd)}',
              ),
              _buildAnalyticsRow(
                AppText.get('revenue_next_reset'),
                _formatDate(nextReset),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyticsRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.all(AppSpacing.spacing2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(width: AppSpacing.spacing2),
          Flexible(
            child: Text(
              value,
              style: AppTypography.titleSmall.copyWith(
                fontWeight: AppTypography.weightBold,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '—';
    const monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final monthName = monthNames[date.month - 1];
    return '${date.day} $monthName ${date.year}';
  }

  Widget _buildRevenueAnalyticsCard() {
    // **FIXED: Use backend API value directly - no fallback**
    final thisMonth = (_revenueData?['thisMonth'] as num?)?.toDouble() ?? 0.0;

    final thisMonthGross =
        thisMonth > 0 ? thisMonth / AppConfig.creatorRevenueShare : 0.0;

    // Get video count and analytics (for display purposes)
    final analytics = _getRevenueAnalytics();
    final totalVideos = analytics['total_videos'] ?? 0;
    final averageRevenue = totalVideos > 0
        ? thisMonth / totalVideos
        : 0.0; // Average per video for current month
    final topPerformingVideoName = analytics['top_performing_video'] as String?;
    final topPerformingRevenue = analytics['top_performing_revenue'] ?? 0.0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.borderPrimary, width: 1),
      ),
      color: AppColors.backgroundPrimary,
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.spacing5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  AppText.get('revenue_analytics'),
                  style: AppTypography.headlineSmall.copyWith(
                    fontWeight: AppTypography.weightBold,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    AppText.get('revenue_analytics_this_month'),
                    style: AppTypography.labelSmall.copyWith(
                      fontWeight: AppTypography.weightBold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: AppSpacing.spacing4),
            _buildAnalyticsRow(AppText.get('revenue_creator_earnings'),
                thisMonth.toStringAsFixed(2)),
            _buildAnalyticsRow(AppText.get('revenue_gross_revenue'),
                thisMonthGross.toStringAsFixed(2)),
            _buildAnalyticsRow(
                AppText.get('revenue_total_videos', fallback: 'Total Videos'),
                totalVideos.toString()),
            _buildAnalyticsRow(
                AppText.get('revenue_avg_per_video',
                    fallback: 'Average Revenue per Video'),
                averageRevenue.toStringAsFixed(2)),
            _buildAnalyticsRow(
                AppText.get('revenue_top_performing',
                    fallback: 'Top Performing Video'),
                topPerformingVideoName ?? 'N/A'),
            _buildAnalyticsRow(
                AppText.get('revenue_top_performing_revenue',
                    fallback: 'Top Performing Revenue'),
                topPerformingRevenue.toStringAsFixed(2)),
          ],
        ),
      ),
    );
  }

  Widget _buildRevenueBreakdownCard() {
    // **FIXED: Use backend API value directly - no fallback**
    final thisMonth = (_revenueData?['thisMonth'] as num?)?.toDouble() ?? 0.0;

    final creatorRevenue = thisMonth;
    final grossRevenue =
        thisMonth > 0 ? thisMonth / AppConfig.creatorRevenueShare : 0.0;
    final hasRevenue = grossRevenue > 0.0;

    final creatorSharePercent =
        (AppConfig.creatorRevenueShare * 100).toStringAsFixed(0);
    final totalFlexUnits = hasRevenue ? 100 : 1;
    int creatorFlex = hasRevenue
        ? (creatorRevenue / grossRevenue * totalFlexUnits).round()
        : 1;
    creatorFlex = creatorFlex.clamp(1, totalFlexUnits);
    int platformFlex = hasRevenue ? totalFlexUnits - creatorFlex : 1;
    if (platformFlex <= 0) {
      platformFlex = hasRevenue ? 1 : platformFlex.abs();
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.borderPrimary, width: 1),
      ),
      color: AppColors.backgroundPrimary,
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.spacing4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppText.get('revenue_breakdown'),
              style: AppTypography.headlineSmall.copyWith(
                fontWeight: AppTypography.weightBold,
              ),
            ),
            SizedBox(height: AppSpacing.spacing4),

            // **NEW: Revenue split visualization**
            Row(
              children: [
                Expanded(
                  flex: creatorFlex,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Expanded(
                  flex: platformFlex,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),

            AppSpacing.vSpace16,

            _buildBreakdownRow(AppText.get('revenue_gross_revenue'),
                grossRevenue.toStringAsFixed(2), AppColors.success),
            const Divider(),
            _buildBreakdownRow(
                AppText.get('revenue_creator_earnings',
                        fallback: 'Creator Earnings ({percent}%)')
                    .replaceAll('{percent}', creatorSharePercent),
                creatorRevenue.toStringAsFixed(2),
                AppColors.textSecondary, // Changed from AppColors.primary
                isTotal: true),
          ],
        ),
      ),
    );
  }

  Widget _buildBreakdownRow(String label, String value, Color color,
      {bool isTotal = false}) {
    return Padding(
      padding: EdgeInsets.all(AppSpacing.spacing2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style:
                isTotal ? AppTypography.titleMedium : AppTypography.bodyMedium,
          ),
          Text(
            value,
            style:
                (isTotal ? AppTypography.titleMedium : AppTypography.bodyMedium)
                    .copyWith(
              fontWeight: isTotal
                  ? AppTypography.weightBold
                  : AppTypography.weightRegular,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// Show detailed video analytics

  /// Show detailed video analytics
  Map<String, dynamic> _getRevenueAnalytics() {
    try {
      final topPerformingVideo = _userVideos.isNotEmpty
          ? _userVideos.reduce((a, b) =>
              (_videoRevenueMap[a.id] ?? 0.0) > (_videoRevenueMap[b.id] ?? 0.0)
                  ? a
                  : b)
          : null;

      // Calculate totals from map if needed, or use _revenueData
      final thisMonth = (_revenueData?['thisMonth'] as num?)?.toDouble() ?? 0.0;
      final grossRevenue = thisMonth / AppConfig.creatorRevenueShare;

      final averageRevenuePerVideo =
          _userVideos.isNotEmpty ? thisMonth / _userVideos.length : 0.0;

      return {
        'total_revenue': thisMonth,
        'creator_revenue': thisMonth,
        'gross_revenue': grossRevenue,
        'platform_fee': (grossRevenue - thisMonth).clamp(0.0, double.infinity),
        'total_videos': _userVideos.length,
        'average_revenue_per_video': averageRevenuePerVideo,
        'top_performing_video': topPerformingVideo?.videoName,
        'top_performing_revenue': topPerformingVideo != null
            ? _videoRevenueMap[topPerformingVideo.id] ?? 0.0
            : 0.0,
        'revenue_breakdown': _videoRevenueMap,
        'calculation_timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      AppLogger.log('❌ Error getting revenue analytics: $e');
      return {};
    }
  }
}
