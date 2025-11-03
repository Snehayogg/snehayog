import 'package:flutter/material.dart';
import 'package:vayu/model/ad_model.dart';
import 'package:snehayog_monetization/snehayog_monetization.dart';
import 'package:vayu/services/authservices.dart';
import 'package:vayu/config/app_config.dart';

/// **PaymentHandlerWidget - Handles payment processing and dialogs**
class PaymentHandlerWidget {
  static final AuthService _authService = AuthService();
  static late final RazorpayService _razorpayService;

  static void initialize() {
    _razorpayService = RazorpayService();
    _razorpayService.initialize(
      keyId: 'rzp_test_1234567890', // Replace with actual key
      keySecret: 'test_secret', // Replace with actual secret
      webhookSecret: 'test_webhook', // Replace with actual webhook
      baseUrl: AppConfig.baseUrl, // Use environment-configured base URL
    );
  }

  /// Show payment options dialog
  static void showPaymentOptions(
    BuildContext context,
    AdModel ad,
    Map<String, dynamic> invoice,
    Function() onPaymentSuccess,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.payment, color: Colors.blue, size: 24),
            SizedBox(width: 8),
            Text('Payment Required'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ad: ${ad.title}'),
            Text('Order ID: ${invoice['orderId']}'),
            Text('Amount: ₹${invoice['amount']}'),
            const SizedBox(height: 16),
            const Text(
              'Your ad has been created in draft status. Please complete the payment to activate it.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '💰 Campaign Metrics:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text('• 80% revenue share for creators'),
                  Text('• Real-time performance tracking'),
                  Text('• Professional ad management'),
                  Text('• Guaranteed impressions delivery'),
                ],
              ),
            ),
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
              _initiatePayment(context, ad, invoice, onPaymentSuccess);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Pay Now'),
          ),
        ],
      ),
    );
  }

  /// Initiate Razorpay payment
  static Future<void> _initiatePayment(
    BuildContext context,
    AdModel ad,
    Map<String, dynamic> invoice,
    Function() onPaymentSuccess,
  ) async {
    try {
      final userData = await _authService.getUserData();
      if (userData == null) {
        throw Exception('User not authenticated');
      }

      final totalAmount = invoice['amount'] as double;

      await _razorpayService.makePayment(
        amount: totalAmount,
        currency: 'INR',
        name: 'Vayug Ad Campaign',
        description: 'Advertisement campaign payment',
        email: userData['email'] ?? 'user@example.com',
        contact: userData['phone'] ?? '9999999999',
        userName: userData['name'] ?? 'User',
        onSuccess: (Map<String, dynamic> response) async {
          await _processSuccessfulPayment(
            context,
            response,
            onPaymentSuccess,
          );
        },
        onError: (String errorMessage) {
          _showErrorSnackBar(context, 'Payment failed: $errorMessage');
        },
      );
    } catch (e) {
      _showErrorSnackBar(context, 'Payment error: $e');
    }
  }

  /// Process successful payment
  static Future<void> _processSuccessfulPayment(
    BuildContext context,
    Map<String, dynamic> response,
    Function() onPaymentSuccess,
  ) async {
    try {
      final verificationResult =
          await _razorpayService.verifyPaymentWithBackend(
        orderId: response['orderId'] ?? '',
        paymentId: response['paymentId'] ?? '',
        signature: response['signature'] ?? '',
      );

      if (verificationResult['message'] == 'Payment verified successfully') {
        _showSuccessSnackBar(
            context, '✅ Payment verified! Ad campaign created successfully.');
        onPaymentSuccess();
      } else {
        throw Exception('Payment verification failed');
      }
    } catch (e) {
      _showErrorSnackBar(context, 'Payment verification failed: $e');
    }
  }

  /// Show advertising benefits dialog
  static void showAdvertisingBenefits(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.star, color: Colors.amber.shade600, size: 24),
            const SizedBox(width: 12),
            const Text(
              'Why Advertise on Vayug?',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBenefitItem(
                'Guaranteed Ad Impressions',
                'Unlike other platforms where ad reach is uncertain, Vayug ensures advertisers get guaranteed impressions, providing clear ROI visibility.',
                Icons.visibility,
                Colors.blue.shade600,
              ),
              const SizedBox(height: 16),
              _buildBenefitItem(
                'Creator-First Model (80% Revenue Share)',
                'Creators receive 80% of ad revenue, leading to higher motivation and engagement. This results in more authentic content, ensuring advertisers\' ads are placed in highly engaging and trusted environments.',
                Icons.people,
                Colors.green.shade600,
              ),
              const SizedBox(height: 16),
              _buildBenefitItem(
                'High Engagement & Brand Recall',
                'Since creators are directly incentivized, they actively promote and integrate brand ads, leading to better click-through and conversion rates.',
                Icons.trending_up,
                Colors.orange.shade600,
              ),
              const SizedBox(height: 16),
              _buildBenefitItem(
                'Less Competition, More Attention',
                'Unlike crowded platforms (YouTube, Instagram, etc.), Vayug offers advertisers a space with lower competition for user attention, increasing ad visibility and impact.',
                Icons.psychology,
                Colors.purple.shade600,
              ),
              const SizedBox(height: 16),
              _buildBenefitItem(
                'Safe & Relevant Ad Placements',
                'Ads are displayed only on clean and safe content, ensuring brand safety and alignment with advertiser values.',
                Icons.security,
                Colors.teal.shade600,
              ),
              const SizedBox(height: 16),
              _buildBenefitItem(
                'Focused User Experience',
                'With a clutter-free interface and fewer distractions, ads receive greater user focus compared to traditional platforms overloaded with content.',
                Icons.center_focus_strong,
                Colors.indigo.shade600,
              ),
              const SizedBox(height: 16),
              _buildBenefitItem(
                'Emerging Market Advantage',
                'Early advertisers on Vayug benefit from first-mover advantage, capturing audience attention before the platform scales massively.',
                Icons.rocket_launch,
                Colors.red.shade600,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it!'),
          ),
        ],
      ),
    );
  }

  static Widget _buildBenefitItem(
      String title, String description, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static void _showSuccessSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  static void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }
}
