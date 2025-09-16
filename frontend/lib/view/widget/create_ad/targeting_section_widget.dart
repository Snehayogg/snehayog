import 'package:flutter/material.dart';
import 'package:snehayog/services/city_search_service.dart';

/// **TargetingSectionWidget - Handles advanced targeting options**
class TargetingSectionWidget extends StatefulWidget {
  final int? minAge;
  final int? maxAge;
  final String selectedGender;
  final List<String> selectedLocations;
  final List<String> selectedInterests;
  final List<String> selectedPlatforms;
  final String? appVersion;
  final Function(int?) onMinAgeChanged;
  final Function(int?) onMaxAgeChanged;
  final Function(String) onGenderChanged;
  final Function(List<String>) onLocationsChanged;
  final Function(List<String>) onInterestsChanged;
  final Function(List<String>) onPlatformsChanged;
  final Function(String?) onAppVersionChanged;

  const TargetingSectionWidget({
    Key? key,
    required this.minAge,
    required this.maxAge,
    required this.selectedGender,
    required this.selectedLocations,
    required this.selectedInterests,
    required this.selectedPlatforms,
    required this.appVersion,
    required this.onMinAgeChanged,
    required this.onMaxAgeChanged,
    required this.onGenderChanged,
    required this.onLocationsChanged,
    required this.onInterestsChanged,
    required this.onPlatformsChanged,
    required this.onAppVersionChanged,
  }) : super(key: key);

  @override
  State<TargetingSectionWidget> createState() => _TargetingSectionWidgetState();
}

class _TargetingSectionWidgetState extends State<TargetingSectionWidget> {
  final List<String> _genderOptions = ['all', 'male', 'female', 'other'];
  final List<String> _platformOptions = ['android', 'ios', 'web'];

  // Location search functionality
  final TextEditingController _locationSearchController =
      TextEditingController();
  List<String> _filteredLocations = [];
  bool _isLocationSearchVisible = false;

  // Custom interest functionality
  final TextEditingController _customInterestController =
      TextEditingController();
  final List<String> _customInterests = [];
  // Major Indian cities for quick selection
  final List<String> _majorCities = [
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
  List<String> _locationOptions = [];
  final List<String> _interestOptions = [
    // Gaming & Entertainment
    'Gaming',
    'Mobile Games',
    'PC Gaming',
    'Console Gaming',
    'Esports',
    'Game Development',
    'Gaming Streams',
    'Gaming Reviews',
    'Indie Games',
    'Retro Gaming',
    'Gaming Hardware',
    'Gaming Accessories',

    // Educational Content
    'Education',
    'Online Learning',
    'Coding & Programming',
    'Web Development',
    'Mobile App Development',
    'Data Science',
    'Machine Learning',
    'Artificial Intelligence',
    'Cybersecurity',
    'Digital Marketing',
    'Graphic Design',
    'Video Editing',
    'Photography',
    'Music Production',
    'Language Learning',
    'Mathematics',
    'Science',
    'Physics',
    'Chemistry',
    'Biology',
    'History',
    'Geography',
    'Literature',
    'Philosophy',
    'Psychology',
    'Business Studies',
    'Finance & Economics',
    'Tutorials',
    'How-to Guides',
    'Skill Development',
    'Career Development',

    // Technology & Innovation
    'Technology',
    'Software Development',
    'Tech Reviews',
    'Gadgets',
    'Smartphones',
    'Laptops',
    'Tablets',
    'Wearables',
    'IoT Devices',
    'Tech News',
    'Innovation',
    'Startups',
    'Entrepreneurship',

    // Creative & Arts
    'Art & Design',
    'Digital Art',
    'UI/UX Design',
    'Animation',
    '3D Modeling',
    'Creative Writing',
    'Content Creation',
    'YouTube',
    'TikTok',
    'Instagram',
    'Social Media',

    // Health & Wellness
    'Health & Fitness',
    'Mental Health',
    'Yoga',
    'Meditation',
    'Nutrition',
    'Exercise',
    'Wellness',

    // Custom Interest Option
    'Custom Interest'
  ];

  @override
  void initState() {
    super.initState();
    _locationOptions = List.from(_majorCities);
    _filteredLocations = List.from(_locationOptions);
    _locationSearchController.addListener(_filterLocations);
  }

  @override
  void dispose() {
    _locationSearchController.dispose();
    _customInterestController.dispose();
    super.dispose();
  }

  void _filterLocations() {
    setState(() {
      if (_locationSearchController.text.isEmpty) {
        _filteredLocations = List.from(_locationOptions);
      } else {
        _filteredLocations = _locationOptions
            .where((location) => location
                .toLowerCase()
                .contains(_locationSearchController.text.toLowerCase()))
            .toList();
      }
    });
  }

  void _addSearchedCity(String city) {
    if (!_locationOptions.contains(city)) {
      setState(() {
        _locationOptions.add(city);
        _filteredLocations = List.from(_locationOptions);
      });
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

  Future<void> _searchAndAddCity() async {
    final query = _locationSearchController.text.trim();
    if (query.length < 3) return;

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Searching for cities...'),
          ],
        ),
      ),
    );

    try {
      final cities = await CitySearchService.searchCities(query);

      // Close loading dialog
      Navigator.pop(context);

      if (cities.isNotEmpty) {
        // Show search results dialog
        _showCitySearchResults(cities);
      } else {
        // Show no results message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No cities found for "$query"'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      // Close loading dialog
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error searching cities: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showCitySearchResults(List<String> cities) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Found ${cities.length} cities'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: cities.length,
            itemBuilder: (context, index) {
              final city = cities[index];
              final isSelected = widget.selectedLocations.contains(city);

              return ListTile(
                title: Text(city),
                leading: isSelected
                    ? const Icon(Icons.check_circle, color: Colors.blue)
                    : const Icon(Icons.location_city, color: Colors.grey),
                trailing: isSelected
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: () {
                          _addSearchedCity(city);
                          widget.selectedLocations.add(city);
                          widget.onLocationsChanged(
                              List<String>.from(widget.selectedLocations));
                          Navigator.pop(context);
                        },
                      ),
                onTap: () {
                  if (!isSelected) {
                    _addSearchedCity(city);
                    widget.selectedLocations.add(city);
                    widget.onLocationsChanged(
                        List<String>.from(widget.selectedLocations));
                  }
                  Navigator.pop(context);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
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

        // App Version
        TextFormField(
          initialValue: widget.appVersion,
          decoration: const InputDecoration(
            labelText: 'App Version (Optional)',
            hintText: 'e.g., 1.0.0',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.apps),
            helperText: 'Target specific app versions',
          ),
          onChanged: (value) {
            widget.onAppVersionChanged(
                value.trim().isEmpty ? null : value.trim());
          },
        ),
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
        const Text(
          'Locations',
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
              // Selected locations display
              if (widget.selectedLocations.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.selectedLocations.map((location) {
                    return Chip(
                      label: Text(location),
                      deleteIcon: const Icon(Icons.close, size: 18),
                      onDeleted: () {
                        final newItems =
                            List<String>.from(widget.selectedLocations)
                              ..remove(location);
                        widget.onLocationsChanged(newItems);
                      },
                      backgroundColor: Colors.blue.shade100,
                      labelStyle: TextStyle(color: Colors.blue.shade800),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
              ],

              // Search and Add button
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _locationSearchController,
                      decoration: InputDecoration(
                        hintText:
                            'Search cities (type 3+ characters for live search)...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _locationSearchController.text.length >= 3
                            ? IconButton(
                                icon: const Icon(Icons.public),
                                onPressed: () => _searchAndAddCity(),
                                tooltip: 'Search online for cities',
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _isLocationSearchVisible = value.isNotEmpty;
                        });
                        _filterLocations();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _showLocationSelectionDialog(),
                    icon: const Icon(Icons.add_location, size: 18),
                    label: Text(widget.selectedLocations.isEmpty
                        ? 'Add Locations'
                        : 'Add More'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade50,
                      foregroundColor: Colors.blue.shade700,
                      elevation: 0,
                    ),
                  ),
                ],
              ),

              // Search results dropdown
              if (_isLocationSearchVisible &&
                  _filteredLocations.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.white,
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _filteredLocations.length,
                    itemBuilder: (context, index) {
                      final location = _filteredLocations[index];
                      final isSelected =
                          widget.selectedLocations.contains(location);

                      return ListTile(
                        dense: true,
                        title: Text(location),
                        leading: isSelected
                            ? const Icon(Icons.check_circle, color: Colors.blue)
                            : const Icon(Icons.radio_button_unchecked,
                                color: Colors.grey),
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              widget.selectedLocations.remove(location);
                            } else {
                              widget.selectedLocations.add(location);
                            }
                          });
                          widget.onLocationsChanged(
                              List<String>.from(widget.selectedLocations));
                        },
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _showLocationSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Select Locations'),
          content: SizedBox(
            width: double.maxFinite,
            height: 500,
            child: Column(
              children: [
                // Search bar in dialog
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search locations...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    setDialogState(() {
                      if (value.isEmpty) {
                        _filteredLocations = List.from(_locationOptions);
                      } else {
                        _filteredLocations = _locationOptions
                            .where((location) => location
                                .toLowerCase()
                                .contains(value.toLowerCase()))
                            .toList();
                      }
                    });
                  },
                ),
                const SizedBox(height: 16),
                // Locations list
                Expanded(
                  child: ListView.builder(
                    itemCount: _filteredLocations.length,
                    itemBuilder: (context, index) {
                      final location = _filteredLocations[index];
                      final isSelected =
                          widget.selectedLocations.contains(location);

                      return CheckboxListTile(
                        title: Text(location),
                        value: isSelected,
                        onChanged: (value) {
                          setDialogState(() {
                            if (value == true) {
                              widget.selectedLocations.add(location);
                            } else {
                              widget.selectedLocations.remove(location);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                widget.onLocationsChanged(
                    List<String>.from(widget.selectedLocations));
                Navigator.pop(context);
              },
              child: const Text('Done'),
            ),
          ],
        ),
      ),
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
}
