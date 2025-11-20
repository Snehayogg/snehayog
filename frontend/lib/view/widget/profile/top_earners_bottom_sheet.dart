import 'package:flutter/material.dart';
import 'package:vayu/utils/app_logger.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vayu/view/screens/profile_screen.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:vayu/config/app_config.dart';
import 'package:vayu/services/authservices.dart';

// Import AppConfig to access clearCache

/// Bottom sheet to display top earners from user's following list
class TopEarnersBottomSheet extends StatefulWidget {
  const TopEarnersBottomSheet({super.key});

  @override
  State<TopEarnersBottomSheet> createState() => _TopEarnersBottomSheetState();
}

class _TopEarnersBottomSheetState extends State<TopEarnersBottomSheet> {
  List<Map<String, dynamic>> _topEarners = [];
  bool _isLoading = false;
  bool _hasError = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Clear URL cache to force re-check of local server
    AppConfig.clearCache();
    AppLogger.log(
        '🔄 TopEarnersBottomSheet: Cleared URL cache, will re-detect server');
    _loadTopEarners();
  }

  Future<void> _loadTopEarners() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = null;
    });

    try {
      final token = await AuthService.getToken();
      if (token == null) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Not authenticated';
          _isLoading = false;
        });
        return;
      }

      final baseUrl = await AppConfig.getBaseUrlWithFallback();
      final uri = Uri.parse('$baseUrl/api/users/top-earners-from-following');

      AppLogger.log('========================================');
      AppLogger.log('💰💰💰 TOP EARNERS REQUEST 💰💰💰');
      AppLogger.log('📡 TopEarnersBottomSheet: Using base URL: $baseUrl');
      AppLogger.log('📡 TopEarnersBottomSheet: Full API URL: $uri');
      AppLogger.log(
          '📡 TopEarnersBottomSheet: Token available: ${token.isNotEmpty}');
      AppLogger.log(
          '📡 TopEarnersBottomSheet: Fetching top earners from following list...');

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 30));

      AppLogger.log('========================================');
      AppLogger.log('📡 TopEarnersBottomSheet: Response received');
      AppLogger.log(
          '📡 TopEarnersBottomSheet: Response status: ${response.statusCode}');
      AppLogger.log(
          '📡 TopEarnersBottomSheet: Response headers: ${response.headers}');
      AppLogger.log(
          '📡 TopEarnersBottomSheet: Response body: ${response.body}');
      AppLogger.log('========================================');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final topEarners =
            List<Map<String, dynamic>>.from(data['topEarners'] ?? []);

        AppLogger.log(
            '✅ TopEarnersBottomSheet: Found ${topEarners.length} top earners');

        setState(() {
          _topEarners = topEarners;
          _isLoading = false;
        });
      } else {
        final errorBody = response.body;
        AppLogger.log(
            '❌ TopEarnersBottomSheet: API error: ${response.statusCode} - $errorBody');
        setState(() {
          _hasError = true;
          _errorMessage = response.statusCode == 404
              ? 'User not found'
              : response.statusCode == 401
                  ? 'Authentication failed'
                  : 'Failed to load top earners (${response.statusCode})';
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      AppLogger.log('❌ TopEarnersBottomSheet: Error loading top earners: $e');
      AppLogger.log('❌ TopEarnersBottomSheet: Stack trace: $stackTrace');
      setState(() {
        _hasError = true;
        _errorMessage = e.toString().contains('TimeoutException')
            ? 'Request timeout. Please check your connection.'
            : e.toString().contains('SocketException')
                ? 'Network error. Please check your internet connection.'
                : 'Error: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  void _navigateToUserProfile(String userId) {
    Navigator.pop(context); // Close bottom sheet first
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfileScreen(userId: userId),
      ),
    );
  }

  String _formatEarnings(double? earnings) {
    if (earnings == null) return '₹0';
    if (earnings >= 100000) {
      return '₹${(earnings / 100000).toStringAsFixed(1)}L';
    } else if (earnings >= 1000) {
      return '₹${(earnings / 1000).toStringAsFixed(1)}K';
    }
    return '₹${earnings.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                border: Border(
                  bottom: BorderSide(color: Colors.grey[300]!, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700).withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.emoji_events,
                      color: Color(0xFFFFD700),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Top Earners (Following)',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.black54),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : _hasError
                      ? _buildErrorView()
                      : _topEarners.isEmpty
                          ? _buildEmptyView()
                          : _buildTopEarnersList(scrollController),
            ),
          ],
        ),
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
            const Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'Failed to load top earners',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadTopEarners,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.people_outline,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            const Text(
              'No top earners found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Start following creators to see top earners',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopEarnersList(ScrollController scrollController) {
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _topEarners.length,
      itemBuilder: (context, index) {
        final earner = _topEarners[index];
        return _buildEarnerCard(earner, index + 1);
      },
    );
  }

  Widget _buildEarnerCard(Map<String, dynamic> earner, int rank) {
    final userId = earner['userId'] as String?;
    final name = earner['name'] as String? ?? 'Unknown';
    final profilePic = earner['profilePic'] as String?;
    final earnings = (earner['totalEarnings'] as num?)?.toDouble() ?? 0.0;

    return GestureDetector(
      onTap: userId != null ? () => _navigateToUserProfile(userId) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Rank badge
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: rank <= 3
                    ? rank == 1
                        ? const Color(0xFFFFD700)
                        : rank == 2
                            ? const Color(0xFFC0C0C0)
                            : const Color(0xFFCD7F32)
                    : Colors.grey[300],
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$rank',
                  style: TextStyle(
                    color: rank <= 3 ? Colors.white : Colors.black87,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),

            // Profile picture
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey[300]!, width: 1),
              ),
              child: ClipOval(
                child: profilePic != null && profilePic.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: profilePic,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: Colors.grey[200],
                          child: const Icon(Icons.person, size: 24),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: Colors.grey[200],
                          child: const Icon(Icons.person, size: 24),
                        ),
                      )
                    : Container(
                        color: Colors.grey[200],
                        child: const Icon(Icons.person, size: 24),
                      ),
              ),
            ),
            const SizedBox(width: 16),

            // Name and earnings
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatEarnings(earnings),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
            ),

            // Arrow icon
            const Icon(
              Icons.chevron_right,
              color: Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}
