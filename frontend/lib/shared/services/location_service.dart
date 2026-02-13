import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:permission_handler/permission_handler.dart';

/// Professional Location Service with comprehensive error handling
/// Handles all location-related operations with proper permission management
class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  // Cache for the last known position
  Position? _lastKnownPosition;
  DateTime? _lastPositionUpdateTime;
  static const Duration _cacheValidityDuration = Duration(minutes: 5);

  /// Get current location with full error handling
  ///
  /// [forceRefresh] - if true, ignores cache and fetches fresh location
  /// Returns Position object or null if unable to get location
  Future<Position?> getCurrentLocation({bool forceRefresh = false}) async {
    try {
      // Check cache first (if not forcing refresh)
      if (!forceRefresh && _isCacheValid()) {
        print('📍 Returning cached location');
        return _lastKnownPosition;
      }

      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('⚠️ Location services are disabled');
        // Attempt to open location settings
        await Geolocator.openLocationSettings();
        return null;
      }

      // Check and request permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('⚠️ Location permissions denied');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('⚠️ Location permissions permanently denied');
        // Guide user to app settings
        await openAppSettings();
        return null;
      }

      // Get the current position
      print('🔄 Fetching current location...');
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10, // Update only if moved 10 meters
          timeLimit: Duration(seconds: 15), // Timeout after 15 seconds
        ),
      );

      // Cache the position
      _lastKnownPosition = position;
      _lastPositionUpdateTime = DateTime.now();

      print('✅ Location fetched: ${position.latitude}, ${position.longitude}');
      return position;
    } catch (e) {
      print('❌ Error getting location: $e');
      return _lastKnownPosition; // Return cached location as fallback
    }
  }

  /// Get the last known location (faster but might be outdated)
  Future<Position?> getLastKnownLocation() async {
    try {
      // Try to get from cache first
      if (_isCacheValid()) {
        return _lastKnownPosition;
      }

      // Try to get last known position from system
      Position? position = await Geolocator.getLastKnownPosition();
      if (position != null) {
        _lastKnownPosition = position;
        _lastPositionUpdateTime = DateTime.now();
      }
      return position;
    } catch (e) {
      print('❌ Error getting last known location: $e');
      return null;
    }
  }

  /// Get address from coordinates (Reverse Geocoding)
  Future<String?> getAddressFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        latitude,
        longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks.first;
        String address = _formatAddress(place);
        print('📍 Address: $address');
        return address;
      }
      return null;
    } catch (e) {
      print('❌ Error getting address: $e');
      return null;
    }
  }

  /// Get detailed placemark from coordinates
  Future<Placemark?> getPlacemarkFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        latitude,
        longitude,
      );
      return placemarks.isNotEmpty ? placemarks.first : null;
    } catch (e) {
      print('❌ Error getting placemark: $e');
      return null;
    }
  }

  /// Get coordinates from address (Forward Geocoding)
  Future<Location?> getCoordinatesFromAddress(String address) async {
    try {
      List<Location> locations = await locationFromAddress(address);
      if (locations.isNotEmpty) {
        print(
            '📍 Coordinates: ${locations.first.latitude}, ${locations.first.longitude}');
        return locations.first;
      }
      return null;
    } catch (e) {
      print('❌ Error getting coordinates: $e');
      return null;
    }
  }

  /// Calculate distance between two locations in meters
  double calculateDistance(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) {
    return Geolocator.distanceBetween(
      startLatitude,
      startLongitude,
      endLatitude,
      endLongitude,
    );
  }

  /// Calculate distance between current location and a target location
  Future<double?> getDistanceFromCurrentLocation(
    double targetLatitude,
    double targetLongitude,
  ) async {
    Position? currentPosition = await getCurrentLocation();
    if (currentPosition == null) return null;

    return calculateDistance(
      currentPosition.latitude,
      currentPosition.longitude,
      targetLatitude,
      targetLongitude,
    );
  }

  /// Format distance in human-readable format
  String formatDistance(double distanceInMeters) {
    if (distanceInMeters < 1000) {
      return '${distanceInMeters.round()} m';
    } else {
      double km = distanceInMeters / 1000;
      return '${km.toStringAsFixed(1)} km';
    }
  }

  /// Check if location permission is granted
  Future<bool> isLocationPermissionGranted() async {
    LocationPermission permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Get current permission status
  Future<LocationPermission> getPermissionStatus() async {
    return await Geolocator.checkPermission();
  }

  /// Request location permission
  Future<bool> requestLocationPermission() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        // Open app settings
        await openAppSettings();
        return false;
      }

      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    } catch (e) {
      print('❌ Error requesting permission: $e');
      return false;
    }
  }

  /// Listen to location updates (for real-time tracking)
  Stream<Position> getLocationStream({
    LocationAccuracy accuracy = LocationAccuracy.high,
    int distanceFilter = 10,
  }) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        timeLimit: const Duration(seconds: 30),
      ),
    );
  }

  /// Get city name from current location
  Future<String?> getCurrentCity() async {
    Position? position = await getCurrentLocation();
    if (position == null) return null;

    Placemark? placemark = await getPlacemarkFromCoordinates(
      position.latitude,
      position.longitude,
    );

    return placemark?.locality ?? placemark?.subAdministrativeArea;
  }

  /// Get country name from current location
  Future<String?> getCurrentCountry() async {
    Position? position = await getCurrentLocation();
    if (position == null) return null;

    Placemark? placemark = await getPlacemarkFromCoordinates(
      position.latitude,
      position.longitude,
    );

    return placemark?.country;
  }

  /// Get full location details as a map
  Future<Map<String, dynamic>?> getCurrentLocationDetails() async {
    Position? position = await getCurrentLocation();
    if (position == null) return null;

    Placemark? placemark = await getPlacemarkFromCoordinates(
      position.latitude,
      position.longitude,
    );

    return {
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracy': position.accuracy,
      'altitude': position.altitude,
      'heading': position.heading,
      'speed': position.speed,
      'timestamp': position.timestamp,
      'street': placemark?.street,
      'subLocality': placemark?.subLocality,
      'locality': placemark?.locality,
      'subAdministrativeArea': placemark?.subAdministrativeArea,
      'administrativeArea': placemark?.administrativeArea,
      'postalCode': placemark?.postalCode,
      'country': placemark?.country,
      'isoCountryCode': placemark?.isoCountryCode,
      'formattedAddress': placemark != null ? _formatAddress(placemark) : null,
    };
  }

  /// Check if location services are enabled
  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Open location settings
  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  /// Open app settings
  Future<void> openAppPermissionSettings() async {
    await openAppSettings();
  }

  /// Clear cached location
  void clearCache() {
    _lastKnownPosition = null;
    _lastPositionUpdateTime = null;
  }

  // Private helper methods

  bool _isCacheValid() {
    if (_lastKnownPosition == null || _lastPositionUpdateTime == null) {
      return false;
    }
    return DateTime.now().difference(_lastPositionUpdateTime!) <
        _cacheValidityDuration;
  }

  String _formatAddress(Placemark place) {
    List<String> addressParts = [];

    if (place.street != null && place.street!.isNotEmpty) {
      addressParts.add(place.street!);
    }
    if (place.subLocality != null && place.subLocality!.isNotEmpty) {
      addressParts.add(place.subLocality!);
    }
    if (place.locality != null && place.locality!.isNotEmpty) {
      addressParts.add(place.locality!);
    }
    if (place.administrativeArea != null &&
        place.administrativeArea!.isNotEmpty) {
      addressParts.add(place.administrativeArea!);
    }
    if (place.postalCode != null && place.postalCode!.isNotEmpty) {
      addressParts.add(place.postalCode!);
    }
    if (place.country != null && place.country!.isNotEmpty) {
      addressParts.add(place.country!);
    }

    return addressParts.join(', ');
  }
}

/// Location data model for easy use
class LocationData {
  final double latitude;
  final double longitude;
  final double? accuracy;
  final String? address;
  final String? city;
  final String? country;
  final DateTime timestamp;

  LocationData({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.address,
    this.city,
    this.country,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'address': address,
        'city': city,
        'country': country,
        'timestamp': timestamp.toIso8601String(),
      };

  factory LocationData.fromJson(Map<String, dynamic> json) => LocationData(
        latitude: json['latitude'],
        longitude: json['longitude'],
        accuracy: json['accuracy'],
        address: json['address'],
        city: json['city'],
        country: json['country'],
        timestamp: DateTime.parse(json['timestamp']),
      );

  @override
  String toString() {
    return 'LocationData(lat: $latitude, lng: $longitude, city: $city, country: $country)';
  }
}
