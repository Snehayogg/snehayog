import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:snehayog/config/app_config.dart';
import 'package:snehayog/services/authservices.dart';

class RazorpayService {
  static final RazorpayService _instance = RazorpayService._internal();
  factory RazorpayService() => _instance;
  RazorpayService._internal();

  static String get keyId => AppConfig.razorpayKeyId;
  static String get keySecret => AppConfig.razorpayKeySecret;
  static String get webhookSecret => AppConfig.razorpayWebhookSecret;

  final AuthService _authService = AuthService();

  /// Create a new order for ad payment
  Future<Map<String, dynamic>> createOrder({
    required double amount,
    required String currency,
    required String receipt,
    String? notes,
  }) async {
    try {
      final userData = await _authService.getUserData();
      if (userData == null) {
        throw Exception('User not authenticated');
      }

      final response = await http.post(
        Uri.parse('https://api.razorpay.com/v1/orders'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization':
              'Basic ${base64Encode(utf8.encode('$keyId:$keySecret'))}',
        },
        body: json.encode({
          'amount': (amount * 100).round(), // Convert to paise
          'currency': currency,
          'receipt': receipt,
          'notes': {
            'user_id': userData['id'],
            'user_name': userData['name'],
            'purpose': 'advertisement_payment',
            if (notes != null) 'description': notes,
          },
        }),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to create order: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error creating Razorpay order: $e');
    }
  }

  /// Capture payment after successful payment
  Future<Map<String, dynamic>> capturePayment({
    required String paymentId,
    required double amount,
    required String currency,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('https://api.razorpay.com/v1/payments/$paymentId/capture'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization':
              'Basic ${base64Encode(utf8.encode('$keyId:$keySecret'))}',
        },
        body: json.encode({
          'amount': (amount * 100).round(), // Convert to paise
          'currency': currency,
        }),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to capture payment: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error capturing payment: $e');
    }
  }

  /// Verify webhook signature
  bool verifyWebhookSignature({
    required String payload,
    required String signature,
  }) {
    try {
      final expectedSignature = Hmac(sha256, utf8.encode(webhookSecret))
          .convert(utf8.encode(payload))
          .toString();

      return expectedSignature == signature;
    } catch (e) {
      return false;
    }
  }

  /// **NEW: Calculate revenue split for creators**
  Map<String, double> calculateRevenueSplit(double adSpend) {
    return {
      'creator': adSpend * 0.80, // 80% to creator
      'platform': adSpend * 0.20, // 20% to platform
    };
  }

  /// **NEW: Process payment callback from Razorpay**
  Future<Map<String, dynamic>> processPaymentCallback({
    required String paymentId,
    required String orderId,
    required String signature,
  }) async {
    try {
      // Verify the payment with Razorpay
      final paymentDetails = await getPaymentDetails(paymentId);

      if (paymentDetails['status'] == 'captured') {
        return {
          'success': true,
          'paymentId': paymentId,
          'orderId': orderId,
          'amount': paymentDetails['amount'] / 100, // Convert from paise
          'currency': paymentDetails['currency'],
          'status': 'success'
        };
      } else {
        throw Exception('Payment not completed: ${paymentDetails['status']}');
      }
    } catch (e) {
      throw Exception('Error processing payment callback: $e');
    }
  }

  /// **NEW: Get payment details from Razorpay**
  Future<Map<String, dynamic>> getPaymentDetails(String paymentId) async {
    try {
      final response = await http.get(
        Uri.parse('https://api.razorpay.com/v1/payments/$paymentId'),
        headers: {
          'Authorization':
              'Basic ${base64Encode(utf8.encode('$keyId:$keySecret'))}',
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to get payment details: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error getting payment details: $e');
    }
  }

  /// Refund payment
  Future<Map<String, dynamic>> refundPayment({
    required String paymentId,
    required double amount,
    String? notes,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('https://api.razorpay.com/v1/payments/$paymentId/refund'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization':
              'Basic ${base64Encode(utf8.encode('$keyId:$keySecret'))}',
        },
        body: json.encode({
          'amount': (amount * 100).round(), // Convert to paise
          if (notes != null) 'notes': notes,
        }),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to refund payment: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error refunding payment: $e');
    }
  }

  /// Get supported payment methods
  List<String> getSupportedPaymentMethods() {
    return AppConfig.supportedPaymentMethods;
  }

  /// Format amount for display (convert from paise to rupees)
  String formatAmount(int amountInPaise) {
    final amount = amountInPaise / 100;
    return '₹${amount.toStringAsFixed(2)}';
  }

  /// Parse amount from rupees to paise
  int parseAmount(String amountInRupees) {
    final amount = double.tryParse(amountInRupees.replaceAll('₹', '')) ?? 0.0;
    return (amount * 100).round();
  }
}
