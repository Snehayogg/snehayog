import 'package:flutter/material.dart';
import 'package:snehayog/view/widget/create_ad/ad_type_selector_widget.dart';
import 'package:snehayog/view/widget/create_ad/media_uploader_widget.dart';
import 'package:snehayog/view/widget/create_ad/ad_details_form_widget.dart';
import 'package:snehayog/view/widget/create_ad/targeting_section_widget.dart';
import 'package:snehayog/view/widget/create_ad/campaign_settings_widget.dart';
import 'package:snehayog/view/widget/create_ad/campaign_preview_widget.dart';
import 'package:snehayog/view/widget/create_ad/payment_handler_widget.dart';
import 'package:snehayog/services/ad_service.dart';
import 'package:snehayog/services/authservices.dart';
import 'package:snehayog/services/cloudinary_service.dart';
import 'package:snehayog/model/ad_model.dart';
import 'dart:io';

class CreateAdScreenRefactored extends StatefulWidget {
  const CreateAdScreenRefactored({super.key});

  @override
  State<CreateAdScreenRefactored> createState() =>
      _CreateAdScreenRefactoredState();
}

class _CreateAdScreenRefactoredState extends State<CreateAdScreenRefactored> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _linkController = TextEditingController();
  final _budgetController = TextEditingController();
  final _targetAudienceController = TextEditingController();
  final _keywordsController = TextEditingController();

  // Ad type and media
  String _selectedAdType = 'banner';
  File? _selectedImage;
  File? _selectedVideo;
  final List<File> _selectedImages = [];

  // Campaign settings
  DateTime? _startDate;
  DateTime? _endDate;

  // Advanced targeting
  int? _minAge;
  int? _maxAge;
  String _selectedGender = 'all';
  final List<String> _selectedLocations = [];
  final List<String> _selectedInterests = [];
  final List<String> _selectedPlatforms = [];

  // **NEW: Additional targeting fields**
  String? _deviceType;
  String? _optimizationGoal;
  int? _frequencyCap;
  String? _timeZone;
  final Map<String, bool> _dayParting = {};
  final Map<String, String> _hourParting = {};

  // State management
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  // Services
  final AdService _adService = AdService();
  final AuthService _authService = AuthService();
  final CloudinaryService _cloudinaryService = CloudinaryService();

  @override
  void initState() {
    super.initState();
    _budgetController.text = '100.00';
    _targetAudienceController.text = 'all';

    // **FIXED: Safe PaymentHandler initialization**
    try {
      PaymentHandlerWidget.initialize();
    } catch (e) {
      // Continue without payment handler - user can still create ads
    }
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
          // Show loading state
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading...'),
                ],
              ),
            );
          }

          // Show error state
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, color: Colors.red, size: 64),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => setState(() {}),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

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
            // Success/Error Messages
            if (_successMessage != null) _buildSuccessMessage(),
            if (_errorMessage != null) _buildErrorMessage(),

            // Ad Type Selector
            AdTypeSelectorWidget(
              selectedAdType: _selectedAdType,
              onAdTypeChanged: _handleAdTypeChanged,
              onShowBenefits: () =>
                  PaymentHandlerWidget.showAdvertisingBenefits(context),
            ),
            const SizedBox(height: 16),

            // Media Uploader
            MediaUploaderWidget(
              selectedAdType: _selectedAdType,
              selectedImage: _selectedImage,
              selectedVideo: _selectedVideo,
              selectedImages: _selectedImages,
              onImageSelected: (image) {
                setState(() => _selectedImage = image);
              },
              onVideoSelected: (video) {
                setState(() => _selectedVideo = video);
              },
              onImagesSelected: (images) {
                setState(() {
                  _selectedImages.clear();
                  _selectedImages.addAll(images);
                });
              },
              onError: (error) => setState(() => _errorMessage = error),
            ),
            const SizedBox(height: 16),

            // Ad Details Form
            AdDetailsFormWidget(
              titleController: _titleController,
              descriptionController: _descriptionController,
              linkController: _linkController,
              onClearErrors: _clearErrorMessages,
            ),
            const SizedBox(height: 16),

            // Campaign Settings
            CampaignSettingsWidget(
              budgetController: _budgetController,
              startDate: _startDate,
              endDate: _endDate,
              onClearErrors: _clearErrorMessages,
              onSelectDateRange: _selectDateRange,
            ),
            const SizedBox(height: 16),

            // Advanced Targeting
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TargetingSectionWidget(
                  minAge: _minAge,
                  maxAge: _maxAge,
                  selectedGender: _selectedGender,
                  selectedLocations: _selectedLocations,
                  selectedInterests: _selectedInterests,
                  selectedPlatforms: _selectedPlatforms,
                  // **NEW: Additional targeting parameters**
                  deviceType: _deviceType,
                  optimizationGoal: _optimizationGoal,
                  frequencyCap: _frequencyCap,
                  timeZone: _timeZone,
                  dayParting: _dayParting,
                  hourParting: _hourParting,

                  onMinAgeChanged: (age) {
                    setState(() => _minAge = age);
                  },
                  onMaxAgeChanged: (age) {
                    setState(() => _maxAge = age);
                  },
                  onGenderChanged: (gender) {
                    setState(() => _selectedGender = gender);
                  },
                  onLocationsChanged: (locations) {
                    setState(() {
                      _selectedLocations.clear();
                      _selectedLocations.addAll(locations);
                    });
                  },
                  onInterestsChanged: (interests) {
                    setState(() {
                      _selectedInterests.clear();
                      _selectedInterests.addAll(interests);
                    });
                  },
                  onPlatformsChanged: (platforms) {
                    setState(() {
                      _selectedPlatforms.clear();
                      _selectedPlatforms.addAll(platforms);
                    });
                  },
                  // **NEW: Additional targeting callbacks**
                  onDeviceTypeChanged: (deviceType) {
                    setState(() => _deviceType = deviceType);
                  },
                  onOptimizationGoalChanged: (goal) {
                    setState(() => _optimizationGoal = goal);
                  },
                  onFrequencyCapChanged: (cap) {
                    setState(() => _frequencyCap = cap);
                  },
                  onTimeZoneChanged: (timeZone) {
                    setState(() => _timeZone = timeZone);
                  },
                  onDayPartingChanged: (dayParting) {
                    setState(() {
                      _dayParting.clear();
                      _dayParting.addAll(dayParting);
                    });
                  },
                  onHourPartingChanged: (hourParting) {
                    setState(() {
                      _hourParting.clear();
                      _hourParting.addAll(hourParting);
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Campaign Preview
            CampaignPreviewWidget(
              startDate: _startDate,
              endDate: _endDate,
              budgetText: _budgetController.text,
              selectedAdType: _selectedAdType,
            ),

            // Submit Button
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

  Widget _buildSuccessMessage() {
    return Container(
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
    );
  }

  Widget _buildErrorMessage() {
    return Container(
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
          if (_errorMessage!.contains('upload') ||
              _errorMessage!.contains('media'))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() => _errorMessage = null);
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
                    onPressed: () => setState(() => _errorMessage = null),
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
    );
  }

  void _handleAdTypeChanged(String newAdType) {
    setState(() {
      _selectedAdType = newAdType;

      // Clear inappropriate media when ad type changes
      if (newAdType == 'banner') {
        if (_selectedVideo != null) {
          _selectedVideo = null;
          _errorMessage =
              'Banner ads only support images. Video has been removed.';
        }
        if (_selectedImages.isNotEmpty) {
          _selectedImages.clear();
          _errorMessage =
              'Banner ads only support single images. Multiple images have been removed.';
        }
      } else if (newAdType == 'carousel') {
        if (_selectedImage != null ||
            _selectedVideo != null ||
            _selectedImages.isNotEmpty) {
          _selectedImage = null;
          _selectedVideo = null;
          _selectedImages.clear();
          _errorMessage =
              'Carousel ads require exclusive selection. Please choose either images OR video.';
        }
      } else if (newAdType == 'video feed ad') {
        if (_selectedImages.isNotEmpty) {
          _selectedImages.clear();
          _errorMessage =
              'Video feed ads only support single images. Multiple images have been removed.';
        }
      }

      _clearErrorMessages();
    });
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
        _clearErrorMessages();
      });
    }
  }

  void _clearErrorMessages() {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
  }

  void _clearMediaSelection() {
    setState(() {
      _selectedImage = null;
      _selectedVideo = null;
      _selectedImages.clear();
    });
  }

  Future<void> _submitAd() async {
    if (!_validateForm()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      // Upload media files
      final mediaUrls = await _uploadMediaFiles();
      if (mediaUrls.isEmpty) {
        throw Exception('Media upload failed - no URLs returned');
      }

      // Create ad with payment
      final result = await _adService.createAdWithPayment(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        imageUrl: _getImageUrl(mediaUrls),
        videoUrl: _selectedVideo != null ? mediaUrls.first : null,
        link: _linkController.text.trim(),
        adType: _selectedAdType,
        budget: double.parse(_budgetController.text.trim()),
        targetAudience: _targetAudienceController.text.trim(),
        targetKeywords: _keywordsController.text
            .trim()
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        startDate: _startDate,
        endDate: _endDate,
        minAge: _minAge,
        maxAge: _maxAge,
        gender: _selectedGender != 'all' ? _selectedGender : null,
        locations: _selectedLocations.isNotEmpty ? _selectedLocations : null,
        interests: _selectedInterests.isNotEmpty ? _selectedInterests : null,
        platforms: _selectedPlatforms.isNotEmpty ? _selectedPlatforms : null,
      );

      if (result['success']) {
        PaymentHandlerWidget.showPaymentOptions(
          context,
          AdModel.fromJson(result['ad']),
          result['invoice'],
          () {
            _clearForm();
            Navigator.pop(context);
          },
        );
      } else {
        throw Exception(
            'Failed to create ad: ${result['message'] ?? 'Unknown error'}');
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  bool _validateForm() {
    if (_titleController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please enter an ad title');
      return false;
    }
    if (_descriptionController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please enter a description');
      return false;
    }
    if (_startDate == null || _endDate == null) {
      setState(
          () => _errorMessage = 'Please select campaign start and end dates');
      return false;
    }
    if (_selectedAdType == 'banner' && _selectedImage == null) {
      setState(() => _errorMessage = 'Banner ads require an image');
      return false;
    }
    if (_selectedAdType == 'carousel' &&
        _selectedImages.isEmpty &&
        _selectedVideo == null) {
      setState(() => _errorMessage =
          'Please select either images or video for your carousel ad');
      return false;
    }
    if (_selectedAdType == 'video feed ad' &&
        _selectedImage == null &&
        _selectedVideo == null) {
      setState(
          () => _errorMessage = 'Please select an image or video for your ad');
      return false;
    }
    return true;
  }

  Future<List<String>> _uploadMediaFiles() async {
    final List<String> mediaUrls = [];

    if (_selectedAdType == 'banner' && _selectedImage != null) {
      final imageUrl = await _cloudinaryService.uploadImage(_selectedImage!);
      mediaUrls.add(imageUrl);
    } else if (_selectedAdType == 'carousel') {
      if (_selectedImages.isNotEmpty) {
        for (final image in _selectedImages) {
          final imageUrl = await _cloudinaryService.uploadImage(image);
          mediaUrls.add(imageUrl);
        }
      }
      if (_selectedVideo != null) {
        final result = await _cloudinaryService.uploadVideo(_selectedVideo!);
        final videoUrl =
            result['url'] ?? result['hls_urls']?['hls_stream'] ?? '';
        mediaUrls.add(videoUrl);
      }
    } else if (_selectedAdType == 'video feed ad') {
      if (_selectedImage != null) {
        final imageUrl = await _cloudinaryService.uploadImage(_selectedImage!);
        mediaUrls.add(imageUrl);
      } else if (_selectedVideo != null) {
        final result = await _cloudinaryService.uploadVideo(_selectedVideo!);
        final videoUrl =
            result['url'] ?? result['hls_urls']?['hls_stream'] ?? '';
        mediaUrls.add(videoUrl);
      }
    }

    return mediaUrls;
  }

  String? _getImageUrl(List<String> mediaUrls) {
    if (_selectedAdType == 'banner' && _selectedImage != null) {
      return mediaUrls.first;
    } else if (_selectedAdType == 'carousel' && _selectedImages.isNotEmpty) {
      return mediaUrls.first;
    } else if (_selectedAdType == 'video feed ad' && _selectedImage != null) {
      return mediaUrls.first;
    }
    return null;
  }

  void _clearForm() {
    _titleController.clear();
    _descriptionController.clear();
    _linkController.clear();
    _budgetController.text = '100.00';
    _targetAudienceController.text = 'all';
    _keywordsController.clear();
    _selectedAdType = 'banner';
    _startDate = null;
    _endDate = null;
    _selectedImage = null;
    _selectedVideo = null;
    _selectedImages.clear();
    _minAge = null;
    _maxAge = null;
    _selectedGender = 'all';
    _selectedLocations.clear();
    _selectedInterests.clear();
    _selectedPlatforms.clear();

    // **NEW: Clear additional targeting fields**
    _deviceType = null;
    _optimizationGoal = null;
    _frequencyCap = null;
    _timeZone = null;
    _dayParting.clear();
    _hourParting.clear();

    setState(() {
      _errorMessage = null;
      _successMessage = null;
    });
  }
}
