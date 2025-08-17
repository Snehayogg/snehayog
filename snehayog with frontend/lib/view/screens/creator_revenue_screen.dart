import 'package:flutter/material.dart';
import 'package:snehayog/services/ad_service.dart';
import 'package:snehayog/services/authservices.dart';

class CreatorRevenueScreen extends StatefulWidget {
  const CreatorRevenueScreen({super.key});

  @override
  State<CreatorRevenueScreen> createState() => _CreatorRevenueScreenState();
}

class _CreatorRevenueScreenState extends State<CreatorRevenueScreen> {
  final AdService _adService = AdService();
  final AuthService _authService = AuthService();

  Map<String, dynamic>? _revenueData;
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

          // **NEW: Revenue Breakdown**
          _buildRevenueBreakdownCard(),

          const SizedBox(height: 24),

          // **NEW: Payment History**
          _buildPaymentHistoryCard(),

          const SizedBox(height: 24),

          // **NEW: Withdrawal Options**
          _buildWithdrawalCard(),
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
}
