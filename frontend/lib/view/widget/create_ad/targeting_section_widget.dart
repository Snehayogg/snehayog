import 'dart:async';
import 'package:flutter/material.dart';
import 'package:snehayog/services/city_search_service.dart';
import 'package:snehayog/core/constants/interests.dart';

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
  final Map<String, String> hourParting;

  final Function(int?) onMinAgeChanged;
  final Function(int?) onMaxAgeChanged;
  final Function(String) onGenderChanged;
  final Function(List<String>) onLocationsChanged;
  final Function(List<String>) onInterestsChanged;
  final Function(List<String>) onPlatformsChanged;
  // **NEW: Additional targeting callbacks**
  final Function(String?) onDeviceTypeChanged;
  final Function(String?) onOptimizationGoalChanged;
  final Function(int?) onFrequencyCapChanged;
  final Function(String?) onTimeZoneChanged;
  final Function(Map<String, bool>) onDayPartingChanged;
  final Function(Map<String, String>) onHourPartingChanged;

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
    this.hourParting = const {},
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
    required this.onHourPartingChanged,
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
    'conversions'
  ];
  final List<String> _timeZoneOptions = [
    'Asia/Kolkata',
    'Asia/Dubai',
    'America/New_York',
    'Europe/London',
    'Asia/Singapore',
    'Australia/Sydney',
    'America/Los_Angeles'
  ];

  final List<String> _daysOfWeek = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday'
  ];

  // **ENHANCED: Professional location search functionality**
  final TextEditingController _locationSearchController =
      TextEditingController();
  List<Map<String, dynamic>> _locationSuggestions = [];
  bool _isSearchingLocations = false;
  Timer? _searchDebouncer;

  // Custom interest functionality
  final TextEditingController _customInterestController =
      TextEditingController();
  final List<String> _customInterests = [];

  // **NEW: Popular quick-select locations for convenience**
  final List<String> _popularLocations = [
    'All India',
    'Delhi',
    'Mumbai',
    'Bangalore',
    'Chennai',
    'Kolkata',
    'Hyderabad',
    'Pune',
    'Ahmedabad',
    'Jaipur',
    'Surat',
    'Lucknow',
    'Kanpur',
    'Nagpur',
    'Indore',
    'Thane',
    'Bhopal',
    'Visakhapatnam',
    'Patna',
    'Vadodara',
    'Ghaziabad',
    'Ludhiana',
    'Agra',
    'Nashik',
    'Faridabad',
    'Meerut',
    'Rajkot',
    'Varanasi',
    'Srinagar',
    'Aurangabad',
    'Navi Mumbai',
    'Solapur',
    'Vijayawada',
    'Kolhapur',
    'Amritsar',
    'Noida',
    'Ranchi',
    'Howrah',
    'Coimbatore',
    'Raipur',
    'Jabalpur',
    'Gwalior',
    'Chandigarh',
    'Tiruchirappalli',
    'Mysore',
    'Bhubaneswar',
    'Kochi',
    'Bhavnagar',
    'Salem',
    'Warangal',
    'Guntur',
    'Bhiwandi',
    'Amravati',
    'Nanded',
    'Sangli',
    'Malegaon',
    'Ulhasnagar',
    'Jalgaon',
    'Latur',
    'Ahmadnagar',
    'Dhule',
    'Ichalkaranji',
    'Parbhani',
    'Jalna',
    'Bhusawal',
    'Panvel',
    'Satara',
    'Beed',
    'Yavatmal',
    'Kamptee',
    'Gondia',
    'Barshi',
    'Achalpur',
    'Osmanabad',
    'Nandurbar',
    'Wardha',
    'Udgir',
    'Hinganghat'
  ];

  // All available locations (major cities + searched cities)
  final List<String> _locationOptions = [];
  final List<String> _interestOptions = kInterestOptions;

  @override
  void initState() {
    super.initState();
    _locationSearchController.addListener(_onLocationSearchChanged);
  }

  @override
  void dispose() {
    _locationSearchController.dispose();
    _customInterestController.dispose();
    _searchDebouncer?.cancel();
    super.dispose();
  }

  /// **NEW: Handle location search with debouncing**
  void _onLocationSearchChanged() {
    final query = _locationSearchController.text.trim();

    // Cancel previous search
    _searchDebouncer?.cancel();

    if (query.isEmpty) {
      setState(() {
        _locationSuggestions = [];
        _isSearchingLocations = false;
      });
      return;
    }

    if (query.length < 3) {
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

  /// **NEW: Search locations using professional API**
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
      print('❌ Error searching locations: $e');
      if (mounted) {
        setState(() {
          _locationSuggestions = [];
          _isSearchingLocations = false;
        });
      }
    }
  }

  /// **NEW: Add location from API suggestions**
  void _addLocationFromAPI(Map<String, dynamic> location) {
    final locationName = '${location['name']}, ${location['state']}, India';

    if (!widget.selectedLocations.contains(locationName)) {
      final updatedLocations = List<String>.from(widget.selectedLocations);
      updatedLocations.add(locationName);
      widget.onLocationsChanged(updatedLocations);

      // Clear search
      _locationSearchController.clear();
      setState(() {
        _locationSuggestions = [];
      });
    }
  }

  /// **NEW: Add popular location**
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.gps_fixed, color: Colors.blue.shade600),
            const SizedBox(width: 8),
            const Text(
              'Advanced Targeting',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Age Range
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: widget.minAge,
                decoration: const InputDecoration(
                  labelText: 'Min Age',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                items: List.generate(53, (index) => index + 13)
                    .map((age) => DropdownMenuItem(
                          value: age,
                          child: Text('$age'),
                        ))
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
                        (age) => widget.minAge == null || age >= widget.minAge!)
                    .map((age) => DropdownMenuItem(
                          value: age,
                          child: Text('$age'),
                        ))
                    .toList(),
                onChanged: widget.onMaxAgeChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Gender Selection
        DropdownButtonFormField<String>(
          initialValue: widget.selectedGender,
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
        const SizedBox(height: 16),

        // Location Targeting with Search
        _buildLocationFieldWithSearch(),
        const SizedBox(height: 16),

        // Interests Selection
        _buildInterestsField(),
        const SizedBox(height: 16),

        // Platform Targeting
        _buildMultiSelectField(
          'Platforms',
          widget.selectedPlatforms,
          _platformOptions,
          Icons.phone_android,
          'Select target platforms',
          widget.onPlatformsChanged,
        ),
        const SizedBox(height: 16),

        // **NEW: Device Type**
        DropdownButtonFormField<String>(
          initialValue: widget.deviceType,
          decoration: const InputDecoration(
            labelText: 'Device Type',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.devices),
            helperText: 'Target specific device types',
          ),
          items: [
            const DropdownMenuItem(value: null, child: Text('All Devices')),
            ..._deviceTypeOptions.map((type) => DropdownMenuItem(
                  value: type,
                  child: Text(type.toUpperCase()),
                )),
          ],
          onChanged: widget.onDeviceTypeChanged,
        ),
        const SizedBox(height: 16),

        // **NEW: Advanced Campaign Settings**
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.settings, color: Colors.green.shade600),
                    const SizedBox(width: 8),
                    const Text(
                      'Advanced Campaign Settings',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Optimization Goal
                DropdownButtonFormField<String>(
                  initialValue: widget.optimizationGoal,
                  decoration: const InputDecoration(
                    labelText: 'Optimization Goal',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.track_changes),
                    helperText: 'What to optimize for',
                  ),
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('Auto Optimize')),
                    ..._optimizationGoalOptions.map((goal) => DropdownMenuItem(
                          value: goal,
                          child: Text(goal.toUpperCase()),
                        )),
                  ],
                  onChanged: widget.onOptimizationGoalChanged,
                ),
                const SizedBox(height: 16),

                // Frequency Cap
                TextFormField(
                  initialValue: widget.frequencyCap?.toString(),
                  decoration: const InputDecoration(
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
                const SizedBox(height: 16),

                // Time Zone
                DropdownButtonFormField<String>(
                  initialValue: widget.timeZone,
                  decoration: const InputDecoration(
                    labelText: 'Time Zone',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.schedule),
                    helperText: 'Campaign scheduling timezone',
                  ),
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('Auto (User Timezone)')),
                    ..._timeZoneOptions.map((tz) => DropdownMenuItem(
                          value: tz,
                          child: Text(tz.replaceAll('_', ' ')),
                        )),
                  ],
                  onChanged: widget.onTimeZoneChanged,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // **NEW: Day Parting (Days of Week)**
        _buildDayPartingSection(),
        const SizedBox(height: 16),

        // **NEW: Hour Parting**
        _buildHourPartingSection(),
      ],
    );
  }

  Widget _buildInterestsField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Interests',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
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
                      deleteIcon: const Icon(Icons.close, size: 18),
                      onDeleted: () {
                        if (isCustom) {
                          _removeCustomInterest(interest);
                        } else {
                          final newItems =
                              List<String>.from(widget.selectedInterests)
                                ..remove(interest);
                          widget.onInterestsChanged(newItems);
                        }
                      },
                      backgroundColor: isCustom
                          ? Colors.green.shade100
                          : Colors.blue.shade100,
                      labelStyle: TextStyle(
                        color: isCustom
                            ? Colors.green.shade800
                            : Colors.blue.shade800,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
              ],

              // Predefined interests button
              ElevatedButton.icon(
                onPressed: () => _showMultiSelectDialog(
                    'Interests',
                    widget.selectedInterests,
                    _interestOptions,
                    widget.onInterestsChanged),
                icon: const Icon(Icons.favorite, size: 18),
                label: Text(widget.selectedInterests.isEmpty
                    ? 'Select Interests'
                    : 'Add More'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade50,
                  foregroundColor: Colors.blue.shade700,
                  elevation: 0,
                ),
              ),

              const SizedBox(height: 12),

              // Custom interest input
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _customInterestController,
                      decoration: const InputDecoration(
                        hintText: 'Add custom interest...',
                        prefixIcon: Icon(Icons.add_circle_outline),
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onSubmitted: (_) => _addCustomInterest(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _addCustomInterest,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade50,
                      foregroundColor: Colors.green.shade700,
                      elevation: 0,
                    ),
                  ),
                ],
              ),

              // Custom interests info
              if (_customInterests.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Custom Interests: ${_customInterests.join(', ')}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.green.shade600,
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
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
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
                      deleteIcon: const Icon(Icons.close, size: 18),
                      onDeleted: () {
                        final newItems = List<String>.from(selectedItems)
                          ..remove(item);
                        onChanged(newItems);
                      },
                      backgroundColor: Colors.blue.shade100,
                      labelStyle: TextStyle(color: Colors.blue.shade800),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
              ],

              // Add button
              ElevatedButton.icon(
                onPressed: () => _showMultiSelectDialog(
                    label, selectedItems, options, onChanged),
                icon: Icon(icon, size: 18),
                label: Text(selectedItems.isEmpty ? hint : 'Add More'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade50,
                  foregroundColor: Colors.blue.shade700,
                  elevation: 0,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLocationFieldWithSearch() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.location_on, color: Colors.blue.shade600, size: 20),
            const SizedBox(width: 8),
            const Text(
              'Target Locations',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Selected locations display
        if (widget.selectedLocations.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
              color: Colors.grey.shade50,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Selected Locations:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.selectedLocations.map((location) {
                    return Chip(
                      label: Text(
                        location,
                        style: const TextStyle(fontSize: 12),
                      ),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      onDeleted: () {
                        final newItems =
                            List<String>.from(widget.selectedLocations)
                              ..remove(location);
                        widget.onLocationsChanged(newItems);
                      },
                      backgroundColor: Colors.green.shade100,
                      labelStyle: TextStyle(color: Colors.green.shade800),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // **NEW: Professional search input with API integration**
        Stack(
          children: [
            TextField(
              controller: _locationSearchController,
              decoration: InputDecoration(
                hintText: 'Type city name (e.g., Mumbai, Delhi, Bangalore)...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _isSearchingLocations
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _locationSearchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _locationSearchController.clear();
                              setState(() {
                                _locationSuggestions = [];
                              });
                            },
                          )
                        : null,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
            ),

            // **NEW: Professional API suggestions dropdown**
            if (_locationSuggestions.isNotEmpty)
              Positioned(
                top: 60,
                left: 0,
                right: 0,
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 300),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _locationSuggestions.length,
                      itemBuilder: (context, index) {
                        final location = _locationSuggestions[index];
                        final locationName =
                            '${location['name']}, ${location['state']}, India';
                        final isAlreadySelected =
                            widget.selectedLocations.contains(locationName);

                        return ListTile(
                          dense: true,
                          leading: Icon(
                            Icons.location_city,
                            color: isAlreadySelected
                                ? Colors.grey
                                : Colors.blue.shade600,
                            size: 20,
                          ),
                          title: Text(
                            location['name'],
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: isAlreadySelected
                                  ? Colors.grey
                                  : Colors.black87,
                            ),
                          ),
                          subtitle: Text(
                            '${location['state']}, India',
                            style: TextStyle(
                              fontSize: 12,
                              color: isAlreadySelected
                                  ? Colors.grey
                                  : Colors.grey.shade600,
                            ),
                          ),
                          trailing: isAlreadySelected
                              ? Icon(Icons.check,
                                  color: Colors.green.shade600, size: 20)
                              : const Icon(Icons.add,
                                  color: Colors.blue, size: 20),
                          onTap: isAlreadySelected
                              ? null
                              : () => _addLocationFromAPI(location),
                        );
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),

        // **NEW: Popular locations for quick selection**
        const SizedBox(height: 12),
        const Text(
          'Popular Locations:',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _popularLocations.map((location) {
              final isSelected = widget.selectedLocations.contains(location);
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(
                    location,
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected ? Colors.white : Colors.blue.shade700,
                    ),
                  ),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      _addPopularLocation(location);
                    } else {
                      final newItems =
                          List<String>.from(widget.selectedLocations)
                            ..remove(location);
                      widget.onLocationsChanged(newItems);
                    }
                  },
                  selectedColor: Colors.blue.shade600,
                  backgroundColor: Colors.blue.shade50,
                  checkmarkColor: Colors.white,
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  void _showMultiSelectDialog(String title, List<String> selectedItems,
      List<String> options, Function(List<String>) onChanged) {
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
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    leading: Icon(
                      Icons.add_circle_outline,
                      color: Colors.green.shade700,
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
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
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                onChanged(List<String>.from(selectedItems));
                Navigator.pop(context);
              },
              child: const Text('Done'),
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
        title: const Text('Add Custom Interest'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _customInterestController,
              decoration: const InputDecoration(
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
            const SizedBox(height: 16),
            Text(
              'This will be added to your selected interests and can be used for targeting.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
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
              _addCustomInterest();
              Navigator.pop(context);
            },
            child: const Text('Add Interest'),
          ),
        ],
      ),
    );
  }

  // **NEW: Day Parting Section**
  Widget _buildDayPartingSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_today, color: Colors.purple.shade600),
                const SizedBox(width: 8),
                const Text(
                  'Day Targeting',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Select which days of the week to show ads:',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _daysOfWeek.map((day) {
                final isSelected = widget.dayParting[day] ?? false;
                return FilterChip(
                  label: Text(day.substring(0, 3)),
                  selected: isSelected,
                  onSelected: (selected) {
                    final newDayParting =
                        Map<String, bool>.from(widget.dayParting);
                    newDayParting[day] = selected;
                    widget.onDayPartingChanged(newDayParting);
                  },
                  selectedColor: Colors.purple.shade100,
                  checkmarkColor: Colors.purple.shade700,
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    final allSelected = Map<String, bool>.fromEntries(
                      _daysOfWeek.map((day) => MapEntry(day, true)),
                    );
                    widget.onDayPartingChanged(allSelected);
                  },
                  icon: const Icon(Icons.select_all, size: 16),
                  label: const Text('All Days'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () {
                    final weekdaysSelected = Map<String, bool>.fromEntries(
                      _daysOfWeek.map((day) => MapEntry(
                            day,
                            !['Saturday', 'Sunday'].contains(day),
                          )),
                    );
                    widget.onDayPartingChanged(weekdaysSelected);
                  },
                  icon: const Icon(Icons.business, size: 16),
                  label: const Text('Weekdays'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () {
                    widget.onDayPartingChanged({});
                  },
                  icon: const Icon(Icons.clear, size: 16),
                  label: const Text('Clear'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // **NEW: Hour Parting Section**
  Widget _buildHourPartingSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.access_time, color: Colors.indigo.shade600),
                const SizedBox(width: 8),
                const Text(
                  'Hour Targeting',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Set time ranges when ads should be shown:',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 12),

            // Show current time ranges
            if (widget.hourParting.isNotEmpty) ...[
              ...widget.hourParting.entries.map((entry) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.indigo.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.schedule,
                          color: Colors.indigo.shade700, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        '${entry.key}: ${entry.value}',
                        style: TextStyle(color: Colors.indigo.shade700),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () {
                          final newHourParting =
                              Map<String, String>.from(widget.hourParting);
                          newHourParting.remove(entry.key);
                          widget.onHourPartingChanged(newHourParting);
                        },
                        icon: Icon(Icons.close,
                            color: Colors.indigo.shade700, size: 16),
                      ),
                    ],
                  ),
                );
              }).toList(),
              const SizedBox(height: 8),
            ],

            // Add new time range button
            ElevatedButton.icon(
              onPressed: () => _showHourPartingDialog(),
              icon: const Icon(Icons.add_alarm, size: 16),
              label: Text(widget.hourParting.isEmpty
                  ? 'Add Time Range'
                  : 'Add Another Range'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo.shade50,
                foregroundColor: Colors.indigo.shade700,
                elevation: 0,
              ),
            ),

            if (widget.hourParting.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextButton.icon(
                  onPressed: () => widget.onHourPartingChanged({}),
                  icon: const Icon(Icons.clear, size: 16),
                  label: const Text('Clear All Time Ranges'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red.shade600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // **NEW: Show Hour Parting Dialog**
  void _showHourPartingDialog() {
    String selectedDay = _daysOfWeek.first;
    String startTime = '09:00';
    String endTime = '18:00';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Time Range'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Day selection
              DropdownButtonFormField<String>(
                initialValue: selectedDay,
                decoration: const InputDecoration(
                  labelText: 'Day',
                  border: OutlineInputBorder(),
                ),
                items: _daysOfWeek
                    .map((day) => DropdownMenuItem(
                          value: day,
                          child: Text(day),
                        ))
                    .toList(),
                onChanged: (value) {
                  setDialogState(() {
                    selectedDay = value!;
                  });
                },
              ),
              const SizedBox(height: 16),

              // Time range
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: startTime,
                      decoration: const InputDecoration(
                        labelText: 'Start Time',
                        border: OutlineInputBorder(),
                        hintText: '09:00',
                      ),
                      onChanged: (value) => startTime = value,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      initialValue: endTime,
                      decoration: const InputDecoration(
                        labelText: 'End Time',
                        border: OutlineInputBorder(),
                        hintText: '18:00',
                      ),
                      onChanged: (value) => endTime = value,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Use 24-hour format (e.g., 09:00, 18:30)',
                style: TextStyle(fontSize: 12, color: Colors.grey),
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
                final newHourParting =
                    Map<String, String>.from(widget.hourParting);
                newHourParting[selectedDay] = '$startTime - $endTime';
                widget.onHourPartingChanged(newHourParting);
                Navigator.pop(context);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }
}
