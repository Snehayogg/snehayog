import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
import 'package:snehayog/services/ad_refresh_notifier.dart';
import 'package:snehayog/model/ad_model.dart';
import 'package:snehayog/controller/main_controller.dart';
import 'dart:io';

class CreateAdScreenRefactored extends StatefulWidget {
  const CreateAdScreenRefactored({super.key});

  @override
  State<CreateAdScreenRefactored> createState() =>
      _CreateAdScreenRefactoredState();
}

class _CreateAdScreenRefactoredState extends State<CreateAdScreenRefactored>
    with WidgetsBindingObserver {
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
  String _deviceType = 'all';
  String? _optimizationGoal = 'impressions';
  int? _frequencyCap = 3;
  String? _timeZone = 'Asia/Kolkata';
  final Map<String, bool> _dayParting = {};

  // State management
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  // **NEW: Field-specific validation states**
  bool _isTitleValid = true;
  bool _isDescriptionValid = true;
  bool _isLinkValid = true;
  bool _isBudgetValid = true;
  bool _isDateValid = true;
  bool _isMediaValid = true;
  String? _titleError;
  String? _descriptionError;
  String? _linkError;
  String? _budgetError;
  String? _dateError;
  String? _mediaError;

  // Services
  final AdService _adService = AdService();
  final AuthService _authService = AuthService();
  final CloudinaryService _cloudinaryService = CloudinaryService();
  final ScrollController _scrollController = ScrollController();
  // Cache user future to avoid rebuilding FutureBuilder on every setState
  Future<Map<String, dynamic>?>? _userFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _budgetController.text = '100.00';
    _targetAudienceController.text = 'all';
    _userFuture = _authService.getUserData();

    // **FIX: Pause videos when entering create ad screen**
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pauseBackgroundVideos();
    });

    try {
      PaymentHandlerWidget.initialize();
    } catch (e) {
      // Continue without payment handler - user can still create ads
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _titleController.dispose();
    _descriptionController.dispose();
    _linkController.dispose();
    _budgetController.dispose();
    _targetAudienceController.dispose();
    _keywordsController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    print('🔍 CreateAdScreen: App lifecycle changed to $state');

    // **FIX: Pause videos when app goes to background from create ad screen**
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      print('🛑 CreateAdScreen: App backgrounded - pausing videos');
      _pauseBackgroundVideos();
    } else if (state == AppLifecycleState.resumed) {
      print('▶️ CreateAdScreen: App resumed - videos should stay paused');
      // Don't resume videos automatically - let user navigate back to video feed
    }
  }

  /// **FIX: Pause videos in background when minimizing from create ad screen**
  void _pauseBackgroundVideos() {
    try {
      // Import MainController to pause videos
      final mainController =
          Provider.of<MainController>(context, listen: false);
      mainController.forcePauseVideos();
      print('✅ CreateAdScreen: Background videos paused successfully');
    } catch (e) {
      print('❌ CreateAdScreen: Error pausing background videos: $e');
    }
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
        future: _userFuture,
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
      key: const PageStorageKey('createAdScroll'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      controller: _scrollController,
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
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  setState(() => _selectedImage = image);
                  _validateField('media');
                });
              },
              onVideoSelected: (video) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  setState(() => _selectedVideo = video);
                  _validateField('media');
                });
              },
              onImagesSelected: (images) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  setState(() {
                    _selectedImages.clear();
                    _selectedImages.addAll(images);
                  });
                  _validateField('media');
                });
              },
              onError: (error) => setState(() => _errorMessage = error),
              // **NEW: Pass validation states**
              isMediaValid: _isMediaValid,
              mediaError: _mediaError,
            ),
            const SizedBox(height: 16),

            // Ad Details Form
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Ad Details',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Required',
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    AdDetailsFormWidget(
                      titleController: _titleController,
                      descriptionController: _descriptionController,
                      linkController: _linkController,
                      onClearErrors: _clearErrorMessages,
                      onFieldChanged: _validateField,
                      isTitleValid: _isTitleValid,
                      isDescriptionValid: _isDescriptionValid,
                      isLinkValid: _isLinkValid,
                      titleError: _titleError,
                      descriptionError: _descriptionError,
                      linkError: _linkError,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Campaign Settings
            CampaignSettingsWidget(
              budgetController: _budgetController,
              startDate: _startDate,
              endDate: _endDate,
              onClearErrors: _clearErrorMessages,
              onSelectDateRange: _selectDateRange,
              onFieldChanged: _validateField,
              // **NEW: Pass validation states**
              isBudgetValid: _isBudgetValid,
              isDateValid: _isDateValid,
              budgetError: _budgetError,
              dateError: _dateError,
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

                  onMinAgeChanged: (age) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      setState(() => _minAge = age);
                    });
                  },
                  onMaxAgeChanged: (age) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      setState(() => _maxAge = age);
                    });
                  },
                  onGenderChanged: (gender) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      setState(() => _selectedGender = gender);
                    });
                  },
                  onLocationsChanged: (locations) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      setState(() {
                        _selectedLocations.clear();
                        _selectedLocations.addAll(locations);
                      });
                    });
                  },
                  onInterestsChanged: (interests) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      setState(() {
                        _selectedInterests.clear();
                        _selectedInterests.addAll(interests);
                      });
                    });
                  },
                  onPlatformsChanged: (platforms) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      setState(() {
                        _selectedPlatforms.clear();
                        _selectedPlatforms.addAll(platforms);
                      });
                    });
                  },
                  // **NEW: Additional targeting callbacks**
                  onDeviceTypeChanged: (deviceType) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      setState(() => _deviceType = deviceType);
                    });
                  },
                  onOptimizationGoalChanged: (goal) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      setState(() => _optimizationGoal = goal);
                    });
                  },
                  onFrequencyCapChanged: (cap) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      setState(() => _frequencyCap = cap);
                    });
                  },
                  onTimeZoneChanged: (timeZone) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      setState(() => _timeZone = timeZone);
                    });
                  },
                  onDayPartingChanged: (dayParting) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      setState(() {
                        _dayParting.clear();
                        _dayParting.addAll(dayParting);
                      });
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

            // Validation Summary
            _buildValidationSummary(),

            // Submit Button
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _submitAd,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.create),
                label: Text(
                  _isLoading ? 'Creating Ad...' : 'Create Advertisement',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isLoading ? Colors.grey : Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: _isLoading ? 0 : 4,
                  shadowColor: Colors.green.withOpacity(0.3),
                ),
              ),
            ),

            // Progress indicator
            if (_isLoading && _errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: LinearProgressIndicator(
                  backgroundColor: Colors.grey.shade200,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(Colors.green.shade400),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessMessage() {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade300, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.green.shade100,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_outline,
            color: Colors.green.shade600,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _successMessage!,
              style: TextStyle(
                color: Colors.green.shade800,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _successMessage = null),
            icon: Icon(
              Icons.close,
              color: Colors.green.shade600,
              size: 20,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade300, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.red.shade100,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.error_outline,
                color: Colors.red.shade600,
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Error',
                  style: TextStyle(
                    color: Colors.red.shade800,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _errorMessage = null),
                icon: Icon(
                  Icons.close,
                  color: Colors.red.shade600,
                  size: 20,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage!,
            style: TextStyle(
              color: Colors.red.shade700,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          if (_errorMessage!.contains('upload') ||
              _errorMessage!.contains('media') ||
              _errorMessage!.contains('network'))
            Padding(
              padding: const EdgeInsets.only(top: 12),
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
                          horizontal: 16, vertical: 8),
                      minimumSize: const Size(0, 36),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: () => setState(() => _errorMessage = null),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade600,
                      side: BorderSide(color: Colors.red.shade300),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      minimumSize: const Size(0, 36),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Dismiss'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _handleAdTypeChanged(String newAdType) {
    // **FIXED: Use addPostFrameCallback to maintain scroll position**
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() => _errorMessage = null);
      });
    }
  }

  void _clearFieldErrors() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _isTitleValid = true;
        _isDescriptionValid = true;
        _isLinkValid = true;
        _isBudgetValid = true;
        _isDateValid = true;
        _isMediaValid = true;
        _titleError = null;
        _descriptionError = null;
        _linkError = null;
        _budgetError = null;
        _dateError = null;
        _mediaError = null;
      });
    });
  }

  // **NEW: Real-time field validation**
  void _validateField(String fieldName) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      switch (fieldName) {
        case 'title':
          if (_titleController.text.trim().isEmpty) {
            setState(() {
              _isTitleValid = false;
              _titleError = 'Ad title is required';
            });
          } else {
            setState(() {
              _isTitleValid = true;
              _titleError = null;
            });
          }
          break;
        case 'description':
          if (_descriptionController.text.trim().isEmpty) {
            setState(() {
              _isDescriptionValid = false;
              _descriptionError = 'Description is required';
            });
          } else {
            setState(() {
              _isDescriptionValid = true;
              _descriptionError = null;
            });
          }
          break;
        case 'link':
          if (_linkController.text.trim().isEmpty) {
            setState(() {
              _isLinkValid = false;
              _linkError = 'Link URL is required';
            });
          } else {
            setState(() {
              _isLinkValid = true;
              _linkError = null;
            });
          }
          break;
        case 'budget':
          if (_budgetController.text.trim().isEmpty) {
            setState(() {
              _isBudgetValid = false;
              _budgetError = 'Budget amount is required';
            });
          } else {
            try {
              final budget = double.parse(_budgetController.text.trim());
              if (budget <= 0) {
                setState(() {
                  _isBudgetValid = false;
                  _budgetError = 'Budget must be greater than ₹0';
                });
              } else if (budget < 100) {
                setState(() {
                  _isBudgetValid = false;
                  _budgetError = 'Minimum budget is ₹100';
                });
              } else {
                setState(() {
                  _isBudgetValid = true;
                  _budgetError = null;
                });
              }
            } catch (e) {
              setState(() {
                _isBudgetValid = false;
                _budgetError =
                    'Please enter a valid budget amount (e.g., 100.00)';
              });
            }
          }
          break;
        case 'media':
          if (_selectedAdType == 'banner' && _selectedImage == null) {
            setState(() {
              _isMediaValid = false;
              _mediaError =
                  'Banner ads require an image. Please select an image.';
            });
          } else if (_selectedAdType == 'carousel' &&
              _selectedImages.isEmpty &&
              _selectedVideo == null) {
            setState(() {
              _isMediaValid = false;
              _mediaError =
                  'Carousel ads require either images or video. Please select media.';
            });
          } else if (_selectedAdType == 'video feed ad' &&
              _selectedImage == null &&
              _selectedVideo == null) {
            setState(() {
              _isMediaValid = false;
              _mediaError =
                  'Video feed ads require either an image or video. Please select media.';
            });
          } else {
            setState(() {
              _isMediaValid = true;
              _mediaError = null;
            });
          }
          break;
      }
    });
  }

  Widget _buildValidationSummary() {
    final List<Map<String, dynamic>> validationItems = [
      {
        'label': 'Ad Title',
        'isValid': _titleController.text.trim().isNotEmpty,
        'icon': Icons.title,
      },
      {
        'label': 'Description',
        'isValid': _descriptionController.text.trim().isNotEmpty,
        'icon': Icons.description,
      },
      {
        'label': 'Link URL',
        'isValid': _linkController.text.trim().isNotEmpty,
        'icon': Icons.link,
      },
      {
        'label': 'Budget (₹100+)',
        'isValid': _budgetController.text.trim().isNotEmpty &&
            (double.tryParse(_budgetController.text.trim()) ?? 0) >= 100,
        'icon': Icons.attach_money,
      },
      {
        'label': 'Campaign Dates',
        'isValid': _startDate != null && _endDate != null,
        'icon': Icons.calendar_today,
      },
      {
        'label': 'Media File',
        'isValid': _isMediaValid,
        'icon': _selectedAdType == 'banner' ? Icons.image : Icons.video_library,
      },
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Required Fields Checklist',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ...validationItems.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        item['isValid']
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: item['isValid'] ? Colors.green : Colors.grey,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        item['icon'] as IconData,
                        color: item['isValid'] ? Colors.green : Colors.grey,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item['label'] as String,
                          style: TextStyle(
                            color: item['isValid']
                                ? Colors.green.shade700
                                : Colors.grey.shade600,
                            fontWeight: item['isValid']
                                ? FontWeight.w500
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  void _clearMediaSelection() {
    setState(() {
      _selectedImage = null;
      _selectedVideo = null;
      _selectedImages.clear();
    });
  }

  /// **NEW: Notify video feed to refresh ads**
  void _notifyVideoFeedRefresh() {
    try {
      print('🔄 CreateAdScreen: Notifying video feed to refresh ads');
      AdRefreshNotifier().notifyRefresh();
      print('✅ CreateAdScreen: Video feed notification sent');
    } catch (e) {
      print('❌ Error notifying video feed refresh: $e');
    }
  }

  Future<void> _submitAd() async {
    if (!_validateForm()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      // Step 1: Upload media files
      setState(() {
        _errorMessage = '📤 Uploading media files...';
      });

      final mediaUrls = await _uploadMediaFiles();
      if (mediaUrls.isEmpty) {
        throw Exception(
            '❌ Media upload failed - no URLs returned. Please try selecting different media files.');
      }

      // Step 2: Create ad with payment
      setState(() {
        _errorMessage = '💳 Creating advertisement...';
      });

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
        deviceType: _deviceType,
        optimizationGoal: _optimizationGoal,
        frequencyCap: _frequencyCap,
        timeZone: _timeZone,
        dayParting: _dayParting.isNotEmpty ? _dayParting : null,
      );

      if (result['success']) {
        setState(() {
          _successMessage = '✅ Advertisement created successfully!';
          _errorMessage = null;
        });

        PaymentHandlerWidget.showPaymentOptions(
          context,
          AdModel.fromJson(result['ad']),
          result['invoice'],
          () {
            _clearForm();
            Navigator.pop(context);
            // **NEW: Trigger video feed refresh to show new ads**
            _notifyVideoFeedRefresh();
          },
        );
      } else {
        throw Exception(
            '❌ Failed to create ad: ${result['message'] ?? 'Unknown error occurred. Please try again.'}');
      }
    } catch (e) {
      String errorMessage = e.toString().replaceAll('Exception: ', '');

      // Provide more specific error messages based on common issues
      if (errorMessage.contains('network') ||
          errorMessage.contains('connection')) {
        errorMessage =
            '❌ Network error: Please check your internet connection and try again.';
      } else if (errorMessage.contains('upload') ||
          errorMessage.contains('media')) {
        errorMessage =
            '❌ Media upload failed: Please try with different image/video files.';
      } else if (errorMessage.contains('payment') ||
          errorMessage.contains('billing')) {
        errorMessage =
            '❌ Payment error: Please check your payment details and try again.';
      } else if (errorMessage.contains('validation') ||
          errorMessage.contains('required')) {
        errorMessage =
            '❌ Validation error: Please check all required fields are filled correctly.';
      } else if (errorMessage.contains('server') ||
          errorMessage.contains('500')) {
        errorMessage = '❌ Server error: Please try again in a few moments.';
      } else if (errorMessage.contains('unauthorized') ||
          errorMessage.contains('401')) {
        errorMessage = '❌ Authentication error: Please sign in again.';
      } else if (errorMessage.contains('forbidden') ||
          errorMessage.contains('403')) {
        errorMessage =
            '❌ Access denied: You do not have permission to create ads.';
      }

      setState(() {
        _errorMessage = errorMessage;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  bool _validateForm() {
    // Clear previous errors
    _clearErrorMessages();
    _clearFieldErrors();

    bool isValid = true;

    // Check title
    if (_titleController.text.trim().isEmpty) {
      setState(() {
        _isTitleValid = false;
        _titleError = 'Ad title is required';
        isValid = false;
      });
    } else {
      setState(() {
        _isTitleValid = true;
        _titleError = null;
      });
    }

    // Check description
    if (_descriptionController.text.trim().isEmpty) {
      setState(() {
        _isDescriptionValid = false;
        _descriptionError = 'Description is required';
        isValid = false;
      });
    } else {
      setState(() {
        _isDescriptionValid = true;
        _descriptionError = null;
      });
    }

    // Check link
    if (_linkController.text.trim().isEmpty) {
      setState(() {
        _isLinkValid = false;
        _linkError = 'Link URL is required';
        isValid = false;
      });
    } else {
      setState(() {
        _isLinkValid = true;
        _linkError = null;
      });
    }

    // Check budget
    if (_budgetController.text.trim().isEmpty) {
      setState(() {
        _isBudgetValid = false;
        _budgetError = 'Budget amount is required';
        isValid = false;
      });
    } else {
      // Validate budget format
      try {
        final budget = double.parse(_budgetController.text.trim());
        if (budget <= 0) {
          setState(() {
            _isBudgetValid = false;
            _budgetError = 'Budget must be greater than ₹0';
            isValid = false;
          });
        } else if (budget < 100) {
          setState(() {
            _isBudgetValid = false;
            _budgetError = 'Minimum budget is ₹100';
            isValid = false;
          });
        } else {
          setState(() {
            _isBudgetValid = true;
            _budgetError = null;
          });
        }
      } catch (e) {
        setState(() {
          _isBudgetValid = false;
          _budgetError = 'Please enter a valid budget amount (e.g., 100.00)';
          isValid = false;
        });
      }
    }

    // Check date range
    if (_startDate == null || _endDate == null) {
      setState(() {
        _isDateValid = false;
        _dateError = 'Please select campaign start and end dates';
        isValid = false;
      });
    } else {
      // Check if end date is after start date
      if (_endDate!.isBefore(_startDate!)) {
        setState(() {
          _isDateValid = false;
          _dateError = 'End date must be after start date';
          isValid = false;
        });
      } else if (_startDate!
          .isBefore(DateTime.now().subtract(const Duration(days: 1)))) {
        setState(() {
          _isDateValid = false;
          _dateError = 'Start date cannot be in the past';
          isValid = false;
        });
      } else {
        setState(() {
          _isDateValid = true;
          _dateError = null;
        });
      }
    }

    // Check media requirements based on ad type
    if (_selectedAdType == 'banner' && _selectedImage == null) {
      setState(() {
        _isMediaValid = false;
        _mediaError = 'Banner ads require an image. Please select an image.';
        isValid = false;
      });
    } else if (_selectedAdType == 'carousel' &&
        _selectedImages.isEmpty &&
        _selectedVideo == null) {
      setState(() {
        _isMediaValid = false;
        _mediaError =
            'Carousel ads require either images or video. Please select media.';
        isValid = false;
      });
    } else if (_selectedAdType == 'video feed ad' &&
        _selectedImage == null &&
        _selectedVideo == null) {
      setState(() {
        _isMediaValid = false;
        _mediaError =
            'Video feed ads require either an image or video. Please select media.';
        isValid = false;
      });
    } else {
      setState(() {
        _isMediaValid = true;
        _mediaError = null;
      });
    }

    // Check age range if specified
    if (_minAge != null && _maxAge != null && _minAge! > _maxAge!) {
      setState(() {
        _isDateValid = false;
        _dateError = 'Minimum age cannot be greater than maximum age';
        isValid = false;
      });
    }

    return isValid;
  }

  Future<List<String>> _uploadMediaFiles() async {
    final List<String> mediaUrls = [];

    try {
      if (_selectedAdType == 'banner' && _selectedImage != null) {
        print('🔄 CreateAdScreen: Uploading banner image...');
        final imageUrl = await _cloudinaryService.uploadImage(_selectedImage!);
        mediaUrls.add(imageUrl);
        print('✅ CreateAdScreen: Banner image uploaded: $imageUrl');
      } else if (_selectedAdType == 'carousel') {
        if (_selectedImages.isNotEmpty) {
          print(
              '🔄 CreateAdScreen: Uploading ${_selectedImages.length} carousel images...');
          for (int i = 0; i < _selectedImages.length; i++) {
            final image = _selectedImages[i];
            print(
                '🔄 CreateAdScreen: Uploading carousel image ${i + 1}/${_selectedImages.length}...');
            final imageUrl = await _cloudinaryService.uploadImage(image);
            mediaUrls.add(imageUrl);
            print(
                '✅ CreateAdScreen: Carousel image ${i + 1} uploaded: $imageUrl');
          }
        }
        if (_selectedVideo != null) {
          print('🔄 CreateAdScreen: Uploading carousel video...');
          print('🔄 CreateAdScreen: Video file path: ${_selectedVideo!.path}');
          print(
              '🔄 CreateAdScreen: Video file size: ${await _selectedVideo!.length()} bytes');

          final result =
              await _cloudinaryService.uploadVideoForAd(_selectedVideo!);
          print('🔄 CreateAdScreen: Video upload result: $result');

          final videoUrl =
              result['url'] ?? result['hls_urls']?['hls_stream'] ?? '';
          if (videoUrl.isEmpty) {
            throw Exception(
                'Video upload succeeded but no URL returned. Result: $result');
          }
          mediaUrls.add(videoUrl);
          print('✅ CreateAdScreen: Carousel video uploaded: $videoUrl');
        }
      } else if (_selectedAdType == 'video feed ad') {
        if (_selectedImage != null) {
          print('🔄 CreateAdScreen: Uploading video feed ad image...');
          final imageUrl =
              await _cloudinaryService.uploadImage(_selectedImage!);
          mediaUrls.add(imageUrl);
          print('✅ CreateAdScreen: Video feed ad image uploaded: $imageUrl');
        } else if (_selectedVideo != null) {
          print('🔄 CreateAdScreen: Uploading video feed ad video...');
          final result =
              await _cloudinaryService.uploadVideoForAd(_selectedVideo!);
          final videoUrl =
              result['url'] ?? result['hls_urls']?['hls_stream'] ?? '';
          if (videoUrl.isEmpty) {
            throw Exception(
                'Video upload succeeded but no URL returned. Result: $result');
          }
          mediaUrls.add(videoUrl);
          print('✅ CreateAdScreen: Video feed ad video uploaded: $videoUrl');
        }
      }

      print(
          '✅ CreateAdScreen: All media files uploaded successfully. Total URLs: ${mediaUrls.length}');
      return mediaUrls;
    } catch (e) {
      print('❌ CreateAdScreen: Error uploading media files: $e');
      rethrow;
    }
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
    _deviceType = 'all';
    _optimizationGoal = 'impressions';
    _frequencyCap = 3;
    _timeZone = 'Asia/Kolkata';
    _dayParting.clear();

    setState(() {
      _errorMessage = null;
      _successMessage = null;
      // **NEW: Clear validation states**
      _isTitleValid = true;
      _isDescriptionValid = true;
      _isLinkValid = true;
      _isBudgetValid = true;
      _isDateValid = true;
      _isMediaValid = true;
      _titleError = null;
      _descriptionError = null;
      _linkError = null;
      _budgetError = null;
      _dateError = null;
      _mediaError = null;
    });
  }
}
