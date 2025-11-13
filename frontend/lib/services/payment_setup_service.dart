import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayu/config/app_config.dart';
import 'package:vayu/services/authservices.dart';

/// Service to manage payment setup status and prevent multiple setups
class PaymentSetupService {
  static const String _paymentSetupKey = 'has_payment_setup';
  static const String _paymentProfileKey = 'payment_profile_cache';

  final AuthService _authService = AuthService();

  /// Check if user has completed payment setup
  Future<bool> hasCompletedPaymentSetup() async {
    try {
      // First check local cache for quick response
      final prefs = await SharedPreferences.getInstance();
      final userData = await _authService.getUserData();
      final userId = userData?['googleId'] ?? userData?['id'];

      if (userId == null) return false;

      // Check user-specific flag
      final userSpecificFlag =
          prefs.getBool('${_paymentSetupKey}_$userId') ?? false;
      if (userSpecificFlag) {
        print('✅ Payment setup completed (cached): $userId');
        return true;
      }

      // Check global flag for backward compatibility
      final globalFlag = prefs.getBool(_paymentSetupKey) ?? false;
      if (globalFlag) {
        print('✅ Payment setup completed (global): $userId');
        return true;
      }

      // If no local flag, check with backend
      final backendStatus = await _checkBackendPaymentStatus();
      if (backendStatus) {
        // Cache the result
        await prefs.setBool('${_paymentSetupKey}_$userId', true);
        await prefs.setBool(_paymentSetupKey, true);
        print('✅ Payment setup completed (backend): $userId');
        return true;
      }

      print('❌ Payment setup not completed: $userId');
      return false;
    } catch (e) {
      print('❌ Error checking payment setup status: $e');
      return false;
    }
  }

  /// Check payment status from backend
  Future<bool> _checkBackendPaymentStatus() async {
    try {
      final userData = await _authService.getUserData();
      final token = userData?['token'];

      if (token == null) return false;

      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/creator-payouts/profile'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final paymentDetails = data['paymentDetails'];

        // Check if payment details exist and are complete
        if (paymentDetails != null) {
          final hasPaymentMethod =
              data['creator']?['preferredPaymentMethod'] != null;
          final hasPaymentDetails = _hasValidPaymentDetails(paymentDetails);

          return hasPaymentMethod && hasPaymentDetails;
        }
      }

      return false;
    } catch (e) {
      print('❌ Error checking backend payment status: $e');
      return false;
    }
  }

  /// Check if payment details are valid
  bool _hasValidPaymentDetails(Map<String, dynamic> paymentDetails) {
    // Check for UPI
    if (paymentDetails['upiId'] != null &&
        paymentDetails['upiId'].toString().isNotEmpty) {
      return true;
    }

    // Check for bank account
    if (paymentDetails['bankAccount'] != null) {
      final bankAccount = paymentDetails['bankAccount'];
      if (bankAccount['accountNumber'] != null &&
          bankAccount['accountNumber'].toString().isNotEmpty &&
          bankAccount['ifscCode'] != null &&
          bankAccount['ifscCode'].toString().isNotEmpty) {
        return true;
      }
    }

    // Check for card details
    if (paymentDetails['cardDetails'] != null) {
      final cardDetails = paymentDetails['cardDetails'];
      if (cardDetails['cardNumber'] != null &&
          cardDetails['cardNumber'].toString().isNotEmpty) {
        return true;
      }
    }

    // Check for PayPal
    if (paymentDetails['paypalEmail'] != null &&
        paymentDetails['paypalEmail'].toString().isNotEmpty) {
      return true;
    }

    // Check for Stripe
    if (paymentDetails['stripeAccountId'] != null &&
        paymentDetails['stripeAccountId'].toString().isNotEmpty) {
      return true;
    }

    // Check for Wise
    if (paymentDetails['wiseEmail'] != null &&
        paymentDetails['wiseEmail'].toString().isNotEmpty) {
      return true;
    }

    // Check for international bank
    if (paymentDetails['internationalBank'] != null) {
      final intlBank = paymentDetails['internationalBank'];
      if (intlBank['accountNumber'] != null &&
          intlBank['accountNumber'].toString().isNotEmpty) {
        return true;
      }
    }

    return false;
  }

  /// Mark payment setup as completed
  Future<void> markPaymentSetupCompleted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userData = await _authService.getUserData();
      final userId = userData?['googleId'] ?? userData?['id'];

      if (userId != null) {
        await prefs.setBool('${_paymentSetupKey}_$userId', true);
        await prefs.setBool(_paymentSetupKey, true);
        print('✅ Payment setup marked as completed: $userId');
      }
    } catch (e) {
      print('❌ Error marking payment setup as completed: $e');
    }
  }

  /// Clear payment setup status (for testing or reset)
  Future<void> clearPaymentSetupStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userData = await _authService.getUserData();
      final userId = userData?['googleId'] ?? userData?['id'];

      if (userId != null) {
        await prefs.remove('${_paymentSetupKey}_$userId');
        await prefs.remove(_paymentSetupKey);
        await prefs.remove('${_paymentProfileKey}_$userId');
        print('✅ Payment setup status cleared: $userId');
      }
    } catch (e) {
      print('❌ Error clearing payment setup status: $e');
    }
  }

  /// Get payment setup status with details
  Future<Map<String, dynamic>> getPaymentSetupStatus() async {
    try {
      final hasSetup = await hasCompletedPaymentSetup();
      final userData = await _authService.getUserData();
      final userId = userData?['googleId'] ?? userData?['id'];

      return {
        'hasCompletedSetup': hasSetup,
        'userId': userId,
        'needsSetup': !hasSetup,
        'lastChecked': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      print('❌ Error getting payment setup status: $e');
      return {
        'hasCompletedSetup': false,
        'userId': null,
        'needsSetup': true,
        'error': e.toString(),
      };
    }
  }

  Future<Map<String, dynamic>?> fetchPaymentProfile() async {
    try {
      final userData = await _authService.getUserData();
      final token = userData?['token'];
      if (token == null) return null;

      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/creator-payouts/profile'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map<String, dynamic>) {
          final prefs = await SharedPreferences.getInstance();
          final userId = userData?['googleId'] ?? userData?['id'];
          if (userId != null) {
            await prefs.setString(
              '${_paymentProfileKey}_$userId',
              json.encode(data),
            );
          }
          return data;
        }
      }

      return null;
    } catch (e) {
      print('❌ Error fetching payment profile: $e');
      return null;
    }
  }

  Future<void> updateUpiId(String upiId) async {
    final userData = await _authService.getUserData();
    final token = userData?['token'];
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final response = await http.put(
      Uri.parse('${AppConfig.baseUrl}/api/creator-payouts/payment-method/upi'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode({'upiId': upiId}),
    );

    if (response.statusCode != 200) {
      final message =
          response.body.isNotEmpty ? response.body : 'Unknown error';
      throw Exception('Failed to update UPI ID: $message');
    }
  }
}
