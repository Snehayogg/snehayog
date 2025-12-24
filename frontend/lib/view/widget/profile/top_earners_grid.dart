import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:vayu/config/app_config.dart';
import 'package:vayu/services/authservices.dart';
import 'package:vayu/utils/app_logger.dart';
import 'package:vayu/view/screens/profile_screen.dart';

/// Compact grid (3 columns) showing top earners from the user's following list.
/// This reuses the same API as `TopEarnersBottomSheet` but is optimised for the
/// ProfileScreen "Recommendations" tab.
class TopEarnersGrid extends StatefulWidget {
  const TopEarnersGrid({super.key});

  @override
  State<TopEarnersGrid> createState() => _TopEarnersGridState();
}

class _TopEarnersGridState extends State<TopEarnersGrid> {
  List<Map<String, dynamic>> _topEarners = [];
  bool _isLoading = false;
  bool _hasError = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
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
      if (token == null || token.isEmpty) {
        setState(() {
          _hasError = true;
          _errorMessage =
              'Sign in to see top earners from your following list.';
          _isLoading = false;
        });
        return;
      }

      final baseUrl = await AppConfig.getBaseUrlWithFallback();
      final uri = Uri.parse('$baseUrl/api/users/top-earners-from-following');

      AppLogger.log('💰 TopEarnersGrid: Fetching top earners from $uri');

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 30));

      AppLogger.log(
          '💰 TopEarnersGrid: Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final topEarners =
            List<Map<String, dynamic>>.from(data['topEarners'] ?? []);

        setState(() {
          _topEarners = topEarners;
          _isLoading = false;
        });
      } else {
        setState(() {
          _hasError = true;
          _errorMessage = 'Failed to load top earners (${response.statusCode})';
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      AppLogger.log('❌ TopEarnersGrid: Error loading top earners: $e');
      AppLogger.log('❌ TopEarnersGrid: Stack trace: $stackTrace');
      setState(() {
        _hasError = true;
        _errorMessage = e.toString().contains('TimeoutException')
            ? 'Request timeout. Please check your connection.'
            : e.toString().contains('SocketException')
                ? 'Network error. Please check your internet connection.'
                : 'Failed to load top earners';
        _isLoading = false;
      });
    }
  }

  void _navigateToUserProfile(String userId) {
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfileScreen(userId: userId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 32),
              const SizedBox(height: 8),
              Text(
                _errorMessage ?? 'Failed to load top earners',
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _loadTopEarners,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_topEarners.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_outline, size: 40, color: Colors.grey),
              SizedBox(height: 8),
              Text(
                'No top earners found',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF4B5563),
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Start following creators to see who earns the most.',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF9CA3AF),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // GRID: 3 columns, Instagram-style tiles
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 0.6,
      ),
      itemCount: _topEarners.length,
      itemBuilder: (context, index) {
        final earner = _topEarners[index];
        return _buildEarnerTile(earner, index + 1);
      },
    );
  }

  Widget _buildEarnerTile(Map<String, dynamic> earner, int rank) {
    final userId = earner['userId'] as String?;
    final name = earner['name'] as String? ?? 'Unknown';
    final profilePic = earner['profilePic'] as String?;
    final earnings = (earner['totalEarnings'] as num?)?.toDouble() ?? 0.0;

    Color badgeColor;
    if (rank == 1) {
      badgeColor = const Color(0xFFFFD700); // gold
    } else if (rank == 2) {
      badgeColor = const Color(0xFFC0C0C0); // silver
    } else if (rank == 3) {
      badgeColor = const Color(0xFFCD7F32); // bronze
    } else {
      badgeColor = Colors.grey.shade300;
    }

    return GestureDetector(
      onTap: userId != null ? () => _navigateToUserProfile(userId) : null,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            // Avatar + rank badge
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: const Color(0xFFE5E7EB), width: 1),
                  ),
                  child: ClipOval(
                    child: profilePic != null && profilePic.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: profilePic,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: Colors.grey[200],
                              child: const Icon(Icons.person, size: 22),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: Colors.grey[200],
                              child: const Icon(Icons.person, size: 22),
                            ),
                          )
                        : Container(
                            color: Colors.grey[200],
                            child: const Icon(Icons.person, size: 22),
                          ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$rank',
                    style: TextStyle(
                      color: rank <= 3 ? Colors.white : Colors.black87,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Name
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111827),
                ),
              ),
            ),
            const SizedBox(height: 4),
            // Earnings
            Text(
              _formatEarnings(earnings),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF10B981),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatEarnings(double earnings) {
    if (earnings >= 10000000) {
      return '₹${(earnings / 10000000).toStringAsFixed(1)} Cr';
    } else if (earnings >= 100000) {
      return '₹${(earnings / 100000).toStringAsFixed(1)} L';
    } else if (earnings >= 1000) {
      return '₹${(earnings / 1000).toStringAsFixed(1)}K';
    } else {
      return '₹${earnings.toStringAsFixed(0)}';
    }
  }
}
