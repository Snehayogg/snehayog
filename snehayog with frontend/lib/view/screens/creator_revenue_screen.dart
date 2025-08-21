import 'package:flutter/material.dart';
import 'package:snehayog/services/ad_service.dart';
import 'package:snehayog/services/authservices.dart';
import 'package:snehayog/services/video_service.dart';
import 'package:snehayog/model/video_model.dart';

class CreatorRevenueScreen extends StatefulWidget {
  const CreatorRevenueScreen({super.key});

  @override
  State<CreatorRevenueScreen> createState() => _CreatorRevenueScreenState();
}

class _CreatorRevenueScreenState extends State<CreatorRevenueScreen> {
  final AdService _adService = AdService();
  final AuthService _authService = AuthService();
  final VideoService _videoService = VideoService();

  Map<String, dynamic>? _revenueData;
  List<VideoModel> _userVideos = [];
  Map<String, double> _videoRevenueMap = {};
  double _totalRevenue = 0.0;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadRevenueData();
  }

  Future<void> _loadRevenueData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Load user videos first
      final userData = await _authService.getUserData();
      if (userData != null) {
        final videos = await _videoService.getUserVideos(userData['id'] ?? '');
        setState(() {
          _userVideos = videos;
        });

        // Calculate revenue for all videos
        await _calculateTotalRevenue();
      }

      // Load revenue data from AdService
      final revenueData = await _adService.getCreatorRevenueSummary();
      setState(() {
        _revenueData = revenueData;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading revenue data: $e';
        _isLoading = false;
      });
    }
  }

  /// Calculate revenue for a specific video based on AD IMPRESSIONS
  double _calculateVideoRevenue(VideoModel video) {
    try {
      // Revenue is based on AD IMPRESSIONS, not video views
      // CPM (Cost Per Mille) = Revenue per 1000 ad impressions
      final cpm = 2.0; // Example: $2.00 per 1000 ad impressions

      // Get ad impressions for this video
      final adImpressions = _getAdImpressionsForVideo(video.id);

      // Calculate revenue: (Ad Impressions / 1000) × CPM
      double revenue = (adImpressions / 1000.0) * cpm;

      // Apply ad performance multipliers
      final adPerformanceMultiplier = _calculateAdPerformanceMultiplier(video);
      revenue *= adPerformanceMultiplier;

      return revenue;
    } catch (e) {
      print('❌ Error calculating video revenue: $e');
      return 0.0;
    }
  }

  /// Get ad impressions for a specific video
  int _getAdImpressionsForVideo(String videoId) {
    try {
      // Find the video
      final video = _userVideos.firstWhere((v) => v.id == videoId);

      // Simulate ad impressions based on video performance
      // In production, this would come from your ad network analytics
      int baseImpressions = video.views ?? 0;

      // Ad impressions are typically higher than video views
      // because ads can be shown multiple times per video view
      final adImpressionsMultiplier =
          1.5; // 50% more ad impressions than video views

      // Calculate estimated ad impressions
      final estimatedAdImpressions =
          (baseImpressions * adImpressionsMultiplier).round();

      print(
          '📊 Video ${video.videoName}: ${video.views} views → ${estimatedAdImpressions} estimated ad impressions');

      return estimatedAdImpressions;
    } catch (e) {
      print('❌ Error getting ad impressions: $e');
      return 0;
    }
  }

  /// Calculate ad performance multiplier based on engagement
  double _calculateAdPerformanceMultiplier(VideoModel video) {
    try {
      double multiplier = 1.0;

      // Higher engagement = better ad performance = higher revenue

      // Likes factor: +0.1 for every 100 likes
      if (video.likes > 0) {
        multiplier += (video.likes / 100.0) * 0.1;
      }

      // Comments factor: +0.05 for every 10 comments
      if (video.comments.isNotEmpty) {
        multiplier += (video.comments.length / 10.0) * 0.05;
      }

      // Video completion rate factor
      // Higher completion rate = better ad retention
      if (video.views != null && video.views! > 0) {
        // Assume 70% completion rate as baseline
        final estimatedCompletionRate = 0.7;
        if (estimatedCompletionRate > 0.7) {
          multiplier += (estimatedCompletionRate - 0.7) *
              0.5; // +0.5 for every 10% above 70%
        }
      }

      // Cap multiplier to reasonable bounds
      return multiplier.clamp(0.5, 2.0);
    } catch (e) {
      print('❌ Error calculating ad performance multiplier: $e');
      return 1.0;
    }
  }

  /// Calculate total revenue from all videos
  Future<void> _calculateTotalRevenue() async {
    try {
      double totalRevenue = 0.0;
      _videoRevenueMap.clear();

      for (final video in _userVideos) {
        final videoRevenue = _calculateVideoRevenue(video);
        _videoRevenueMap[video.id] = videoRevenue;
        totalRevenue += videoRevenue;
      }

      setState(() {
        _totalRevenue = totalRevenue;
      });

      print(
          '💰 CreatorRevenueScreen: Total revenue calculated: \$${totalRevenue.toStringAsFixed(4)}');
      print(
          '💰 CreatorRevenueScreen: Video revenue breakdown: $_videoRevenueMap');
    } catch (e) {
      print('❌ Error calculating total revenue: $e');
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
      print('❌ Error getting revenue analytics: $e');
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
            onPressed: _loadRevenueData,
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
              await _authService.signInWithGoogle();
              setState(() {});
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
              onPressed: _loadRevenueData,
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
    final totalRevenue = _revenueData?['totalRevenue'] ?? 0.0;
    final thisMonth = _revenueData?['thisMonth'] ?? 0.0;
    final lastMonth = _revenueData?['lastMonth'] ?? 0.0;

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text(
              'Total Revenue',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '₹${totalRevenue.toStringAsFixed(2)}',
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

  Widget _buildRevenueAnalyticsCard() {
    final analytics = _getRevenueAnalytics();
    final totalRevenue = analytics['total_revenue'] ?? 0.0;
    final totalVideos = analytics['total_videos'] ?? 0;
    final averageRevenue = analytics['average_revenue_per_video'] ?? 0.0;
    final topPerformingVideoName = analytics['top_performing_video'] as String?;
    final topPerformingRevenue = analytics['top_performing_revenue'] ?? 0.0;

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Revenue Analytics',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildAnalyticsRow(
                'Total Revenue', '₹${totalRevenue.toStringAsFixed(2)}'),
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
    final adRevenue = _revenueData?['adRevenue'] ?? 0.0;
    final platformFee = _revenueData?['platformFee'] ?? 0.0;
    final netRevenue = _revenueData?['netRevenue'] ?? 0.0;

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
                  flex: (adRevenue * 100).round(),
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Expanded(
                  flex: (platformFee * 100).round(),
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

            _buildBreakdownRow(
                'Ad Revenue', '₹${adRevenue.toStringAsFixed(2)}', Colors.green),
            _buildBreakdownRow('Platform Fee (20%)',
                '₹${platformFee.toStringAsFixed(2)}', Colors.red),
            const Divider(),
            _buildBreakdownRow(
                'Net Revenue (80%)',
                '₹${netRevenue.toStringAsFixed(2)}',
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
                  'Upload videos to start earning revenue',
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
              final revenue = _videoRevenueMap[video.id] ?? 0.0;
              final adImpressions = _getAdImpressionsForVideo(video.id);

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
                          _buildVideoStat('Views', '${video.views ?? 0}'),
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

  void _showDetailedVideoAnalytics() {
    if (_userVideos.isEmpty) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.analytics, color: Colors.green),
            SizedBox(width: 8),
            Text('📊 Detailed Video Analytics'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Summary
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.attach_money,
                        color: Colors.green, size: 24),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Total Revenue',
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                        Text(
                          '₹${_totalRevenue.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Video breakdown
              ..._userVideos.map((video) {
                final revenue = _videoRevenueMap[video.id] ?? 0.0;
                final adImpressions = _getAdImpressionsForVideo(video.id);

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
                            Expanded(
                              child: _buildDetailedStat(
                                  'Views', '${video.views ?? 0}'),
                            ),
                            Expanded(
                              child:
                                  _buildDetailedStat('Likes', '${video.likes}'),
                            ),
                            Expanded(
                              child: _buildDetailedStat(
                                  'Comments', '${video.comments.length}'),
                            ),
                            Expanded(
                              child: _buildDetailedStat(
                                  'Ad Impressions', '$adImpressions'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}
