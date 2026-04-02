import 'package:flutter/material.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/core/design/radius.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/core/providers/auth_providers.dart';

import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/shared/config/app_config.dart';
import 'package:vayug/features/ads/data/services/ad_service.dart';
import 'package:vayug/features/auth/data/services/authservices.dart';
import 'package:vayug/features/auth/data/services/logout_service.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/shared/utils/app_text.dart';
import 'package:vayug/shared/widgets/app_button.dart';
import 'package:vayug/shared/widgets/vayu_bottom_sheet.dart';

// NEW IMPORTS
import 'package:vayug/features/profile/analytics/data/services/analytics_service.dart';
import 'package:vayug/features/profile/analytics/domain/models/analytics_models.dart';
import 'package:vayug/features/profile/analytics/presentation/widgets/analytics_widgets.dart';

class CreatorRevenueScreen extends ConsumerStatefulWidget {
  const CreatorRevenueScreen({super.key});

  @override
  ConsumerState<CreatorRevenueScreen> createState() => _CreatorRevenueScreenState();
}

class _CreatorRevenueScreenState extends ConsumerState<CreatorRevenueScreen> {
  final AdService _adService = AdService();
  final AuthService _authService = AuthService();
  final AnalyticsService _analyticsService = AnalyticsService();
  
  Map<String, dynamic>? _revenueData;
  CreatorAnalytics? _analytics;
  List<RemovedVideo> _removedVideos = [];
  
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final userData = await _authService.getUserData();
      if (userData case final Map<String, dynamic> userMap) {
        final userId = (userMap['googleId'] ?? userMap['id'] ?? '').toString();

        if (userId.isEmpty) {
          throw Exception('User ID not found. Please sign in again.');
        }

        await Future.wait([
          _fetchRevenueData(forceRefresh),
          _fetchAnalytics(userId),
          _fetchRemovedVideos(),
        ]);

        if (mounted) {
          setState(() => _isLoading = false);
        }
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      AppLogger.log('❌ CreatorDashboard: Error loading data: $e');
      if (mounted) {
        setState(() {
          _errorMessage = "Unable to load dashboard data. Please try again.";
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchRevenueData(bool forceRefresh) async {
    try {
      final freshRevenueData = await _adService.getCreatorRevenueSummary(forceRefresh: forceRefresh);
      if (mounted) {
        setState(() => _revenueData = freshRevenueData);
      }
    } catch (e) {
      AppLogger.log('⚠️ Engagement load failed: $e');
    }
  }

  Future<void> _fetchAnalytics(String userId) async {
    try {
      final data = await _analyticsService.getCreatorAnalytics(userId);
      if (mounted) {
        setState(() => _analytics = data);
      }
    } catch (e) {
      AppLogger.log('⚠️ Analytics load failed: $e');
    }
  }

  Future<void> _fetchRemovedVideos() async {
    try {
      final data = await _analyticsService.getRemovedVideos();
      if (mounted) {
        setState(() => _removedVideos = data);
      }
    } catch (e) {
      AppLogger.log('⚠️ Removed videos load failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Creator Dashboard"),
          centerTitle: true,
          elevation: 0,
          bottom: const TabBar(
            tabs: [
              Tab(text: "Engagement"),
              Tab(text: "Analytics"),
            ],
            indicatorColor: AppColors.primary,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
          ),
          actions: [
            IconButton(
              onPressed: () => _loadAllData(forceRefresh: true),
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

            if (_isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (_errorMessage != null) {
              return _buildErrorView();
            }

            return TabBarView(
              children: [
                _buildRevenueTab(),
                _buildAnalyticsTab(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildLoginPrompt() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock_outline, size: 64, color: AppColors.textSecondary),
          AppSpacing.vSpace16,
          Text(AppText.get('revenue_sign_in_to_view'), textAlign: TextAlign.center),
          AppSpacing.vSpace24,
          AppButton(
            onPressed: () async {
              final authController = ref.read(googleSignInProvider);
              final user = await authController.signIn();
              if (user != null) {
                await LogoutService.refreshAllState(ref);
                _loadAllData();
              }
            },
            label: AppText.get('btn_sign_in_google'),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            AppSpacing.vSpace16,
            Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.error)),
            AppSpacing.vSpace16,
            AppButton(onPressed: _loadAllData, label: "Retry"),
          ],
        ),
      ),
    );
  }

  Widget _buildRevenueTab() {
    if (_revenueData == null) return const Center(child: Text("No engagement data available"));

    return RefreshIndicator(
      onRefresh: () => _loadAllData(forceRefresh: true),
      child: SingleChildScrollView(
        padding: EdgeInsets.all(AppSpacing.spacing4),
        child: Column(
          children: [
            _buildRevenueOverviewCard(),
            AppSpacing.vSpace24,
            _buildRevenueBreakdownCard(),
            if (_removedVideos.isNotEmpty) ...[
              AppSpacing.vSpace24,
              _buildRemovedVideosSection(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyticsTab() {
    if (_analytics == null) return const Center(child: Text("No analytics data available"));

    return RefreshIndicator(
      onRefresh: () => _loadAllData(forceRefresh: true),
      child: SingleChildScrollView(
        padding: EdgeInsets.all(AppSpacing.spacing4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Core Analytics Grid
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: AppSpacing.spacing3,
              mainAxisSpacing: AppSpacing.spacing3,
              childAspectRatio: 1.5,
              children: [
                AnalyticsStatCard(
                  label: "Total Views", 
                  value: _analytics!.core.totalViews.toString(), 
                  icon: Icons.visibility,
                  color: AppColors.primary,
                  growth: _analytics!.core.viewsGrowth,
                  onTap: _showViewsGuide,
                ),
                AnalyticsStatCard(
                  label: "Watch Time", 
                  value: "${_analytics!.core.totalWatchTime}m", 
                  icon: Icons.access_time,
                  color: Colors.orange,
                  growth: _analytics!.core.watchTimeGrowth,
                  onTap: _showWatchTimeGuide,
                ),
                AnalyticsStatCard(
                  label: "Shares", 
                  icon: Icons.share,
                  color: Colors.blue,
                  value: _analytics!.core.totalShares.toString(),
                  onTap: _showSharesGuide,
                ),
                AnalyticsStatCard(
                  label: "Skip Rate", 
                  value: "${(_analytics!.core.skipRate * 100).toStringAsFixed(1)}%", 
                  icon: Icons.skip_next,
                  color: Colors.redAccent,
                  onTap: _showSkipRateGuide,
                ),
              ],
            ),
            
            AppSpacing.vSpace24,
            PerformanceChart(
              data: _analytics!.dailyPerformance, 
              title: "Daily Performance",
              onTap: _showPerformanceGuide,
            ),
            
            AppSpacing.vSpace24,
            TopVideosList(videos: _analytics!.topVideos),

            AppSpacing.vSpace24,
            Text("Viewer Insights", style: AppTypography.titleMedium),
            AppSpacing.vSpace12,
            AudienceInsightCard(
              title: "New vs Returning Viewers", 
              content: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildMiniStat("New", _analytics!.audience.newVsReturning.newValue.toString()),
                  _buildMiniStat("Returning", _analytics!.audience.newVsReturning.returning.toString()),
                ],
              )
            ),
            AppSpacing.vSpace16,
            AudienceInsightCard(
              title: "Top States", 
              content: Column(
                children: _analytics!.audience.topLocations.map((l) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(l.name, style: AppTypography.bodyMedium),
                      Text("${l.value}%", style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                )).toList(),
              )
            ),
            AppSpacing.vSpace24,
          ],
        ),
      ),
    );
  }

  void _showSkipRateGuide() {
    _showGenericGuide(
      title: "Skip Rate Kya Hai?",
      icon: Icons.ads_click,
      content: "Ye pichle 14 dino ka data hai. Ye dikhata hai ki kitne % log aapka video bina dekhe turant agla video dekhne chale gaye. Har din naya data judta hai aur sabse purana (15th day) ka data hat jata hai.",
    );
  }

  void _showViewsGuide() {
    _showGenericGuide(
      title: "Total Views Kya Hai?",
      icon: Icons.visibility,
      content: "Ye pichle 14 dino mein aaye total views hain. Ye data rozana update hota hai: pichle 14 dino ka total dikhane ke liye purana data hat-ta rehta hai.",
    );
  }

  void _showWatchTimeGuide() {
    _showGenericGuide(
      title: "Watch Time Kya Hai?",
      icon: Icons.access_time,
      content: "Ye pichle 14 dino ka total Watch Time hai (minutes mein). Isse ye pata chalta hai ki pichle do hafton mein logon ne aapke content par kitna time bitaya.",
    );
  }

  void _showSharesGuide() {
    _showGenericGuide(
      title: "Shares Kya Hai?",
      icon: Icons.share,
      content: "Ye pichle 14 dino mein hue total shares ka count hai. Har din ye chart pichle 14 dino ki snapshot dikhata hai.",
    );
  }

  void _showPerformanceGuide() {
    _showGenericGuide(
      title: "Daily Performance Kya Hai?",
      icon: Icons.bar_chart,
      content: "Ye graph pichle 7 dino ki performance dikhata hai. Har ek bar ek din ko represent karta hai aur bar ki height ye dikhati hai ki us din kitne views aaye the.",
    );
  }

  void _showGenericGuide({
    required String title,
    required IconData icon,
    required String content,
    List<Widget> items = const [],
  }) {
    VayuBottomSheet.show(
      context: context,
      title: title,
      icon: icon,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            content,
            style: const TextStyle(fontSize: 15, color: AppColors.textPrimary, height: 1.4),
          ),
          if (items.isNotEmpty) ...[
            AppSpacing.vSpace24,
            ...items,
          ],
          AppSpacing.vSpace24,
          SizedBox(
            width: double.infinity,
            child: AppButton(
              onPressed: () => Navigator.pop(context),
              label: "Samajh Gaya!",
            ),
          ),
          AppSpacing.vSpace16,
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value) {
    return Column(
      children: [
        Text(value, style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.bold)),
        Text(label, style: AppTypography.labelSmall.copyWith(color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _buildRevenueOverviewCard() {
    final thisMonth = (_revenueData?['thisMonth'] as num?)?.toDouble() ?? 0.0;
    final lastMonth = (_revenueData?['lastMonth'] as num?)?.toDouble() ?? 0.0;
    final totalPoints = thisMonth > 0 ? thisMonth / AppConfig.creatorRevenueShare : 0.0;

    return Container(
      padding: EdgeInsets.all(AppSpacing.spacing5),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.borderPrimary),
      ),
      child: Column(
        children: [
          const Text("Creator Performance Points", style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
          AppSpacing.vSpace8,
          Text(
            thisMonth.toStringAsFixed(2),
            style: AppTypography.displaySmall.copyWith(color: AppColors.success, fontWeight: FontWeight.bold),
          ),
          AppSpacing.vSpace24,
          Row(
            children: [
              Expanded(
                child: _buildRevenueStat("Total Points", totalPoints.toStringAsFixed(2), Icons.stars),
              ),
              Expanded(
                child: _buildRevenueStat("Last Period", lastMonth.toStringAsFixed(2), Icons.history),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueStat(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: AppColors.textPrimary, size: 24),
        AppSpacing.vSpace4,
        Text(value, style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.bold)),
        Text(label, style: AppTypography.labelSmall.copyWith(color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _buildRevenueBreakdownCard() {
    final thisMonth = (_revenueData?['thisMonth'] as num?)?.toDouble() ?? 0.0;
    if (thisMonth <= 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Engagement Breakdown", style: AppTypography.titleMedium),
        AppSpacing.vSpace12,
        Container(
          padding: EdgeInsets.all(AppSpacing.spacing4),
          decoration: BoxDecoration(
            color: AppColors.backgroundSecondary,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.borderPrimary),
          ),
          child: Column(
            children: [
              _buildBreakdownRow("Creator Points", thisMonth.toStringAsFixed(2), AppColors.success),
              const Divider(height: 24),
              _buildBreakdownRow("Platform Support", (thisMonth * 0.25).toStringAsFixed(2), AppColors.textSecondary),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBreakdownRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTypography.bodyMedium),
        Text(value, style: AppTypography.bodyLarge.copyWith(color: color, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildRemovedVideosSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 20),
            AppSpacing.hSpace8,
            Text("Content Violations", style: AppTypography.titleMedium.copyWith(color: AppColors.error)),
          ],
        ),
        AppSpacing.vSpace12,
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _removedVideos.length,
          separatorBuilder: (_, __) => AppSpacing.vSpace12,
          itemBuilder: (context, index) {
            final video = _removedVideos[index];
            return Container(
              padding: EdgeInsets.all(AppSpacing.spacing3),
              decoration: BoxDecoration(
                color: AppColors.backgroundSecondary,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.error.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  // Non-playable Thumbnail with overlay
                  Stack(
                    children: [
                      Container(
                        width: 80,
                        height: 45,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          image: DecorationImage(
                            image: NetworkImage(video.thumbnailUrl),
                            fit: BoxFit.cover,
                            colorFilter: ColorFilter.mode(
                              Colors.black.withOpacity(0.6),
                              BlendMode.darken,
                            ),
                          ),
                        ),
                      ),
                      const Positioned.fill(
                        child: Center(
                          child: Icon(Icons.block, color: Colors.white, size: 20),
                        ),
                      ),
                    ],
                  ),
                  AppSpacing.hSpace12,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          video.videoName,
                          style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          "Reason: ${video.reason}",
                          style: TextStyle(color: AppColors.error.withOpacity(0.8), fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
