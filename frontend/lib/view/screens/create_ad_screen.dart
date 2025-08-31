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
  // **NEW: Multiple images for carousel ads**
  List<File> _selectedImages = [];
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;
  bool _isProcessingPayment = false;
  // **REMOVED: _upiId variable - not needed since Razorpay handles UPI**
  final AdService _adService = AdService();
  final AuthService _authService = AuthService();
  late final RazorpayService _razorpayService;
  final CloudinaryService _cloudinaryService = CloudinaryService();

  final List<String> _adTypes = ['banner', 'carousel', 'video feed ad'];

  @override
  void initState() {
    super.initState();
    _budgetController.text = '10.00';
    _targetAudienceController.text = 'all';

    _razorpayService = RazorpayService();
    _razorpayService.initialize(
      keyId: AppConfig.razorpayKeyId,
      keySecret: AppConfig.razorpayKeySecret,
      webhookSecret: AppConfig.razorpayWebhookSecret,
      baseUrl: AppConfig.baseUrl,
    );
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
      // For banner ads, only allow single image
      if (_selectedAdType == 'banner') {
        final ImagePicker picker = ImagePicker();
        final XFile? image = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1920,
          maxHeight: 1080,
          imageQuality: 85,
          preferredCameraDevice: CameraDevice.rear,
          requestFullMetadata: true,
        );

        if (image != null) {
          final file = File(image.path);
          final fileName = image.name.toLowerCase();

          // Validate file type
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

          // Check file size
          final fileSize = await file.length();
          if (fileSize > 10 * 1024 * 1024) {
            setState(() {
              _errorMessage = 'Image file size must be less than 10MB';
            });
            return;
          }

          // Verify file is actually an image
          if (!await _isValidImageFile(file)) {
            setState(() {
              _errorMessage =
                  'The selected file does not appear to be a valid image. Please try selecting a different file.';
            });
            return;
          }

          print('🔍 CreateAdScreen: Image selected for banner ad');
          setState(() {
            _selectedImage = file;
            _selectedVideo = null;
            _selectedImages.clear(); // Clear multiple images for banner
            _clearErrorMessages();
          });
        }
      } else if (_selectedAdType == 'carousel') {
        // **UPDATED: For carousel ads, enforce exclusive selection - either images OR video**
        String? choice;

        // If user already has images selected, ask if they want to switch to video
        if (_selectedImages.isNotEmpty) {
          choice = await showDialog<String>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Switch to Video?'),
              content: const Text(
                  'You currently have images selected. Would you like to switch to video? This will remove all selected images.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, 'switch_to_video'),
                  child: const Text('Switch to Video'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, 'keep_images'),
                  child: const Text('Keep Images'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, 'cancel'),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          );

          if (choice == 'switch_to_video') {
            setState(() {
              _selectedImages.clear();
              _selectedImage = null;
            });
            await _pickVideo();
            return;
          } else if (choice == 'keep_images') {
            // Allow adding more images if under limit
            if (_selectedImages.length < 3) {
              await _pickMultipleImages();
            } else {
              setState(() {
                _errorMessage = 'Maximum 3 images already selected';
              });
            }
            return;
          } else {
            return; // Cancel
          }
        }

        // If user already has video selected, ask if they want to switch to images
        if (_selectedVideo != null) {
          choice = await showDialog<String>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Switch to Images?'),
              content: const Text(
                  'You currently have a video selected. Would you like to switch to images? This will remove the selected video.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, 'switch_to_images'),
                  child: const Text('Switch to Images'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, 'keep_video'),
                  child: const Text('Keep Video'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, 'cancel'),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          );

          if (choice == 'switch_to_images') {
            setState(() {
              _selectedVideo = null;
            });
            await _pickMultipleImages();
            return;
          } else if (choice == 'keep_video') {
            return; // Keep current video
          } else {
            return; // Cancel
          }
        }

        // If no media selected yet, show initial choice
        choice = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Select Media Type'),
            content: const Text(
                'Carousel ads support either multiple images (up to 3) OR a single video. Choose one:'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, 'multiple_images'),
                child: const Text('Add Images (up to 3)'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 'video'),
                child: const Text('Add Video'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 'cancel'),
                child: const Text('Cancel'),
              ),
            ],
          ),
        );

        if (choice == 'cancel' || choice == null) {
          return;
        }

        if (choice == 'multiple_images') {
          await _pickMultipleImages();
        } else if (choice == 'video') {
          await _pickVideo();
        }
      } else {
        // For video feed ads, allow single image
        final ImagePicker picker = ImagePicker();
        final XFile? image = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1920,
          maxHeight: 1080,
          imageQuality: 85,
        );

        if (image != null) {
          final file = File(image.path);
          final fileName = image.name.toLowerCase();

          // Validate file type
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

          // Check file size
          final fileSize = await file.length();
          if (fileSize > 10 * 1024 * 1024) {
            setState(() {
              _errorMessage = 'Image file size must be less than 10MB';
            });
            return;
          }

          // Verify file is actually an image
          if (!await _isValidImageFile(file)) {
            setState(() {
              _errorMessage =
                  'The selected file does not appear to be a valid image. Please try selecting a different file.';
            });
            return;
          }

          print('🔍 CreateAdScreen: Image selected for video feed ad');
          setState(() {
            _selectedImage = file;
            _selectedImages.clear(); // Clear multiple images for video feed
            _clearErrorMessages();
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

  // **UPDATED: Pick multiple images for carousel ads**
  Future<void> _pickMultipleImages() async {
    try {
      // **NEW: For carousel ads, clear video when adding images**
      if (_selectedAdType == 'carousel' && _selectedVideo != null) {
        setState(() {
          _selectedVideo = null;
        });
      }

      // Check if already at maximum limit
      if (_selectedImages.length >= 3) {
        setState(() {
          _errorMessage = 'Maximum 3 images allowed for carousel ads';
        });
        return;
      }

      final ImagePicker picker = ImagePicker();
      final List<XFile> images = await picker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (images.isNotEmpty) {
        final List<File> validImages = [];

        for (final image in images) {
          // Check if we've reached the limit
          if (_selectedImages.length + validImages.length >= 3) {
            break;
          }

          final file = File(image.path);
          final fileName = image.name.toLowerCase();

          // Validate file type
          if (!fileName.endsWith('.jpg') &&
              !fileName.endsWith('.jpeg') &&
              !fileName.endsWith('.png') &&
              !fileName.endsWith('.gif') &&
              !fileName.endsWith('.webp')) {
            continue; // Skip invalid files
          }

          // Check file size
          final fileSize = await file.length();
          if (fileSize > 10 * 1024 * 1024) {
            continue; // Skip large files
          }

          // Verify file is actually an image
          if (!await _isValidImageFile(file)) {
            continue; // Skip invalid files
          }

          validImages.add(file);
        }

        if (validImages.isNotEmpty) {
          setState(() {
            _selectedImages.addAll(validImages);
            _clearErrorMessages();
          });

          print(
              '🔍 CreateAdScreen: Added ${validImages.length} images to carousel');
          print('   Total images: ${_selectedImages.length}/3');
        } else {
          setState(() {
            _errorMessage =
                'No valid images selected. Please ensure files are valid image formats under 10MB.';
          });
        }
      }
    } catch (e) {
      print('❌ CreateAdScreen: Error picking multiple images: $e');
      setState(() {
        _errorMessage = 'Error picking images: $e';
      });
    }
  }

  // **NEW: Remove image from carousel**
  void _removeImageFromCarousel(int index) {
    setState(() {
      _selectedImages.removeAt(index);
      _clearErrorMessages();
    });
    print('🔍 CreateAdScreen: Removed image at index $index');
    print('   Remaining images: ${_selectedImages.length}/3');
  }

  // **UPDATED: Build media preview widget**
  Widget _buildMediaPreview() {
    if (_selectedAdType == 'carousel' && _selectedImages.isNotEmpty) {
      // **UPDATED: Show multiple images for carousel (exclusive with video)**
      return ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _selectedImages.length,
        itemBuilder: (context, index) {
          return Container(
            width: 150,
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    _selectedImages[index],
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: () => _removeImageFromCarousel(index),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 4,
                  left: 4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    } else if (_selectedImage != null) {
      // Show single image for banner/video feed ads
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          _selectedImage!,
          fit: BoxFit.cover,
          width: double.infinity,
        ),
      );
    } else if (_selectedVideo != null) {
      // Show video preview
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          color: Colors.black,
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.video_file, size: 48, color: Colors.white),
                Text(
                  'Video Selected',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      // Show placeholder
      return Column(
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
                : _selectedAdType == 'carousel'
                    ? 'Select Images OR Video *'
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
                : _selectedAdType == 'carousel'
                    ? 'Carousel ads: either up to 3 images OR 1 video'
                    : 'Video feed ads support both',
            style: const TextStyle(
              color: Colors.red,
              fontSize: 12,
            ),
          ),
        ],
      );
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

      // **UPDATED: For carousel ads, ensure exclusive selection**
      if (_selectedAdType == 'carousel') {
        // If images are already selected, clear them when adding video
        if (_selectedImages.isNotEmpty) {
          setState(() {
            _selectedImages.clear();
            _selectedImage = null;
          });
        }
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
        // Banner ads only need single image
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
      } else if (_selectedAdType == 'carousel') {
        // **UPDATED: Carousel ads need exclusive selection - either images OR video**
        if (_selectedImages.isEmpty && _selectedVideo == null) {
          print('❌ Validation: Carousel ad requires either images or video');
          errorMessage =
              'Please select either images (up to 3) OR a video for your carousel ad';
          isValid = false;
        }
        // **NEW: Check for exclusive selection - not both images and video**
        if (_selectedImages.isNotEmpty && _selectedVideo != null) {
          print('❌ Validation: Carousel ad cannot have both images and video');
          errorMessage =
              'Carousel ads must have either images OR video, not both';
          isValid = false;
        }
        // Check if too many images
        if (_selectedImages.length > 3) {
          print('❌ Validation: Carousel ad cannot have more than 3 images');
          errorMessage = 'Carousel ads can have maximum 3 images';
          isValid = false;
        }
      } else if (_selectedAdType == 'video feed ad') {
        // Video feed ads need at least one media type
        if (_selectedImage == null && _selectedVideo == null) {
          print('❌ Validation: Video feed ad requires image or video');
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

      // **NEW: Campaign validation using AppConfig**
      if (_startDate != null && _endDate != null) {
        final campaignDays = _endDate!.difference(_startDate!).inDays + 1;
        final budgetText = _budgetController.text.trim();
        if (budgetText.isNotEmpty) {
          final dailyBudget = double.tryParse(budgetText) ?? 0.0;
          final validation = AppConfig.validateCampaign(
            dailyBudget: dailyBudget,
            campaignDays: campaignDays,
            adType: _selectedAdType,
          );

          if (!validation['isValid']) {
            final errors = validation['errors'] as List<String>;
            if (errors.isNotEmpty) {
              errorMessage = errors.first;
              isValid = false;
            }
          }
        }
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
      if (hex.startsWith('00 00 00 20 66 74 79 70 4D 53 4E 56')) {
        return true; // MP4 variant
      }

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
      } else if (_selectedAdType == 'carousel') {
        if (_selectedImages.isEmpty && _selectedVideo == null) {
          throw Exception(
              'Please select at least one image or video for your carousel ad');
        }
      } else if (_selectedAdType == 'video feed ad') {
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

      List<String> mediaUrls = [];
      try {
        if (_selectedAdType == 'banner' && _selectedImage != null) {
          print('🔍 CreateAdScreen: Uploading banner image to Cloudinary...');
          final imageUrl =
              await _cloudinaryService.uploadImage(_selectedImage!);
          mediaUrls.add(imageUrl);
          print(
              '✅ CreateAdScreen: Banner image uploaded successfully: $imageUrl');
        } else if (_selectedAdType == 'carousel') {
          // **NEW: Upload multiple images for carousel**
          if (_selectedImages.isNotEmpty) {
            print(
                '🔍 CreateAdScreen: Uploading ${_selectedImages.length} carousel images to Cloudinary...');
            for (int i = 0; i < _selectedImages.length; i++) {
              final imageUrl =
                  await _cloudinaryService.uploadImage(_selectedImages[i]);
              mediaUrls.add(imageUrl);
              print(
                  '✅ CreateAdScreen: Carousel image ${i + 1} uploaded successfully: $imageUrl');
            }
          }
          if (_selectedVideo != null) {
            print(
                '🔍 CreateAdScreen: Uploading carousel video to Cloudinary...');
            final result =
                await _cloudinaryService.uploadVideo(_selectedVideo!);
            final videoUrl =
                result['url'] ?? result['hls_urls']?['hls_stream'] ?? '';
            mediaUrls.add(videoUrl);
            print(
                '✅ CreateAdScreen: Carousel video uploaded successfully: $videoUrl');
          }
        } else if (_selectedAdType == 'video feed ad') {
          if (_selectedImage != null) {
            print(
                '🔍 CreateAdScreen: Uploading video feed image to Cloudinary...');
            final imageUrl =
                await _cloudinaryService.uploadImage(_selectedImage!);
            mediaUrls.add(imageUrl);
            print(
                '✅ CreateAdScreen: Video feed image uploaded successfully: $imageUrl');
          } else if (_selectedVideo != null) {
            print(
                '🔍 CreateAdScreen: Uploading video feed video to Cloudinary...');
            final result =
                await _cloudinaryService.uploadVideo(_selectedVideo!);
            final videoUrl =
                result['url'] ?? result['hls_urls']?['hls_stream'] ?? '';
            mediaUrls.add(videoUrl);
            print(
                '✅ CreateAdScreen: Video feed video uploaded successfully: $videoUrl');
          }
        }
      } catch (uploadError) {
        print('❌ CreateAdScreen: Media upload failed: $uploadError');
        _handleMediaUploadError('Failed to upload media: $uploadError');
        return; // Exit early to prevent further processing
      }

      if (mediaUrls.isEmpty) {
        throw Exception('Media upload failed - no URLs returned');
      }

      print(
          '✅ CreateAdScreen: Media uploaded successfully: ${mediaUrls.length} items');

      // **FIXED: Better error handling for ad creation**
      final result = await _adService.createAdWithPayment(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        imageUrl: (_selectedAdType == 'banner' && _selectedImage != null) ||
                (_selectedAdType == 'carousel' && mediaUrls.isNotEmpty)
            ? mediaUrls.first
            : null,
        videoUrl: _selectedVideo != null ? mediaUrls.first : null,
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
    // **NEW: Clear multiple images**
    _selectedImages.clear();

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
      _selectedImages.clear();
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
                    '💰 Campaign Metrics:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  // **NEW: Display calculated campaign metrics**
                  ..._buildCampaignMetricsDisplay(),
                  const SizedBox(height: 8),
                  const Text(
                    '✅ What you get:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Text('• 80% revenue share for creators'),
                  const Text('• Real-time performance tracking'),
                  const Text('• Professional ad management'),
                  const Text('• Guaranteed impressions delivery'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // **REMOVED: UPI ID input field - Razorpay checkout handles UPI natively**
            // **REMOVED: Test Payment Info - not needed in production**
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          // **REMOVED: Test Payment Button - not needed in production**
          // **REMOVED: UPI Payment Button - Razorpay checkout handles UPI natively**
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _initiateRazorpayPayment();
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

      print('🔍 CreateAdScreen: Initiating payment for amount: ₹$totalAmount');

      // **FIXED: Make payment using Razorpay with proper error handling**
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

      // **FIXED: Better error message for debugging**
      String errorMessage = 'Payment error: $e';
      if (e.toString().contains('No host specified')) {
        errorMessage =
            'Payment service configuration error. Please check your internet connection and try again.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // **REMOVED: UPI payment method - Razorpay checkout handles UPI natively**

  // **REMOVED: Test payment method - not needed in production**

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
    if (_startDate == null || _endDate == null) {
      return 0.0;
    }

    final campaignDays = _endDate!.difference(_startDate!).inDays + 1;
    final dailyBudget = double.tryParse(_budgetController.text.trim()) ?? 100.0;

    // Use the new campaign calculation logic
    final metrics = AppConfig.calculateCampaignMetrics(
      dailyBudget: dailyBudget,
      campaignDays: campaignDays,
      adType: _selectedAdType,
    );

    return metrics['totalBudget'] as double;
  }

  /// **NEW: Get campaign metrics for display**
  Map<String, dynamic> _getCampaignMetrics() {
    if (_startDate == null || _endDate == null) {
      return {};
    }

    final campaignDays = _endDate!.difference(_startDate!).inDays + 1;
    final dailyBudget = double.tryParse(_budgetController.text.trim()) ?? 100.0;

    return AppConfig.calculateCampaignMetrics(
      dailyBudget: dailyBudget,
      campaignDays: campaignDays,
      adType: _selectedAdType,
    );
  }

  /// **NEW: Build campaign metrics display widgets**
  List<Widget> _buildCampaignMetricsDisplay() {
    final metrics = _getCampaignMetrics();
    if (metrics.isEmpty) {
      return [
        const Text('Please select campaign dates to see metrics'),
      ];
    }

    return [
      _buildMetricRow(
          '💰 Total Budget', '₹${metrics['totalBudget']?.toStringAsFixed(0)}'),
      _buildMetricRow('📊 Expected Impressions',
          '${metrics['expectedImpressions']?.toStringAsFixed(0)}'),
      _buildMetricRow(
          '📅 Campaign Duration', '${metrics['campaignDays']} days'),
      _buildMetricRow('📈 Daily Impressions',
          '${metrics['dailyImpressions']?.toStringAsFixed(0)}'),
      _buildMetricRow(
          '💵 CPM Rate', '₹${metrics['cpm']?.toStringAsFixed(0)} per 1000'),
      _buildMetricRow(
          '⏱️ Estimated Duration', '${metrics['estimatedDuration']} days'),
    ];
  }

  /// **NEW: Build individual metric row**
  Widget _buildMetricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
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
                              ? 'Carousel ads support up to 3 images and 1 video in a swipeable format. You can add multiple media items to create an engaging slideshow.'
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
                            // Clear multiple images for banner
                            if (_selectedImages.isNotEmpty) {
                              _selectedImages.clear();
                              _errorMessage =
                                  'Banner ads only support single images. Multiple images have been removed.';
                            }
                          } else if (value == 'carousel') {
                            // **NEW: For carousel ads, clear all media to enforce exclusive selection**
                            if (_selectedImage != null ||
                                _selectedVideo != null ||
                                _selectedImages.isNotEmpty) {
                              _selectedImage = null;
                              _selectedVideo = null;
                              _selectedImages.clear();
                              _errorMessage =
                                  'Carousel ads require exclusive selection. Please choose either images OR video.';
                            }
                          } else if (value == 'video feed ad') {
                            // Video feed ads can have both image and video
                            // Clear multiple images for video feed ads
                            if (_selectedImages.isNotEmpty) {
                              _selectedImages.clear();
                              _errorMessage =
                                  'Video feed ads only support single images. Multiple images have been removed.';
                            }
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
                      child: _buildMediaPreview(),
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
                                : _selectedAdType == 'carousel'
                                    ? _selectedImages.isNotEmpty
                                        ? 'Add More Images (${_selectedImages.length}/3)'
                                        : 'Add Images (up to 3)'
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
                                : _selectedAdType == 'carousel'
                                    ? _selectedVideo != null
                                        ? 'Video Selected'
                                        : 'Add Video'
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
                          : _selectedAdType == 'carousel'
                              ? 'Carousel ads: choose either up to 3 images OR 1 video (not both)'
                              : 'Video feed ads support both images and videos',
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

            // **NEW: Add carousel tip for carousel ads**
            if (_selectedAdType == 'carousel')
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.view_carousel,
                        size: 16, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '🎠 Carousel Tip: Choose either multiple images (up to 3) OR a single video for your carousel. This creates a cleaner, more focused ad experience.',
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
                        labelText: 'Landing Page URL (Optional)',
                        hintText: 'https://your-website.com',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.link),
                        helperText:
                            'Enter your website URL where users will land after clicking the ad',
                      ),
                      keyboardType: TextInputType.url,
                      onChanged: (value) => _clearErrorMessages(),
                      validator: (value) {
                        if (value != null && value.trim().isNotEmpty) {
                          // Check if it's a valid URL
                          if (!value.trim().startsWith('http://') &&
                              !value.trim().startsWith('https://')) {
                            return 'Please enter a valid URL starting with http:// or https://';
                          }
                          try {
                            Uri.parse(value.trim());
                          } catch (e) {
                            return 'Please enter a valid URL';
                          }
                        }
                        return null;
                      },
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
                              '💡 This field is for your website URL where users will go after clicking your ad. Leave empty if you don\'t have a website.',
                              style: TextStyle(
                                color: Colors.blue.shade700,
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
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
            // **NEW: Campaign Preview Section**
            if (_startDate != null &&
                _endDate != null &&
                _budgetController.text.isNotEmpty)
              Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.analytics, color: Colors.blue.shade600),
                          const SizedBox(width: 8),
                          const Text(
                            'Campaign Preview',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ..._buildCampaignMetricsDisplay(),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle,
                                size: 16, color: Colors.green.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '✅ Campaign configuration looks good! You can proceed to create your ad.',
                                style: TextStyle(
                                  color: Colors.green.shade700,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
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
