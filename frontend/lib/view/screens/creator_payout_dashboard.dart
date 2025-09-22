import 'package:flutter/material.dart';
import 'package:snehayog/config/app_config.dart';
import 'package:snehayog/services/authservices.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class CreatorPayoutDashboard extends StatefulWidget {
  const CreatorPayoutDashboard({Key? key}) : super(key: key);

  @override
  State<CreatorPayoutDashboard> createState() => _CreatorPayoutDashboardState();
}

class _CreatorPayoutDashboardState extends State<CreatorPayoutDashboard> {
  final AuthService _authService = AuthService();
  bool _isLoading = true;
  Map<String, dynamic>? _profileData;
  List<Map<String, dynamic>> _payoutHistory = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null; // Clear previous errors
      });

      print('🔍 CreatorPayoutDashboard: Starting data load...');
      print('🔍 Base URL: ${AppConfig.baseUrl}');

      final userData = await _authService.getUserData();
      print('🔍 CreatorPayoutDashboard: User data loaded: ${userData != null}');

      if (userData != null) {
        print('🔍 User data keys: ${userData.keys.toList()}');
        print('🔍 User ID: ${userData['id']}');
        print('🔍 User email: ${userData['email']}');
      }

      final token = userData?['token'];
      print('🔍 CreatorPayoutDashboard: Token available: ${token != null}');
      if (token != null) {
        print('🔍 Token length: ${token.toString().length}');
        print('🔍 Token starts with: ${token.toString().substring(0, 20)}...');
      }

      if (token == null) {
        print('❌ CreatorPayoutDashboard: No token found');
        setState(() {
          _error = 'Please login first to view payout dashboard';
          _isLoading = false;
        });
        return;
      }

      print('🔍 Token found, making API calls...');
      print('🔍 Base URL: ${AppConfig.baseUrl}');

      // Load profile data
      final profileUrl = '${AppConfig.baseUrl}/api/creator-payouts/profile';
      print('🔍 CreatorPayoutDashboard: Profile URL: $profileUrl');

      final profileResponse = await http.get(
        Uri.parse(profileUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Profile API request timed out');
        },
      ).catchError((error) {
        print('❌ HTTP Request Error: $error');
        throw Exception('Network error: $error');
      });

      print('🔍 Profile response status: ${profileResponse.statusCode}');
      print('🔍 Profile response body: ${profileResponse.body}');

      if (profileResponse.statusCode == 200) {
        setState(() {
          _profileData = json.decode(profileResponse.body);
        });
        print('✅ Profile data loaded successfully');
        print('🔍 Profile data keys: ${_profileData?.keys.toList()}');
        print('🔍 Creator info: ${_profileData?['creator']}');
      } else if (profileResponse.statusCode == 404) {
        // User doesn't have creator profile yet - show setup message
        print(
            '⚠️ Creator profile not found - user needs to set up creator account');
        setState(() {
          _profileData = {
            'creator': {
              'name': 'Creator Account Not Set Up',
              'email': 'Please complete setup',
              'country': 'IN',
              'currency': 'INR',
              'preferredPaymentMethod': null
            },
            'thresholds': {
              'firstPayout': {'INR': 'No minimum'},
              'subsequentPayouts': {'INR': '₹200 minimum'}
            },
            'paymentMethods': ['upi', 'bank_transfer', 'paytm']
          };
          _isLoading = false;
        });
        return;
      } else {
        print('❌ Profile data failed: ${profileResponse.statusCode}');
        setState(() {
          _error =
              'Failed to load profile data (${profileResponse.statusCode}): ${profileResponse.body}';
          _isLoading = false;
        });
        return;
      }

      // Load payout history
      final historyUrl = '${AppConfig.baseUrl}/api/creator-payouts/monthly';
      print('🔍 History URL: $historyUrl');

      final historyResponse = await http.get(
        Uri.parse(historyUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      print('🔍 History response status: ${historyResponse.statusCode}');
      print('🔍 History response body: ${historyResponse.body}');

      if (historyResponse.statusCode == 200) {
        final historyData = json.decode(historyResponse.body);
        setState(() {
          _payoutHistory =
              List<Map<String, dynamic>>.from(historyData['payouts'] ?? []);
        });
        print('✅ Payout history loaded: ${_payoutHistory.length} records');
      } else {
        // Don't fail completely if history fails, just log it
        print(
            '⚠️ Warning: Failed to load payout history (${historyResponse.statusCode}): ${historyResponse.body}');
        setState(() {
          _payoutHistory = []; // Initialize empty list
        });
      }

      setState(() {
        _isLoading = false;
      });
      print('✅ Dashboard data loading completed');
    } catch (e) {
      print('❌ CreatorPayoutDashboard: Error loading dashboard data: $e');
      setState(() {
        _error = 'Failed to load dashboard: ${e.toString()}';
        _isLoading = false;
      });

      // Show error to user immediately
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Dashboard Error: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: _loadDashboardData,
            ),
          ),
        );
      }
    }
  }

  Future<void> _testBackendConnection() async {
    try {
      print('🔍 Testing backend connection...');
      print('🔍 Base URL: ${AppConfig.baseUrl}');

      // Test the health endpoint first (no auth required)
      final healthUrl = '${AppConfig.baseUrl}/api/creator-payouts/health';
      print('🔍 Testing health endpoint: $healthUrl');

      final healthResponse = await http.get(Uri.parse(healthUrl)).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw Exception('Health check timed out - backend may be down');
        },
      );
      print('🔍 Health response status: ${healthResponse.statusCode}');
      print('🔍 Health response body: ${healthResponse.body}');

      if (healthResponse.statusCode == 200) {
        // Test the test endpoint
        final testUrl = '${AppConfig.baseUrl}/api/creator-payouts/test';
        print('🔍 Testing test endpoint: $testUrl');

        final testResponse = await http.get(Uri.parse(testUrl));
        print('🔍 Test response status: ${testResponse.statusCode}');
        print('🔍 Test response body: ${testResponse.body}');

        if (testResponse.statusCode == 200) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Backend connection successful!'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content:
                    Text('❌ Test endpoint failed: ${testResponse.statusCode}'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('❌ Health check failed: ${healthResponse.statusCode}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Backend connection test failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Connection failed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _testAuthentication() async {
    try {
      print('🔍 Testing authentication...');

      final userData = await _authService.getUserData();
      print('🔍 User data available: ${userData != null}');

      if (userData == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ No user data found - please login first'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      final token = userData['token'];
      print('🔍 Token available: ${token != null}');

      if (token == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('❌ No authentication token found - please re-login'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // Test authenticated endpoint
      final profileUrl = '${AppConfig.baseUrl}/api/creator-payouts/profile';
      print('🔍 Testing authenticated endpoint: $profileUrl');

      final response = await http.get(
        Uri.parse(profileUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 5));

      print('🔍 Auth test response status: ${response.statusCode}');
      print('🔍 Auth test response body: ${response.body}');

      if (mounted) {
        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Authentication working correctly!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        } else if (response.statusCode == 401) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Authentication failed - token may be expired'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '⚠️ Auth test failed with status: ${response.statusCode}'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Authentication test failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Auth test error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('💰 Creator Payout Dashboard'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: _testBackendConnection,
            tooltip: 'Test Backend',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDashboardData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? _buildLoadingWidget()
          : _error != null
              ? _buildErrorWidget()
              : _buildDashboardContent(),
    );
  }

  Widget _buildLoadingWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
          ),
          const SizedBox(height: 16),
          const Text(
            'Loading Dashboard...',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Please wait while we fetch your payout data',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              'Unable to Load Dashboard',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _loadDashboardData,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: _testBackendConnection,
                  icon: const Icon(Icons.bug_report),
                  label: const Text('Test Connection'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: _testAuthentication,
                  icon: const Icon(Icons.key),
                  label: const Text('Test Auth'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
              },
              icon: const Icon(Icons.arrow_back),
              label: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardContent() {
    if (_profileData == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.info_outline, size: 64, color: Colors.orange),
              const SizedBox(height: 16),
              const Text(
                'Creator Dashboard',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Welcome to your creator dashboard! Here you can track your earnings, manage payouts, and view your creator statistics.',
                style: TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _loadDashboardData,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Load Data'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _testBackendConnection,
                    icon: const Icon(Icons.bug_report),
                    label: const Text('Test API'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _testAuthentication,
                    icon: const Icon(Icons.key),
                    label: const Text('Test Auth'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profile Summary Card
          _buildProfileSummaryCard(),

          const SizedBox(height: 24),

          // Payment Method Card
          _buildPaymentMethodCard(),

          const SizedBox(height: 24),

          // Payout History
          _buildPayoutHistorySection(),

          const SizedBox(height: 24),

          // Setup Payment Profile Button
          _buildSetupPaymentButton(),
        ],
      ),
    );
  }

  Widget _buildProfileSummaryCard() {
    final creator = _profileData!['creator'] ?? {};
    final thresholds = _profileData!['thresholds'] ?? {};

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.grey[400]?.withOpacity(
                      0.1), // Changed from Colors.blue.withOpacity(0.1)
                  child: Icon(
                    Icons.person,
                    size: 30,
                    color: Colors.grey[700], // Changed from Colors.blue
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        creator['name'] ?? 'Creator',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        creator['email'] ?? 'email@example.com',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${creator['country'] ?? 'IN'} • ${creator['currency'] ?? 'INR'}',
                          style: const TextStyle(
                            color: Colors.green,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Threshold Information
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[300]?.withOpacity(0.1) ??
                    Colors.grey[300]!.withOpacity(0.1), // Fixed null safety
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: Colors.grey[500]?.withOpacity(0.3) ??
                        Colors.grey[500]!
                            .withOpacity(0.3)), // Fixed null safety
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: Colors.grey[700]), // Changed from Colors.blue
                      const SizedBox(width: 8),
                      Text(
                        'Payout Thresholds',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700], // Changed from Colors.blue
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildThresholdItem(
                          'First Payout',
                          thresholds['firstPayout']
                                  ?[creator['currency'] ?? 'INR'] ??
                              'No minimum',
                          Icons.star,
                          Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildThresholdItem(
                          'Subsequent',
                          thresholds['subsequentPayouts']
                                  ?[creator['currency'] ?? 'INR'] ??
                              '₹200 minimum',
                          Icons.repeat,
                          Colors.grey[700]!, // Changed from Colors.blue
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
    );
  }

  Widget _buildThresholdItem(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodCard() {
    final creator = _profileData!['creator'] ?? {};
    final paymentMethod = creator['preferredPaymentMethod'];
    final paymentMethods = _profileData!['paymentMethods'] ?? [];

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.payment, color: Colors.green, size: 24),
                SizedBox(width: 12),
                Text(
                  'Payment Method',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (paymentMethod != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      _getPaymentMethodIcon(paymentMethod),
                      color: Colors.green,
                      size: 32,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getPaymentMethodDisplayName(paymentMethod),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                          const Text(
                            'Active payment method',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 24,
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange, size: 32),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'No Payment Method Set',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                          Text(
                            'Set up your payment method to receive payouts',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Available Payment Methods for ${creator['country'] ?? 'IN'}:',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: paymentMethods.map((method) {
                return Chip(
                  label: Text(_getPaymentMethodDisplayName(method)),
                  backgroundColor: method == paymentMethod
                      ? Colors.green.withOpacity(0.1)
                      : Colors.grey[200],
                  labelStyle: TextStyle(
                    color: method == paymentMethod
                        ? Colors.green
                        : Colors.grey[600],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPayoutHistorySection() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history,
                    color: Colors.grey[700],
                    size: 24), // Changed from Colors.blue
                const SizedBox(width: 12),
                const Text(
                  'Payout History',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_payoutHistory.isEmpty) ...[
              Container(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    const Icon(
                      Icons.history,
                      size: 48,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No Payouts Yet',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your payout history will appear here once you start earning from ads',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ] else ...[
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _payoutHistory.length,
                itemBuilder: (context, index) {
                  final payout = _payoutHistory[index];
                  return _buildPayoutHistoryItem(payout);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPayoutHistoryItem(Map<String, dynamic> payout) {
    final status = payout['status'] ?? 'pending';
    final month = payout['month'] ?? 'Unknown';
    final amount = payout['payableINR'] ?? 0;
    final currency = payout['currency'] ?? 'INR';

    Color statusColor;
    IconData statusIcon;

    switch (status) {
      case 'paid':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'processing':
        statusColor = Colors.orange;
        statusIcon = Icons.hourglass_empty;
        break;
      case 'failed':
        statusColor = Colors.red;
        statusIcon = Icons.error;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.schedule;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(statusIcon, color: statusColor, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatMonth(month),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Amount: ${_formatCurrency(amount, currency)}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                if (payout['thresholdDisplay'] != null)
                  Text(
                    payout['thresholdDisplay'],
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              status.toUpperCase(),
              style: TextStyle(
                color: statusColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSetupPaymentButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        onPressed: () {
          // Navigate to payment setup screen
          Navigator.pushNamed(context, '/creator-payment-setup');
        },
        icon: const Icon(Icons.payment),
        label: const Text(
          'Setup Payment Profile',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.grey[700], // Changed from Colors.blue
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  String _getPaymentMethodDisplayName(String method) {
    switch (method) {
      case 'upi':
        return 'UPI';
      case 'bank_transfer':
        return 'Bank Transfer';
      case 'paytm':
        return 'Paytm';
      case 'phonepe':
        return 'PhonePe';
      case 'paypal':
        return 'PayPal';
      case 'stripe':
        return 'Stripe';
      case 'wise':
        return 'Wise';
      case 'payoneer':
        return 'Payoneer';
      case 'bank_wire':
        return 'International Bank Wire';
      default:
        return method;
    }
  }

  IconData _getPaymentMethodIcon(String method) {
    switch (method) {
      case 'upi':
        return Icons.phone_android;
      case 'bank_transfer':
        return Icons.account_balance;
      case 'paytm':
        return Icons.payment;
      case 'phonepe':
        return Icons.payment;
      case 'paypal':
        return Icons.payment;
      case 'stripe':
        return Icons.credit_card;
      case 'wise':
        return Icons.account_balance_wallet;
      case 'payoneer':
        return Icons.account_balance_wallet;
      case 'bank_wire':
        return Icons.account_balance;
      default:
        return Icons.payment;
    }
  }

  String _formatMonth(String month) {
    try {
      final parts = month.split('-');
      if (parts.length == 2) {
        final year = parts[0];
        final monthNum = int.parse(parts[1]);
        final monthNames = [
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
        return '${monthNames[monthNum - 1]} $year';
      }
    } catch (e) {
      // Handle parsing errors
    }
    return month;
  }

  String _formatCurrency(double amount, String currency) {
    final symbols = {
      'INR': '₹',
      'USD': '\$',
      'EUR': '€',
      'GBP': '£',
      'CAD': 'C\$',
      'AUD': 'A\$'
    };

    final symbol = symbols[currency] ?? '₹';
    return '$symbol${amount.toStringAsFixed(2)}';
  }
}
