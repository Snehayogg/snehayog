import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vayu/core/design/theme.dart';
import 'package:vayu/core/design/colors.dart';
import 'package:vayu/core/design/typography.dart';
import 'package:vayu/core/design/elevation.dart';
import 'package:vayu/shared/widgets/app_button.dart';
import 'package:vayu/shared/services/city_search_service.dart';
import 'package:vayu/shared/constants/interests.dart';

/// **TargetingSectionWidget - Handles advanced targeting options**
class TargetingSectionWidget extends StatefulWidget {
  final int? minAge;
  final int? maxAge;
  final String selectedGender;
  final List<String> selectedLocations;
  final List<String> selectedInterests;
  final List<String> selectedPlatforms;
  // **NEW: Additional targeting parameters**
  final String? deviceType;
  final String? optimizationGoal;
  final int? frequencyCap;
  final String? timeZone;
  final Map<String, bool> dayParting;
  // **NEW: Advanced KPI parameters**
  final String? bidType; // 'CPM' or 'CPC'
  final double? bidAmount; // CPM or CPC bid amount
  final String? pacing; // 'smooth' or 'asap'
  final double? targetCPA; // Target Cost Per Acquisition
  final double? targetROAS; // Target Return on Ad Spend
  final int? attributionWindow; // Attribution window in days

  final Function(int?) onMinAgeChanged;
  final Function(int?) onMaxAgeChanged;
  final Function(String) onGenderChanged;
  final Function(List<String>) onLocationsChanged;
  final Function(List<String>) onInterestsChanged;
  final Function(List<String>) onPlatformsChanged;
  // **NEW: Additional targeting callbacks**
  final Function(String) onDeviceTypeChanged;
  final Function(String?) onOptimizationGoalChanged;
  final Function(int?) onFrequencyCapChanged;
  final Function(String?) onTimeZoneChanged;
  final Function(Map<String, bool>) onDayPartingChanged;
  // **NEW: Advanced KPI callbacks**
  final Function(String?) onBidTypeChanged;
  final Function(double?) onBidAmountChanged;
  final Function(String?) onPacingChanged;
  final Function(double?) onTargetCPAChanged;
  final Function(double?) onTargetROASChanged;
  final Function(int?) onAttributionWindowChanged;

  const TargetingSectionWidget({
    Key? key,
    required this.minAge,
    required this.maxAge,
    required this.selectedGender,
    required this.selectedLocations,
    required this.selectedInterests,
    required this.selectedPlatforms,
    // **NEW: Additional targeting parameters**
    this.deviceType,
    this.optimizationGoal,
    this.frequencyCap,
    this.timeZone,
    this.dayParting = const {},
    // **NEW: Advanced KPI parameters**
    this.bidType,
    this.bidAmount,
    this.pacing,
    this.targetCPA,
    this.targetROAS,
    this.attributionWindow,
    required this.onMinAgeChanged,
    required this.onMaxAgeChanged,
    required this.onGenderChanged,
    required this.onLocationsChanged,
    required this.onInterestsChanged,
    required this.onPlatformsChanged,
    // **NEW: Additional targeting callbacks**
    required this.onDeviceTypeChanged,
    required this.onOptimizationGoalChanged,
    required this.onFrequencyCapChanged,
    required this.onTimeZoneChanged,
    required this.onDayPartingChanged,
    // **NEW: Advanced KPI callbacks**
    required this.onBidTypeChanged,
    required this.onBidAmountChanged,
    required this.onPacingChanged,
    required this.onTargetCPAChanged,
    required this.onTargetROASChanged,
    required this.onAttributionWindowChanged,
  }) : super(key: key);

  @override
  State<TargetingSectionWidget> createState() => _TargetingSectionWidgetState();
}

class _TargetingSectionWidgetState extends State<TargetingSectionWidget> {
  final List<String> _genderOptions = ['all', 'male', 'female', 'other'];
  final List<String> _platformOptions = ['android', 'ios', 'web'];

  // **NEW: Additional targeting options**
  final List<String> _deviceTypeOptions = ['mobile', 'tablet', 'desktop'];
  final List<String> _optimizationGoalOptions = [
    'clicks',
    'impressions',
    'conversions',
  ];
  final List<String> _timeZoneOptions = [
    'Asia/Kolkata',
    'Asia/Dubai',
    'America/New_York',
    'Europe/London',
    'Asia/Singapore',
    'Australia/Sydney',
    'America/Los_Angeles',
  ];

  // **NEW: Advanced KPI options**
  final List<String> _bidTypeOptions = ['CPM', 'CPC'];
  final List<String> _pacingOptions = ['smooth', 'asap'];
  final List<int> _attributionWindowOptions = [1, 7, 14, 30];

  final List<String> _daysOfWeek = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  // **RESTORED: Location search functionality**
  final TextEditingController _locationSearchController =
      TextEditingController();
  final FocusNode _locationSearchFocusNode = FocusNode();
  List<Map<String, dynamic>> _locationSuggestions = [];
  bool _isSearchingLocations = false;
  bool _hasSearchText = false; // **FIXED: Track search text state separately**
  Timer? _searchDebouncer;
  late final ScrollController _locationSuggestionsController;

  void _handleLocationFocusChange() {
    if (!_locationSearchFocusNode.hasFocus) {
      if (_locationSuggestions.isNotEmpty) {
        setState(() {
          _locationSuggestions = [];
        });
      }
    }
  }

  // Popular Indian cities for quick selection
  final List<String> _popularLocations = [
    'All India',
    'Mumbai',
    'Delhi',
    'Bangalore',
    'Chennai',
    'Hyderabad',
    'Ahmedabad',
    'Lucknow',
    'Noida',
    'Indore',
  ];

  // Custom interest functionality
  final TextEditingController _customInterestController =
      TextEditingController();
  final List<String> _customInterests = [];

  final List<String> _interestOptions = kInterestOptions;

  @override
  void initState() {
    super.initState();
    _locationSuggestionsController = ScrollController();
    _locationSearchFocusNode.addListener(_handleLocationFocusChange);
    // **FIXED: Initialize state properly to prevent grey texture on first render**
    _locationSuggestions = [];
    _isSearchingLocations = false;
    _hasSearchText = false;

    // **FIXED: Use postFrameCallback to ensure widget is fully built before adding listener**
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _locationSearchController.addListener(_onLocationSearchChanged);
      }
    });
  }

  @override
  void dispose() {
    // **FIXED: Remove listener before disposing to prevent memory leaks**
    _locationSearchController.removeListener(_onLocationSearchChanged);
    _locationSearchFocusNode
      ..removeListener(_handleLocationFocusChange)
      ..dispose();
    _locationSearchController.dispose();
    _customInterestController.dispose();
    _searchDebouncer?.cancel();
    _locationSuggestionsController.dispose();
    super.dispose();
  }

  /// **RESTORED: Handle location search with debouncing**
  void _onLocationSearchChanged() {
    final query = _locationSearchController.text.trim();
    final hasText = query.isNotEmpty;

    // **FIXED: Update search text state**
    if (_hasSearchText != hasText) {
      setState(() {
        _hasSearchText = hasText;
      });
    }

    // Cancel previous search
    _searchDebouncer?.cancel();

    if (query.isEmpty || query.length < 3) {
      setState(() {
        _locationSuggestions = [];
        _isSearchingLocations = false;
      });
      return;
    }

    // Debounce search to avoid too many API calls
    _searchDebouncer = Timer(const Duration(milliseconds: 500), () {
      _searchLocationsWithAPI(query);
    });
  }

  /// **RESTORED: Search locations using API**
  Future<void> _searchLocationsWithAPI(String query) async {
    setState(() {
      _isSearchingLocations = true;
    });

    try {
      final results = await CitySearchService.searchCitiesDetailed(query);

      if (mounted) {
        setState(() {
          _locationSuggestions = results;
          _isSearchingLocations = false;
        });
      }
    } catch (e) {
      // Fallback to popular cities
      final fallbackResults = _getFallbackSuggestions(query);
      if (mounted) {
        setState(() {
          _locationSuggestions = fallbackResults;
          _isSearchingLocations = false;
        });
      }
    }
  }

  /// **RESTORED: Get fallback suggestions from popular cities**
  List<Map<String, dynamic>> _getFallbackSuggestions(String query) {
    final queryLower = query.toLowerCase();
    final suggestions = <Map<String, dynamic>>[];

    for (final city in _popularLocations) {
      if (city.toLowerCase().contains(queryLower)) {
        suggestions.add({
          'name': city,
          'state': city == 'All India' ? 'India' : 'Various States',
          'displayName': city,
          'lat': '0',
          'lon': '0',
        });
      }
    }

    return suggestions;
  }

  /// **RESTORED: Add location from API suggestions**
  void _addLocationFromAPI(Map<String, dynamic> location) {
    final locationName = '${location['name']}, ${location['state']}, India';

    if (!widget.selectedLocations.contains(locationName)) {
      final updatedLocations = List<String>.from(widget.selectedLocations);
      updatedLocations.add(locationName);
      widget.onLocationsChanged(updatedLocations);

      // Clear search
      _locationSearchController.clear();
      if (mounted) {
        setState(() {
          _locationSuggestions = [];
        });
      }
      setState(() {
        _locationSuggestions = [];
      });
    }
  }

  /// **RESTORED: Add popular location**
  void _addPopularLocation(String location) {
    if (!widget.selectedLocations.contains(location)) {
      final updatedLocations = List<String>.from(widget.selectedLocations);
      updatedLocations.add(location);
      widget.onLocationsChanged(updatedLocations);
    }
  }

  void _addCustomInterest() {
    final interest = _customInterestController.text.trim();
    if (interest.isNotEmpty && !_customInterests.contains(interest)) {
      setState(() {
        _customInterests.add(interest);
        _customInterestController.clear();
      });

      // Add to selected interests
      final updatedInterests = List<String>.from(widget.selectedInterests);
      if (!updatedInterests.contains(interest)) {
        updatedInterests.add(interest);
        widget.onInterestsChanged(updatedInterests);
      }
    }
  }

  void _removeCustomInterest(String interest) {
    setState(() {
      _customInterests.remove(interest);
    });

    // Remove from selected interests
    final updatedInterests = List<String>.from(widget.selectedInterests);
    updatedInterests.remove(interest);
    widget.onInterestsChanged(updatedInterests);
  }

  @override
  Widget build(BuildContext context) {
    // **FIXED: Wrap in Container with explicit constraints to prevent grey texture on first render**
    return Container(
      constraints: BoxConstraints(
        minHeight: 0,
        maxHeight: double.infinity,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.gps_fixed, color: AppColors.primary),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Advanced Targeting',
                  style: AppTypography.headlineSmall.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),

          // Age Range
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: widget.minAge,
                  decoration: InputDecoration(
                    labelText: 'Min Age',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                  items: List.generate(53, (index) => index + 13)
                      .map(
                        (age) =>
                            DropdownMenuItem(value: age, child: Text('$age')),
                      )
                      .toList(),
                  onChanged: (value) {
                    widget.onMinAgeChanged(value);
                    if (widget.maxAge != null &&
                        value != null &&
                        value > widget.maxAge!) {
                      widget.onMaxAgeChanged(value);
                    }
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: widget.maxAge,
                  decoration: const InputDecoration(
                    labelText: 'Max Age',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  items: List.generate(53, (index) => index + 13)
                      .where(
                        (age) => widget.minAge == null || age >= widget.minAge!,
                      )
                      .map(
                        (age) =>
                            DropdownMenuItem(value: age, child: Text('$age')),
                      )
                      .toList(),
                  onChanged: widget.onMaxAgeChanged,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),

          // Gender Selection
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _genderOptions.contains(widget.selectedGender) ? widget.selectedGender : 'all',
            decoration: const InputDecoration(
              labelText: 'Gender',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.wc),
            ),
            items: _genderOptions.map((gender) {
              return DropdownMenuItem(
                value: gender,
                child: Text(gender.toUpperCase()),
              );
            }).toList(),
            onChanged: (value) => widget.onGenderChanged(value!),
          ),
          SizedBox(height: 16),

          // **RESTORED: Location Targeting with Search**
          _buildLocationFieldWithSearch(),
          SizedBox(height: 16),

          // Interests Selection
          _buildInterestsField(),
          SizedBox(height: 16),

          // Platform Targeting
          _buildMultiSelectField(
            'Platforms',
            widget.selectedPlatforms,
            _platformOptions,
            Icons.phone_android,
            'Select target platforms',
            widget.onPlatformsChanged,
          ),
          SizedBox(height: 16),

          // **NEW: Device Type**
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _deviceTypeOptions.contains(widget.deviceType) ? widget.deviceType : 'all',
            decoration: InputDecoration(
              labelText: 'Device Type',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.devices),
              helperText: 'Target specific device types',
            ),
            items: [
              const DropdownMenuItem(value: 'all', child: Text('All Devices')),
              ..._deviceTypeOptions.map(
                (type) => DropdownMenuItem(
                  value: type,
                  child: Text(type.toUpperCase()),
                ),
              ),
            ],
            onChanged: (value) => widget.onDeviceTypeChanged(value ?? 'all'),
          ),
          SizedBox(height: 16),

          // **NEW: Advanced Campaign Settings**
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.settings, color: AppColors.primary),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Advanced Campaign Settings',
                          style: AppTypography.headlineSmall.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),

                  // Optimization Goal
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: (widget.optimizationGoal == null || _optimizationGoalOptions.contains(widget.optimizationGoal)) 
                        ? widget.optimizationGoal 
                        : 'impressions',
                    decoration: InputDecoration(
                      labelText: 'Optimization Goal',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.track_changes),
                      helperText: 'What to optimize for',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Auto Optimize'),
                      ),
                      ..._optimizationGoalOptions.map(
                        (goal) => DropdownMenuItem(
                          value: goal,
                          child: Text(goal.toUpperCase()),
                        ),
                      ),
                    ],
                    onChanged: widget.onOptimizationGoalChanged,
                  ),
                  SizedBox(height: 16),

                  // Frequency Cap
                  TextFormField(
                    initialValue: widget.frequencyCap?.toString(),
                    decoration: InputDecoration(
                      labelText: 'Frequency Cap',
                      hintText: '3',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.repeat),
                      helperText: 'Max times shown to same user per day',
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      final cap = int.tryParse(value.trim());
                      widget.onFrequencyCapChanged(cap);
                    },
                  ),
                  SizedBox(height: 16),

                  // Time Zone
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: (widget.timeZone == null || _timeZoneOptions.contains(widget.timeZone)) 
                        ? widget.timeZone 
                        : 'Asia/Kolkata',
                    decoration: InputDecoration(
                      labelText: 'Time Zone',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.schedule),
                      helperText: 'Campaign scheduling timezone',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Auto (User Timezone)'),
                      ),
                      ..._timeZoneOptions.map(
                        (tz) => DropdownMenuItem(
                          value: tz,
                          child: Text(tz.replaceAll('_', ' ')),
                        ),
                      ),
                    ],
                    onChanged: widget.onTimeZoneChanged,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 16),

          // **NEW: Bidding & Performance KPIs Section**
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.trending_up, color: AppColors.warning),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Bidding & Performance KPIs',
                          style: AppTypography.headlineSmall.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),

                  // Bid Strategy & Amount
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                          initialValue: _bidTypeOptions.contains(widget.bidType) ? widget.bidType : 'CPM',
                          decoration: InputDecoration(
                            labelText: 'Bid Strategy',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.attach_money),
                            helperText: 'How you want to bid',
                          ),
                          items: _bidTypeOptions
                              .map(
                                (type) => DropdownMenuItem(
                                  value: type,
                                  child: Text(type),
                                ),
                              )
                              .toList(),
                          onChanged: widget.onBidTypeChanged,
                        ),
                        SizedBox(height: 16),
                      Builder(
                          builder: (context) {
                            final bidType = widget.bidType ?? 'CPM';
                            return TextFormField(
                              key: ValueKey(
                                bidType,
                              ), // Rebuild when bid type changes
                              initialValue: widget.bidAmount?.toString(),
                              decoration: InputDecoration(
                                labelText: bidType == 'CPC'
                                    ? 'Max CPC (₹)'
                                    : 'CPM Bid (₹)',
                                hintText: bidType == 'CPC' ? '5.00' : '30.00',
                                border: OutlineInputBorder(),
                                prefixText: '₹',
                                helperText: bidType == 'CPC'
                                    ? 'Max cost per click'
                                    : 'Cost per 1000 impressions',
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (value) {
                                final amount = double.tryParse(value.trim());
                                widget.onBidAmountChanged(amount);
                              },
                            );
                          },
                        ),
                      SizedBox(height: 16),
                    ],
                  ),
                  SizedBox(height: 16),

                  // Budget Pacing
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: widget.pacing ?? 'smooth',
                    decoration: InputDecoration(
                      labelText: 'Budget Pacing',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.speed),
                      helperText: 'How budget is spent over time',
                    ),
                    items: _pacingOptions.map((pacing) {
                      return DropdownMenuItem(
                        value: pacing,
                        child: Text(
                          pacing == 'smooth'
                              ? 'Smooth (Even distribution)'
                              : 'Accelerated (Spend quickly)',
                        ),
                      );
                    }).toList(),
                    onChanged: widget.onPacingChanged,
                  ),
                  SizedBox(height: 16),

                  // Target CPA
                  TextFormField(
                    initialValue: widget.targetCPA?.toString(),
                    decoration: InputDecoration(
                      labelText: 'Target CPA (₹)',
                      hintText: '500.00',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.account_balance_wallet),
                      helperText: 'Target cost per acquisition (optional)',
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      final cpa = double.tryParse(value.trim());
                      widget.onTargetCPAChanged(cpa);
                    },
                  ),
                  SizedBox(height: 16),

                  // Target ROAS
                  TextFormField(
                    initialValue: widget.targetROAS?.toString(),
                    decoration: InputDecoration(
                      labelText: 'Target ROAS',
                      hintText: '3.0',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.monetization_on),
                      helperText:
                          'Target return on ad spend (e.g., 3.0 = 3x return)',
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      final roas = double.tryParse(value.trim());
                      widget.onTargetROASChanged(roas);
                    },
                  ),
                  SizedBox(height: 16),

                  // Attribution Window
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    initialValue: widget.attributionWindow,
                    decoration: InputDecoration(
                      labelText: 'Attribution Window',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.access_time),
                      helperText: 'Conversion attribution period',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Default (7 days)'),
                      ),
                      ..._attributionWindowOptions.map(
                        (days) => DropdownMenuItem(
                          value: days,
                          child: Text('$days day${days > 1 ? 's' : ''}'),
                        ),
                      ),
                    ],
                    onChanged: widget.onAttributionWindowChanged,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 16),

          _buildDayPartingSection(),
        ],
      ),
    );
  }

  Widget _buildInterestsField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Interests',
          style: AppTypography.headlineSmall.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: AppColors.white,
          ),
        ),
        SizedBox(height: 8),
        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Selected interests display
              if (widget.selectedInterests.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.selectedInterests.map((interest) {
                    final isCustom = _customInterests.contains(interest);
                    return Chip(
                      label: Text(interest),
                      deleteIcon: Icon(Icons.close, size: 18),
                      onDeleted: () {
                        if (isCustom) {
                          _removeCustomInterest(interest);
                        } else {
                          final newItems = List<String>.from(
                            widget.selectedInterests,
                          )..remove(interest);
                          widget.onInterestsChanged(newItems);
                        }
                      },
                      backgroundColor: isCustom
                          ? AppColors.success.withValues(alpha: 0.1)
                          : AppColors.primary.withValues(alpha: 0.1),
                      labelStyle: TextStyle(
                        color: isCustom
                            ? AppColors.success
                            : AppColors.primary,
                      ),
                    );
                  }).toList(),
                ),
                SizedBox(height: 12),
              ],

              // Predefined interests button
              AppButton(
                onPressed: () => _showMultiSelectDialog(
                  'Interests',
                  widget.selectedInterests,
                  _interestOptions,
                  widget.onInterestsChanged,
                ),
                icon: Icon(Icons.favorite, size: 18),
                label: widget.selectedInterests.isEmpty
                      ? 'Select Interests'
                      : 'Add More',
                variant: AppButtonVariant.outline,
                size: AppButtonSize.small,
              ),

              SizedBox(height: 12),

              // Custom interest input
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _customInterestController,
                      decoration: InputDecoration(
                        hintText: 'Add custom interest...',
                        prefixIcon: Icon(Icons.add_circle_outline),
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      onSubmitted: (_) => _addCustomInterest(),
                    ),
                  ),
                  SizedBox(width: 8),
                  AppButton(
                    onPressed: _addCustomInterest,
                    icon: Icon(Icons.add, size: 18),
                    label: 'Add',
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.small,
                  ),
                ],
              ),

              // Custom interests info
              if (_customInterests.isNotEmpty) ...[
                SizedBox(height: 8),
                Text(
                  'Custom Interests: ${_customInterests.join(', ')}',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.success,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMultiSelectField(
    String label,
    List<String> selectedItems,
    List<String> options,
    IconData icon,
    String hint,
    Function(List<String>) onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.headlineSmall.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: AppColors.white,
          ),
        ),
        SizedBox(height: 8),
        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Selected items display
              if (selectedItems.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: selectedItems.map((item) {
                    return Chip(
                      label: Text(item),
                      deleteIcon: Icon(Icons.close, size: 18),
                      onDeleted: () {
                        final newItems = List<String>.from(selectedItems)
                          ..remove(item);
                        onChanged(newItems);
                      },
                      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                      labelStyle: TextStyle(color: AppColors.primary),
                    );
                  }).toList(),
                ),
                SizedBox(height: 12),
              ],

              // Add button
              AppButton(
                onPressed: () => _showMultiSelectDialog(
                  label,
                  selectedItems,
                  options,
                  onChanged,
                ),
                icon: Icon(icon, size: 18),
                label: selectedItems.isEmpty ? hint : 'Add More',
                variant: AppButtonVariant.outline,
                size: AppButtonSize.small,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// **RESTORED: Location field with search (simplified to avoid layout bugs)**
  Widget _buildLocationFieldWithSearch() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min, // **FIXED: Prevent unbounded height**
      children: [
        Row(
          children: [
            Icon(Icons.location_on, color: AppColors.primary, size: 20),
            SizedBox(width: 8),
            Text(
              'Target Locations (India)',
              style: AppTypography.headlineSmall.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppColors.white,
              ),
            ),
          ],
        ),
        SizedBox(height: 12),

        // Selected locations display
        if (widget.selectedLocations.isNotEmpty) ...[
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.backgroundTertiary),
              borderRadius: BorderRadius.circular(8),
              color: AppColors.backgroundSecondary,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Selected Locations:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textTertiary,
                  ),
                ),
                SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.selectedLocations.map((location) {
                    return Chip(
                      label: Text(
                        location,
                        style: TextStyle(fontSize: 12),
                      ),
                      deleteIcon: Icon(Icons.close, size: 16),
                      onDeleted: () {
                        final newItems = List<String>.from(
                          widget.selectedLocations,
                        )..remove(location);
                        widget.onLocationsChanged(newItems);
                      },
                      backgroundColor: AppColors.success.withValues(alpha: 0.1),
                      labelStyle: TextStyle(color: AppColors.success),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          SizedBox(height: 12),
        ],

        // **FIXED: Simple search input with manual dropdown (avoids Autocomplete rendering bugs)**
        TextField(
          controller: _locationSearchController,
          focusNode: _locationSearchFocusNode,
          decoration: InputDecoration(
            hintText: 'Type city name (e.g., Mumbai, Delhi)...',
            prefixIcon: Icon(Icons.search, color: AppColors.primary),
            suffixIcon: _isSearchingLocations
                ? Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                      ),
                    ),
                  )
                : _hasSearchText
                    ? IconButton(
                        icon: Icon(Icons.clear, color: AppColors.textTertiary),
                        onPressed: () {
                          _locationSearchController.clear();
                          setState(() {
                            _locationSuggestions = [];
                            _hasSearchText = false;
                          });
                        },
                      )
                    : Icon(Icons.location_on_outlined,
                        color: Colors.grey),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.backgroundTertiary),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.backgroundTertiary),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
            filled: true,
            fillColor: AppColors.backgroundSecondary,
            contentPadding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            helperText:
                'Start typing (3+ characters) to see location suggestions',
          ),
        ),

        // **FIXED: Show suggestions dropdown only when there are suggestions**
        // **FIXED: Use SizedBox with explicit height to prevent grey texture bug**
        if (_locationSuggestions.isNotEmpty) ...[
          SizedBox(height: 8),
          SizedBox(
            height: _locationSuggestions.length > 5
                ? 200
                : (_locationSuggestions.length * 56.0).clamp(0.0, 200.0),
            child: Container(
              decoration: BoxDecoration(
              color: AppColors.backgroundSecondary,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.backgroundTertiary),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: NotificationListener<OverscrollIndicatorNotification>(
                  onNotification: (notification) {
                    notification.disallowIndicator();
                    return true;
                  },
                  child: ListView.separated(
                    controller: _locationSuggestionsController,
                    primary: false,
                    shrinkWrap: true,
                    physics: _locationSuggestions.length > 5
                        ? const ClampingScrollPhysics()
                        : const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    itemCount: _locationSuggestions.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      thickness: 1,
                      color: AppColors.backgroundTertiary,
                    ),
                    itemBuilder: (context, index) {
                      final location = _locationSuggestions[index];
                      final locationName =
                          '${location['name']}, ${location['state']}, India';
                      final isAlreadySelected =
                          widget.selectedLocations.contains(
                        locationName,
                      );

                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        leading: Icon(
                          Icons.location_city,
                          color: isAlreadySelected
                              ? AppColors.textTertiary
                              : AppColors.primary,
                          size: 20,
                        ),
                        title: Text(
                          location['name'] ?? '',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: isAlreadySelected
                                ? AppColors.textTertiary
                                : AppColors.white,
                          ),
                        ),
                        subtitle: Text(
                          '${location['state'] ?? ''}, India',
                          style: TextStyle(
                            fontSize: 12,
                            color: isAlreadySelected
                                ? AppColors.textTertiary
                                : AppColors.textSecondary,
                          ),
                        ),
                        trailing: isAlreadySelected
                            ? Icon(
                                Icons.check,
                                color: Colors.green.shade600,
                                size: 20,
                              )
                            : Icon(
                                Icons.add,
                                color: AppColors.primary,
                                size: 20,
                              ),
                        enabled: !isAlreadySelected,
                        onTap: isAlreadySelected
                            ? null
                            : () {
                                _addLocationFromAPI(location);
                              },
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],

        // Popular Indian locations for quick selection
        SizedBox(height: 16),
        Text(
          'Popular Indian Cities:',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textTertiary,
          ),
        ),
        SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _popularLocations.map((location) {
              final isSelected = widget.selectedLocations.contains(location);
              return Padding(
                padding: EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(
                    location,
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected ? AppColors.white : AppColors.primary,
                    ),
                  ),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      _addPopularLocation(location);
                    } else {
                      final newItems = List<String>.from(
                        widget.selectedLocations,
                      )..remove(location);
                      widget.onLocationsChanged(newItems);
                    }
                  },
                  selectedColor: AppColors.primary,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.05),
                  checkmarkColor: AppColors.white,
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  void _showMultiSelectDialog(
    String title,
    List<String> selectedItems,
    List<String> options,
    Function(List<String>) onChanged,
  ) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Select $title'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: ListView.builder(
              itemCount: options.length,
              itemBuilder: (context, index) {
                final option = options[index];
                final isSelected = selectedItems.contains(option);

                // Handle "Custom Interest" option specially
                if (option == 'Custom Interest') {
                  return ListTile(
                    title: Text(
                      option,
                      style: TextStyle(
                        color: AppColors.success,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    leading: Icon(
                      Icons.add_circle_outline,
                      color: AppColors.success,
                    ),
                    trailing: Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      Navigator.pop(context);
                      _showCustomInterestDialog();
                    },
                  );
                }

                return CheckboxListTile(
                  title: Text(option),
                  value: isSelected,
                  onChanged: (value) {
                    setDialogState(() {
                      if (value == true) {
                        selectedItems.add(option);
                      } else {
                        selectedItems.remove(option);
                      }
                    });
                  },
                );
              },
            ),
          ),
          actions: [
            AppButton(
              onPressed: () => Navigator.pop(context),
              label: 'Cancel',
              variant: AppButtonVariant.text,
            ),
            AppButton(
              onPressed: () {
                onChanged(List<String>.from(selectedItems));
                Navigator.pop(context);
              },
              label: 'Done',
              variant: AppButtonVariant.primary,
            ),
          ],
        ),
      ),
    );
  }

  void _showCustomInterestDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add Custom Interest'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _customInterestController,
              decoration: InputDecoration(
                hintText: 'Enter your custom interest...',
                prefixIcon: Icon(Icons.add_circle_outline),
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              onSubmitted: (_) {
                _addCustomInterest();
                Navigator.pop(context);
              },
            ),
            SizedBox(height: 16),
            Text(
              'This will be added to your selected interests and can be used for targeting.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          AppButton(
            onPressed: () => Navigator.pop(context),
            label: 'Cancel',
            variant: AppButtonVariant.text,
          ),
          AppButton(
            onPressed: () {
              _addCustomInterest();
              Navigator.pop(context);
            },
            label: 'Add Interest',
            variant: AppButtonVariant.primary,
          ),
        ],
      ),
    );
  }

  // **NEW: Day Parting Section**
  Widget _buildDayPartingSection() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_today, color: AppColors.primary),
                SizedBox(width: 8),
                Text(
                  'Day Targeting',
                  style: AppTypography.headlineSmall.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.white,
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            Text(
              'Select which days of the week to show ads:',
              style: TextStyle(fontSize: 14, color: AppColors.textTertiary),
            ),
            SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _daysOfWeek.map((day) {
                final isSelected = widget.dayParting[day] ?? false;
                return FilterChip(
                  label: Text(day.substring(0, 3)),
                  selected: isSelected,
                  onSelected: (selected) {
                    final newDayParting = Map<String, bool>.from(
                      widget.dayParting,
                    );
                    newDayParting[day] = selected;
                    widget.onDayPartingChanged(newDayParting);
                  },
                  selectedColor: AppColors.primary.withValues(alpha: 0.2),
                  checkmarkColor: AppColors.primary,
                );
              }).toList(),
            ),
            SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                AppButton(
                  onPressed: () {
                    final allSelected = Map<String, bool>.fromEntries(
                      _daysOfWeek.map((day) => MapEntry(day, true)),
                    );
                    widget.onDayPartingChanged(allSelected);
                  },
                  icon: Icon(Icons.select_all, size: 16),
                  label: 'All Days',
                  variant: AppButtonVariant.text,
                  size: AppButtonSize.small,
                ),
                AppButton(
                  onPressed: () {
                    final weekdaysSelected = Map<String, bool>.fromEntries(
                      _daysOfWeek.map(
                        (day) => MapEntry(
                          day,
                          !['Saturday', 'Sunday'].contains(day),
                        ),
                      ),
                    );
                    widget.onDayPartingChanged(weekdaysSelected);
                  },
                  icon: Icon(Icons.business, size: 16),
                  label: 'Weekdays',
                  variant: AppButtonVariant.text,
                  size: AppButtonSize.small,
                ),
                AppButton(
                  onPressed: () {
                    widget.onDayPartingChanged({});
                  },
                  icon: Icon(Icons.clear, size: 16),
                  label: 'Clear',
                  variant: AppButtonVariant.text,
                  size: AppButtonSize.small,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
