import 'package:flutter/material.dart';
import 'package:snehayog/services/ad_service.dart';
import 'package:snehayog/services/authservices.dart';
import 'package:snehayog/model/ad_model.dart';
import 'package:http/http.dart' as http;
import 'package:snehayog/config/app_config.dart';

class AdManagementScreen extends StatefulWidget {
  const AdManagementScreen({super.key});

  @override
  State<AdManagementScreen> createState() => _AdManagementScreenState();
}

class _AdManagementScreenState extends State<AdManagementScreen> {
  final AdService _adService = AdService();
  final AuthService _authService = AuthService();

  List<AdModel> _ads = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _selectedFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadAds();
  }

  Future<void> _loadAds() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      print('🔍 AdManagementScreen: Loading user ads...');
      final ads = await _adService.getUserAds();
      print('✅ AdManagementScreen: Successfully loaded ${ads.length} ads');

      setState(() {
        _ads = ads;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ AdManagementScreen: Error loading ads: $e');
      setState(() {
        _errorMessage = 'Error loading ads: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _updateAdStatus(AdModel ad, String newStatus) async {
    try {
      await _adService.updateAdStatus(ad.id, newStatus);
      await _loadAds(); // Reload ads to get updated data

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ad status updated to ${newStatus.toUpperCase()}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating ad status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteAd(AdModel ad) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Advertisement'),
        content: Text(
            'Are you sure you want to delete "${ad.title}"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _adService.deleteAd(ad.id);
        await _loadAds(); // Reload ads
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ad "${ad.title}" deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting ad: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  /// **NEW: Test API endpoint for debugging**
  Future<void> _testApiEndpoint() async {
    try {
      print('🔍 AdManagementScreen: Testing API endpoint...');

      final userData = await _authService.getUserData();
      if (userData == null) {
        throw Exception('User not authenticated');
      }

      final userId =
          userData['id']?.toString() ?? userData['googleId']?.toString();
      print('🔍 AdManagementScreen: User ID: $userId');
      print('🔍 AdManagementScreen: User data keys: ${userData.keys.toList()}');

      // Test the debug endpoint
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/ads/debug/check'),
        headers: {
          'Authorization': 'Bearer ${userData['token']}',
        },
      );

      print(
          '🔍 AdManagementScreen: Debug API response status: ${response.statusCode}');
      print('🔍 AdManagementScreen: Debug API response body: ${response.body}');

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('API Test Results'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Status: ${response.statusCode}'),
                  Text('User ID: $userId'),
                  Text('Response: ${response.body}'),
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
    } catch (e) {
      print('❌ AdManagementScreen: API test error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('API test failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// **NEW: Show user data for debugging**
  void _showUserData() async {
    try {
      final userData = await _authService.getUserData();
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('User Data'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('ID: ${userData?['id'] ?? 'Not found'}'),
                  Text('Google ID: ${userData?['googleId'] ?? 'Not found'}'),
                  Text('Name: ${userData?['name'] ?? 'Not found'}'),
                  Text('Email: ${userData?['email'] ?? 'Not found'}'),
                  Text(
                      'Token: ${userData?['token'] != null ? 'Present' : 'Not found'}'),
                  const SizedBox(height: 8),
                  const Text('All Keys:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  ...(userData?.keys
                          .map((key) => Text('• $key: ${userData[key]}')) ??
                      []),
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error getting user data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showAdDetails(AdModel ad) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(ad.title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (ad.imageUrl != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    ad.imageUrl!,
                    height: 150,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      height: 150,
                      color: Colors.grey.shade300,
                      child:
                          const Icon(Icons.image, size: 48, color: Colors.grey),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Text('Description: ${ad.description}'),
              const SizedBox(height: 8),
              Text('Type: ${ad.adType.toUpperCase()}'),
              const SizedBox(height: 8),
              Text('Status: ${ad.status.toUpperCase()}'),
              const SizedBox(height: 8),
              Text('Budget: ${ad.formattedBudget}'),
              const SizedBox(height: 8),
              Text('Impressions: ${ad.impressions}'),
              const SizedBox(height: 8),
              Text('Clicks: ${ad.clicks}'),
              const SizedBox(height: 8),
              Text('CTR: ${ad.formattedCtr}'),
              if (ad.startDate != null) ...[
                const SizedBox(height: 8),
                Text('Start Date: ${ad.startDate!.toString().split(' ')[0]}'),
              ],
              if (ad.endDate != null) ...[
                const SizedBox(height: 8),
                Text('End Date: ${ad.endDate!.toString().split(' ')[0]}'),
              ],
              if (ad.targetKeywords.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Keywords: ${ad.targetKeywords.join(', ')}'),
              ],
              if (ad.link != null) ...[
                const SizedBox(height: 8),
                Text('Link: ${ad.link}'),
              ],
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

  List<AdModel> get _filteredAds {
    switch (_selectedFilter) {
      case 'active':
        return _ads.where((ad) => ad.isActive).toList();
      case 'draft':
        return _ads.where((ad) => ad.isDraft).toList();
      case 'paused':
        return _ads.where((ad) => ad.isPaused).toList();
      case 'completed':
        return _ads.where((ad) => ad.isCompleted).toList();
      default:
        return _ads;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ad Management'),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _loadAds,
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

          return _buildAdManagementContent();
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
            'Please sign in to manage advertisements',
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

  Widget _buildAdManagementContent() {
    return Column(
      children: [
        // Filter and Stats
        Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Filter Dropdown
              Row(
                children: [
                  const Text('Filter: ',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _selectedFilter,
                    items: [
                      DropdownMenuItem(
                          value: 'all', child: Text('All (${_ads.length})')),
                      DropdownMenuItem(
                          value: 'active',
                          child: Text(
                              'Active (${_ads.where((ad) => ad.isActive).length})')),
                      DropdownMenuItem(
                          value: 'draft',
                          child: Text(
                              'Draft (${_ads.where((ad) => ad.isDraft).length})')),
                      DropdownMenuItem(
                          value: 'paused',
                          child: Text(
                              'Paused (${_ads.where((ad) => ad.isPaused).length})')),
                      DropdownMenuItem(
                          value: 'completed',
                          child: Text(
                              'Completed (${_ads.where((ad) => ad.isCompleted).length})')),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedFilter = value!;
                      });
                    },
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Stats Cards
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      'Total Ads',
                      _ads.length.toString(),
                      Icons.campaign,
                      Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatCard(
                      'Active',
                      _ads.where((ad) => ad.isActive).length.toString(),
                      Icons.play_circle,
                      Colors.green,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatCard(
                      'Total Budget',
                      '\$${(_ads.fold(0.0, (sum, ad) => sum + (ad.budget / 100))).toStringAsFixed(2)}',
                      Icons.attach_money,
                      Colors.orange,
                    ),
                  ),
                ],
              ),

              // **NEW: Debug section for troubleshooting**
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.bug_report,
                            color: Colors.orange[600], size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Debug Tools',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange[800],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _testApiEndpoint,
                            icon: const Icon(Icons.api, size: 16),
                            label: const Text('Test API'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _showUserData,
                            icon: const Icon(Icons.person, size: 16),
                            label: const Text('Show User Data'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Ads List
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline,
                              size: 64, color: Colors.red),
                          const SizedBox(height: 16),
                          Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.red),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _loadAds,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : _filteredAds.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.campaign_outlined,
                                  size: 64, color: Colors.grey),
                              const SizedBox(height: 16),
                              Text(
                                _selectedFilter == 'all'
                                    ? 'No advertisements found'
                                    : 'No $_selectedFilter advertisements found',
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 18),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Create your first advertisement to get started',
                                style: TextStyle(color: Colors.grey),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredAds.length,
                          itemBuilder: (context, index) {
                            final ad = _filteredAds[index];
                            return _buildAdCard(ad);
                          },
                        ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdCard(AdModel ad) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with status
            Row(
              children: [
                Expanded(
                  child: Text(
                    ad.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getStatusColor(ad.status),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    ad.status.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Description
            Text(
              ad.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey.shade600),
            ),

            const SizedBox(height: 12),

            // Stats row
            Row(
              children: [
                _buildStatItem(Icons.attach_money, ad.formattedBudget),
                const SizedBox(width: 16),
                _buildStatItem(Icons.visibility, '${ad.impressions}'),
                const SizedBox(width: 16),
                _buildStatItem(Icons.touch_app, '${ad.clicks}'),
                const SizedBox(width: 16),
                _buildStatItem(Icons.trending_up, ad.formattedCtr),
              ],
            ),

            const SizedBox(height: 12),

            // Actions row
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showAdDetails(ad),
                    icon: const Icon(Icons.info_outline),
                    label: const Text('Details'),
                  ),
                ),
                const SizedBox(width: 8),
                if (ad.isDraft || ad.isPaused)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _updateAdStatus(ad, 'active'),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Activate'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                if (ad.isActive)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _updateAdStatus(ad, 'paused'),
                      icon: const Icon(Icons.pause),
                      label: const Text('Pause'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _deleteAd(ad),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return Colors.green;
      case 'draft':
        return Colors.grey;
      case 'paused':
        return Colors.orange;
      case 'completed':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
}
