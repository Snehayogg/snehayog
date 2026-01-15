import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class RazorpayService {
  String? _keyId;
  String? _baseUrl;

  void initialize({
    required String keyId,
    required String keySecret,
    required String webhookSecret,
    required String baseUrl,
  }) {
    _keyId = keyId;
    _baseUrl = baseUrl;
  }

  Future<void> makePayment({
    required double amount,
    required String currency,
    required String name,
    required String description,
    required String email,
    required String contact,
    required String userName,
    required Function(Map<String, dynamic>) onSuccess,
    required Function(String) onError,
  }) async {
    try {
      // **NEW: Validate base URL**
      if (_baseUrl == null || _baseUrl!.isEmpty) {
        throw Exception(
          'Payment service not properly configured. Base URL is missing.',
        );
      }



      // Create order on backend first
      final orderResponse = await http
          .post(
            Uri.parse('$_baseUrl/api/billing/create-order'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'amount': amount, // Send amount in rupees (not paise)
              'currency': currency,
              'receipt': 'receipt_${DateTime.now().millisecondsSinceEpoch}',
              'notes': {
                'name': name,
                'description': description,
                'email': email,
                'contact': contact,
                'userName': userName,
              },
            }),
          )
          .timeout(const Duration(seconds: 30));



      if (orderResponse.statusCode != 200) {
        final errorBody = json.decode(orderResponse.body);
        throw Exception(
          'Failed to create order: ${errorBody['error'] ?? orderResponse.statusCode}',
        );
      }

      final orderData = json.decode(orderResponse.body);
      final orderId = orderData['order']['id'];



      // **FIXED: Create proper Razorpay payment URL with test mode**
      final paymentUrl = _createRazorpayPaymentUrl(
        orderId: orderId,
        amount: amount,
        currency: currency,
        name: name,
        description: description,
        email: email,
        contact: contact,
        userName: userName,
      );



      // **NEW: Validate URL format**
      try {
        final uri = Uri.parse(paymentUrl);


        // **NEW: Validate that it's a proper Razorpay URL**
        if (uri.host != 'checkout.razorpay.com') {
          throw Exception('Invalid Razorpay host: ${uri.host}');
        }

        if (!uri.path.contains('checkout.html')) {
          throw Exception('Invalid Razorpay path: ${uri.path}');
        }



        // **NEW: Debug URL parameters**

      } catch (e) {

        throw Exception('Invalid payment URL format: $e');
      }

      // **NEW: Test if URL can be launched before attempting to launch**
      final canLaunch = await canLaunchUrl(Uri.parse(paymentUrl));


      if (!canLaunch) {

        // Try launching with different mode
        final launchedAlternative = await launchUrl(
          Uri.parse(paymentUrl),
          mode: LaunchMode.platformDefault,
        );

        if (!launchedAlternative) {
          throw Exception(
            'Cannot launch payment URL. Please check your internet connection.',
          );
        }


        return;
      }

      // **FIXED: Launch payment URL with proper error handling**

      final launched = await launchUrl(
        Uri.parse(paymentUrl),
        mode: LaunchMode.externalApplication,
      );



      if (!launched) {


        // Try with platform default mode as fallback
        final launchedFallback = await launchUrl(
          Uri.parse(paymentUrl),
          mode: LaunchMode.platformDefault,
        );

        if (!launchedFallback) {
          throw Exception('Failed to launch payment page. Please try again.');
        }


        return;
      }


    } catch (e) {

      onError('Error making payment: $e');
    }
  }

  // **REMOVED: UPI payment method - Razorpay checkout handles UPI natively**

  // **REMOVED: UPI Intent URL creation - not needed since Razorpay handles UPI**

  // **REMOVED: UPI apps detection - not needed since Razorpay handles UPI**

  String _createRazorpayPaymentUrl({
    required String orderId,
    required double amount,
    required String currency,
    required String name,
    required String description,
    required String email,
    required String contact,
    required String userName,
  }) {
    // **FIXED: Create proper Razorpay checkout URL with all required parameters**
    final params = {
      'key': _keyId ?? '',
      'amount': (amount * 100).round().toString(), // Convert to paise
      'currency': currency,
      'name': name,
      'description': description,
      'order_id': orderId,
      'prefill[contact]': contact,
      'prefill[email]': email,
      'prefill[name]': userName,
      'callback_url': 'http://192.168.0.190:5001/api/billing/payment-success',
      'cancel_url': 'http://192.168.0.190:5001/api/billing/payment-cancelled',
      // **REMOVED: Test mode parameters - not needed in production**
      // **NEW: Add theme and styling**
      'theme[color]': '#3B82F6',
      'theme[hide_topbar]': 'false',
      // **NEW: Add payment method preferences**
      'method': 'card,netbanking,wallet,upi',
      'prefill[method]': 'card',
    };

    // **FIXED: Build query string with proper encoding**
    final queryParams = <String>[];
    params.forEach((key, value) {
      if (value.isNotEmpty) {
        queryParams.add(
          '${Uri.encodeComponent(key)}=${Uri.encodeComponent(value)}',
        );
      }
    });

    final queryString = queryParams.join('&');

    // **FIXED: Use the correct Razorpay checkout URL**
    final paymentUrl =
        'https://checkout.razorpay.com/v1/checkout.html?$queryString';



    // **NEW: Validate URL length (Razorpay has limits)**
    if (paymentUrl.length > 2000) {

      // Create simplified URL with essential parameters only
      final simplifiedParams = {
        'key': _keyId ?? '',
        'amount': (amount * 100).round().toString(),
        'currency': currency,
        'name': name,
        'description': description,
        'order_id': orderId,
        'prefill[email]': email,
        'prefill[contact]': contact,
      };

      final simplifiedQueryParams = <String>[];
      simplifiedParams.forEach((key, value) {
        if (value.isNotEmpty) {
          simplifiedQueryParams.add(
            '${Uri.encodeComponent(key)}=${Uri.encodeComponent(value)}',
          );
        }
      });

      final simplifiedQueryString = simplifiedQueryParams.join('&');
      final simplifiedUrl =
          'https://checkout.razorpay.com/v1/checkout.html?$simplifiedQueryString';


      return simplifiedUrl;
    }

    return paymentUrl;
  }

  Future<Map<String, dynamic>> verifyPaymentWithBackend({
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/billing/verify-payment'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'razorpay_order_id': orderId,
          'razorpay_payment_id': paymentId,
          'razorpay_signature': signature,
        }),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Payment verification failed: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Payment verification error: $e');
    }
  }

  Map<String, double> calculateRevenueSplit(double amount) {
    // Calculate revenue split between platform and creator
    // Platform takes 20%, creator gets 80%
    const double platformShare = 0.20;
    const double creatorShare = 0.80;

    return {
      'platform': amount * platformShare,
      'creator': amount * creatorShare,
      'total': amount,
    };
  }

  Future<Map<String, dynamic>> getPaymentDetails(String paymentId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/billing/payment/$paymentId'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception(
          'Failed to get payment details: ${response.statusCode}',
        );
      }
    } catch (e) {
      throw Exception('Error getting payment details: $e');
    }
  }

  // **REMOVED: Test payment method - not needed in production**

  void dispose() {
    // No cleanup needed for web-based implementation
  }
}
