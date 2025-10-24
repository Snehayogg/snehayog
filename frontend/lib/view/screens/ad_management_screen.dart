import 'package:flutter/material.dart';
import 'package:vayu/services/ad_service.dart';
import 'package:vayu/services/authservices.dart';
import 'package:vayu/model/ad_model.dart';

/// **ENHANCED AD MANAGEMENT SCREEN**
/// Complete ad management with advanced targeting, performance analytics, and bulk operations
class AdManagementScreen extends StatefulWidget {
  const AdManagementScreen({super.key});

  @override
  State<AdManagementScreen> createState() => _AdManagementScreenState();
}

class _AdManagementScreenState extends State<AdManagementScreen>
    with TickerProviderStateMixin {
  final AdService _adService = AdService();
  final AuthService _authService = AuthService();

  List<AdModel> _ads = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _selectedFilter = 'all';
  String _selectedSort = 'created_desc';
  bool _isMultiSelectMode = false;
  final Set<String> _selectedAdIds = {};

  // **NEW: Tab controller for different views**
  late TabController _tabController;

  // **NEW: Search and filter state**
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  DateTimeRange? _dateFilter;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAds();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
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
        print(
            '🗑️ AdManagementScreen: Starting delete for ad: ${ad.id} - ${ad.title}');

        final success = await _adService.deleteAd(ad.id);
        print('🔍 AdManagementScreen: Delete result: $success');

        if (success) {
          print('✅ AdManagementScreen: Delete successful, reloading ads...');
          await _loadAds(); // Reload ads

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Ad "${ad.title}" deleted successfully'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          print('❌ AdManagementScreen: Delete returned false');
          throw Exception('Delete operation failed');
        }
      } catch (e) {
        print('❌ AdManagementScreen: Delete error: $e');
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

  // **NEW: Bulk operations**
  Future<void> _bulkUpdateStatus(String newStatus) async {
    if (_selectedAdIds.isEmpty) return;

    try {
      for (final adId in _selectedAdIds) {
        await _adService.updateAdStatus(adId, newStatus);
      }

      setState(() {
        _selectedAdIds.clear();
        _isMultiSelectMode = false;
      });

      await _loadAds();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${_selectedAdIds.length} ads updated to ${newStatus.toUpperCase()}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating ads: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _bulkDelete() async {
    if (_selectedAdIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Multiple Ads'),
        content: Text(
            'Are you sure you want to delete ${_selectedAdIds.length} selected ads? This action cannot be undone.'),
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
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        for (final adId in _selectedAdIds) {
          await _adService.deleteAd(adId);
        }

        setState(() {
          _selectedAdIds.clear();
          _isMultiSelectMode = false;
        });

        await _loadAds();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('${_selectedAdIds.length} ads deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting ads: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _showAdDetails(AdModel ad) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        ad.title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: ad.performanceColor,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        ad.performanceStatus,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Media preview
                if (ad.imageUrl != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      ad.imageUrl!,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        height: 200,
                        color: Colors.grey.shade300,
                        child: const Icon(Icons.image,
                            size: 48, color: Colors.grey),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Performance metrics tabs
                DefaultTabController(
                  length: 3,
                  child: Column(
                    children: [
                      const TabBar(
                        tabs: [
                          Tab(text: 'Performance'),
                          Tab(text: 'Targeting'),
                          Tab(text: 'Details'),
                        ],
                      ),
                      SizedBox(
                        height: 400,
                        child: TabBarView(
                          children: [
                            _buildPerformanceTab(ad),
                            _buildTargetingTab(ad),
                            _buildDetailsTab(ad),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPerformanceTab(AdModel ad) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Key metrics cards
          GridView.count(
            shrinkWrap: true,
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.5,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildMetricCard('Impressions', ad.impressions.toString(),
                  Icons.visibility, Colors.blue),
              _buildMetricCard('Clicks', ad.clicks.toString(), Icons.touch_app,
                  Colors.green),
              _buildMetricCard(
                  'CTR', ad.formattedCtr, Icons.trending_up, Colors.orange),
              _buildMetricCard(
                  'Spend', ad.formattedSpend, Icons.attach_money, Colors.red),
              _buildMetricCard('Conversions', ad.conversions.toString(),
                  Icons.star, Colors.purple),
              _buildMetricCard(
                  'CPC', ad.formattedCpc, Icons.monetization_on, Colors.teal),
            ],
          ),
          const SizedBox(height: 16),

          // Budget pacing
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Budget Pacing',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: ad.budgetPacing.clamp(0.0, 1.0),
                    backgroundColor: Colors.grey.shade300,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      ad.budgetPacing > 1.2
                          ? Colors.red
                          : ad.budgetPacing > 0.8
                              ? Colors.green
                              : Colors.orange,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(ad.budgetPacingStatus),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetingTab(AdModel ad) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildTargetingCard('Age', ad.ageTargeting, Icons.person),
          _buildTargetingCard('Gender', ad.genderTargeting, Icons.wc),
          _buildTargetingCard(
              'Locations', ad.locationSummary, Icons.location_on),
          _buildTargetingCard('Interests', ad.interestSummary, Icons.interests),
          _buildTargetingCard('Platforms', ad.platformSummary, Icons.devices),
          if (ad.deviceType != null)
            _buildTargetingCard(
                'Device Type', ad.deviceType!, Icons.phone_android),
        ],
      ),
    );
  }

  Widget _buildDetailsTab(AdModel ad) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDetailItem('Description', ad.description),
          _buildDetailItem('Ad Type', ad.adType.toUpperCase()),
          _buildDetailItem('Status', ad.status.toUpperCase()),
          _buildDetailItem('Budget', ad.formattedBudget),
          if (ad.startDate != null)
            _buildDetailItem(
                'Start Date', ad.startDate!.toString().split(' ')[0]),
          if (ad.endDate != null)
            _buildDetailItem('End Date', ad.endDate!.toString().split(' ')[0]),
          if (ad.targetKeywords.isNotEmpty)
            _buildDetailItem('Keywords', ad.targetKeywords.join(', ')),
          if (ad.link != null) _buildDetailItem('Link', ad.link!),
          _buildDetailItem('Created', ad.createdAt.toString().split(' ')[0]),
        ],
      ),
    );
  }

  Widget _buildMetricCard(
      String title, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
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

  Widget _buildTargetingCard(String title, String value, IconData icon) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: Colors.blue),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(value),
      ),
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  List<AdModel> get _filteredAds {
    var filtered = _ads;

    // Apply status filter
    switch (_selectedFilter) {
      case 'active':
        filtered = filtered.where((ad) => ad.isActive).toList();
        break;
      case 'draft':
        filtered = filtered.where((ad) => ad.isDraft).toList();
        break;
      case 'paused':
        filtered = filtered.where((ad) => ad.isPaused).toList();
        break;
      case 'completed':
        filtered = filtered.where((ad) => ad.isCompleted).toList();
        break;
    }

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered
          .where((ad) =>
              ad.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              ad.description
                  .toLowerCase()
                  .contains(_searchQuery.toLowerCase()) ||
              ad.targetKeywords.any((keyword) =>
                  keyword.toLowerCase().contains(_searchQuery.toLowerCase())))
          .toList();
    }

    // Apply date filter
    if (_dateFilter != null) {
      filtered = filtered
          .where((ad) =>
              ad.createdAt.isAfter(_dateFilter!.start) &&
              ad.createdAt.isBefore(_dateFilter!.end))
          .toList();
    }

    // Apply sorting
    switch (_selectedSort) {
      case 'created_desc':
        filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case 'created_asc':
        filtered.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case 'performance_desc':
        filtered.sort((a, b) => b.ctr.compareTo(a.ctr));
        break;
      case 'spend_desc':
        filtered.sort((a, b) => b.spend.compareTo(a.spend));
        break;
      case 'budget_desc':
        filtered.sort((a, b) => b.budget.compareTo(a.budget));
        break;
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isMultiSelectMode
            ? Text('${_selectedAdIds.length} selected')
            : const Text('Ad Management'),
        centerTitle: true,
        elevation: 0,
        actions: [
          if (_isMultiSelectMode) ...[
            IconButton(
              onPressed: () => _bulkUpdateStatus('active'),
              icon: const Icon(Icons.play_arrow),
              tooltip: 'Activate Selected',
            ),
            IconButton(
              onPressed: () => _bulkUpdateStatus('paused'),
              icon: const Icon(Icons.pause),
              tooltip: 'Pause Selected',
            ),
            IconButton(
              onPressed: _bulkDelete,
              icon: const Icon(Icons.delete),
              tooltip: 'Delete Selected',
            ),
            IconButton(
              onPressed: () {
                setState(() {
                  _isMultiSelectMode = false;
                  _selectedAdIds.clear();
                });
              },
              icon: const Icon(Icons.close),
            ),
          ] else ...[
            IconButton(
              onPressed: () {
                setState(() {
                  _isMultiSelectMode = true;
                });
              },
              icon: const Icon(Icons.checklist),
              tooltip: 'Multi-select',
            ),
            IconButton(
              onPressed: _loadAds,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'All Ads'),
            Tab(text: 'Analytics'),
            Tab(text: 'Insights'),
            Tab(text: 'Settings'),
          ],
        ),
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _authService.getUserData(),
        builder: (context, snapshot) {
          final isSignedIn = snapshot.hasData && snapshot.data != null;

          if (!isSignedIn) {
            return _buildLoginPrompt();
          }

          return TabBarView(
            controller: _tabController,
            children: [
              _buildAdListTab(),
              _buildAnalyticsTab(),
              _buildInsightsTab(),
              _buildSettingsTab(),
            ],
          );
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

  Widget _buildAdListTab() {
    return Column(
      children: [
        // Search and filters
        Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Search bar
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search ads, keywords...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                          icon: const Icon(Icons.clear),
                        )
                      : null,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
              ),
              const SizedBox(height: 12),

              // Filter and sort row
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedFilter,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
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
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedSort,
                      decoration: const InputDecoration(
                        labelText: 'Sort by',
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'created_desc', child: Text('Newest first')),
                        DropdownMenuItem(
                            value: 'created_asc', child: Text('Oldest first')),
                        DropdownMenuItem(
                            value: 'performance_desc', child: Text('Best CTR')),
                        DropdownMenuItem(
                            value: 'spend_desc', child: Text('Highest spend')),
                        DropdownMenuItem(
                            value: 'budget_desc',
                            child: Text('Highest budget')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedSort = value!;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Stats overview
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                  child: _buildStatCard('Total Ads', _ads.length.toString(),
                      Icons.campaign, Colors.blue)),
              const SizedBox(width: 8),
              Expanded(
                  child: _buildStatCard(
                      'Active',
                      _ads.where((ad) => ad.isActive).length.toString(),
                      Icons.play_circle,
                      Colors.green)),
              const SizedBox(width: 8),
              Expanded(
                  child: _buildStatCard(
                      'Total Spend',
                      '₹${_ads.fold(0.0, (sum, ad) => sum + ad.spend).toStringAsFixed(2)}',
                      Icons.attach_money,
                      Colors.orange)),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Ads list
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
                            return _buildEnhancedAdCard(ad);
                          },
                        ),
        ),
      ],
    );
  }

  Widget _buildEnhancedAdCard(AdModel ad) {
    final isSelected = _selectedAdIds.contains(ad.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isSelected ? 4 : 1,
      color: isSelected ? Colors.blue.shade50 : null,
      child: InkWell(
        onTap: _isMultiSelectMode
            ? () {
                setState(() {
                  if (isSelected) {
                    _selectedAdIds.remove(ad.id);
                  } else {
                    _selectedAdIds.add(ad.id);
                  }
                });
              }
            : () => _showAdDetails(ad),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with selection checkbox
              Row(
                children: [
                  if (_isMultiSelectMode) ...[
                    Checkbox(
                      value: isSelected,
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _selectedAdIds.add(ad.id);
                          } else {
                            _selectedAdIds.remove(ad.id);
                          }
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ad.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          ad.adType.toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Status and performance badges
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
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
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: ad.performanceColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: ad.performanceColor.withOpacity(0.3)),
                        ),
                        child: Text(
                          ad.performanceStatus,
                          style: TextStyle(
                            color: ad.performanceColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Performance metrics
              Row(
                children: [
                  Expanded(
                      child: _buildMiniMetric('Impressions',
                          ad.impressions.toString(), Icons.visibility)),
                  Expanded(
                      child: _buildMiniMetric(
                          'Clicks', ad.clicks.toString(), Icons.touch_app)),
                  Expanded(
                      child: _buildMiniMetric(
                          'CTR', ad.formattedCtr, Icons.trending_up)),
                  Expanded(
                      child: _buildMiniMetric(
                          'Spend', ad.formattedSpend, Icons.attach_money)),
                ],
              ),

              const SizedBox(height: 12),

              // Targeting summary
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _buildTargetingChip(ad.ageTargeting, Icons.person),
                  _buildTargetingChip(ad.locationSummary, Icons.location_on),
                  _buildTargetingChip(ad.platformSummary, Icons.devices),
                ],
              ),

              const SizedBox(height: 12),

              // Actions row (only when not in multi-select mode)
              if (!_isMultiSelectMode)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showAdDetails(ad),
                        icon: const Icon(Icons.analytics, size: 16),
                        label: const Text('Analytics'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (ad.isDraft || ad.isPaused)
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _updateAdStatus(ad, 'active'),
                          icon: const Icon(Icons.play_arrow, size: 16),
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
                          icon: const Icon(Icons.pause, size: 16),
                          label: const Text('Pause'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => _deleteAd(ad),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                      child: const Icon(Icons.delete_outline, size: 16),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniMetric(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildTargetingChip(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.blue.shade700),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              color: Colors.blue.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsTab() {
    if (_ads.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.analytics_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No ads to analyze',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              'Create some ads to view analytics',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Overall performance summary
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Overall Performance',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildAnalyticsMetric(
                          'Total Impressions',
                          _ads
                              .fold(0, (sum, ad) => sum + ad.impressions)
                              .toString(),
                          Icons.visibility,
                          Colors.blue,
                        ),
                      ),
                      Expanded(
                        child: _buildAnalyticsMetric(
                          'Total Clicks',
                          _ads.fold(0, (sum, ad) => sum + ad.clicks).toString(),
                          Icons.touch_app,
                          Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildAnalyticsMetric(
                          'Average CTR',
                          '${(_ads.fold(0.0, (sum, ad) => sum + ad.ctr) / _ads.length).toStringAsFixed(2)}%',
                          Icons.trending_up,
                          Colors.orange,
                        ),
                      ),
                      Expanded(
                        child: _buildAnalyticsMetric(
                          'Total Spend',
                          '₹${_ads.fold(0.0, (sum, ad) => sum + ad.spend).toStringAsFixed(2)}',
                          Icons.attach_money,
                          Colors.red,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Top performing ads
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Top Performing Ads',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  ..._getTopPerformingAds().map((ad) => ListTile(
                        title: Text(ad.title),
                        subtitle: Text(
                            'CTR: ${ad.formattedCtr} • Clicks: ${ad.clicks}'),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: ad.performanceColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            ad.performanceStatus,
                            style: TextStyle(
                              color: ad.performanceColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      )),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Ad type performance comparison
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Performance by Ad Type',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  ..._getAdTypePerformance().entries.map((entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.key.toUpperCase(),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: 4),
                            LinearProgressIndicator(
                              value: (entry.value['ctr'] ?? 0) /
                                  10, // Normalize to 0-1 scale
                              backgroundColor: Colors.grey.shade300,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                (entry.value['ctr'] ?? 0) > 5
                                    ? Colors.green
                                    : (entry.value['ctr'] ?? 0) > 2
                                        ? Colors.orange
                                        : Colors.red,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'CTR: ${(entry.value['ctr'] ?? 0).toStringAsFixed(2)}% • Spend: ₹${(entry.value['spend'] ?? 0).toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightsTab() {
    if (_ads.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lightbulb_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No insights available',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              'Create and run ads to get insights',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Performance insights
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Performance Insights',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  ..._getPerformanceInsights()
                      .map((insight) => _buildInsightCard(insight)),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Optimization recommendations
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Optimization Recommendations',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  ..._getOptimizationRecommendations().map((recommendation) =>
                      _buildRecommendationCard(recommendation)),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Best practices
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Best Practices',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  ..._getBestPractices().map((practice) => ListTile(
                        leading: const Icon(Icons.check_circle,
                            color: Colors.green, size: 20),
                        title: Text(practice['title']!),
                        subtitle: Text(practice['description']!),
                        contentPadding: EdgeInsets.zero,
                      )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Account settings
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Account Settings',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading:
                        const Icon(Icons.notifications, color: Colors.blue),
                    title: const Text('Email Notifications'),
                    subtitle: const Text('Get notified about ad performance'),
                    trailing: Switch(
                      value: true, // TODO: Connect to actual setting
                      onChanged: (value) {
                        // TODO: Implement notification toggle
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Notification settings updated')),
                        );
                      },
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.warning, color: Colors.orange),
                    title: const Text('Budget Alerts'),
                    subtitle: const Text('Alert when 80% of budget is spent'),
                    trailing: Switch(
                      value: true, // TODO: Connect to actual setting
                      onChanged: (value) {
                        // TODO: Implement budget alert toggle
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Budget alert settings updated')),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Default ad settings
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Default Ad Settings',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading:
                        const Icon(Icons.attach_money, color: Colors.green),
                    title: const Text('Default Daily Budget'),
                    subtitle: const Text('₹100.00'),
                    trailing: IconButton(
                      onPressed: () => _showBudgetDialog(),
                      icon: const Icon(Icons.edit),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.group, color: Colors.purple),
                    title: const Text('Default Target Audience'),
                    subtitle: const Text('All ages, All locations'),
                    trailing: IconButton(
                      onPressed: () => _showTargetingDialog(),
                      icon: const Icon(Icons.edit),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.schedule, color: Colors.blue),
                    title: const Text('Auto-pause Low Performance'),
                    subtitle: const Text('Pause ads with CTR < 1%'),
                    trailing: Switch(
                      value: false, // TODO: Connect to actual setting
                      onChanged: (value) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Auto-pause setting updated')),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Billing and payments
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Billing & Payments',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: const Icon(Icons.credit_card, color: Colors.blue),
                    title: const Text('Payment Methods'),
                    subtitle: const Text('Manage your payment methods'),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Payment methods coming soon')),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.receipt, color: Colors.green),
                    title: const Text('Billing History'),
                    subtitle: const Text('View past invoices and payments'),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Billing history coming soon')),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Advanced settings
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Advanced Settings',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: const Icon(Icons.download, color: Colors.blue),
                    title: const Text('Export Data'),
                    subtitle: const Text('Download ad performance reports'),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () => _exportAdData(),
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete_sweep, color: Colors.red),
                    title: const Text('Clear Analytics Data'),
                    subtitle: const Text('Reset all performance metrics'),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () => _showClearDataDialog(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
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

  // **NEW: Helper methods for Analytics tab**

  Widget _buildAnalyticsMetric(
      String title, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
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
    );
  }

  List<AdModel> _getTopPerformingAds() {
    final sortedAds = List<AdModel>.from(_ads);
    sortedAds.sort((a, b) => b.ctr.compareTo(a.ctr));
    return sortedAds.take(3).toList();
  }

  Map<String, Map<String, double>> _getAdTypePerformance() {
    final performance = <String, Map<String, double>>{};

    for (final adType in ['banner', 'carousel', 'video feed ad']) {
      final adsOfType = _ads.where((ad) => ad.adType == adType).toList();
      if (adsOfType.isNotEmpty) {
        final avgCtr =
            adsOfType.fold(0.0, (sum, ad) => sum + ad.ctr) / adsOfType.length;
        final totalSpend = adsOfType.fold(0.0, (sum, ad) => sum + ad.spend);

        performance[adType] = {
          'ctr': avgCtr,
          'spend': totalSpend,
        };
      }
    }

    return performance;
  }

  // **NEW: Helper methods for Insights tab**

  List<Map<String, String>> _getPerformanceInsights() {
    final insights = <Map<String, String>>[];

    // Best performing ad type
    final adTypePerf = _getAdTypePerformance();
    if (adTypePerf.isNotEmpty) {
      final bestType = adTypePerf.entries
          .reduce((a, b) => a.value['ctr']! > b.value['ctr']! ? a : b)
          .key;
      insights.add({
        'title': 'Best Performing Ad Type',
        'description': '${bestType.toUpperCase()} ads have the highest CTR',
        'type': 'success',
      });
    }

    // Budget utilization
    final totalBudget = _ads.fold(0.0, (sum, ad) => sum + ad.budget);
    final totalSpend = _ads.fold(0.0, (sum, ad) => sum + ad.spend);
    final utilization = totalBudget > 0 ? (totalSpend / totalBudget) * 100 : 0;

    if (utilization < 50) {
      insights.add({
        'title': 'Low Budget Utilization',
        'description':
            'Only ${utilization.toStringAsFixed(1)}% of budget used. Consider increasing bids.',
        'type': 'warning',
      });
    }

    return insights;
  }

  List<Map<String, String>> _getOptimizationRecommendations() {
    final recommendations = <Map<String, String>>[];

    // Low CTR ads
    final lowCtrAds = _ads.where((ad) => ad.ctr < 1.0).toList();
    if (lowCtrAds.isNotEmpty) {
      recommendations.add({
        'title': 'Improve Low CTR Ads',
        'description':
            '${lowCtrAds.length} ads have CTR < 1%. Try updating creative or targeting.',
        'action': 'Review',
      });
    }

    // High spend, low performance
    final inefficientAds =
        _ads.where((ad) => ad.spend > 500 && ad.ctr < 2.0).toList();
    if (inefficientAds.isNotEmpty) {
      recommendations.add({
        'title': 'High Spend, Low Performance',
        'description':
            '${inefficientAds.length} ads spending >₹500 with poor CTR. Consider pausing.',
        'action': 'Optimize',
      });
    }

    // No active ads
    final activeAds = _ads.where((ad) => ad.isActive).toList();
    if (activeAds.isEmpty) {
      recommendations.add({
        'title': 'No Active Ads',
        'description':
            'All ads are paused or draft. Activate ads to start getting impressions.',
        'action': 'Activate',
      });
    }

    return recommendations;
  }

  List<Map<String, String>> _getBestPractices() {
    return [
      {
        'title': 'Use High-Quality Images',
        'description':
            'Clear, vibrant images get 40% more clicks than low-quality ones',
      },
      {
        'title': 'Target Specific Audiences',
        'description':
            'Narrow targeting often performs better than broad targeting',
      },
      {
        'title': 'Test Multiple Creatives',
        'description':
            'A/B test different images and copy to find what works best',
      },
      {
        'title': 'Monitor CTR Regularly',
        'description': 'Pause ads with CTR < 1% and optimize or replace them',
      },
      {
        'title': 'Set Realistic Budgets',
        'description': 'Start with smaller budgets and scale up successful ads',
      },
    ];
  }

  Widget _buildInsightCard(Map<String, String> insight) {
    final isSuccess = insight['type'] == 'success';
    final isWarning = insight['type'] == 'warning';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSuccess
            ? Colors.green.withOpacity(0.1)
            : isWarning
                ? Colors.orange.withOpacity(0.1)
                : Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSuccess
              ? Colors.green.withOpacity(0.3)
              : isWarning
                  ? Colors.orange.withOpacity(0.3)
                  : Colors.blue.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isSuccess
                ? Icons.trending_up
                : isWarning
                    ? Icons.warning
                    : Icons.info,
            color: isSuccess
                ? Colors.green
                : isWarning
                    ? Colors.orange
                    : Colors.blue,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insight['title']!,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  insight['description']!,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationCard(Map<String, String> recommendation) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lightbulb, color: Colors.blue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recommendation['title']!,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  recommendation['description']!,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(
                        '${recommendation['action']} feature coming soon')),
              );
            },
            child: Text(recommendation['action']!),
          ),
        ],
      ),
    );
  }

  // **NEW: Helper methods for Settings tab**

  void _showBudgetDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Default Daily Budget'),
        content: const TextField(
          decoration: InputDecoration(
            labelText: 'Daily Budget (₹)',
            hintText: '100.00',
            prefixText: '₹',
          ),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Default budget updated')),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showTargetingDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Default Targeting'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Set your default targeting preferences for new ads'),
            SizedBox(height: 16),
            Text('• Age range: 18-65'),
            Text('• Gender: All'),
            Text('• Location: All locations'),
            Text('• Interests: General'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Default targeting updated')),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _exportAdData() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export Ad Data'),
        content: const Text('Export your ad performance data as CSV or PDF?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('CSV export coming soon')),
              );
            },
            child: const Text('CSV'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('PDF export coming soon')),
              );
            },
            child: const Text('PDF'),
          ),
        ],
      ),
    );
  }

  void _showClearDataDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Analytics Data'),
        content: const Text(
          'This will reset all performance metrics (impressions, clicks, CTR) for all your ads. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Analytics data cleared'),
                  backgroundColor: Colors.orange,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear Data'),
          ),
        ],
      ),
    );
  }
}
