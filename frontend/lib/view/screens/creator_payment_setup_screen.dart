import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:snehayog/config/app_config.dart';
import 'package:snehayog/services/authservices.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class CreatorPaymentSetupScreen extends StatefulWidget {
  const CreatorPaymentSetupScreen({Key? key}) : super(key: key);

  @override
  State<CreatorPaymentSetupScreen> createState() =>
      _CreatorPaymentSetupScreenState();
}

class _CreatorPaymentSetupScreenState extends State<CreatorPaymentSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String _selectedCountry = 'IN';
  String _selectedCurrency = 'INR';
  String _selectedPaymentMethod = 'upi';

  // Form controllers
  final _upiIdController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final _ifscCodeController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _accountHolderNameController = TextEditingController();
  final _paypalEmailController = TextEditingController();
  final _stripeAccountIdController = TextEditingController();
  final _wiseEmailController = TextEditingController();
  final _swiftCodeController = TextEditingController();
  final _routingNumberController = TextEditingController();
  final _panNumberController = TextEditingController();
  final _gstNumberController = TextEditingController();
  // **NEW: Card payment controllers**
  final _cardNumberController = TextEditingController();
  final _cardExpiryController = TextEditingController();
  final _cardCvvController = TextEditingController();
  final _cardholderNameController = TextEditingController();

  // Auth service
  final AuthService _authService = AuthService();

  // Country and payment method mappings
  final Map<String, List<String>> _countryPaymentMethods = {
    'IN': ['upi', 'bank_transfer', 'card_payment'],
    'US': ['paypal', 'stripe', 'bank_wire', 'card_payment'],
    'CA': ['paypal', 'stripe', 'bank_wire', 'card_payment'],
    'GB': ['paypal', 'stripe', 'wise', 'bank_wire', 'card_payment'],
    'DE': ['paypal', 'stripe', 'wise', 'bank_wire', 'card_payment'],
    'AU': ['paypal', 'stripe', 'bank_wire', 'card_payment'],
    'default': ['paypal', 'stripe', 'wise', 'payoneer', 'card_payment']
  };

  final Map<String, String> _countryNames = {
    'IN': 'India',
    'US': 'United States',
    'CA': 'Canada',
    'GB': 'United Kingdom',
    'DE': 'Germany',
    'AU': 'Australia'
  };

  final Map<String, String> _currencySymbols = {
    'INR': '₹',
    'USD': '\$',
    'EUR': '€',
    'GBP': '£',
    'CAD': 'C\$',
    'AUD': 'A\$'
  };

  @override
  void initState() {
    super.initState();
    _loadCachedPaymentProfile();
    _loadExistingProfile();
  }

  /// **FIX: Load cached payment profile with user-specific cache key**
  Future<void> _loadCachedPaymentProfile() async {
    try {
      final userData = await _authService.getUserData();
      final userId = userData?['googleId'] ?? userData?['id'];

      if (userId == null) {
        print('⚠️ No user ID available for cache lookup');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      // **FIX: Use user-specific cache key**
      final cacheKey = 'payment_profile_cache_$userId';
      final cachedJson = prefs.getString(cacheKey);

      if (cachedJson == null) {
        print('ℹ️ No cached payment profile found for user: $userId');
        return;
      }

      print('✅ Loading cached payment profile for user: $userId');
      final data = json.decode(cachedJson) as Map<String, dynamic>;

      setState(() {
        _selectedCountry = data['country'] ?? _selectedCountry;
        _selectedCurrency = data['currency'] ?? _selectedCurrency;
        _selectedPaymentMethod =
            data['paymentMethod'] ?? _selectedPaymentMethod;

        final payment = data['paymentDetails'] as Map<String, dynamic>?;
        if (payment != null) {
          _upiIdController.text = payment['upiId'] ?? '';
          _accountNumberController.text =
              payment['bankAccount']?['accountNumber'] ?? '';
          _ifscCodeController.text = payment['bankAccount']?['ifscCode'] ?? '';
          _bankNameController.text = payment['bankAccount']?['bankName'] ?? '';
          _accountHolderNameController.text =
              payment['bankAccount']?['accountHolderName'] ?? '';
          _paypalEmailController.text = payment['paypalEmail'] ?? '';
          _stripeAccountIdController.text = payment['stripeAccountId'] ?? '';
          _wiseEmailController.text = payment['wiseEmail'] ?? '';
          _swiftCodeController.text =
              payment['internationalBank']?['swiftCode'] ?? '';
          _routingNumberController.text =
              payment['internationalBank']?['routingNumber'] ?? '';
        }

        final tax = data['taxInfo'] as Map<String, dynamic>?;
        if (tax != null) {
          _panNumberController.text = tax['panNumber'] ?? '';
          _gstNumberController.text = tax['gstNumber'] ?? '';
        }
      });

      print('✅ Payment profile loaded from cache successfully');
    } catch (e) {
      print('❌ Error loading cached payment profile: $e');
    }
  }

  Future<void> _loadExistingProfile() async {
    try {
      final userData = await _authService.getUserData();
      final token = userData?['token'];

      if (token == null) return;

      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/creator-payouts/profile'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _selectedCountry = data['creator']['country'] ?? 'IN';
          _selectedCurrency = data['creator']['currency'] ?? 'INR';
          _selectedPaymentMethod =
              data['creator']['preferredPaymentMethod'] ?? 'upi';

          // Load existing payment details if available
          if (data['paymentDetails'] != null) {
            _upiIdController.text = data['paymentDetails']['upiId'] ?? '';
            _accountNumberController.text =
                data['paymentDetails']['bankAccount']?['accountNumber'] ?? '';
            _ifscCodeController.text =
                data['paymentDetails']['bankAccount']?['ifscCode'] ?? '';
            _bankNameController.text =
                data['paymentDetails']['bankAccount']?['bankName'] ?? '';
            _accountHolderNameController.text = data['paymentDetails']
                    ['bankAccount']?['accountHolderName'] ??
                '';
            _paypalEmailController.text =
                data['paymentDetails']['paypalEmail'] ?? '';
            _stripeAccountIdController.text =
                data['paymentDetails']['stripeAccountId'] ?? '';
            _wiseEmailController.text =
                data['paymentDetails']['wiseEmail'] ?? '';
            _swiftCodeController.text =
                data['paymentDetails']['internationalBank']?['swiftCode'] ?? '';
            _routingNumberController.text = data['paymentDetails']
                    ['internationalBank']?['routingNumber'] ??
                '';
            _panNumberController.text = data['taxInfo']?['panNumber'] ?? '';
            _gstNumberController.text = data['taxInfo']?['gstNumber'] ?? '';
          }
        });

        // **FIX: Cache for instant prefill next time with user-specific key**
        try {
          final prefs = await SharedPreferences.getInstance();
          final userData = await _authService.getUserData();
          final userId = userData?['googleId'] ?? userData?['id'];

          if (userId != null) {
            // **FIX: Use user-specific cache key**
            final cacheKey = 'payment_profile_cache_$userId';
            await prefs.setString(
                cacheKey,
                json.encode({
                  'country': _selectedCountry,
                  'currency': _selectedCurrency,
                  'paymentMethod': _selectedPaymentMethod,
                  'paymentDetails': data['paymentDetails'] ?? {},
                  'taxInfo': data['taxInfo'] ?? {},
                }));
            // **FIX: Also set user-specific flag**
            await prefs.setBool('has_payment_setup_$userId', true);
            // Keep global flag for backward compatibility
            await prefs.setBool('has_payment_setup', true);
            print('✅ Payment profile cached for user: $userId');
          }
        } catch (e) {
          print('❌ Error caching payment profile: $e');
        }
      }
    } catch (e) {
      print('Error loading profile: $e');
    }
  }

  Future<void> _savePaymentProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      print('🔍 Starting to save payment profile...');

      final userData = await _authService.getUserData();
      final token = userData?['token'];

      print(
          '🔍 User data retrieved: ${userData != null ? 'Success' : 'Failed'}');
      print('🔍 Token available: ${token != null ? 'Yes' : 'No'}');
      if (token != null) {
        print('🔍 Token type: ${token.substring(0, 20)}...');
      }

      if (token == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please login first')),
        );
        return;
      }

      // Prepare payment details based on selected method
      Map<String, dynamic> paymentDetails = {};

      switch (_selectedPaymentMethod) {
        case 'upi':
          paymentDetails['upiId'] = _upiIdController.text.trim();
          break;

        case 'bank_transfer':
          paymentDetails['bankAccount'] = {
            'accountNumber': _accountNumberController.text.trim(),
            'ifscCode': _ifscCodeController.text.trim(),
            'bankName': _bankNameController.text.trim(),
            'accountHolderName': _accountHolderNameController.text.trim(),
          };
          break;

        case 'card_payment':
          paymentDetails['cardDetails'] = {
            'cardNumber': _cardNumberController.text.trim(),
            'expiryDate': _cardExpiryController.text.trim(),
            'cvv': _cardCvvController.text.trim(),
            'cardholderName': _cardholderNameController.text.trim(),
          };
          break;

        case 'paypal':
          paymentDetails['paypalEmail'] = _paypalEmailController.text.trim();
          break;

        case 'stripe':
          paymentDetails['stripeAccountId'] =
              _stripeAccountIdController.text.trim();
          break;

        case 'wise':
          paymentDetails['wiseEmail'] = _wiseEmailController.text.trim();
          break;

        case 'bank_wire':
          paymentDetails['internationalBank'] = {
            'accountNumber': _accountNumberController.text.trim(),
            'swiftCode': _swiftCodeController.text.trim(),
            'routingNumber': _routingNumberController.text.trim(),
            'bankName': _bankNameController.text.trim(),
            'accountHolderName': _accountHolderNameController.text.trim(),
          };
          break;
      }

      final requestBody = {
        'paymentMethod': _selectedPaymentMethod,
        'paymentDetails': paymentDetails,
        'currency': _selectedCurrency,
        'country': _selectedCountry,
        'taxInfo': {
          'panNumber': _panNumberController.text.trim(),
          'gstNumber': _gstNumberController.text.trim(),
        }
      };

      print('🔍 Request body prepared: $requestBody');
      print(
          '🔍 API endpoint: ${AppConfig.baseUrl}/api/creator-payouts/payment-method');
      print('🔍 Headers: Authorization: Bearer ${token.substring(0, 20)}...');

      final response = await http.put(
        Uri.parse('${AppConfig.baseUrl}/api/creator-payouts/payment-method'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode(requestBody),
      );

      print('🔍 Response status code: ${response.statusCode}');
      print('🔍 Response body: ${response.body}');

      if (response.statusCode == 200) {
        print('✅ Payment profile saved successfully!');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Payment profile saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        // **FIX: Persist user-specific payment setup flag and cache**
        final prefs = await SharedPreferences.getInstance();
        final userId = userData?['googleId'] ?? userData?['id'];

        if (userId != null) {
          // **FIX: Set user-specific flag**
          await prefs.setBool('has_payment_setup_$userId', true);
          // Keep global flag for backward compatibility
          await prefs.setBool('has_payment_setup', true);

          // **FIX: Cache sanitized profile with user-specific key (never store CVV)**
          final sanitized = {
            'country': _selectedCountry,
            'currency': _selectedCurrency,
            'paymentMethod': _selectedPaymentMethod,
            'paymentDetails': {
              ...paymentDetails,
              if (paymentDetails['cardDetails'] != null)
                'cardDetails': {
                  ...paymentDetails['cardDetails'],
                  'cvv': null, // Never store CVV locally
                }
            },
            'taxInfo': {
              'panNumber': _panNumberController.text.trim(),
              'gstNumber': _gstNumberController.text.trim(),
            }
          };

          final cacheKey = 'payment_profile_cache_$userId';
          await prefs.setString(cacheKey, json.encode(sanitized));
          print('✅ Payment profile cached for user: $userId');
        }

        // Show success dialog
        _showSuccessDialog();
      } else {
        final errorBody = json.decode(response.body);
        final error = errorBody['error'] ?? 'Failed to save profile';
        print('❌ Payment profile save failed: $error');
        print('❌ Full error response: $errorBody');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('❌ Exception during payment profile save: $e');
      print('❌ Exception type: ${e.runtimeType}');
      if (e.toString().contains('SocketException')) {
        print('❌ Network error - backend might be unreachable');
      }
      if (e.toString().contains('timeout')) {
        print('❌ Request timeout - backend might be slow');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSuccessDialog() {
    final currencySymbol = _currencySymbols[_selectedCurrency] ?? '₹';
    final thresholdAmount = _selectedCurrency == 'INR'
        ? '200'
        : (_selectedCurrency == 'USD' ||
                _selectedCurrency == 'EUR' ||
                _selectedCurrency == 'GBP')
            ? '5'
            : '7';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('🎉 Payment Profile Setup Complete!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Your payment profile has been saved successfully.'),
            const SizedBox(height: 16),
            const Text('💰 What happens next:'),
            const Text('• You\'ll receive 80% of ad revenue automatically'),
            const Text('• First payout: No minimum amount'),
            Text(
                '• Subsequent payouts: $currencySymbol$thresholdAmount minimum'),
            const Text('• Money transferred on 1st of every month'),
            const SizedBox(height: 16),
            const Text(
                '🔄 You can update these details anytime from your profile.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              // Set flag that payment setup is complete
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('has_payment_setup', true);

              Navigator.of(context).pop();
              Navigator.of(context).pop(); // Go back to previous screen
            },
            child: const Text('Got it!'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          Colors.grey[100], // Changed from AppTheme.backgroundColor
      appBar: AppBar(
        title: const Text('💰 Payment Profile Setup'),
        backgroundColor: Colors.grey[700], // Changed from Colors.blue
        foregroundColor: Colors.white, // Changed from AppTheme.white
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Info
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors
                      .grey[200], // Changed from Colors.blue.withOpacity(0.1)
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: Colors.grey[
                          400]!), // Changed from Colors.blue.withOpacity(0.3)
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline,
                            color:
                                Colors.grey[700]), // Changed from Colors.blue
                        const SizedBox(width: 8),
                        Text(
                          'Setup Once, Get Paid Monthly!',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[700], // Changed from Colors.blue
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Enter your payment details once, and we\'ll automatically transfer 80% of your ad revenue every month on the 1st.',
                      style: TextStyle(
                          color: Colors.grey[700]), // Changed from Colors.blue
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Country Selection
              Text(
                '🌍 Select Your Country',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors
                        .grey[800]), // Changed from AppTheme.subheadingStyle
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _selectedCountry,
                decoration: const InputDecoration(
                  labelText: 'Country',
                  border: OutlineInputBorder(),
                ),
                items: _countryNames.entries.map((entry) {
                  return DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedCountry = value!;
                    // Reset payment method to first available for selected country
                    _selectedPaymentMethod =
                        _countryPaymentMethods[value]?.first ?? 'paypal';
                  });
                },
                validator: (value) =>
                    value == null ? 'Please select a country' : null,
              ),

              const SizedBox(height: 16),

              // Currency Selection
              Text(
                '💱 Select Your Preferred Currency',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors
                        .grey[800]), // Changed from AppTheme.subheadingStyle
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _selectedCurrency,
                decoration: const InputDecoration(
                  labelText: 'Currency',
                  border: OutlineInputBorder(),
                ),
                items: _currencySymbols.entries.map((entry) {
                  return DropdownMenuItem(
                    value: entry.key,
                    child: Text('${entry.value} $entry.key'),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedCurrency = value!;
                  });
                },
                validator: (value) =>
                    value == null ? 'Please select a currency' : null,
              ),

              const SizedBox(height: 16),

              // Payment Method Selection
              Text(
                '💳 Select Payment Method',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors
                        .grey[800]), // Changed from AppTheme.subheadingStyle
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _selectedPaymentMethod,
                decoration: const InputDecoration(
                  labelText: 'Payment Method',
                  border: OutlineInputBorder(),
                ),
                items: (_countryPaymentMethods[_selectedCountry] ??
                        _countryPaymentMethods['default']!)
                    .map((method) {
                  return DropdownMenuItem(
                    value: method,
                    child: Text(_getPaymentMethodDisplayName(method)),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedPaymentMethod = value!;
                  });
                },
                validator: (value) =>
                    value == null ? 'Please select a payment method' : null,
              ),

              const SizedBox(height: 24),

              // Payment Details Form
              Text(
                '📝 Enter Payment Details',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors
                        .grey[800]), // Changed from AppTheme.subheadingStyle
              ),
              const SizedBox(height: 16),

              // Dynamic form fields based on payment method
              _buildPaymentMethodFields(),

              const SizedBox(height: 24),

              // Tax Information
              Text(
                '📋 Tax Information (Optional)',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors
                        .grey[800]), // Changed from AppTheme.subheadingStyle
              ),
              const SizedBox(height: 16),

              if (_selectedCountry == 'IN') ...[
                TextFormField(
                  controller: _panNumberController,
                  decoration: const InputDecoration(
                    labelText: 'PAN Number',
                    border: OutlineInputBorder(),
                    hintText: 'ABCDE1234F',
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _gstNumberController,
                  decoration: const InputDecoration(
                    labelText: 'GST Number (Optional)',
                    border: OutlineInputBorder(),
                    hintText: '22AAAAA0000A1Z5',
                  ),
                ),
              ],

              const SizedBox(height: 32),

              // Save Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _savePaymentProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        Colors.grey[700], // Changed from Colors.blue
                    foregroundColor:
                        Colors.white, // Changed from AppTheme.white
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          '💾 Save Payment Profile',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),

              const SizedBox(height: 24),

              // Info Box
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green[600]),
                        const SizedBox(width: 8),
                        Text(
                          'Automatic Monthly Payouts',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.green[800],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Once saved, your payment details will be used automatically every month. You\'ll receive 80% of your ad revenue on the 1st of every month.',
                      style: TextStyle(color: Colors.green[700], fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentMethodFields() {
    switch (_selectedPaymentMethod) {
      case 'upi':
        return TextFormField(
          controller: _upiIdController,
          decoration: const InputDecoration(
            labelText: 'UPI ID',
            border: OutlineInputBorder(),
            hintText: 'username@upi',
            prefixIcon: Icon(Icons.phone_android),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Please enter your UPI ID';
            }
            if (!value.contains('@')) {
              return 'Please enter a valid UPI ID (e.g., username@upi)';
            }
            return null;
          },
        );

      case 'bank_transfer':
        return Column(
          children: [
            TextFormField(
              controller: _accountNumberController,
              decoration: const InputDecoration(
                labelText: 'Account Number',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.account_balance),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter account number';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _ifscCodeController,
              decoration: const InputDecoration(
                labelText: 'IFSC Code',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.code),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter IFSC code';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _bankNameController,
              decoration: const InputDecoration(
                labelText: 'Bank Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.account_balance),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter bank name';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _accountHolderNameController,
              decoration: const InputDecoration(
                labelText: 'Account Holder Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter account holder name';
                }
                return null;
              },
            ),
          ],
        );

      case 'card_payment':
        return Column(
          children: [
            TextFormField(
              controller: _cardNumberController,
              decoration: const InputDecoration(
                labelText: 'Card Number',
                border: OutlineInputBorder(),
                hintText: '1234 5678 9012 3456',
                prefixIcon: Icon(Icons.credit_card),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(16),
                CardNumberFormatter(),
              ],
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter card number';
                }
                if (value.replaceAll(' ', '').length < 13 ||
                    value.replaceAll(' ', '').length > 19) {
                  return 'Please enter a valid card number';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _cardExpiryController,
                    decoration: const InputDecoration(
                      labelText: 'Expiry Date',
                      border: OutlineInputBorder(),
                      hintText: 'MM/YY',
                      prefixIcon: Icon(Icons.calendar_today),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                      ExpiryDateFormatter(),
                    ],
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter expiry date';
                      }
                      if (!RegExp(r'^\d{2}/\d{2}$').hasMatch(value)) {
                        return 'Please enter in MM/YY format';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _cardCvvController,
                    decoration: const InputDecoration(
                      labelText: 'CVV',
                      border: OutlineInputBorder(),
                      hintText: '123',
                      prefixIcon: Icon(Icons.security),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter CVV';
                      }
                      if (value.length < 3 || value.length > 4) {
                        return 'Please enter a valid CVV';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _cardholderNameController,
              decoration: const InputDecoration(
                labelText: 'Cardholder Name',
                border: OutlineInputBorder(),
                hintText: 'As printed on card',
                prefixIcon: Icon(Icons.person),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter cardholder name';
                }
                return null;
              },
            ),
          ],
        );

      case 'paypal':
        return TextFormField(
          controller: _paypalEmailController,
          decoration: const InputDecoration(
            labelText: 'PayPal Email',
            border: OutlineInputBorder(),
            hintText: 'your.email@example.com',
            prefixIcon: Icon(Icons.email),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Please enter your PayPal email';
            }
            if (!value.contains('@')) {
              return 'Please enter a valid email address';
            }
            return null;
          },
        );

      case 'stripe':
        return TextFormField(
          controller: _stripeAccountIdController,
          decoration: const InputDecoration(
            labelText: 'Stripe Account ID',
            border: OutlineInputBorder(),
            hintText: 'acct_1234567890',
            prefixIcon: Icon(Icons.account_circle),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Please enter your Stripe account ID';
            }
            return null;
          },
        );

      case 'wise':
        return TextFormField(
          controller: _wiseEmailController,
          decoration: const InputDecoration(
            labelText: 'Wise Email',
            border: OutlineInputBorder(),
            hintText: 'your.email@example.com',
            prefixIcon: Icon(Icons.email),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Please enter your Wise email';
            }
            if (!value.contains('@')) {
              return 'Please enter a valid email address';
            }
            return null;
          },
        );

      case 'bank_wire':
        return Column(
          children: [
            TextFormField(
              controller: _accountNumberController,
              decoration: const InputDecoration(
                labelText: 'Account Number',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.account_balance),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter account number';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _swiftCodeController,
              decoration: const InputDecoration(
                labelText: 'SWIFT Code',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.code),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter SWIFT code';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _routingNumberController,
              decoration: const InputDecoration(
                labelText: 'Routing Number',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.code),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter routing number';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _bankNameController,
              decoration: const InputDecoration(
                labelText: 'Bank Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.account_balance),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter bank name';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _accountHolderNameController,
              decoration: const InputDecoration(
                labelText: 'Account Holder Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter account holder name';
                }
                return null;
              },
            ),
          ],
        );

      default:
        return const Text('Please select a payment method');
    }
  }

  String _getPaymentMethodDisplayName(String method) {
    switch (method) {
      case 'upi':
        return 'UPI';
      case 'bank_transfer':
        return 'Bank Transfer';
      case 'card_payment':
        return 'Credit/Debit Card';
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

  @override
  void dispose() {
    _upiIdController.dispose();
    _accountNumberController.dispose();
    _ifscCodeController.dispose();
    _bankNameController.dispose();
    _accountHolderNameController.dispose();
    _paypalEmailController.dispose();
    _stripeAccountIdController.dispose();
    _wiseEmailController.dispose();
    _swiftCodeController.dispose();
    _routingNumberController.dispose();
    _panNumberController.dispose();
    _gstNumberController.dispose();
    _cardNumberController.dispose();
    _cardExpiryController.dispose();
    _cardCvvController.dispose();
    _cardholderNameController.dispose();
    super.dispose();
  }
}

class CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;

    if (text.length < oldValue.text.length) {
      return newValue;
    }

    final newText = StringBuffer();

    for (int i = 0; i < text.length; i++) {
      if (i > 0 && i % 4 == 0) {
        newText.write(' ');
      }
      newText.write(text[i]);
    }

    return TextEditingValue(
      text: newText.toString(),
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}

class ExpiryDateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;

    if (text.length < oldValue.text.length) {
      return newValue;
    }

    final newText = StringBuffer();

    for (int i = 0; i < text.length; i++) {
      if (i == 2 && text.length > 2) {
        newText.write('/');
      }
      newText.write(text[i]);
    }

    return TextEditingValue(
      text: newText.toString(),
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}
