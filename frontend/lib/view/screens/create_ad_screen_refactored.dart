import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayu/view/widget/create_ad/ad_type_selector_widget.dart';
import 'package:vayu/view/widget/create_ad/media_uploader_widget.dart';
import 'package:vayu/view/widget/create_ad/ad_details_form_widget.dart';
import 'package:vayu/view/widget/create_ad/targeting_section_widget.dart';
import 'package:vayu/view/widget/create_ad/campaign_preview_widget.dart';
import 'package:vayu/view/widget/create_ad/ad_placement_preview_widget.dart';
import 'package:vayu/view/widget/create_ad/payment_handler_widget.dart';
import 'package:vayu/services/ad_service.dart';
import 'package:vayu/services/authservices.dart';
import 'package:vayu/controller/google_sign_in_controller.dart';
import 'package:vayu/services/logout_service.dart';
import 'package:vayu/services/cloudinary_service.dart';
import 'package:vayu/services/ad_refresh_notifier.dart';
import 'package:vayu/model/ad_model.dart';
import 'package:vayu/controller/main_controller.dart';
import 'dart:io';
import 'package:vayu/utils/app_logger.dart';

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
  // **NEW: Advanced KPI fields**
  String? _bidType = 'CPM';
  double? _bidAmount;
  String? _pacing = 'smooth';
  final Map<String, String> _hourParting = {};
  double? _targetCPA;
  double? _targetROAS;
  int? _attributionWindow;

  // State management
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  // **NEW: Simple mode for beginners**
  bool _showAdvancedSettings = false;

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

    // **NEW: Smart defaults for beginners**
    _budgetController.text = '300.00'; // Recommended ₹300/day
    _targetAudienceController.text = 'smart'; // Smart targeting
    _keywordsController.text = 'general'; // Default keywords

    // **NEW: Auto-set dates (14 days from now)**
    final now = DateTime.now();
    _startDate = now;
    _endDate = now.add(const Duration(days: 14));

    // **NEW: Smart targeting defaults**
    _selectedGender = 'all';
    _deviceType = 'all';
    _optimizationGoal = 'impressions';
    _frequencyCap = 3;
    _timeZone = 'Asia/Kolkata';
    // **NEW: Advanced KPI defaults**
    _bidType = 'CPM';
    _pacing = 'smooth';

    _userFuture = _authService.getUserData();

    // **FIX: Pause videos when entering create ad screen**
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pauseBackgroundVideos();
    });

    // **NEW: Restore form state if user had previously minimized the app**
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreFormState();
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

  /// Reset UI to a fresh state after successful ad creation
  void _showFreshAdScreen() {
    // Clear all form fields and saved state
    _clearForm();
    // Scroll to top for a clean start
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
    // Inform user
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Advertisement created. You can create another one.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    AppLogger.log('🔍 CreateAdScreen: App lifecycle changed to $state');

    // **FIX: Handle app lifecycle properly to maintain state**
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      AppLogger.log(
        '🛑 CreateAdScreen: App backgrounded - pausing videos and saving state',
      );
      _pauseBackgroundVideos();
      _saveFormState();
    } else if (state == AppLifecycleState.resumed) {
      AppLogger.log('▶️ CreateAdScreen: App resumed - restoring state');
      _restoreFormState();
      // Don't resume videos automatically - let user navigate back to video feed
    }
  }

  /// **FIX: Pause videos in background when minimizing from create ad screen**
  void _pauseBackgroundVideos() {
    try {
      // Import MainController to pause videos
      final mainController = Provider.of<MainController>(
        context,
        listen: false,
      );
      mainController.forcePauseVideos();
      AppLogger.log('✅ CreateAdScreen: Background videos paused successfully');
    } catch (e) {
      AppLogger.log('❌ CreateAdScreen: Error pausing background videos: $e');
    }
  }

  /// **NEW: Save form state when app is minimized**
  void _saveFormState() {
    try {
      AppLogger.log('💾 CreateAdScreen: Saving form state...');

      // Save form data to SharedPreferences
      _saveFormData();

      AppLogger.log('✅ CreateAdScreen: Form state saved successfully');
    } catch (e) {
      AppLogger.log('❌ CreateAdScreen: Error saving form state: $e');
    }
  }

  /// **NEW: Restore form state when app is resumed**
  void _restoreFormState() {
    try {
      AppLogger.log('🔄 CreateAdScreen: Restoring form state...');

      // Restore form data from SharedPreferences
      _restoreFormData();

      AppLogger.log('✅ CreateAdScreen: Form state restored successfully');
    } catch (e) {
      AppLogger.log('❌ CreateAdScreen: Error restoring form state: $e');
    }
  }

  /// **NEW: Save form data to SharedPreferences**
  void _saveFormData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Save all form fields
      await prefs.setString('create_ad_title', _titleController.text);
      await prefs.setString(
        'create_ad_description',
        _descriptionController.text,
      );
      await prefs.setString('create_ad_link', _linkController.text);
      await prefs.setString('create_ad_budget', _budgetController.text);
      await prefs.setString(
        'create_ad_target_audience',
        _targetAudienceController.text,
      );
      await prefs.setString('create_ad_keywords', _keywordsController.text);
      await prefs.setString('create_ad_type', _selectedAdType);

      // Save dates
      if (_startDate != null) {
        await prefs.setString(
          'create_ad_start_date',
          _startDate!.millisecondsSinceEpoch.toString(),
        );
      }
      if (_endDate != null) {
        await prefs.setString(
          'create_ad_end_date',
          _endDate!.millisecondsSinceEpoch.toString(),
        );
      }

      // Save targeting data
      await prefs.setString('create_ad_min_age', _minAge?.toString() ?? '');
      await prefs.setString('create_ad_max_age', _maxAge?.toString() ?? '');
      await prefs.setString('create_ad_gender', _selectedGender);
      await prefs.setStringList('create_ad_locations', _selectedLocations);
      await prefs.setStringList('create_ad_interests', _selectedInterests);
      await prefs.setStringList('create_ad_platforms', _selectedPlatforms);

      // Save additional targeting
      await prefs.setString('create_ad_device_type', _deviceType);
      await prefs.setString(
        'create_ad_optimization_goal',
        _optimizationGoal ?? '',
      );
      await prefs.setString(
        'create_ad_frequency_cap',
        _frequencyCap?.toString() ?? '',
      );
      await prefs.setString('create_ad_timezone', _timeZone ?? '');

      // Save day parting
      final dayPartingKeys = _dayParting.keys.toList();
      final dayPartingValues =
          _dayParting.values.map((v) => v.toString()).toList();
      await prefs.setStringList('create_ad_day_parting_keys', dayPartingKeys);
      await prefs.setStringList(
        'create_ad_day_parting_values',
        dayPartingValues,
      );

      AppLogger.log('✅ CreateAdScreen: Form data saved to SharedPreferences');
    } catch (e) {
      AppLogger.log('❌ CreateAdScreen: Error saving form data: $e');
    }
  }

  /// **NEW: Restore form data from SharedPreferences**
  void _restoreFormData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Restore all form fields
      _titleController.text = prefs.getString('create_ad_title') ?? '';
      _descriptionController.text =
          prefs.getString('create_ad_description') ?? '';
      _linkController.text = prefs.getString('create_ad_link') ?? '';
      _budgetController.text = prefs.getString('create_ad_budget') ?? '100.00';
      _targetAudienceController.text =
          prefs.getString('create_ad_target_audience') ?? 'all';
      _keywordsController.text = prefs.getString('create_ad_keywords') ?? '';
      _selectedAdType = prefs.getString('create_ad_type') ?? 'banner';

      // Restore dates
      final startDateStr = prefs.getString('create_ad_start_date');
      if (startDateStr != null && startDateStr.isNotEmpty) {
        _startDate = DateTime.fromMillisecondsSinceEpoch(
          int.parse(startDateStr),
        );
      }
      final endDateStr = prefs.getString('create_ad_end_date');
      if (endDateStr != null && endDateStr.isNotEmpty) {
        _endDate = DateTime.fromMillisecondsSinceEpoch(int.parse(endDateStr));
      }

      // Restore targeting data
      final minAgeStr = prefs.getString('create_ad_min_age');
      _minAge = minAgeStr != null && minAgeStr.isNotEmpty
          ? int.parse(minAgeStr)
          : null;
      final maxAgeStr = prefs.getString('create_ad_max_age');
      _maxAge = maxAgeStr != null && maxAgeStr.isNotEmpty
          ? int.parse(maxAgeStr)
          : null;
      _selectedGender = prefs.getString('create_ad_gender') ?? 'all';
      _selectedLocations.clear();
      _selectedLocations.addAll(
        prefs.getStringList('create_ad_locations') ?? [],
      );
      _selectedInterests.clear();
      _selectedInterests.addAll(
        prefs.getStringList('create_ad_interests') ?? [],
      );
      _selectedPlatforms.clear();
      _selectedPlatforms.addAll(
        prefs.getStringList('create_ad_platforms') ?? [],
      );

      // Restore additional targeting
      _deviceType = prefs.getString('create_ad_device_type') ?? 'all';
      _optimizationGoal = prefs.getString('create_ad_optimization_goal');
      final frequencyCapStr = prefs.getString('create_ad_frequency_cap');
      _frequencyCap = frequencyCapStr != null && frequencyCapStr.isNotEmpty
          ? int.parse(frequencyCapStr)
          : 3;
      _timeZone = prefs.getString('create_ad_timezone') ?? 'Asia/Kolkata';

      // Restore day parting
      _dayParting.clear();
      final dayPartingKeys =
          prefs.getStringList('create_ad_day_parting_keys') ?? [];
      final dayPartingValues =
          prefs.getStringList('create_ad_day_parting_values') ?? [];
      for (int i = 0;
          i < dayPartingKeys.length && i < dayPartingValues.length;
          i++) {
        _dayParting[dayPartingKeys[i]] = dayPartingValues[i] == 'true';
      }

      // Trigger UI update
      if (mounted) {
        setState(() {});
      }

      AppLogger.log(
        '✅ CreateAdScreen: Form data restored from SharedPreferences',
      );
    } catch (e) {
      AppLogger.log('❌ CreateAdScreen: Error restoring form data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Ad'),
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
                children: [CircularProgressIndicator()],
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
          const Icon(Icons.lock_outline, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text(
            'Sign in to create ads',
            style: TextStyle(fontSize: 18, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () async {
              final authController = Provider.of<GoogleSignInController>(
                context,
                listen: false,
              );
              final user = await authController.signIn();
              if (user != null) {
                await LogoutService.refreshAllState(context);
              }
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

            // **ENHANCED: Ad Details Form with helpful tips**
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.edit, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text(
                          _selectedAdType == 'banner'
                              ? 'Banner Details'
                              : 'Ad Details',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    // **NEW: Helpful tip for beginners**
                    Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.tips_and_updates,
                            size: 16,
                            color: Colors.amber.shade700,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _selectedAdType == 'banner'
                                  ? 'Tip: Keep headline short (4-6 words) and use a clear, bright image'
                                  : 'Tip: Use engaging visuals and a clear call-to-action',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.amber.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    AdDetailsFormWidget(
                      titleController: _titleController,
                      descriptionController: _descriptionController,
                      linkController: _linkController,
                      adType: _selectedAdType,
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

            // **REMOVED: Campaign Settings moved to Budget & Duration section above**

            // **NEW: Simple Budget & Duration Section (Beginner-friendly)**
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.attach_money, color: Colors.green),
                        SizedBox(width: 8),
                        Text(
                          'Budget & Duration',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Spacer(),
                        // **NEW: Helpful tip icon**
                        Tooltip(
                          message:
                              'Recommended: ₹300/day for 14 days gives you good reach',
                          child: Icon(
                            Icons.help_outline,
                            size: 20,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Budget with recommended badge
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _budgetController,
                            decoration: InputDecoration(
                              labelText: 'Daily Budget (₹)',
                              hintText: '300',
                              prefixText: '₹',
                              border: const OutlineInputBorder(),
                              helperText: 'Minimum ₹100',
                              suffixIcon: _budgetController.text == '300.00'
                                  ? Container(
                                      margin: const EdgeInsets.all(8),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade50,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.green.shade200,
                                        ),
                                      ),
                                      child: const Center(
                                        child: Text(
                                          'Recommended',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.green,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (value) {
                              _validateField('budget');
                              setState(() {}); // Update recommended badge
                            },
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Budget is required';
                              }
                              try {
                                final budget = double.parse(value.trim());
                                if (budget < 100) {
                                  return 'Minimum budget is ₹100';
                                }
                              } catch (e) {
                                return 'Enter a valid amount';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    // **NEW: Show budget error if any**
                    if (!_isBudgetValid && _budgetError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 16,
                              color: Colors.red.shade700,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _budgetError!,
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    // Quick duration picker
                    const Text(
                      'Campaign Duration',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final days in [7, 14, 30])
                          ChoiceChip(
                            label: Text('$days days'),
                            selected: _endDate != null &&
                                _startDate != null &&
                                _endDate!.difference(_startDate!).inDays ==
                                    days,
                            onSelected: (_) {
                              setState(() {
                                _startDate = DateTime.now();
                                _endDate = _startDate!.add(
                                  Duration(days: days),
                                );
                              });
                            },
                          ),
                        ChoiceChip(
                          label: const Text('Custom'),
                          selected: _endDate != null &&
                              _startDate != null &&
                              !([7, 14, 30].contains(
                                _endDate!.difference(_startDate!).inDays,
                              )),
                          onSelected: (_) => _selectDateRange(),
                        ),
                      ],
                    ),
                    if (_startDate != null && _endDate != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${_startDate!.day}/${_startDate!.month}/${_startDate!.year} - ${_endDate!.day}/${_endDate!.month}/${_endDate!.year}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ] else if (!_isDateValid && _dateError != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 16,
                            color: Colors.red.shade700,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              _dateError!,
                              style: TextStyle(
                                color: Colors.red.shade700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // **NEW: Advanced Settings Toggle (animation removed)**
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    leading: const Icon(Icons.tune, color: Colors.blue),
                    title: const Text(
                      'Advanced Settings (Optional)',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text(
                      'Smart targeting is enabled by default. Customize if needed.',
                      style: TextStyle(fontSize: 12),
                    ),
                    trailing: Icon(
                      _showAdvancedSettings
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: Colors.blue,
                    ),
                    onTap: () {
                      setState(() {
                        _showAdvancedSettings = !_showAdvancedSettings;
                      });
                    },
                  ),
                  if (_showAdvancedSettings) const Divider(height: 1),
                  if (_showAdvancedSettings)
                    Container(
                      constraints: const BoxConstraints(
                        minHeight: 0,
                        maxHeight: double.infinity,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.blue.shade200),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.lightbulb_outline,
                                    color: Colors.blue,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Smart Targeting is ON: Your ad will automatically reach the right audience based on your content.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.blue.shade800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            TargetingSectionWidget(
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
                              // **NEW: Advanced KPI parameters**
                              bidType: _bidType,
                              bidAmount: _bidAmount,
                              pacing: _pacing,
                              hourParting: _hourParting,
                              targetCPA: _targetCPA,
                              targetROAS: _targetROAS,
                              attributionWindow: _attributionWindow,

                              onMinAgeChanged: (age) {
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  setState(() => _minAge = age);
                                });
                              },
                              onMaxAgeChanged: (age) {
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  setState(() => _maxAge = age);
                                });
                              },
                              onGenderChanged: (gender) {
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  setState(() => _selectedGender = gender);
                                });
                              },
                              onLocationsChanged: (locations) {
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  setState(() {
                                    _selectedLocations.clear();
                                    _selectedLocations.addAll(locations);
                                  });
                                });
                              },
                              onInterestsChanged: (interests) {
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  setState(() {
                                    _selectedInterests.clear();
                                    _selectedInterests.addAll(interests);
                                  });
                                });
                              },
                              onPlatformsChanged: (platforms) {
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  setState(() {
                                    _selectedPlatforms.clear();
                                    _selectedPlatforms.addAll(platforms);
                                  });
                                });
                              },
                              // **NEW: Additional targeting callbacks**
                              onDeviceTypeChanged: (deviceType) {
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  setState(() => _deviceType = deviceType);
                                });
                              },
                              onOptimizationGoalChanged: (goal) {
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  setState(() => _optimizationGoal = goal);
                                });
                              },
                              onFrequencyCapChanged: (cap) {
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  setState(() => _frequencyCap = cap);
                                });
                              },
                              onTimeZoneChanged: (timeZone) {
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  setState(() => _timeZone = timeZone);
                                });
                              },
                              onDayPartingChanged: (dayParting) {
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  setState(() {
                                    _dayParting.clear();
                                    _dayParting.addAll(dayParting);
                                  });
                                });
                              },
                              // **NEW: Advanced KPI callbacks**
                              onBidTypeChanged: (bidType) {
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  setState(() => _bidType = bidType);
                                });
                              },
                              onBidAmountChanged: (amount) {
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  setState(() => _bidAmount = amount);
                                });
                              },
                              onPacingChanged: (pacing) {
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  setState(() => _pacing = pacing);
                                });
                              },
                              onHourPartingChanged: (hourParting) {
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  setState(() {
                                    _hourParting.clear();
                                    _hourParting.addAll(hourParting);
                                  });
                                });
                              },
                              onTargetCPAChanged: (cpa) {
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  setState(() => _targetCPA = cpa);
                                });
                              },
                              onTargetROASChanged: (roas) {
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  setState(() => _targetROAS = roas);
                                });
                              },
                              onAttributionWindowChanged: (window) {
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  setState(() => _attributionWindow = window);
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Ad Placement Preview (visual mockup)
            if ((_selectedAdType == 'banner' && _selectedImage != null) ||
                (_selectedAdType == 'carousel' &&
                    (_selectedImages.isNotEmpty || _selectedVideo != null)))
              AdPlacementPreviewWidget(
                selectedAdType: _selectedAdType,
                selectedImage: _selectedImage,
                selectedVideo: _selectedVideo,
                selectedImages: _selectedImages,
              ),

            if ((_selectedAdType == 'banner' && _selectedImage != null) ||
                (_selectedAdType == 'carousel' &&
                    (_selectedImages.isNotEmpty || _selectedVideo != null)))
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
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
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
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Colors.green.shade400,
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
            icon: Icon(Icons.close, color: Colors.green.shade600, size: 20),
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
              Icon(Icons.error_outline, color: Colors.red.shade600, size: 24),
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
                icon: Icon(Icons.close, color: Colors.red.shade600, size: 20),
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
                        horizontal: 16,
                        vertical: 8,
                      ),
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
                        horizontal: 16,
                        vertical: 8,
                      ),
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
          // Title is required for all ad types including banner
          if (_titleController.text.trim().isEmpty) {
            setState(() {
              _isTitleValid = false;
              _titleError = 'Ad title is required';
            });
          } else {
            // Check word count for banner ads (max 30 words)
            if (_selectedAdType == 'banner') {
              final wordCount =
                  _titleController.text.trim().split(RegExp(r'\s+')).length;
              if (wordCount > 30) {
                setState(() {
                  _isTitleValid = false;
                  _titleError = 'Banner ad title must be 30 words or less';
                });
              } else {
                setState(() {
                  _isTitleValid = true;
                  _titleError = null;
                });
              }
            } else {
              setState(() {
                _isTitleValid = true;
                _titleError = null;
              });
            }
          }
          break;
        case 'description':
          // Skip description validation for banner ads
          if (_selectedAdType == 'banner') {
            setState(() {
              _isDescriptionValid = true;
              _descriptionError = null;
            });
          } else if (_descriptionController.text.trim().isEmpty) {
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
    final List<Map<String, dynamic>> validationItems = [];

    // Show title for all ad types (including banner)
    validationItems.add({
      'label': _selectedAdType == 'banner'
          ? 'Banner Title (max 30 words)'
          : 'Ad Title',
      'isValid': _titleController.text.trim().isNotEmpty &&
          (_selectedAdType != 'banner' ||
              _titleController.text.trim().split(RegExp(r'\s+')).length <= 30),
      'icon': Icons.title,
    });

    // Only show description for non-banner ads
    if (_selectedAdType != 'banner') {
      validationItems.add({
        'label': 'Description',
        'isValid': _descriptionController.text.trim().isNotEmpty,
        'icon': Icons.description,
      });
    }

    // Link URL is required for all ad types
    validationItems.add({
      'label': _selectedAdType == 'banner' ? 'Destination URL' : 'Link URL',
      'isValid': _linkController.text.trim().isNotEmpty,
      'icon': Icons.link,
    });

    // Budget, dates, and media are required for all ad types
    validationItems.addAll([
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
    ]);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Required Fields Checklist',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...validationItems.map(
              (item) => Padding(
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
              ),
            ),
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
      AppLogger.log('🔄 CreateAdScreen: Notifying video feed to refresh ads');
      AdRefreshNotifier().notifyRefresh();
      AppLogger.log('✅ CreateAdScreen: Video feed notification sent');
    } catch (e) {
      AppLogger.log('❌ Error notifying video feed refresh: $e');
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
          '❌ Media upload failed - no URLs returned. Please try selecting different media files.',
        );
      }

      // Step 2: Create ad with payment
      setState(() {
        _errorMessage = '💳 Creating advertisement...';
      });

      final result = await _adService.createAdWithPayment(
        // For banner ads, title and description are optional (use defaults)
        title: _selectedAdType == 'banner'
            ? (_titleController.text.trim().isEmpty
                ? 'Banner Ad'
                : _titleController.text.trim())
            : _titleController.text.trim(),
        description: _selectedAdType == 'banner'
            ? (_descriptionController.text.trim().isEmpty
                ? 'Click to learn more'
                : _descriptionController.text.trim())
            : _descriptionController.text.trim(),
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
        // **NEW: Advanced KPI parameters**
        bidType: _bidType,
        bidAmount: _bidAmount,
        pacing: _pacing,
        hourParting: _hourParting.isNotEmpty ? _hourParting : null,
        targetCPA: _targetCPA,
        targetROAS: _targetROAS,
        attributionWindow: _attributionWindow,
        // **NEW: Pass all carousel image URLs**
        imageUrls: _selectedAdType == 'carousel' && _selectedImages.isNotEmpty
            ? mediaUrls
            : null,
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
            // Show a fresh create-ad screen instead of popping back
            _showFreshAdScreen();
            // Trigger video feed refresh to show new ads
            _notifyVideoFeedRefresh();
          },
        );
      } else {
        throw Exception(
          '❌ Failed to create ad: ${result['message'] ?? 'Unknown error occurred. Please try again.'}',
        );
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

    // Check title (required for all ad types including banner)
    if (_titleController.text.trim().isEmpty) {
      setState(() {
        _isTitleValid = false;
        _titleError = 'Ad title is required';
        isValid = false;
      });
    } else {
      // Check word count for banner ads (max 30 words)
      if (_selectedAdType == 'banner') {
        final wordCount =
            _titleController.text.trim().split(RegExp(r'\s+')).length;
        if (wordCount > 30) {
          setState(() {
            _isTitleValid = false;
            _titleError = 'Banner ad title must be 30 words or less';
            isValid = false;
          });
        } else {
          setState(() {
            _isTitleValid = true;
            _titleError = null;
          });
        }
      } else {
        setState(() {
          _isTitleValid = true;
          _titleError = null;
        });
      }
    }

    // Check description (skip for banner ads)
    if (_selectedAdType != 'banner') {
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
      } else if (_startDate!.isBefore(
        DateTime.now().subtract(const Duration(days: 1)),
      )) {
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
        AppLogger.log('🔄 CreateAdScreen: Uploading banner image...');
        final imageUrl = await _cloudinaryService.uploadImage(_selectedImage!);
        mediaUrls.add(imageUrl);
        AppLogger.log('✅ CreateAdScreen: Banner image uploaded: $imageUrl');
      } else if (_selectedAdType == 'carousel') {
        if (_selectedImages.isNotEmpty) {
          AppLogger.log(
            '🔄 CreateAdScreen: Uploading ${_selectedImages.length} carousel images...',
          );
          for (int i = 0; i < _selectedImages.length; i++) {
            final image = _selectedImages[i];
            AppLogger.log(
              '🔄 CreateAdScreen: Uploading carousel image ${i + 1}/${_selectedImages.length}...',
            );
            final imageUrl = await _cloudinaryService.uploadImage(image);
            mediaUrls.add(imageUrl);
            AppLogger.log(
              '✅ CreateAdScreen: Carousel image ${i + 1} uploaded: $imageUrl',
            );
          }
        }
        if (_selectedVideo != null) {
          AppLogger.log('🔄 CreateAdScreen: Uploading carousel video...');
          AppLogger.log(
            '🔄 CreateAdScreen: Video file path: ${_selectedVideo!.path}',
          );
          AppLogger.log(
            '🔄 CreateAdScreen: Video file size: ${await _selectedVideo!.length()} bytes',
          );

          final result = await _cloudinaryService.uploadVideoForAd(
            _selectedVideo!,
          );
          AppLogger.log('🔄 CreateAdScreen: Video upload result: $result');

          final videoUrl =
              result['url'] ?? result['hls_urls']?['hls_stream'] ?? '';
          if (videoUrl.isEmpty) {
            throw Exception(
              'Video upload succeeded but no URL returned. Result: $result',
            );
          }
          mediaUrls.add(videoUrl);
          AppLogger.log('✅ CreateAdScreen: Carousel video uploaded: $videoUrl');
        }
      }

      AppLogger.log(
        '✅ CreateAdScreen: All media files uploaded successfully. Total URLs: ${mediaUrls.length}',
      );
      return mediaUrls;
    } catch (e) {
      AppLogger.log('❌ CreateAdScreen: Error uploading media files: $e');
      rethrow;
    }
  }

  String? _getImageUrl(List<String> mediaUrls) {
    if (_selectedAdType == 'banner' && _selectedImage != null) {
      return mediaUrls.first;
    } else if (_selectedAdType == 'carousel' && _selectedImages.isNotEmpty) {
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
    // **NEW: Clear advanced KPI fields**
    _bidType = 'CPM';
    _bidAmount = null;
    _pacing = 'smooth';
    _hourParting.clear();
    _targetCPA = null;
    _targetROAS = null;
    _attributionWindow = null;

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

    // **NEW: Clear saved form state**
    _clearSavedFormState();
  }

  /// **NEW: Clear saved form state from SharedPreferences**
  void _clearSavedFormState() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Clear all saved form data
      await prefs.remove('create_ad_title');
      await prefs.remove('create_ad_description');
      await prefs.remove('create_ad_link');
      await prefs.remove('create_ad_budget');
      await prefs.remove('create_ad_target_audience');
      await prefs.remove('create_ad_keywords');
      await prefs.remove('create_ad_type');
      await prefs.remove('create_ad_start_date');
      await prefs.remove('create_ad_end_date');
      await prefs.remove('create_ad_min_age');
      await prefs.remove('create_ad_max_age');
      await prefs.remove('create_ad_gender');
      await prefs.remove('create_ad_locations');
      await prefs.remove('create_ad_interests');
      await prefs.remove('create_ad_platforms');
      await prefs.remove('create_ad_device_type');
      await prefs.remove('create_ad_optimization_goal');
      await prefs.remove('create_ad_frequency_cap');
      await prefs.remove('create_ad_timezone');
      await prefs.remove('create_ad_day_parting_keys');
      await prefs.remove('create_ad_day_parting_values');

      AppLogger.log('✅ CreateAdScreen: Saved form state cleared');
    } catch (e) {
      AppLogger.log('❌ CreateAdScreen: Error clearing saved form state: $e');
    }
  }
}
