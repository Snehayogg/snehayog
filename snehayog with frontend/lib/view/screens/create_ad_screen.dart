import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'package:snehayog/services/ad_service.dart';
import 'package:snehayog/services/authservices.dart';
import 'package:snehayog/model/ad_model.dart';
import 'package:snehayog/services/razorpay_service.dart';
import 'package:snehayog/services/cloudinary_service.dart';
import 'package:http/http.dart' as http;
import 'package:snehayog/config/app_config.dart';

class CreateAdScreen extends StatefulWidget {
  const CreateAdScreen({super.key});

  @override
  State<CreateAdScreen> createState() => _CreateAdScreenState();
}

class _CreateAdScreenState extends State<CreateAdScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _linkController = TextEditingController();
  final _budgetController = TextEditingController();
  final _targetAudienceController = TextEditingController();
  final _keywordsController = TextEditingController();

  String _selectedAdType = 'banner';
  DateTime? _startDate;
  DateTime? _endDate;
  File? _selectedImage;
  File? _selectedVideo;
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  final AdService _adService = AdService();
  final AuthService _authService = AuthService();
  final RazorpayService _razorpayService =
      RazorpayService(); // Added RazorpayService instance
  final CloudinaryService _cloudinaryService = CloudinaryService();

  final List<String> _adTypes = ['banner', 'carousel', 'video feed ad'];

  @override
  void initState() {
    super.initState();
    _budgetController.text = '10.00';
    _targetAudienceController.text = 'all';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _linkController.dispose();
    _budgetController.dispose();
    _targetAudienceController.dispose();
    _keywordsController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      // For banner ads, only allow images
      if (_selectedAdType == 'banner') {
        final ImagePicker picker = ImagePicker();
        final XFile? image = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1920,
          maxHeight: 1080,
          imageQuality: 85,
        );

        if (image != null) {
          setState(() {
            _selectedImage = File(image.path);
            _selectedVideo = null;
          });
        }
      } else {
        // For carousel and video feed ads, allow both image and video
        final ImagePicker picker = ImagePicker();
        final XFile? image = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1920,
          maxHeight: 1080,
          imageQuality: 85,
        );

        if (image != null) {
          setState(() {
            _selectedImage = File(image.path);
            // Don't clear video for carousel and video feed ads
          });
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error picking image: $e';
      });
    }
  }

  Future<void> _pickVideo() async {
    try {
      // Only allow video selection for carousel and video feed ads
      if (_selectedAdType == 'banner') {
        setState(() {
          _errorMessage =
              'Banner ads only support images. Please select an image instead.';
        });
        return;
      }

      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
      );

      if (result != null) {
        setState(() {
          _selectedVideo = File(result.files.single.path!);
          // Don't clear image for carousel/video feed ads
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error picking video: $e';
      });
    }
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  // Manual validation method to check all required fields
  bool _validateAllFields() {
    bool isValid = true;

    // Check title
    if (_titleController.text.trim().isEmpty) {
      print('❌ Validation: Title is empty');
      isValid = false;
    } else if (_titleController.text.trim().length < 5) {
      print(
          '❌ Validation: Title too short (${_titleController.text.trim().length} chars)');
      isValid = false;
    }

    // Check description
    if (_descriptionController.text.trim().isEmpty) {
      print('❌ Validation: Description is empty');
      isValid = false;
    } else if (_descriptionController.text.trim().length < 10) {
      print(
          '❌ Validation: Description too short (${_descriptionController.text.trim().length} chars)');
      isValid = false;
    }

    // Check budget
    final budget = double.tryParse(_budgetController.text.trim());
    if (budget == null || budget <= 0) {
      print('❌ Validation: Invalid budget: ${_budgetController.text}');
      isValid = false;
    } else if (budget < 100) {
      print('❌ Validation: Budget too low: $budget');
      isValid = false;
    }

    // Check media selection based on ad type
    if (_selectedAdType == 'banner') {
      // Banner ads only need image
      if (_selectedImage == null) {
        print('❌ Validation: Banner ad requires an image');
        isValid = false;
      }
      if (_selectedVideo != null) {
        print('❌ Validation: Banner ads cannot have videos');
        isValid = false;
      }
    } else if (_selectedAdType == 'carousel' ||
        _selectedAdType == 'video feed ad') {
      // Carousel and video feed ads need at least one media type
      if (_selectedImage == null && _selectedVideo == null) {
        print('❌ Validation: Carousel/video feed ad requires image or video');
        isValid = false;
      }
    }

    // Check dates
    if (_startDate == null || _endDate == null) {
      print(
          '❌ Validation: Dates not selected - Start: $_startDate, End: $_endDate');
      isValid = false;
    }

    print('🔍 Validation result: $isValid');
    return isValid;
  }

  Future<void> _submitAd() async {
    print('🔍 CreateAdScreen: Submit button pressed');

    // First validate the form using Flutter's built-in validation
    if (!_formKey.currentState!.validate()) {
      print('❌ CreateAdScreen: Flutter form validation failed');
      print('🔍 Debug: Form state - ${_formKey.currentState}');
      return;
    }

    // Then do our custom validation
    if (!_validateAllFields()) {
      print('❌ CreateAdScreen: Custom validation failed');
      setState(() {
        _errorMessage = 'Please complete all required fields correctly';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      print('🔍 CreateAdScreen: Starting ad submission...');
      print('🔍 Debug: Form data:');
      print('   Title: "${_titleController.text.trim()}"');
      print('   Description: "${_descriptionController.text.trim()}"');
      print('   Budget: "${_budgetController.text.trim()}"');
      print('   Ad Type: "$_selectedAdType"');
      print('   Start Date: $_startDate');
      print('   End Date: $_endDate');
      print('   Image Selected: ${_selectedImage != null}');
      print('   Video Selected: ${_selectedVideo != null}');

      // Validate media selection
      if (_selectedAdType == 'banner') {
        if (_selectedImage == null) {
          throw Exception('Banner ads require an image');
        }
        if (_selectedVideo != null) {
          throw Exception('Banner ads cannot have videos');
        }
      } else if (_selectedAdType == 'carousel' ||
          _selectedAdType == 'video feed ad') {
        // Carousel and video feed ads need at least one media type
        if (_selectedImage == null && _selectedVideo == null) {
          throw Exception('Please select an image or video for your ad');
        }
      }

      // Validate budget - convert to double and check minimum
      final budgetText = _budgetController.text.trim();
      final budget = double.tryParse(budgetText);
      if (budget == null || budget <= 0) {
        throw Exception('Please enter a valid budget amount');
      }
      if (budget < 1) {
        throw Exception('Budget must be at least ₹1.00');
      }

      // Validate required fields
      if (_titleController.text.trim().isEmpty) {
        throw Exception('Please enter an ad title');
      }
      if (_descriptionController.text.trim().isEmpty) {
        throw Exception('Please enter a description');
      }
      if (_startDate == null || _endDate == null) {
        throw Exception('Please select campaign start and end dates');
      }

      print('✅ CreateAdScreen: Form validation passed');

      // Upload media to Cloudinary first
      String? mediaUrl;
      if (_selectedImage != null) {
        print('🔍 CreateAdScreen: Uploading image to Cloudinary...');
        mediaUrl = await _cloudinaryService.uploadImage(_selectedImage!);
      } else if (_selectedVideo != null) {
        print('🔍 CreateAdScreen: Uploading video to Cloudinary...');
        mediaUrl = await _cloudinaryService.uploadVideo(_selectedVideo!);
      }

      print('✅ CreateAdScreen: Media uploaded successfully: $mediaUrl');

      // Create ad with payment processing
      final result = await _adService.createAdWithPayment(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        imageUrl: _selectedImage != null ? mediaUrl : null,
        videoUrl: _selectedVideo != null ? mediaUrl : null,
        link: _linkController.text.trim(),
        adType: _selectedAdType,
        budget: budget,
        targetAudience: _targetAudienceController.text.trim(),
        targetKeywords: _keywordsController.text
            .trim()
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        startDate: _startDate,
        endDate: _endDate,
      );

      if (result['success']) {
        print('✅ CreateAdScreen: Ad created successfully, payment required');

        // Show payment options
        _showPaymentOptions(
          AdModel.fromJson(result['ad']),
          result['invoice'],
        );
      } else {
        throw Exception('Failed to create ad');
      }
    } catch (e) {
      print('❌ CreateAdScreen: Error submitting ad: $e');
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _clearForm() {
    _titleController.clear();
    _descriptionController.clear();
    _linkController.clear();
    _budgetController.text = '10.00';
    _targetAudienceController.text = 'all';
    _keywordsController.clear();
    _selectedAdType = 'banner';
    _startDate = null;
    _endDate = null;
    _selectedImage = null;
    _selectedVideo = null;
  }

  void _showSuccessDialog(AdModel ad) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ad Created Successfully!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Title: ${ad.title}'),
            Text('Type: ${ad.adType}'),
            Text('Status: ${ad.status}'),
            Text('Budget: ${ad.formattedBudget}'),
            if (ad.startDate != null)
              Text('Start: ${ad.startDate!.toString().split(' ')[0]}'),
            if (ad.endDate != null)
              Text('End: ${ad.endDate!.toString().split(' ')[0]}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Back to Upload'),
          ),
        ],
      ),
    );
  }

  // **NEW: Show payment options for Razorpay**
  void _showPaymentOptions(AdModel ad, Map<String, dynamic> invoice) {
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '💰 What you get:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                      '• Estimated ${(invoice['amount'] / 30 * 1000).round()} impressions'),
                  const Text('• 80% revenue share for creators'),
                  const Text('• Real-time performance tracking'),
                  const Text('• Professional ad management'),
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
              _initiatePayment(invoice);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Pay Now'),
          ),
        ],
      ),
    );
  }

  // **NEW: Initiate Razorpay payment**
  void _initiatePayment(Map<String, dynamic> order) async {
    try {
      setState(() {
        _isLoading = true;
        _successMessage = 'Processing payment...';
      });

      // Get user data for payment
      final userData = await _authService.getUserData();
      if (userData == null) {
        throw Exception('User not authenticated');
      }

      // Create Razorpay order
      final razorpayOrder = await _razorpayService.createOrder(
        amount: order['amount']?.toDouble() ?? 0.0,
        currency: 'INR',
        receipt: order['id']?.toString() ?? '',
        notes: 'Campaign payment for user: ${userData['id']}',
      );

      // For now, simulate payment success since we don't have Razorpay checkout UI
      // In production, you would integrate with razorpay_flutter package
      await Future.delayed(
          const Duration(seconds: 2)); // Simulate payment processing

      // Simulate successful payment
      final paymentResult = {
        'status': 'success',
        'razorpay_order_id': razorpayOrder['id'],
        'razorpay_payment_id': 'pay_${DateTime.now().millisecondsSinceEpoch}',
        'razorpay_signature':
            'simulated_signature_${DateTime.now().millisecondsSinceEpoch}',
      };

      if (paymentResult['status'] == 'success') {
        // Verify payment with backend
        final verificationResult = await _verifyPaymentWithBackend(
          orderId: paymentResult['razorpay_order_id'],
          paymentId: paymentResult['razorpay_payment_id'],
          signature: paymentResult['razorpay_signature'],
        );

        if (verificationResult['verified']) {
          // Activate campaign
          await _activateCampaign(order['campaignId']?.toString() ?? '');

          setState(() {
            _successMessage = 'Payment successful! Your ad is now active.';
            _clearForm();
          });

          if (mounted) {
            _showPaymentSuccessDialog();
          }
        } else {
          throw Exception('Payment verification failed');
        }
      } else {
        throw Exception('Payment failed: ${paymentResult['error']}');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Payment error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // **NEW: Verify payment with backend**
  Future<Map<String, dynamic>> _verifyPaymentWithBackend({
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/billing/verify-payment'),
        headers: {
          'Content-Type': 'application/json',
        },
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

  // **NEW: Activate campaign after successful payment**
  Future<void> _activateCampaign(String campaignId) async {
    try {
      // Call backend to activate campaign
      final response = await http.post(
        Uri.parse(
            '${AppConfig.baseUrl}/api/ads/campaigns/$campaignId/activate'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to activate campaign: ${response.statusCode}');
      }
    } catch (e) {
      print('Error activating campaign: $e');
      // Campaign will be activated by backend after payment verification
    }
  }

  // **NEW: Show payment success dialog**
  void _showPaymentSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 24),
            SizedBox(width: 8),
            Text('Payment Successful!'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your advertisement campaign has been activated!'),
            SizedBox(height: 16),
            Text('Features:'),
            Text('• Ad will be shown to your target audience'),
            Text('• Real-time performance tracking'),
            Text('• Budget management and optimization'),
            Text('• Analytics and insights'),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('View Campaign'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Advertisement'),
        centerTitle: true,
        elevation: 0,
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _authService.getUserData(),
        builder: (context, snapshot) {
          final isSignedIn = snapshot.hasData && snapshot.data != null;

          if (!isSignedIn) {
            return _buildLoginPrompt();
          }

          return _buildCreateAdForm();
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
            'Please sign in to create advertisements',
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

  Widget _buildCreateAdForm() {
    print('🔍 CreateAdScreen: Building create ad form');
    print('🔍 Debug: Form key state: ${_formKey.currentState}');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_successMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: Text(
                  _successMessage!,
                  style: TextStyle(color: Colors.green.shade800),
                ),
              ),
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade300),
                ),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: Colors.red.shade800),
                ),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ad Type',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _selectedAdType == 'banner'
                          ? 'Banner ads are static image advertisements displayed at the top or sides of content'
                          : _selectedAdType == 'carousel'
                              ? 'Carousel ads allow multiple images/videos to be displayed in a swipeable format'
                              : 'Video feed ads appear between video content like Instagram Reels',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedAdType,
                      decoration: const InputDecoration(
                        labelText: 'Select Ad Type',
                        border: OutlineInputBorder(),
                      ),
                      items: _adTypes.map((type) {
                        return DropdownMenuItem(
                          value: type,
                          child: Text(type.toUpperCase()),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedAdType = value!;

                          // Clear inappropriate media when ad type changes
                          if (value == 'banner') {
                            // Banner ads can't have videos
                            if (_selectedVideo != null) {
                              _selectedVideo = null;
                              _errorMessage =
                                  'Banner ads only support images. Video has been removed.';
                            }
                          } else if (value == 'carousel' ||
                              value == 'video feed ad') {
                            // Carousel and video feed ads can have both image and video
                            // No need to clear anything
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Media Content',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      height: 200,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _selectedImage != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                _selectedImage!,
                                fit: BoxFit.cover,
                                width: double.infinity,
                              ),
                            )
                          : _selectedVideo != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    color: Colors.black,
                                    child: const Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.video_file,
                                            size: 48,
                                            color: Colors.white,
                                          ),
                                          Text(
                                            'Video Selected',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                )
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _selectedAdType == 'banner'
                                          ? Icons.image
                                          : Icons.add_photo_alternate,
                                      size: 48,
                                      color: Colors.grey,
                                    ),
                                    Text(
                                      _selectedAdType == 'banner'
                                          ? 'Select Image *'
                                          : 'Select Image or Video *',
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _selectedAdType == 'banner'
                                          ? 'Banner ads require an image'
                                          : 'Carousel and video feed ads support both',
                                      style: TextStyle(
                                        color: Colors.red,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _pickImage,
                            icon: const Icon(Icons.image),
                            label: Text(_selectedAdType == 'banner'
                                ? 'Select Image *'
                                : 'Select Image'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed:
                                _selectedAdType == 'banner' ? null : _pickVideo,
                            icon: const Icon(Icons.video_library),
                            label: Text(_selectedAdType == 'banner'
                                ? 'Video Not Allowed'
                                : 'Select Video'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _selectedAdType == 'banner'
                                  ? Colors.grey
                                  : Colors.green,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _selectedAdType == 'banner'
                          ? 'Banner ads only support images'
                          : 'Carousel and video feed ads support both images and videos',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ad Details',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Ad Title *',
                        hintText: 'Enter a compelling title for your ad',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter an ad title';
                        }
                        if (value.trim().length < 5) {
                          return 'Title must be at least 5 characters';
                        }
                        if (value.trim().length > 100) {
                          return 'Title must be less than 100 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description *',
                        hintText: 'Describe your ad content and call to action',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a description';
                        }
                        if (value.trim().length < 10) {
                          return 'Description must be at least 10 characters';
                        }
                        if (value.trim().length > 500) {
                          return 'Description must be less than 500 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _linkController,
                      decoration: const InputDecoration(
                        labelText: 'Landing Page URL',
                        hintText: 'https://your-website.com',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.link),
                      ),
                      keyboardType: TextInputType.url,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Campaign Settings',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _budgetController,
                      decoration: const InputDecoration(
                        labelText: 'Daily Budget (₹) *',
                        hintText: '100',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.attach_money),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a budget';
                        }
                        final budget = double.tryParse(value.trim());
                        if (budget == null || budget <= 0) {
                          return 'Please enter a valid budget';
                        }
                        if (budget < 100) {
                          return 'Minimum budget is ₹100';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _targetAudienceController,
                      decoration: const InputDecoration(
                        labelText: 'Target Audience',
                        hintText: 'all, youth, professionals, etc.',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.people),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _keywordsController,
                      decoration: const InputDecoration(
                        labelText: 'Target Keywords',
                        hintText: 'Enter keywords separated by commas',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.tag),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _selectDateRange,
                            icon: const Icon(Icons.calendar_today),
                            label: Text(
                              _startDate != null && _endDate != null
                                  ? '${_startDate!.toString().split(' ')[0]} - ${_endDate!.toString().split(' ')[0]}'
                                  : 'Select Date Range *',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_startDate != null && _endDate != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Campaign will run for ${_endDate!.difference(_startDate!).inDays + 1} days',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    if (_startDate == null || _endDate == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Please select start and end dates for your campaign',
                          style: TextStyle(
                            color: Colors.red.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _submitAd,
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.create),
              label:
                  Text(_isLoading ? 'Creating Ad...' : 'Create Advertisement'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
