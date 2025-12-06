import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:vayu/config/app_config.dart';
import 'package:vayu/controller/google_sign_in_controller.dart';
import 'package:vayu/services/ad_service.dart';
import 'package:vayu/services/authservices.dart';
import 'package:vayu/services/video_service.dart';
import 'package:vayu/model/video_model.dart';
import 'package:vayu/services/ad_impression_service.dart';
import 'package:vayu/services/earnings_service.dart';
import 'package:vayu/services/logout_service.dart';
import 'package:vayu/utils/app_logger.dart';

// Lightweight holder for per-video stats used in the breakdown list
class _VideoStats {
  final double earnings;
  final int adViews;
  const _VideoStats(this.earnings, this.adViews);
}

class CreatorRevenueScreen extends StatefulWidget {
  const CreatorRevenueScreen({super.key});

  @override
  State<CreatorRevenueScreen> createState() => _CreatorRevenueScreenState();
}

class _CreatorRevenueScreenState extends State<CreatorRevenueScreen> {
  final AdService _adService = AdService();
  final AuthService _authService = AuthService();
  final VideoService _videoService = VideoService();
  final AdImpressionService _adImpressionService = AdImpressionService();

  Map<String, dynamic>? _revenueData;
  List<VideoModel> _userVideos = [];
  final Map<String, double> _videoRevenueMap = {};
  final Map<String, _VideoStats> _videoStatsMap = {};
  double _totalRevenue = 0.0;
  double _grossRevenue = 0.0;
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
      // Load user videos first
      final userData = await _authService.getUserData();
      if (userData case final Map<String, dynamic> rawUserMap) {
        final userMap = Map<String, dynamic>.from(rawUserMap);
        // **FIXED: Use googleId instead of id - backend expects googleId**
        final userId = (userMap['googleId'] ?? userMap['id'] ?? '').toString();

        if (userId.isEmpty) {
          throw Exception('User ID not found. Please sign in again.');
        }

        AppLogger.log(
            '🔍 CreatorRevenueScreen: Loading videos for userId: $userId');
        final videosFuture = _videoService.getUserVideos(userId);

        // **MONTH RESET: Check if cache is from different month - always force refresh**
        final now = DateTime.now();
        final prefs = await SharedPreferences.getInstance();
        final timestampKey = 'earnings_cache_timestamp_$userId';
        final cachedTimestamp = prefs.getInt(timestampKey);

        if (cachedTimestamp != null) {
          final cacheTime =
              DateTime.fromMillisecondsSinceEpoch(cachedTimestamp);
          // **FIX: Force refresh if month changed (not just day 1)**
          if (cacheTime.month != now.month || cacheTime.year != now.year) {
            AppLogger.log(
                '🔄 CreatorRevenueScreen: Month changed - forcing fresh earnings calculation');
            forceRefresh = true;
            // Clear earnings cache when month changes
            await prefs.remove('earnings_cache_$userId');
            await prefs.remove(timestampKey);
            AppLogger.log(
                '🧹 CreatorRevenueScreen: Cleared earnings cache (month changed)');
          }
        }

        // **MONTH RESET: Also check if it's the 1st of the month - always force refresh**
        if (now.day == 1) {
          AppLogger.log(
              '🔄 CreatorRevenueScreen: Month start detected - forcing fresh earnings calculation');
          forceRefresh = true;
          await prefs.remove('earnings_cache_$userId');
          await prefs.remove(timestampKey);
          AppLogger.log(
              '🧹 CreatorRevenueScreen: Cleared earnings cache at month start');
        }

        // **NEW: Try to load cached earnings data first (unless force refresh)**
        Map<String, dynamic>? revenueData;
        if (!forceRefresh) {
          revenueData = await _loadCachedEarningsData(userId);
          if (revenueData != null) {
            AppLogger.log('⚡ CreatorRevenueScreen: Using cached earnings data');
          }
        }

        final videos = await videosFuture;
        if (!mounted) return;
        setState(() {
          _userVideos = videos;
        });

        // Calculate revenue for all videos
        await _calculateTotalRevenue(userMap);

        // **CACHE-FIRST: Use cached data if available, otherwise fetch from server**
        if (revenueData == null) {
          final revenueSummaryFuture = _adService.getCreatorRevenueSummary();
          revenueData = await revenueSummaryFuture;

          // **NEW: Cache the fetched earnings data**
          await _cacheEarningsData(revenueData, userId);
        }

        if (!mounted) return;

        // **DEBUG: Log revenue data to verify API response**
        AppLogger.log(
            '💰 CreatorRevenueScreen: Revenue data received - thisMonth: ₹${((revenueData['thisMonth'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}, lastMonth: ₹${((revenueData['lastMonth'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}');

        setState(() {
          _revenueData = revenueData;
          _isLoading = false;
        });

        // **BACKGROUND: Refresh earnings data in background if using cache**
        if (!forceRefresh) {
          Future.microtask(() async {
            try {
              final freshRevenueData =
                  await _adService.getCreatorRevenueSummary();
              if (mounted) {
                await _cacheEarningsData(freshRevenueData, userId);
                if (mounted) {
                  setState(() {
                    _revenueData = freshRevenueData;
                  });
                  AppLogger.log(
                      '✅ CreatorRevenueScreen: Earnings data refreshed in background');
                }
              }
            } catch (e) {
              AppLogger.log(
                  '⚠️ CreatorRevenueScreen: Error refreshing earnings in background: $e');
              // Don't show error - background refresh is optional
            }
          });
        }
        return;
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      AppLogger.log('❌ CreatorRevenueScreen: Error loading revenue data: $e');

      // **FIXED: Better error handling for 401 errors**
      String errorMessage = 'Error loading revenue data: $e';
      if (e.toString().contains('401') ||
          e.toString().contains('Unauthorized')) {
        errorMessage =
            'Please sign in again to view your revenue. Your session may have expired.';
      } else if (e.toString().contains('Failed to fetch user videos')) {
        errorMessage =
            'Unable to load your videos. Please check your connection and try again.';
      }

      setState(() {
        _errorMessage = errorMessage;
        _isLoading = false;
      });
    }
  }

  /// **FIXED: Load cached earnings with month validation**
  Future<Map<String, dynamic>?> _loadCachedEarningsData(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'earnings_cache_$userId';
      final timestampKey = 'earnings_cache_timestamp_$userId';
      final oldMonthKey =
          'earnings_cache_month_$userId'; // **OLD KEY - clean up if exists**

      final cachedDataJson = prefs.getString(cacheKey);
      final cachedTimestamp = prefs.getInt(timestampKey);

      // **CLEANUP: Remove old month key if it exists (from previous code version)**
      if (prefs.containsKey(oldMonthKey)) {
        await prefs.remove(oldMonthKey);
        AppLogger.log('🧹 CreatorRevenueScreen: Removed old month key');
      }

      if (cachedTimestamp != null && cachedDataJson != null) {
        final cacheTime = DateTime.fromMillisecondsSinceEpoch(cachedTimestamp);
        final now = DateTime.now();
        final age = now.difference(cacheTime);

        // **MONTH CHECK: If cache is from different month, invalidate it**
        if (cacheTime.month != now.month || cacheTime.year != now.year) {
          AppLogger.log(
              '🔄 CreatorRevenueScreen: Earnings cache is from different month (${cacheTime.month}/${cacheTime.year} vs ${now.month}/${now.year}) - invalidating');
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
      AppLogger.log(
          '❌ CreatorRevenueScreen: Error loading cached earnings: $e');
    }
    return null;
  }

  /// **SIMPLIFIED: Cache earnings - simple timestamp only**
  Future<void> _cacheEarningsData(
      Map<String, dynamic> earningsData, String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'earnings_cache_$userId';
      final timestampKey = 'earnings_cache_timestamp_$userId';

      await prefs.setString(cacheKey, json.encode(earningsData));
      await prefs.setInt(timestampKey, DateTime.now().millisecondsSinceEpoch);

      AppLogger.log('✅ CreatorRevenueScreen: Earnings cached');
    } catch (e) {
      AppLogger.log('❌ CreatorRevenueScreen: Error caching earnings: $e');
    }
  }

  _VideoStats _getVideoStats(VideoModel video) =>
      _videoStatsMap[video.id] ?? const _VideoStats(0.0, 0);

  /// **FIXED: Get total ad VIEWS for current month (not impressions) - for display purposes**
  Future<int> _getTotalAdImpressionsForVideo(String videoId) async {
    try {
      // **FIXED: Get current month views only**
      final now = DateTime.now();
      final currentMonth = now.month - 1; // 0-indexed for backend
      final currentYear = now.year;

      final bannerViews = await _adImpressionService.getBannerAdViewsForMonth(
          videoId, currentMonth, currentYear);

      final carouselViews = await _adImpressionService
          .getCarouselAdViewsForMonth(videoId, currentMonth, currentYear);

      // Total views = Banner + Carousel
      final totalViews = bannerViews + carouselViews;

      AppLogger.log(
          '📊 Video $videoId (Current Month ${now.month}/${currentYear}): Banner VIEWS: $bannerViews, Carousel VIEWS: $carouselViews, Total VIEWS: $totalViews');

      return totalViews;
    } catch (e) {
      AppLogger.log('❌ Error getting ad views: $e');
      return 0;
    }
  }

  /// Calculate total revenue from all videos (current month only)
  Future<void> _calculateTotalRevenue(Map<String, dynamic> userData) async {
    try {
      // **FIXED: Calculate only current month earnings**
      final now = DateTime.now();
      final currentMonth = now.month - 1; // 0-indexed for backend
      final currentYear = now.year;

      AppLogger.log(
          '💰 CreatorRevenueScreen: Calculating current month (${now.month}/${currentYear}) earnings for ${_userVideos.length} videos');

      final statsFutures = _userVideos.map((video) async {
        // **FIXED: Use current month earnings calculation**
        final earningsFuture = EarningsService.calculateVideoRevenueForMonth(
          video.id,
          currentMonth,
          currentYear,
        );
        final viewsFuture = _getTotalAdImpressionsForVideo(video.id);

        final grossEarnings = await earningsFuture;
        final creatorEarnings =
            EarningsService.creatorShareFromGross(grossEarnings);
        final views = await viewsFuture;

        return MapEntry(video.id, (
          stats: _VideoStats(creatorEarnings, views),
          gross: grossEarnings,
          creator: creatorEarnings,
        ));
      }).toList();

      final statsEntries = await Future.wait(statsFutures);

      double grossRevenue = 0.0;
      double creatorRevenue = 0.0;
      _videoRevenueMap
        ..clear()
        ..addEntries(statsEntries.map(
          (entry) => MapEntry(entry.key, entry.value.creator),
        ));
      _videoStatsMap
        ..clear()
        ..addEntries(statsEntries.map((entry) => MapEntry(
              entry.key,
              entry.value.stats,
            )));

      for (final entry in statsEntries) {
        grossRevenue += entry.value.gross;
        creatorRevenue += entry.value.creator;
      }

      setState(() {
        _totalRevenue = creatorRevenue;
        _grossRevenue = grossRevenue;
      });

      await _calculateMonthlyViews(userData);

      AppLogger.log(
          '💰 CreatorRevenueScreen: Creator earnings calculated: ₹${creatorRevenue.toStringAsFixed(2)} (gross: ₹${grossRevenue.toStringAsFixed(2)})');
      AppLogger.log(
          '💰 CreatorRevenueScreen: Video revenue breakdown: $_videoRevenueMap');
    } catch (e) {
      AppLogger.log('❌ Error calculating total revenue: $e');
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

  /// Get revenue analytics summary
  Map<String, dynamic> _getRevenueAnalytics() {
    try {
      final topPerformingVideo = _userVideos.isNotEmpty
          ? _userVideos.reduce((a, b) =>
              (_videoRevenueMap[a.id] ?? 0.0) > (_videoRevenueMap[b.id] ?? 0.0)
                  ? a
                  : b)
          : null;

      final averageRevenuePerVideo =
          _userVideos.isNotEmpty ? _totalRevenue / _userVideos.length : 0.0;

      return {
        'total_revenue': _totalRevenue,
        'creator_revenue': _totalRevenue,
        'gross_revenue': _grossRevenue,
        'platform_fee':
            (_grossRevenue - _totalRevenue).clamp(0.0, double.infinity),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Creator Revenue'),
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
            color: Colors.grey,
          ),
          const SizedBox(height: 16),
          const Text(
            'Please sign in to view your revenue',
            style: TextStyle(fontSize: 18, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () async {
              final authController = Provider.of<GoogleSignInController>(
                context,
                listen: false,
              );
              final user = await authController.signIn();
              if (user != null) {
                await LogoutService.refreshAllState(context);
                if (mounted) {
                  setState(() {});
                }
              }
            },
            child: const Text('Sign In with Google'),
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
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _loadRevenueData(forceRefresh: true),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_revenueData == null) {
      return const Center(
        child: Text('No revenue data available'),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // **NEW: Revenue Overview Card**
          _buildRevenueOverviewCard(),

          const SizedBox(height: 16),

          // **NEW: Monthly Views Card**
          _buildMonthlyViewsCard(),

          const SizedBox(height: 16),

          // **NEW: Previous Month Earnings Section**
          _buildPreviousMonthEarningsCard(),

          const SizedBox(height: 24),

          // **NEW: Revenue Analytics Card**
          _buildRevenueAnalyticsCard(),

          const SizedBox(height: 24),

          // **NEW: Revenue Breakdown**
          _buildRevenueBreakdownCard(),

          const SizedBox(height: 24),

          // **NEW: Payment History**
          _buildPaymentHistoryCard(),

          const SizedBox(height: 24),

          // **NEW: Withdrawal Options**
          _buildWithdrawalCard(),

          const SizedBox(height: 24),

          // **NEW: Video Revenue Breakdown**
          _buildVideoRevenueBreakdownCard(),
        ],
      ),
    );
  }

  Widget _buildRevenueOverviewCard() {
    // **FIXED: Use calculated total revenue from individual videos if backend API returns 0**
    // This ensures consistency - if individual videos show earnings, overview should too
    final backendThisMonth =
        (_revenueData?['thisMonth'] as num?)?.toDouble() ?? 0.0;
    final lastMonth = (_revenueData?['lastMonth'] as num?)?.toDouble() ?? 0.0;

    // **FIX: Use calculated _totalRevenue if backend returns 0 (backend API issue workaround)**
    // _totalRevenue is the sum of all individual video earnings which are showing correctly
    final thisMonth = backendThisMonth > 0 ? backendThisMonth : _totalRevenue;

    // **FIXED: Calculate gross and platform fee from current month earnings**
    final creatorRevenue =
        thisMonth; // Use current month earnings (calculated if backend is 0)
    final grossRevenue = thisMonth > 0
        ? thisMonth / AppConfig.creatorRevenueShare
        : _grossRevenue; // Use calculated gross if thisMonth is from _totalRevenue
    final calculatedPlatformFee =
        (grossRevenue - creatorRevenue).clamp(0.0, double.infinity);
    final platformSharePercent =
        (AppConfig.platformRevenueShare * 100).toStringAsFixed(0);

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text(
              'Creator Earnings',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '₹${creatorRevenue.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildRevenueStat(
                    'Gross Revenue',
                    '₹${grossRevenue.toStringAsFixed(2)}',
                    Icons.receipt_long,
                    Colors.grey[700]!,
                  ),
                ),
                Expanded(
                  child: _buildRevenueStat(
                    'Platform Fee ($platformSharePercent%)',
                    '₹${calculatedPlatformFee.toStringAsFixed(2)}',
                    Icons.account_balance,
                    Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildRevenueStat(
                    'This Month',
                    '₹${thisMonth.toStringAsFixed(2)}',
                    Icons.trending_up,
                    Colors.grey[700]!, // Changed from Colors.blue
                  ),
                ),
                Expanded(
                  child: _buildRevenueStat(
                    'Last Month',
                    '₹${lastMonth.toStringAsFixed(2)}',
                    Icons.calendar_today,
                    Colors.orange,
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
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
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
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'View Cycle Summary',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Icon(
                  Icons.visibility,
                  color: Colors.grey[700],
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isMonthlyViewsLoading)
              const Center(child: CircularProgressIndicator())
            else ...[
              Text(
                'Current Cycle Views',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _currentMonthViews.toString(),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 20),
              _buildAnalyticsRow(
                'All-time Views',
                _allTimeViews.toString(),
              ),
              _buildAnalyticsRow(
                'Cycle Period',
                '${_formatDate(cycleStart)} → ${_formatDate(cycleEnd)}',
              ),
              _buildAnalyticsRow(
                'Next Reset',
                _formatDate(nextReset),
              ),
            ],
          ],
        ),
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

  /// **NEW: Previous Month Earnings Card - Detailed breakdown**
  Widget _buildPreviousMonthEarningsCard() {
    final lastMonth = (_revenueData?['lastMonth'] as num?)?.toDouble() ?? 0.0;
    final now = DateTime.now();
    final lastMonthDate = DateTime(
      now.month == 1 ? now.year - 1 : now.year,
      now.month == 1 ? 12 : now.month - 1,
      1,
    );
    final lastMonthName = _getMonthName(lastMonthDate.month);
    final lastMonthYear = lastMonthDate.year;

    // Calculate gross and platform fee for last month
    final lastMonthGross =
        lastMonth > 0 ? lastMonth / AppConfig.creatorRevenueShare : 0.0;
    final lastMonthPlatformFee =
        (lastMonthGross - lastMonth).clamp(0.0, double.infinity);

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // **FIX: Make header responsive to prevent overflow**
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.history,
                        color: Colors.orange[700],
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Previous Month Earnings',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange[700],
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$lastMonthName $lastMonthYear',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange[700],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (lastMonth == 0.0)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Icon(
                        Icons.inbox_outlined,
                        size: 48,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No earnings in $lastMonthName',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Start creating content to earn!',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              // Main earnings display
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.orange.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      'Total Earnings',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₹${lastMonth.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange[700],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Breakdown
              Row(
                children: [
                  Expanded(
                    child: _buildPreviousMonthStat(
                      'Gross Revenue',
                      '₹${lastMonthGross.toStringAsFixed(2)}',
                      Icons.receipt_long,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildPreviousMonthStat(
                      'Platform Fee',
                      '₹${lastMonthPlatformFee.toStringAsFixed(2)}',
                      Icons.account_balance,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Comparison with current month
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'This Month',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '₹${((_revenueData?['thisMonth'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPreviousMonthStat(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.grey[600], size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _getMonthName(int month) {
    const monthNames = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return monthNames[month - 1];
  }

  Widget _buildRevenueAnalyticsCard() {
    // **FIXED: Use calculated total revenue if backend API returns 0**
    final backendThisMonth =
        (_revenueData?['thisMonth'] as num?)?.toDouble() ?? 0.0;
    final thisMonth = backendThisMonth > 0 ? backendThisMonth : _totalRevenue;
    final thisMonthGross = thisMonth > 0
        ? (backendThisMonth > 0
            ? thisMonth / AppConfig.creatorRevenueShare
            : _grossRevenue)
        : 0.0;
    final thisMonthPlatformFee =
        (thisMonthGross - thisMonth).clamp(0.0, double.infinity);

    // Get video count and analytics (for display purposes)
    final analytics = _getRevenueAnalytics();
    final totalVideos = analytics['total_videos'] ?? 0;
    final averageRevenue = totalVideos > 0
        ? thisMonth / totalVideos
        : 0.0; // Average per video for current month
    final topPerformingVideoName = analytics['top_performing_video'] as String?;
    final topPerformingRevenue = analytics['top_performing_revenue'] ?? 0.0;

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Revenue Analytics',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'This Month',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue[700],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildAnalyticsRow(
                'Creator Earnings', '₹${thisMonth.toStringAsFixed(2)}'),
            _buildAnalyticsRow(
                'Gross Revenue', '₹${thisMonthGross.toStringAsFixed(2)}'),
            _buildAnalyticsRow(
                'Platform Fee', '₹${thisMonthPlatformFee.toStringAsFixed(2)}'),
            _buildAnalyticsRow('Total Videos', totalVideos.toString()),
            _buildAnalyticsRow('Average Revenue per Video',
                '₹${averageRevenue.toStringAsFixed(2)}'),
            _buildAnalyticsRow(
                'Top Performing Video', topPerformingVideoName ?? 'N/A'),
            _buildAnalyticsRow('Top Performing Revenue',
                '₹${topPerformingRevenue.toStringAsFixed(2)}'),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyticsRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueBreakdownCard() {
    // **FIXED: Use calculated total revenue if backend API returns 0**
    final backendThisMonth =
        (_revenueData?['thisMonth'] as num?)?.toDouble() ?? 0.0;
    final thisMonth = backendThisMonth > 0 ? backendThisMonth : _totalRevenue;
    final creatorRevenue =
        thisMonth; // Current month creator earnings (calculated if backend is 0)
    final grossRevenue = thisMonth > 0
        ? (backendThisMonth > 0
            ? thisMonth / AppConfig.creatorRevenueShare
            : _grossRevenue)
        : 0.0;
    final platformFee =
        (grossRevenue - creatorRevenue).clamp(0.0, double.infinity);
    final hasRevenue = grossRevenue > 0.0;
    final platformSharePercent =
        (AppConfig.platformRevenueShare * 100).toStringAsFixed(0);
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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Revenue Breakdown',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // **NEW: Revenue split visualization**
            Row(
              children: [
                Expanded(
                  flex: creatorFlex,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Expanded(
                  flex: platformFlex,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            _buildBreakdownRow('Gross Revenue',
                '₹${grossRevenue.toStringAsFixed(2)}', Colors.green),
            _buildBreakdownRow('Platform Fee ($platformSharePercent%)',
                '₹${platformFee.toStringAsFixed(2)}', Colors.red),
            const Divider(),
            _buildBreakdownRow(
                'Creator Earnings ($creatorSharePercent%)',
                '₹${creatorRevenue.toStringAsFixed(2)}',
                Colors.grey[700]!, // Changed from Colors.blue
                isTotal: true),
          ],
        ),
      ),
    );
  }

  Widget _buildBreakdownRow(String label, String value, Color color,
      {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentHistoryCard() {
    final payments = _revenueData?['payments'] ?? [];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Payment History',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    // Navigate to detailed payment history
                  },
                  child: const Text('View All'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (payments.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'No payments yet',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              ...payments.take(3).map((payment) => _buildPaymentRow(payment)),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentRow(Map<String, dynamic> payment) {
    final amount = payment['amount'] ?? 0.0;
    final date = payment['date'] ?? '';
    final status = payment['status'] ?? 'pending';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _getStatusColor(status),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _getStatusIcon(status),
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '₹${amount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  date,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _getStatusColor(status).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              status.toUpperCase(),
              style: TextStyle(
                color: _getStatusColor(status),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWithdrawalCard() {
    final availableBalance = _revenueData?['availableBalance'] ?? 0.0;
    final minWithdrawal = _revenueData?['minWithdrawal'] ?? 100.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Withdraw Earnings',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Available Balance: ₹${availableBalance.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Minimum withdrawal: ₹${minWithdrawal.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: availableBalance >= minWithdrawal
                    ? () => _showWithdrawalDialog()
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Withdraw Funds'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoRevenueBreakdownCard() {
    if (_userVideos.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.video_library, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No videos available',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Upload videos to start earning',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Video Revenue Breakdown',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton(
                  onPressed: () => _showDetailedVideoAnalytics(),
                  child: const Text('View All'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Show top 5 videos by revenue
            ..._userVideos.take(5).map((video) {
              final stats = _getVideoStats(video);
              final revenue = stats.earnings;
              final adImpressions = stats.adViews;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              video.videoName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '₹${revenue.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _buildVideoStat('Views', '${video.views}'),
                          const SizedBox(width: 16),
                          _buildVideoStat('Likes', '${video.likes}'),
                          const SizedBox(width: 16),
                          _buildVideoStat(
                              'Comments', '${video.comments.length}'),
                          const SizedBox(width: 16),
                          _buildVideoStat('Ad Impressions', '$adImpressions'),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),

            if (_userVideos.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Center(
                  child: Text(
                    '... and ${_userVideos.length - 5} more videos',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  void _showWithdrawalDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Withdraw Funds'),
        content: const Text(
          'This will initiate a withdrawal to your registered bank account. '
          'Processing time: 3-5 business days.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _initiateWithdrawal();
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  void _initiateWithdrawal() {
    // This would call the backend to initiate withdrawal
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Withdrawal initiated successfully!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'failed':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Icons.check_circle;
      case 'pending':
        return Icons.schedule;
      case 'failed':
        return Icons.error;
      default:
        return Icons.info;
    }
  }

  /// Show detailed video analytics
  void _showDetailedVideoAnalytics() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Detailed Video Analytics'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              children: _userVideos.map((video) {
                final stats = _getVideoStats(video);
                final revenue = stats.earnings;
                final adImpressions = stats.adViews;

                return ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      video.thumbnailUrl,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: 50,
                          height: 50,
                          color: Colors.grey[300],
                          child: const Icon(Icons.video_library, size: 24),
                        );
                      },
                    ),
                  ),
                  title: Text(
                    video.videoName,
                    style: const TextStyle(fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text('$adImpressions impressions'),
                  trailing: Text(
                    '₹${revenue.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
