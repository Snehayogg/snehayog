import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:snehayog/services/ad_service.dart';
import 'package:snehayog/services/google_auth_service.dart';
import 'package:snehayog/model/ad_model.dart';

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
  final GoogleAuthService _authService = GoogleAuthService();

  final List<String> _adTypes = [
    'banner',
    'interstitial',
    'rewarded',
    'native'
  ];

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
    } catch (e) {
      setState(() {
        _errorMessage = 'Error picking image: $e';
      });
    }
  }

  Future<void> _pickVideo() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
      );

      if (result != null) {
        setState(() {
          _selectedVideo = File(result.files.single.path!);
          _selectedImage = null;
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

  Future<void> _createAd() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      String? imageUrl;
      String? videoUrl;

      if (_selectedImage != null) {
        imageUrl = await _adService.uploadAdMedia(_selectedImage!, 'image');
      } else if (_selectedVideo != null) {
        videoUrl = await _adService.uploadAdMedia(_selectedVideo!, 'video');
      }

      final budget = double.parse(_budgetController.text);

      final keywords = _keywordsController.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      // **NEW: Create ad with payment processing**
      final result = await _adService.createAdWithPayment(
        title: _titleController.text,
        description: _descriptionController.text,
        imageUrl: imageUrl,
        videoUrl: videoUrl,
        link: _linkController.text.isNotEmpty ? _linkController.text : null,
        adType: _selectedAdType,
        budget: budget,
        targetAudience: _targetAudienceController.text,
        targetKeywords: keywords,
        startDate: _startDate,
        endDate: _endDate,
      );

      if (result['paymentRequired'] == true) {
        // **NEW: Show payment options**
        if (mounted) {
          _showPaymentOptions(result['ad'], result['order']);
        }
      } else {
        setState(() {
          _successMessage = 'Ad created successfully! ID: ${result['ad'].id}';
          _clearForm();
        });

        if (mounted) {
          _showSuccessDialog(result['ad']);
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error creating ad: $e';
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
  void _showPaymentOptions(AdModel ad, Map<String, dynamic> order) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Payment Required'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ad: ${ad.title}'),
            Text('Order ID: ${order['id']}'),
            Text('Amount: ₹${(ad.budget / 100).toStringAsFixed(2)}'),
            const SizedBox(height: 16),
            const Text(
              'Your ad has been created in draft status. Please complete the payment to activate it.',
              style: TextStyle(fontSize: 14),
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
              _initiatePayment(order);
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
  void _initiatePayment(Map<String, dynamic> order) {
    // This would integrate with Razorpay checkout
    // For now, we'll show a success message
    setState(() {
      _successMessage = 'Payment initiated! Please complete payment to activate your ad.';
    });
    
    // In a real implementation, you would:
    // 1. Open Razorpay checkout
    // 2. Handle payment success/failure
    // 3. Update ad status accordingly
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
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _selectedAdType,
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
                              : const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.add_photo_alternate,
                                        size: 48,
                                        color: Colors.grey,
                                      ),
                                      Text(
                                        'Select Image or Video',
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _pickImage,
                            icon: const Icon(Icons.image),
                            label: const Text('Select Image'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _pickVideo,
                            icon: const Icon(Icons.video_library),
                            label: const Text('Select Video'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
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
                        if (value == null || value.isEmpty) {
                          return 'Please enter an ad title';
                        }
                        if (value.length < 5) {
                          return 'Title must be at least 5 characters';
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
                        if (value == null || value.isEmpty) {
                          return 'Please enter a description';
                        }
                        if (value.length < 10) {
                          return 'Description must be at least 10 characters';
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
                        labelText: 'Daily Budget (\$) *',
                        hintText: '10.00',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.attach_money),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a budget';
                        }
                        final budget = double.tryParse(value);
                        if (budget == null || budget <= 0) {
                          return 'Please enter a valid budget';
                        }
                        if (budget < 1) {
                          return 'Minimum budget is \$1.00';
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
                                  : 'Select Date Range',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              