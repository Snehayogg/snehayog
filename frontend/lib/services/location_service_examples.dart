/// LOCATION SERVICE USAGE EXAMPLES
///
/// This file demonstrates how to use LocationService in various scenarios.
/// These are examples - integrate them into your widgets as needed.

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'location_service.dart';

/// Example 1: Basic Location Access in a Widget
class LocationExampleWidget extends StatefulWidget {
  const LocationExampleWidget({super.key});

  @override
  State<LocationExampleWidget> createState() => _LocationExampleWidgetState();
}

class _LocationExampleWidgetState extends State<LocationExampleWidget> {
  final LocationService _locationService = LocationService();
  String _locationInfo = 'Tap button to get location';
  bool _isLoading = false;

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Get current position
      Position? position = await _locationService.getCurrentLocation();

      if (position != null) {
        // Get address from coordinates
        String? address = await _locationService.getAddressFromCoordinates(
          position.latitude,
          position.longitude,
        );

        setState(() {
          _locationInfo = '''
📍 Location Found!
Latitude: ${position.latitude}
Longitude: ${position.longitude}
Accuracy: ${position.accuracy} meters
Address: ${address ?? 'Unable to get address'}
          ''';
        });
      } else {
        setState(() {
          _locationInfo =
              '❌ Unable to get location. Please enable location services.';
        });
      }
    } catch (e) {
      setState(() {
        _locationInfo = '❌ Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Location Example')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _locationInfo,
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (_isLoading)
              const CircularProgressIndicator()
            else
              ElevatedButton.icon(
                onPressed: _getCurrentLocation,
                icon: const Icon(Icons.location_on),
                label: const Text('Get My Location'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Example 2: Get City and Country
Future<void> exampleGetCityAndCountry() async {
  final locationService = LocationService();

  String? city = await locationService.getCurrentCity();
  String? country = await locationService.getCurrentCountry();

  print('📍 You are in: $city, $country');
}

/// Example 3: Calculate Distance
Future<void> exampleCalculateDistance() async {
  final locationService = LocationService();

  // Get current location
  Position? currentPosition = await locationService.getCurrentLocation();

  if (currentPosition != null) {
    // Example: Distance to New York (40.7128, -74.0060)
    double distance = locationService.calculateDistance(
      currentPosition.latitude,
      currentPosition.longitude,
      40.7128,
      -74.0060,
    );

    String formattedDistance = locationService.formatDistance(distance);
    print('📏 Distance to New York: $formattedDistance');
  }
}

/// Example 4: Real-time Location Tracking
class RealTimeLocationWidget extends StatefulWidget {
  const RealTimeLocationWidget({super.key});

  @override
  State<RealTimeLocationWidget> createState() => _RealTimeLocationWidgetState();
}

class _RealTimeLocationWidgetState extends State<RealTimeLocationWidget> {
  final LocationService _locationService = LocationService();
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _startLocationTracking();
  }

  void _startLocationTracking() {
    _locationService.getLocationStream().listen(
      (Position position) {
        setState(() {
          _currentPosition = position;
        });
        print(
            '📍 Location updated: ${position.latitude}, ${position.longitude}');
      },
      onError: (error) {
        print('❌ Location stream error: $error');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Real-time Location')),
      body: Center(
        child: _currentPosition != null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.my_location, size: 80, color: Colors.blue),
                  const SizedBox(height: 20),
                  Text(
                    'Latitude: ${_currentPosition!.latitude.toStringAsFixed(6)}',
                    style: const TextStyle(fontSize: 18),
                  ),
                  Text(
                    'Longitude: ${_currentPosition!.longitude.toStringAsFixed(6)}',
                    style: const TextStyle(fontSize: 18),
                  ),
                  Text(
                    'Speed: ${_currentPosition!.speed.toStringAsFixed(2)} m/s',
                    style: const TextStyle(fontSize: 18),
                  ),
                ],
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}

/// Example 5: Check Permission Before Using Location
Future<void> exampleCheckPermission() async {
  final locationService = LocationService();

  // Check if permission is already granted
  bool hasPermission = await locationService.isLocationPermissionGranted();

  if (!hasPermission) {
    // Request permission
    bool granted = await locationService.requestLocationPermission();

    if (granted) {
      print('✅ Location permission granted');
      // Now you can use location services
      Position? position = await locationService.getCurrentLocation();
      print('📍 Location: ${position?.latitude}, ${position?.longitude}');
    } else {
      print('❌ Location permission denied');
      // Show user a message to enable in settings
    }
  } else {
    print('✅ Location permission already granted');
  }
}

/// Example 6: Get Complete Location Details
Future<void> exampleGetCompleteLocationDetails() async {
  final locationService = LocationService();

  Map<String, dynamic>? details =
      await locationService.getCurrentLocationDetails();

  if (details != null) {
    print('📍 Complete Location Details:');
    print('Coordinates: ${details['latitude']}, ${details['longitude']}');
    print('City: ${details['locality']}');
    print('State: ${details['administrativeArea']}');
    print('Country: ${details['country']}');
    print('Postal Code: ${details['postalCode']}');
    print('Full Address: ${details['formattedAddress']}');
  }
}

/// Example 7: Search Location by Address
Future<void> exampleSearchByAddress() async {
  final locationService = LocationService();

  // Search for a location
  var location =
      await locationService.getCoordinatesFromAddress('New York, USA');

  if (location != null) {
    print('📍 New York coordinates:');
    print('Latitude: ${location.latitude}');
    print('Longitude: ${location.longitude}');
  }
}

/// Example 8: Use with ListView (Show Nearby Items)
class NearbyItemsListWidget extends StatefulWidget {
  const NearbyItemsListWidget({super.key});

  @override
  State<NearbyItemsListWidget> createState() => _NearbyItemsListWidgetState();
}

class _NearbyItemsListWidgetState extends State<NearbyItemsListWidget> {
  final LocationService _locationService = LocationService();
  Position? _currentPosition;

  // Example locations (replace with your actual data)
  final List<Map<String, dynamic>> _items = [
    {'name': 'Restaurant A', 'lat': 40.7128, 'lng': -74.0060},
    {'name': 'Store B', 'lat': 34.0522, 'lng': -118.2437},
    {'name': 'Park C', 'lat': 51.5074, 'lng': -0.1278},
  ];

  @override
  void initState() {
    super.initState();
    _loadLocation();
  }

  Future<void> _loadLocation() async {
    Position? position = await _locationService.getCurrentLocation();
    setState(() {
      _currentPosition = position;
    });
  }

  String _getDistanceText(double lat, double lng) {
    if (_currentPosition == null) return 'Calculating...';

    double distance = _locationService.calculateDistance(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      lat,
      lng,
    );

    return _locationService.formatDistance(distance);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nearby Items')),
      body: ListView.builder(
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final item = _items[index];
          return ListTile(
            leading: const Icon(Icons.location_on),
            title: Text(item['name']),
            trailing: Text(
              _getDistanceText(item['lat'], item['lng']),
              style: const TextStyle(color: Colors.grey),
            ),
          );
        },
      ),
    );
  }
}

/// Example 9: Location Permission Dialog
class LocationPermissionDialog extends StatelessWidget {
  const LocationPermissionDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Location Permission'),
      content: const Text(
        'We need access to your location to show you nearby content and personalized experiences.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Not Now'),
        ),
        ElevatedButton(
          onPressed: () async {
            final locationService = LocationService();
            bool granted = await locationService.requestLocationPermission();
            if (context.mounted) {
              Navigator.pop(context, granted);
            }
          },
          child: const Text('Allow'),
        ),
      ],
    );
  }

  static Future<bool> show(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => const LocationPermissionDialog(),
        ) ??
        false;
  }
}

/// Example 10: Use in API Calls
class LocationApiExample {
  final LocationService _locationService = LocationService();

  /// Example: Send location to your backend
  Future<void> sendLocationToBackend() async {
    Map<String, dynamic>? locationDetails =
        await _locationService.getCurrentLocationDetails();

    if (locationDetails != null) {
      // Prepare data for API
      final data = {
        'latitude': locationDetails['latitude'],
        'longitude': locationDetails['longitude'],
        'city': locationDetails['locality'],
        'country': locationDetails['country'],
        'timestamp': locationDetails['timestamp'].toString(),
      };

      // Send to your backend
      // await http.post(
      //   Uri.parse('YOUR_API_ENDPOINT/location'),
      //   body: jsonEncode(data),
      //   headers: {'Content-Type': 'application/json'},
      // );

      print('📤 Location data ready to send: $data');
    }
  }

  /// Example: Filter content by location
  Future<List<dynamic>> getLocationBasedContent() async {
    String? city = await _locationService.getCurrentCity();
    String? country = await _locationService.getCurrentCountry();

    if (city != null && country != null) {
      // Use location in API request
      // final response = await http.get(
      //   Uri.parse('YOUR_API_ENDPOINT/content?city=$city&country=$country'),
      // );

      print('📍 Fetching content for: $city, $country');
      return []; // Return your filtered data
    }

    return [];
  }
}

/*
==========================================
QUICK INTEGRATION GUIDE
==========================================

1. Basic Usage (Get Current Location):
   ```dart
   final locationService = LocationService();
   Position? position = await locationService.getCurrentLocation();
   if (position != null) {
     print('Lat: ${position.latitude}, Lng: ${position.longitude}');
   }
   ```

2. Get Address:
   ```dart
   String? address = await locationService.getAddressFromCoordinates(
     position.latitude,
     position.longitude,
   );
   ```

3. Get City:
   ```dart
   String? city = await locationService.getCurrentCity();
   ```

4. Calculate Distance:
   ```dart
   double distance = locationService.calculateDistance(
     lat1, lng1, lat2, lng2
   );
   String formatted = locationService.formatDistance(distance);
   ```

5. Real-time Tracking:
   ```dart
   locationService.getLocationStream().listen((position) {
     print('Updated location: ${position.latitude}, ${position.longitude}');
   });
   ```

==========================================
BEST PRACTICES
==========================================

✅ Always check permissions before requesting location
✅ Handle errors gracefully with try-catch
✅ Show user-friendly messages when location is unavailable
✅ Use cached location for better performance
✅ Request location only when needed (battery optimization)
✅ Be transparent about why you need location
✅ Provide option to deny/enable later in app settings

==========================================
COMMON USE CASES
==========================================

🎯 Show nearby content (restaurants, stores, events)
🎯 Personalized feed based on location
🎯 Delivery address auto-fill
🎯 Location-based search results
🎯 Check-in features
🎯 Track delivery/ride in real-time
🎯 Find friends nearby
🎯 Weather information
🎯 Local notifications
🎯 Analytics and user insights

==========================================
*/
