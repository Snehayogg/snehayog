import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'package:snehayog/services/ad_service.dart';
import 'package:snehayog/services/authservices.dart';
import 'package:snehayog/model/ad_model.dart';
import 'package:snehayog/services/cloudinary_service.dart';
import 'package:http/http.dart' as http;
import 'package:snehayog/config/app_config.dart';
// Removed razorpay_flutter import - using custom RazorpayService instead
import 'package:snehayog_monetization/snehayog_monetization.dart';

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
  bool _isProcessingPayment = false;

  final AdService _adService = AdService();
  final AuthService _authService = AuthService();
  final RazorpayService _razorpayService = RazorpayService();
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
          // **FIXED: Add specific image type filtering**
          preferredCameraDevice: CameraDevice.rear,
          // **NEW: Add more restrictive image picker options**
          requestFullMetadata: true,
        );

        if (image != null) {
          // **NEW: Validate file type before proceeding**
          final file = File(image.path);
          final fileName = image.name.toLowerCase();

          // Check file extension
          if (!fileName.endsWith('.jpg') &&
              !fileName.endsWith('.jpeg') &&
              !fileName.endsWith('.png') &&
              !fileName.endsWith('.gif') &&
              !fileName.endsWith('.webp')) {
            setState(() {
              _errorMessage =
                  'Please select a valid image file (JPG, PNG, GIF, or WebP)';
            });
            return;
          }

          // **NEW: Check file size (max 10MB for images)**
          final fileSize = await file.length();
          if (fileSize > 10 * 1024 * 1024) {
            // 10MB
            setState(() {
              _errorMessage = 'Image file size must be less than 10MB';
            });
            return;
          }

          // **NEW: Verify file is actually an image**
          if (!await _isValidImageFile(file)) {
            setState(() {
              _errorMessage =
                  'The selected file does not appear to be a valid image. Please try selecting a different file.';
            });
            return;
          }

          print('🔍 CreateAdScreen: Image selected successfully');
          print('   File path: ${image.path}');
          print('   File name: ${image.name}');
          print(
              '   File size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');

          setState(() {
            _selectedImage = file;
            _selectedVideo = null;
            // **NEW: Clear error messages when image is selected**
            _clearErrorMessages();
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
          // **NEW: Validate file type for carousel/video feed ads too**
          final file = File(image.path);
          final fileName = image.name.toLowerCase();

          // Check file extension
          if (!fileName.endsWith('.jpg') &&
              !fileName.endsWith('.jpeg') &&
              !fileName.endsWith('.png') &&
              !fileName.endsWith('.gif') &&
              !fileName.endsWith('.webp')) {
            setState(() {
              _errorMessage =
                  'Please select a valid image file (JPG, PNG, GIF, or WebP)';
            });
            return;
          }

          // **NEW: Check file size (max 10MB for images)**
          final fileSize = await file.length();
          if (fileSize > 10 * 1024 * 1024) {
            // 10MB
            setState(() {
              _errorMessage = 'Image file size must be less than 10MB';
            });
            return;
          }

          // **NEW: Verify file is actually an image**
          if (!await _isValidImageFile(file)) {
            setState(() {
              _errorMessage =
                  'The selected file does not appear to be a valid image. Please try selecting a different file.';
            });
            return;
          }

          print('🔍 CreateAdScreen: Image selected for carousel/video feed ad');
          print('   File path: ${image.path}');
          print('   File name: ${image.name}');
          print(
              '   File size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');

          setState(() {
            _selectedImage = file;
            // Don't clear video for carousel and video feed ads
          });
        }
      }
    } catch (e) {
      print('❌ CreateAdScreen: Error picking image: $e');
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
        // **FIXED: Remove allowedExtensions when using FileType.video**
        // allowedExtensions: ['mp4', 'webm', 'avi', 'mov', 'mkv'], // This causes the error
      );

      if (result != null) {
        final file = File(result.files.single.path!);
        final fileName = result.files.single.name.toLowerCase();

        print('🔍 CreateAdScreen: Video file selected: $fileName');

        // **NEW: Enhanced file extension validation**
        final supportedVideoExtensions = [
          '.mp4',
          '.webm',
          '.avi',
          '.mov',
          '.mkv'
        ];
        bool hasValidExtension = false;

        for (final extension in supportedVideoExtensions) {
          if (fileName.endsWith(extension)) {
            hasValidExtension = true;
            break;
          }
        }

        if (!hasValidExtension) {
          setState(() {
            _errorMessage =
                '''Unsupported video format. Please select a video with one of these formats:
            
🎬 MP4, WebM, AVI, MOV, or MKV

The selected file "$fileName" is not supported.''';
          });
          return;
        }

        // **NEW: Check file size (max 100MB for videos)**
        final fileSize = await file.length();
        if (fileSize > 100 * 1024 * 1024) {
          // 100MB
          setState(() {
            _errorMessage = 'Video file size must be less than 100MB';
          });
          return;
        }

        // **NEW: Verify file is actually a video**
        if (!await _isValidVideoFile(file)) {
          setState(() {
            _errorMessage =
                'The selected file does not appear to be a valid video. Please try selecting a different file.';
          });
          return;
        }

        print('🔍 CreateAdScreen: Video selected successfully');
        print('   File path: ${result.files.single.path}');
        print('   File name: ${result.files.single.name}');
        print(
            '   File size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');

        setState(() {
          _selectedVideo = file;
          // Don't clear image for carousel/video feed ads
          // **NEW: Clear error messages when video is selected**
          _clearErrorMessages();
        });
      }
    } catch (e) {
      print('❌ CreateAdScreen: Error picking video: $e');
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
        // **NEW: Clear error messages when dates are selected**
        _clearErrorMessages();
      });
    }
  }

  // Manual validation method to check all required fields
  bool _validateAllFields() {
    bool isValid = true;
    String errorMessage = '';

    try {
      // Check title
      if (_titleController.text.trim().isEmpty) {
        print('❌ Validation: Title is empty');
        errorMessage = 'Ad title is required';
        isValid = false;
      } else if (_titleController.text.trim().length < 5) {
        print(
            '❌ Validation: Title too short (${_titleController.text.trim().length} chars)');
        errorMessage = 'Ad title must be at least 5 characters long';
        isValid = false;
      } else if (_titleController.text.trim().length > 100) {
        print(
            '❌ Validation: Title too long (${_titleController.text.trim().length} chars)');
        errorMessage = 'Ad title must be less than 100 characters';
        isValid = false;
      }

      // Check description
      if (_descriptionController.text.trim().isEmpty) {
        print('❌ Validation: Description is empty');
        errorMessage = 'Ad description is required';
        isValid = false;
      } else if (_descriptionController.text.trim().length < 10) {
        print(
            '❌ Validation: Description too short (${_descriptionController.text.trim().length} chars)');
        errorMessage = 'Ad description must be at least 10 characters long';
        isValid = false;
      } else if (_descriptionController.text.trim().length > 500) {
        print(
            '❌ Validation: Description too long (${_descriptionController.text.trim().length} chars)');
        errorMessage = 'Ad description must be less than 500 characters';
        isValid = false;
      }

      // Check budget
      final budgetText = _budgetController.text.trim();
      if (budgetText.isEmpty) {
        print('❌ Validation: Budget is empty');
        errorMessage = 'Daily budget is required';
        isValid = false;
      } else {
        final budget = double.tryParse(budgetText);
        if (budget == null || budget <= 0) {
          print('❌ Validation: Invalid budget: $budgetText');
          errorMessage = 'Please enter a valid budget amount';
          isValid = false;
        } else if (budget < 100) {
          print('❌ Validation: Budget too low: $budget');
          errorMessage = 'Minimum daily budget is ₹100.00';
          isValid = false;
        }
      }

      // Check media selection based on ad type
      if (_selectedAdType == 'banner') {
        // Banner ads only need image
        if (_selectedImage == null) {
          print('❌ Validation: Banner ad requires an image');
          errorMessage = 'Banner ads require an image';
          isValid = false;
        }
        if (_selectedVideo != null) {
          print('❌ Validation: Banner ads cannot have videos');
          errorMessage = 'Banner ads cannot have videos';
          isValid = false;
        }
      } else if (_selectedAdType == 'carousel' ||
          _selectedAdType == 'video feed ad') {
        // Carousel and video feed ads need at least one media type
        if (_selectedImage == null && _selectedVideo == null) {
          print('❌ Validation: Carousel/video feed ad requires image or video');
          errorMessage = 'Please select an image or video for your ad';
          isValid = false;
        }
      }

      // Check dates
      if (_startDate == null || _endDate == null) {
        print(
            '❌ Validation: Dates not selected - Start: $_startDate, End: $_endDate');
        errorMessage = 'Please select campaign start and end dates';
        isValid = false;
      } else if (_startDate!
          .isBefore(DateTime.now().subtract(const Duration(days: 1)))) {
        print('❌ Validation: Start date is in the past');
        errorMessage = 'Start date cannot be in the past';
        isValid = false;
      } else if (_endDate!.isBefore(_startDate!)) {
        print('❌ Validation: End date is before start date');
        errorMessage = 'End date must be after start date';
        isValid = false;
      } else if (_endDate!.difference(_startDate!).inDays < 1) {
        print('❌ Validation: Campaign duration too short');
        errorMessage = 'Campaign must run for at least 1 day';
        isValid = false;
      }

      print('🔍 Validation result: $isValid');

      // If validation failed, set the error message
      if (!isValid && errorMessage.isNotEmpty) {
        setState(() {
          _errorMessage = errorMessage;
        });
      }

      return isValid;
    } catch (e) {
      print('❌ Validation error: $e');
      setState(() {
        _errorMessage = 'Validation error: $e';
      });
      return false;
    }
  }

  // **NEW: Method to validate files before upload**
  Future<bool> _validateFiles() async {
    try {
      if (_selectedAdType == 'banner') {
        if (_selectedImage == null) {
          setState(() {
            _errorMessage =
                'Banner ads require an image. Please select an image file.';
          });
          return false;
        }

        // Validate image file
        final fileName = _selectedImage!.path.split('/').last.toLowerCase();
        if (!fileName.endsWith('.jpg') &&
            !fileName.endsWith('.jpeg') &&
            !fileName.endsWith('.png') &&
            !fileName.endsWith('.gif') &&
            !fileName.endsWith('.webp')) {
          setState(() {
            _errorMessage =
                'Please select a valid image file (JPG, PNG, GIF, or WebP)';
          });
          return false;
        }

        // **NEW: Verify file is actually an image**
        if (!await _isValidImageFile(_selectedImage!)) {
          setState(() {
            _errorMessage =
                'The selected image file appears to be corrupted or invalid. Please try selecting a different file.';
          });
          return false;
        }
      } else if (_selectedAdType == 'carousel' ||
          _selectedAdType == 'video feed ad') {
        if (_selectedImage == null && _selectedVideo == null) {
          setState(() {
            _errorMessage = 'Please select an image or video for your ad';
          });
          return false;
        }

        // Validate image if selected
        if (_selectedImage != null) {
          final fileName = _selectedImage!.path.split('/').last.toLowerCase();
          if (!fileName.endsWith('.jpg') &&
              !fileName.endsWith('.jpeg') &&
              !fileName.endsWith('.png') &&
              !fileName.endsWith('.gif') &&
              !fileName.endsWith('.webp')) {
            setState(() {
              _errorMessage =
                  'Please select a valid image file (JPG, PNG, GIF, or WebP)';
            });
            return false;
          }

          // **NEW: Verify file is actually an image**
          if (!await _isValidImageFile(_selectedImage!)) {
            setState(() {
              _errorMessage =
                  'The selected image file appears to be corrupted or invalid. Please try selecting a different file.';
            });
            return false;
          }
        }

        // Validate video if selected
        if (_selectedVideo != null) {
          final fileName = _selectedVideo!.path.split('/').last.toLowerCase();
          if (!fileName.endsWith('.mp4') &&
              !fileName.endsWith('.webm') &&
              !fileName.endsWith('.avi') &&
              !fileName.endsWith('.mov') &&
              !fileName.endsWith('.mkv')) {
            setState(() {
              _errorMessage =
                  'Please select a valid video file (MP4, WebM, AVI, MOV, or MKV)';
            });
            return false;
          }

          // **NEW: Verify file is actually a video**
          if (!await _isValidVideoFile(_selectedVideo!)) {
            setState(() {
              _errorMessage =
                  'The selected video file appears to be corrupted or invalid. Please try selecting a different file.';
            });
            return false;
          }
        }
      }

      return true;
    } catch (e) {
      print('❌ CreateAdScreen: File validation error: $e');
      setState(() {
        _errorMessage = 'Error validating files: $e';
      });
      return false;
    }
  }

  // **NEW: Method to verify file is actually an image**
  Future<bool> _isValidImageFile(File file) async {
    try {
      // Read first few bytes to check file signature
      final bytes = await file.openRead(0, 12).first;
      final hex = bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ')
          .toUpperCase();

      // Check for common image file signatures
      if (hex.startsWith('FF D8 FF')) return true; // JPEG
      if (hex.startsWith('89 50 4E 47')) return true; // PNG
      if (hex.startsWith('47 49 46 38')) return true; // GIF
      if (hex.startsWith('52 49 46 46')) return true; // WebP (RIFF)

      print('❌ CreateAdScreen: Invalid image file signature: $hex');
      return false;
    } catch (e) {
      print('❌ CreateAdScreen: Error checking image file signature: $e');
      return false;
    }
  }

  // **NEW: Method to verify file is actually a video**
  Future<bool> _isValidVideoFile(File file) async {
    try {
      // Read first few bytes to check file signature
      final bytes = await file.openRead(0, 16).first;
      final hex = bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ')
          .toUpperCase();

      // Check for common video file signatures
      if (hex.startsWith('00 00 00 18 66 74 79 70')) return true; // MP4
      if (hex.startsWith('1A 45 DF A3')) return true; // WebM/MKV
      if (hex.startsWith('52 49 46 46')) return true; // AVI (RIFF)
      if (hex.startsWith('00 00 00 14 66 74 79 70 71 74')) return true; // MOV
      if (hex.startsWith('00 00 00 20 66 74 79 70 4D 53 4E 56'))
        return true; // MP4 variant

      print('❌ CreateAdScreen: Invalid video file signature: $hex');
      return false;
    } catch (e) {
      print('❌ CreateAdScreen: Error checking video file signature: $e');
      return false;
    }
  }

  Future<void> _submitAd() async {
    print('🔍 CreateAdScreen: Submit button pressed');

    // **FIXED: Simplified validation approach - use only custom validation for now**
    // The issue was with conflicting validation logic between Flutter's built-in and custom validation

    // First do our custom validation
    if (!_validateAllFields()) {
      print('❌ CreateAdScreen: Custom validation failed');
      setState(() {
        _errorMessage = 'Please complete all required fields correctly';
      });
      return;
    }

    // **NEW: Validate files before upload**
    if (!await _validateFiles()) {
      print('❌ CreateAdScreen: File validation failed');
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

      // **FIXED: Simplified media validation**
      if (_selectedAdType == 'banner') {
        if (_selectedImage == null) {
          throw Exception('Banner ads require an image');
        }
        // Banner ads can't have videos - this is already handled in _validateAllFields
      } else if (_selectedAdType == 'carousel' ||
          _selectedAdType == 'video feed ad') {
        if (_selectedImage == null && _selectedVideo == null) {
          throw Exception('Please select an image or video for your ad');
        }
      }

      // **FIXED: Simplified budget validation**
      final budgetText = _budgetController.text.trim();
      final budget = double.tryParse(budgetText);
      if (budget == null || budget <= 0) {
        throw Exception('Please enter a valid budget amount');
      }
      if (budget < 100) {
        throw Exception('Budget must be at least ₹100.00');
      }

      // **FIXED: Simplified required field validation**
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

      // **FIXED: Better error handling for media upload**
      String? mediaUrl;
      try {
        if (_selectedImage != null) {
          print('🔍 CreateAdScreen: Uploading image to Cloudinary...');
          mediaUrl = await _cloudinaryService.uploadImage(_selectedImage!);
          print('✅ CreateAdScreen: Image uploaded successfully: $mediaUrl');
        } else if (_selectedVideo != null) {
          print('🔍 CreateAdScreen: Uploading video to Cloudinary...');
          final result = await _cloudinaryService.uploadVideo(_selectedVideo!);
          // Extract URL from the result map
          mediaUrl = result['url'] ?? result['hls_urls']?['hls_stream'] ?? '';
          print('✅ CreateAdScreen: Video uploaded successfully: $mediaUrl');
        }
      } catch (uploadError) {
        print('❌ CreateAdScreen: Media upload failed: $uploadError');
        // **NEW: Use improved error handling**
        _handleMediaUploadError('Failed to upload media: $uploadError');
        return; // Exit early to prevent further processing
      }

      if (mediaUrl == null || mediaUrl.isEmpty) {
        throw Exception('Media upload failed - no URL returned');
      }

      print('✅ CreateAdScreen: Media uploaded successfully: $mediaUrl');

      // **FIXED: Better error handling for ad creation**
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
        throw Exception(
            'Failed to create ad: ${result['message'] ?? 'Unknown error'}');
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

    // **NEW: Clear error messages when form is cleared**
    setState(() {
      _errorMessage = null;
      _successMessage = null;
    });
  }

  // **NEW: Method to clear error messages when user makes changes**
  void _clearErrorMessages() {
    if (_errorMessage != null) {
      setState(() {
        _errorMessage = null;
      });
    }
  }

  // **NEW: Method to clear media selection when there are errors**
  void _clearMediaSelection() {
    setState(() {
      _selectedImage = null;
      _selectedVideo = null;
    });
  }

  // **NEW: Method to handle media upload errors**
  void _handleMediaUploadError(String error) {
    print('❌ CreateAdScreen: Media upload error: $error');

    // **NEW: Provide more helpful error messages**
    String userFriendlyError = error;

    if (error.contains('Invalid file type')) {
      userFriendlyError =
          '''File type not supported. Please ensure your file is one of these formats:
      
📸 Images: JPG, JPEG, PNG, GIF, WebP
🎬 Videos: MP4, WebM, AVI, MOV, MKV

Try selecting a different file or converting your file to a supported format.''';
    } else if (error.contains('File too large')) {
      userFriendlyError = '''File size too large. Please ensure:
      
📸 Images: Less than 10MB
🎬 Videos: Less than 100MB

Try compressing your file or selecting a smaller one.''';
    } else if (error.contains('Failed to upload')) {
      userFriendlyError = '''Upload failed. This could be due to:
      
• Network connection issues
• File corruption
• Server temporarily unavailable

Please try again or contact support if the problem persists.''';
    }

    setState(() {
      _errorMessage = userFriendlyError;
      // Clear media selection on error to allow user to try again
      _clearMediaSelection();
    });
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
                      '• Estimated ${(invoice['amount'] / (_selectedAdType == 'banner' ? 10 : 30) * 1000).round()} impressions'),
                  Text(
                    '• CPM: ₹${_selectedAdType == 'banner' ? '10' : '30'} per 1000 impressions',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
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
              _initiateRazorpayPayment();
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

  /// **NEW: Initiate Razorpay payment**
  Future<void> _initiateRazorpayPayment() async {
    try {
      setState(() {
        _isProcessingPayment = true;
      });

      // Get user data for payment
      final userData = await _authService.getUserData();
      if (userData == null) {
        throw Exception('User not authenticated');
      }

      // Calculate total amount
      final totalAmount = _calculateTotalAmount();

      // Make payment using Razorpay
      await _razorpayService.makePayment(
        amount: totalAmount,
        currency: 'INR',
        name: 'Snehayog Ad Campaign',
        description: 'Advertisement campaign payment',
        email: userData['email'] ?? 'user@example.com',
        contact: userData['phone'] ?? '9999999999',
        userName: userData['name'] ?? 'User',
        onSuccess: (Map<String, dynamic> response) async {
          print('✅ Payment successful: ${response['paymentId']}');

          // Process successful payment
          await _processSuccessfulPayment(
            orderId: response['orderId'] ?? '',
            paymentId: response['paymentId'] ?? '',
            signature: response['signature'] ?? '',
          );
        },
        onError: (String errorMessage) {
          print('❌ Payment failed: $errorMessage');
          setState(() {
            _isProcessingPayment = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Payment failed: $errorMessage'),
              backgroundColor: Colors.red,
            ),
          );
        },
      );
    } catch (e) {
      print('❌ Error initiating payment: $e');
      setState(() {
        _isProcessingPayment = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// **NEW: Process successful payment with backend verification**
  Future<void> _processSuccessfulPayment({
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    try {
      // Verify payment with backend
      final verificationResult =
          await _razorpayService.verifyPaymentWithBackend(
        orderId: orderId,
        paymentId: paymentId,
        signature: signature,
      );

      if (verificationResult['message'] == 'Payment verified successfully') {
        // Payment verified successfully
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('✅ Payment verified! Ad campaign created successfully.'),
            backgroundColor: Colors.green,
          ),
        );

        // Clear form and navigate back
        _clearForm();
        Navigator.pop(context);
      } else {
        throw Exception('Payment verification failed');
      }
    } catch (e) {
      print('❌ Error processing payment: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment verification failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isProcessingPayment = false;
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

  // **NEW: Show advertising benefits dialog**
  void _showAdvertisingBenefits() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.star, color: Colors.amber.shade600, size: 24),
            const SizedBox(width: 12),
            const Text(
              'Why Advertise on Snehayog?',
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
                'Unlike other platforms where ad reach is uncertain, Snehayog ensures advertisers get guaranteed impressions, providing clear ROI visibility.',
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
                'Unlike crowded platforms (YouTube, Instagram, etc.), Snehayog offers advertisers a space with lower competition for user attention, increasing ad visibility and impact.',
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
                'Early advertisers on Snehayog benefit from first-mover advantage, capturing audience attention before the platform scales massively.',
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

  // **NEW: Build benefit item widget**
  Widget _buildBenefitItem(
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

  /// **NEW: Calculate total amount for ad campaign**
  double _calculateTotalAmount() {
    // Calculate based on ad type and estimated impressions
    double basePrice = 100.0; // Base price in INR
    double adTypeMultiplier = _selectedAdType == 'banner'
        ? 1.0
        : _selectedAdType == 'carousel'
            ? 1.5
            : 2.0;

    // Estimate impressions based on ad type
    double estimatedImpressions = _selectedAdType == 'banner' ? 10000 : 5000;
    double cpm =
        _selectedAdType == 'banner' ? 10.0 : 30.0; // Cost per 1000 impressions

    return (estimatedImpressions / 1000) * cpm * adTypeMultiplier;
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _errorMessage!,
                      style: TextStyle(color: Colors.red.shade800),
                    ),
                    // **NEW: Add retry button for media upload errors**
                    if (_errorMessage!.contains('upload') ||
                        _errorMessage!.contains('media'))
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            ElevatedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _errorMessage = null;
                                });
                                // Clear media selection to allow retry
                                _clearMediaSelection();
                              },
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('Try Again'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.shade600,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                minimumSize: const Size(0, 32),
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _errorMessage = null;
                                });
                              },
                              child: Text(
                                'Dismiss',
                                style: TextStyle(color: Colors.red.shade600),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            // Benefits Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _showAdvertisingBenefits,
                icon: const Icon(Icons.info_outline, size: 20),
                label: const Text(
                  'Why Advertise on Snehayog?',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade50,
                  foregroundColor: Colors.blue.shade700,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.blue.shade200, width: 1),
                  ),
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
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 16, color: Colors.blue.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _selectedAdType == 'banner'
                                  ? 'CPM: ₹10 per 1000 impressions (lower cost for static ads)'
                                  : 'CPM: ₹30 per 1000 impressions (higher engagement for interactive ads)',
                              style: TextStyle(
                                color: Colors.blue.shade700,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
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

                          // **NEW: Clear error messages when ad type changes**
                          _clearErrorMessages();
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
                                      style: const TextStyle(
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
                    // **NEW: Add supported file types information**
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info_outline,
                                  size: 16, color: Colors.blue.shade700),
                              const SizedBox(width: 8),
                              Text(
                                'Supported File Types:',
                                style: TextStyle(
                                  color: Colors.blue.shade700,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Images: JPG, PNG, GIF, WebP (max 10MB)\nVideos: MP4, WebM, AVI, MOV, MKV (max 100MB)',
                            style: TextStyle(
                              color: Colors.blue.shade700,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // **NEW: Add helpful tip about file formats**
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.lightbulb_outline,
                      size: 16, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '💡 Tip: If you\'re having trouble uploading, try converting your file to JPG or PNG format. Some image formats (like HEIC from iPhone) may not be supported.',
                      style: TextStyle(
                        color: Colors.orange.shade700,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // **NEW: Add video selection tip for video feed ads**
            if (_selectedAdType == 'video feed ad')
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.video_library,
                        size: 16, color: Colors.green.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '🎬 Video Tip: For best results, use MP4 videos with H.264 encoding. Keep file size under 100MB for faster uploads.',
                        style: TextStyle(
                          color: Colors.green.shade700,
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
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
                      onChanged: (value) => _clearErrorMessages(),
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
                      onChanged: (value) => _clearErrorMessages(),
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
                      onChanged: (value) => _clearErrorMessages(),
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
                      onChanged: (value) => _clearErrorMessages(),
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
                      onChanged: (value) => _clearErrorMessages(),
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
              onPressed: _isLoading
                  ? null
                  : () {
                      // **FIXED: Add error handling wrapper to prevent crashes**
                      try {
                        _submitAd();
                      } catch (e) {
                        print(
                            '❌ CreateAdScreen: Unexpected error in submit button: $e');
                        setState(() {
                          _errorMessage = 'An unexpected error occurred: $e';
                          _isLoading = false;
                        });
                      }
                    },
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
