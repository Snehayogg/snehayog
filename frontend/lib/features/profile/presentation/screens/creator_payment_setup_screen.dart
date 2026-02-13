import 'package:flutter/material.dart';
import 'package:vayu/shared/config/app_config.dart';
import 'package:vayu/features/auth/data/services/authservices.dart';
import 'package:vayu/features/profile/data/services/payment_setup_service.dart';
import 'dart:convert';
import 'package:vayu/shared/services/http_client_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayu/shared/utils/app_logger.dart';

class CreatorPaymentSetupScreen extends StatefulWidget {
  const CreatorPaymentSetupScreen({Key? key}) : super(key: key);

  @override
  State<CreatorPaymentSetupScreen> createState() =>
      _CreatorPaymentSetupScreenState();
}

class _CreatorPaymentSetupScreenState extends State<CreatorPaymentSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isEditMode = false;
  bool _hasExistingProfile = false;
  bool _isInitializing = true;
  bool _isRefreshing = false;
  String _selectedCountry = 'IN';
  String _selectedCurrency = 'INR';
  String _selectedPaymentMethod = 'upi';

  // Form controllers
  final _upiIdController = TextEditingController();
  final _paypalEmailController = TextEditingController();
  final _stripeAccountIdController = TextEditingController();
  final _wiseEmailController = TextEditingController();
  final _panNumberController = TextEditingController();
  final _gstNumberController = TextEditingController();
  bool _showOptionalTaxInfo = false;

  // Auth service
  final AuthService _authService = AuthService();

  // Country and payment method mappings
  final Map<String, List<String>> _countryPaymentMethods = {
    'IN': ['upi'],
    'US': ['paypal', 'stripe'],
    'CA': ['paypal', 'stripe'],
    'GB': ['paypal', 'stripe', 'wise'],
    'DE': ['paypal', 'stripe', 'wise'],
    'AU': ['paypal', 'stripe'],
    'default': ['paypal', 'stripe', 'wise', 'payoneer']
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

  void _normalizeSelectedPaymentMethod() {
    final methods = _countryPaymentMethods[_selectedCountry] ??
        _countryPaymentMethods['default']!;
    if (!methods.contains(_selectedPaymentMethod)) {
      _selectedPaymentMethod = methods.first;
    }
  }

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  /// Initialize data with instant cache loading and background refresh
  Future<void> _initializeData() async {
    setState(() => _isInitializing = true);

    try {
      // First, load cached data instantly for immediate display
      await _loadCachedPaymentProfile();

      // Set initializing to false so UI can render with cached data
      setState(() => _isInitializing = false);

      // Then fetch fresh data in the background
      await _loadExistingProfile();
    } catch (e) {
      AppLogger.log('❌ Error initializing data: $e');
      setState(() => _isInitializing = false);
    }
  }

  /// Refresh data from server
  Future<void> _refreshData() async {
    setState(() => _isRefreshing = true);

    try {
      await _loadExistingProfile();
    } catch (e) {
      AppLogger.log('❌ Error refreshing data: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to refresh data: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isRefreshing = false);
    }
  }

  /// **FIX: Load cached payment profile with user-specific cache key**
  Future<void> _loadCachedPaymentProfile() async {
    try {
      // Try to get user data with retry logic
      Map<String, dynamic>? userData;
      int attempts = 0;
      const maxAttempts = 3;

      while (attempts < maxAttempts && userData == null) {
        userData = await _authService.getUserData();
        if (userData == null) {
          attempts++;
          AppLogger.log('⏳ Waiting for user data... attempt $attempts');
          await Future.delayed(const Duration(milliseconds: 200));
        }
      }

      final userId = userData?['googleId'] ?? userData?['id'];

      if (userId == null) {
        AppLogger.log(
            '⚠️ No user ID available for cache lookup after $maxAttempts attempts');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      // **FIX: Use user-specific cache key**
      final cacheKey = 'payment_profile_cache_$userId';
      final cachedJson = prefs.getString(cacheKey);

      if (cachedJson == null) {
        AppLogger.log('ℹ️ No cached payment profile found for user: $userId');
        return;
      }

      AppLogger.log('✅ Loading cached payment profile for user: $userId');
      final data = json.decode(cachedJson) as Map<String, dynamic>;

      setState(() {
        _selectedCountry = data['country'] ?? _selectedCountry;
        _selectedCurrency = data['currency'] ?? _selectedCurrency;
        _selectedPaymentMethod =
            data['paymentMethod'] ?? _selectedPaymentMethod;
        _normalizeSelectedPaymentMethod();

        final payment = data['paymentDetails'] as Map<String, dynamic>?;
        if (payment != null) {
          _upiIdController.text = payment['upiId'] ?? '';
          _paypalEmailController.text = payment['paypalEmail'] ?? '';
          _stripeAccountIdController.text = payment['stripeAccountId'] ?? '';
          _wiseEmailController.text = payment['wiseEmail'] ?? '';
        }

        final tax = data['taxInfo'] as Map<String, dynamic>?;
        if (tax != null) {
          _panNumberController.text = tax['panNumber'] ?? '';
          _gstNumberController.text = tax['gstNumber'] ?? '';
        }
        _showOptionalTaxInfo = _panNumberController.text.isNotEmpty ||
            _gstNumberController.text.isNotEmpty;
      });

      AppLogger.log('✅ Payment profile loaded from cache successfully');
    } catch (e) {
      AppLogger.log('❌ Error loading cached payment profile: $e');
    }
  }

  Future<void> _loadExistingProfile() async {
    try {
      final userData = await _authService.getUserData();
      final token = userData?['token'];

      if (token == null) {
        AppLogger.log('⚠️ No token available for profile loading');
        return;
      }

      AppLogger.log('🔄 Fetching fresh profile data from server...');
      final response = await httpClientService.get(
        Uri.parse('${NetworkHelper.apiBaseUrl}/creator-payouts/profile'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        AppLogger.log('✅ Fresh profile data received from server');

        setState(() {
          _hasExistingProfile = true;
          _selectedCountry = data['creator']['country'] ?? 'IN';
          _selectedCurrency = data['creator']['currency'] ?? 'INR';
          _selectedPaymentMethod =
              data['creator']['preferredPaymentMethod'] ?? 'upi';
          _normalizeSelectedPaymentMethod();

          // Load existing payment details if available
          if (data['paymentDetails'] != null) {
            _upiIdController.text = data['paymentDetails']['upiId'] ?? '';
            _paypalEmailController.text =
                data['paymentDetails']['paypalEmail'] ?? '';
            _stripeAccountIdController.text =
                data['paymentDetails']['stripeAccountId'] ?? '';
            _wiseEmailController.text =
                data['paymentDetails']['wiseEmail'] ?? '';
            _panNumberController.text = data['taxInfo']?['panNumber'] ?? '';
            _gstNumberController.text = data['taxInfo']?['gstNumber'] ?? '';
          }
          _showOptionalTaxInfo = _panNumberController.text.isNotEmpty ||
              _gstNumberController.text.isNotEmpty;
        });

        // **FIX: Cache for instant prefill next time with user-specific key**
        try {
          final prefs = await SharedPreferences.getInstance();
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
            AppLogger.log('✅ Payment profile cached for user: $userId');
          }
        } catch (e) {
          AppLogger.log('❌ Error caching payment profile: $e');
        }

        // Show success message if this was a refresh
        if (_isRefreshing) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Profile data refreshed successfully'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        AppLogger.log('⚠️ Server returned status: ${response.statusCode}');
        if (_isRefreshing) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⚠️ Failed to refresh: ${response.statusCode}'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      AppLogger.log('❌ Error loading profile: $e');
      if (_isRefreshing) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error refreshing data: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _savePaymentProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      AppLogger.log('🔍 Starting to save payment profile...');

      final userData = await _authService.getUserData();
      final token = userData?['token'];

      AppLogger.log(
          '🔍 User data retrieved: ${userData != null ? 'Success' : 'Failed'}');
      AppLogger.log('🔍 Token available: ${token != null ? 'Yes' : 'No'}');
      if (token != null) {
        AppLogger.log('🔍 Token type: ${token.substring(0, 20)}...');
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

      AppLogger.log('🔍 Request body prepared: $requestBody');
      AppLogger.log(
          '🔍 API endpoint: ${AppConfig.baseUrl}/api/creator-payouts/payment-method');
      AppLogger.log(
          '🔍 Headers: Authorization: Bearer ${token.substring(0, 20)}...');

      final response = await httpClientService.put(
        Uri.parse('${NetworkHelper.apiBaseUrl}/creator-payouts/payment-method'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode(requestBody),
      );

      AppLogger.log('🔍 Response status code: ${response.statusCode}');
      AppLogger.log('🔍 Response body: ${response.body}');

      if (response.statusCode == 200) {
        AppLogger.log('✅ Payment profile saved successfully!');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Payment profile saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        // **NEW: Mark payment setup as completed using service**
        final paymentService = PaymentSetupService();
        await paymentService.markPaymentSetupCompleted();

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
            },
            'taxInfo': {
              'panNumber': _panNumberController.text.trim(),
              'gstNumber': _gstNumberController.text.trim(),
            }
          };

          final cacheKey = 'payment_profile_cache_$userId';
          await prefs.setString(cacheKey, json.encode(sanitized));
          AppLogger.log('✅ Payment profile cached for user: $userId');
        }

        // Show success dialog
        _showSuccessDialog();
      } else {
        final errorBody = json.decode(response.body);
        final error = errorBody['error'] ?? 'Failed to save profile';
        AppLogger.log('❌ Payment profile save failed: $error');
        AppLogger.log('❌ Full error response: $errorBody');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      AppLogger.log('❌ Exception during payment profile save: $e');
      AppLogger.log('❌ Exception type: ${e.runtimeType}');
      if (e.toString().contains('SocketException')) {
        AppLogger.log('❌ Network error - backend might be unreachable');
      }
      if (e.toString().contains('timeout')) {
        AppLogger.log('❌ Request timeout - backend might be slow');
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

  void _toggleEditMode() {
    setState(() {
      _isEditMode = !_isEditMode;
    });
  }

  void _cancelEdit() {
    setState(() {
      _isEditMode = false;
    });
    // Reload existing profile to reset form
    _loadExistingProfile();
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
        title: Text(_hasExistingProfile && !_isEditMode
            ? '💰 Payment Profile Review'
            : '💰 Payment Profile Setup'),
        backgroundColor: Colors.grey[700], // Changed from Colors.blue
        foregroundColor: Colors.white, // Changed from AppTheme.white
        actions: [
          if (_hasExistingProfile && !_isEditMode)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: _toggleEditMode,
              tooltip: 'Edit Payment Details',
            ),
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isRefreshing ? null : _refreshData,
            tooltip: 'Refresh Data',
          ),
        ],
      ),
      body: _isInitializing
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading your payment profile...'),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _refreshData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: _hasExistingProfile && !_isEditMode
                    ? _buildReviewMode()
                    : Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header Info
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.grey[
                                    200], // Changed from Colors.blue.withOpacity(0.1)
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
                                          color: Colors.grey[
                                              700]), // Changed from Colors.blue
                                      const SizedBox(width: 8),
                                      Text(
                                        'Setup Once, Get Paid Monthly!',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey[
                                              700], // Changed from Colors.blue
                                        ),
                                      ),
                                      if (_isRefreshing) ...[
                                        const SizedBox(width: 8),
                                        const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    _isRefreshing
                                        ? 'Refreshing your payment details...'
                                        : 'Enter your payment details once, and we\'ll automatically transfer 80% of your ad revenue every month on the 1st.',
                                    style: TextStyle(
                                        color: Colors.grey[
                                            700]), // Changed from Colors.blue
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
                                  color: Colors.grey[
                                      800]), // Changed from AppTheme.subheadingStyle
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
                                      _countryPaymentMethods[value]?.first ??
                                          'paypal';
                                });
                              },
                              validator: (value) => value == null
                                  ? 'Please select a country'
                                  : null,
                            ),

                            const SizedBox(height: 16),

                            // Currency Selection
                            Text(
                              '💱 Select Your Preferred Currency',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[
                                      800]), // Changed from AppTheme.subheadingStyle
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
                              validator: (value) => value == null
                                  ? 'Please select a currency'
                                  : null,
                            ),

                            const SizedBox(height: 16),

                            // Payment Method Selection
                            Text(
                              '💳 Select Payment Method',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[
                                      800]), // Changed from AppTheme.subheadingStyle
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              initialValue: _selectedPaymentMethod,
                              decoration: const InputDecoration(
                                labelText: 'Payment Method',
                                border: OutlineInputBorder(),
                              ),
                              items:
                                  (_countryPaymentMethods[_selectedCountry] ??
                                          _countryPaymentMethods['default']!)
                                      .map((method) {
                                return DropdownMenuItem(
                                  value: method,
                                  child: Text(
                                      _getPaymentMethodDisplayName(method)),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedPaymentMethod = value!;
                                });
                              },
                              validator: (value) => value == null
                                  ? 'Please select a payment method'
                                  : null,
                            ),

                            const SizedBox(height: 24),

                            // Payment Details Form
                            Text(
                              '📝 Enter Payment Details',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[
                                      800]), // Changed from AppTheme.subheadingStyle
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
                                  color: Colors.grey[
                                      800]), // Changed from AppTheme.subheadingStyle
                            ),
                            const SizedBox(height: 16),

                            if (_selectedCountry == 'IN') ...[
                              OutlinedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _showOptionalTaxInfo =
                                        !_showOptionalTaxInfo;
                                  });
                                },
                                icon: Icon(
                                  _showOptionalTaxInfo
                                      ? Icons.keyboard_arrow_up
                                      : Icons.keyboard_arrow_down,
                                ),
                                label: Text(_showOptionalTaxInfo
                                    ? 'Hide Optional Tax Details'
                                    : 'Add Optional Tax Details'),
                              ),
                              if (_showOptionalTaxInfo) ...[
                                const SizedBox(height: 16),
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
                            ],

                            const SizedBox(height: 32),

                            // Action Buttons
                            if (_hasExistingProfile && _isEditMode) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: _cancelEdit,
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 14),
                                      ),
                                      child: const Text('Cancel'),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: _isLoading
                                          ? null
                                          : _savePaymentProfile,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 14),
                                      ),
                                      child: _isLoading
                                          ? const CircularProgressIndicator(
                                              color: Colors.white)
                                          : const Text('Update Profile'),
                                    ),
                                  ),
                                ],
                              ),
                            ] else ...[
                              // Save Button for new profiles
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton(
                                  onPressed:
                                      _isLoading ? null : _savePaymentProfile,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors
                                        .grey[700], // Changed from Colors.blue
                                    foregroundColor: Colors
                                        .white, // Changed from AppTheme.white
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: _isLoading
                                      ? const CircularProgressIndicator(
                                          color: Colors.white)
                                      : const Text(
                                          '💾 Save Payment Profile',
                                          style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold),
                                        ),
                                ),
                              ),
                            ],

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
                                      Icon(Icons.check_circle,
                                          color: Colors.green[600]),
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
                                    style: TextStyle(
                                        color: Colors.green[700], fontSize: 12),
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

  Widget _buildReviewMode() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Info
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
                    'Payment Profile Complete',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[800],
                    ),
                  ),
                  if (_isRefreshing) ...[
                    const SizedBox(width: 8),
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _isRefreshing
                    ? 'Refreshing your payment details...'
                    : 'Your payment details are set up and ready for automatic monthly payouts.',
                style: TextStyle(color: Colors.green[700]),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Country & Currency Review
        _buildReviewSection(
          title: 'Country & Currency',
          children: [
            _buildReviewItem(
                'Country', _countryNames[_selectedCountry] ?? _selectedCountry),
            _buildReviewItem('Currency',
                '${_currencySymbols[_selectedCurrency]} $_selectedCurrency'),
          ],
        ),

        const SizedBox(height: 16),

        // Payment Method Review
        _buildReviewSection(
          title: 'Payment Method',
          children: [
            _buildReviewItem(
                'Method', _getPaymentMethodDisplayName(_selectedPaymentMethod)),
            ..._buildPaymentMethodReview(),
          ],
        ),

        const SizedBox(height: 16),

        // Tax Information Review
        if (_panNumberController.text.isNotEmpty ||
            _gstNumberController.text.isNotEmpty)
          _buildReviewSection(
            title: 'Tax Information',
            children: [
              if (_panNumberController.text.isNotEmpty)
                _buildReviewItem('PAN Number', _panNumberController.text),
              if (_gstNumberController.text.isNotEmpty)
                _buildReviewItem('GST Number', _gstNumberController.text),
            ],
          ),

        const SizedBox(height: 32),

        // Action Buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _toggleEditMode,
                icon: const Icon(Icons.edit),
                label: const Text('Edit Details'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.check),
                label: const Text('Done'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // Info Box
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue[200]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[600]),
                  const SizedBox(width: 8),
                  Text(
                    'Automatic Monthly Payouts',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[800],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Your payment details will be used automatically every month. You\'ll receive 80% of your ad revenue on the 1st of every month.',
                style: TextStyle(color: Colors.blue[700], fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReviewSection(
      {required String title, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildReviewItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPaymentMethodReview() {
    List<Widget> items = [];

    switch (_selectedPaymentMethod) {
      case 'upi':
        if (_upiIdController.text.isNotEmpty) {
          items.add(_buildReviewItem('UPI ID', _upiIdController.text));
        }
        break;
      case 'paypal':
        if (_paypalEmailController.text.isNotEmpty) {
          items.add(
              _buildReviewItem('PayPal Email', _paypalEmailController.text));
        }
        break;
      case 'stripe':
        if (_stripeAccountIdController.text.isNotEmpty) {
          items.add(_buildReviewItem(
              'Stripe Account ID', _stripeAccountIdController.text));
        }
        break;
      case 'wise':
        if (_wiseEmailController.text.isNotEmpty) {
          items.add(_buildReviewItem('Wise Email', _wiseEmailController.text));
        }
        break;
    }

    return items;
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

      default:
        return const Text('Please select a payment method');
    }
  }

  String _getPaymentMethodDisplayName(String method) {
    switch (method) {
      case 'upi':
        return 'UPI';
      case 'paypal':
        return 'PayPal';
      case 'stripe':
        return 'Stripe';
      case 'wise':
        return 'Wise';
      case 'payoneer':
        return 'Payoneer';
      default:
        return method;
    }
  }

  @override
  void dispose() {
    _upiIdController.dispose();
    _paypalEmailController.dispose();
    _stripeAccountIdController.dispose();
    _wiseEmailController.dispose();
    _panNumberController.dispose();
    _gstNumberController.dispose();
    super.dispose();
  }
}
