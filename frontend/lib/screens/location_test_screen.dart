import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart';

/// Quick test screen for location service
/// Add this to your app to test location functionality
///
/// Usage:
/// Navigator.push(
///   context,
///   MaterialPageRoute(builder: (context) => LocationTestScreen()),
/// );
class LocationTestScreen extends StatefulWidget {
  const LocationTestScreen({super.key});

  @override
  State<LocationTestScreen> createState() => _LocationTestScreenState();
}

class _LocationTestScreenState extends State<LocationTestScreen> {
  final LocationService _locationService = LocationService();

  bool _isLoading = false;
  String _statusMessage = 'Tap a button to test location features';
  Position? _currentPosition;
  String? _address;
  String? _city;
  String? _country;
  Map<String, dynamic>? _fullDetails;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Location Service Test'),
        backgroundColor: Colors.blue,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Card
            Card(
              color: _isLoading ? Colors.blue.shade50 : Colors.grey.shade100,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (_isLoading)
                      const CircularProgressIndicator()
                    else
                      Icon(
                        _currentPosition != null
                            ? Icons.check_circle
                            : Icons.location_on,
                        size: 48,
                        color: _currentPosition != null
                            ? Colors.green
                            : Colors.grey,
                      ),
                    const SizedBox(height: 12),
                    Text(
                      _statusMessage,
                      style: const TextStyle(fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Test Buttons
            const Text(
              'Basic Tests:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            ElevatedButton.icon(
              onPressed: _isLoading ? null : _testGetCurrentLocation,
              icon: const Icon(Icons.my_location),
              label: const Text('Get Current Location'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 8),

            ElevatedButton.icon(
              onPressed: _isLoading ? null : _testGetCityCountry,
              icon: const Icon(Icons.location_city),
              label: const Text('Get City & Country'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 8),

            ElevatedButton.icon(
              onPressed: _isLoading ? null : _testGetAddress,
              icon: const Icon(Icons.home),
              label: const Text('Get Full Address'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 8),

            ElevatedButton.icon(
              onPressed: _isLoading ? null : _testGetFullDetails,
              icon: const Icon(Icons.info),
              label: const Text('Get All Details'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 8),

            ElevatedButton.icon(
              onPressed: _isLoading ? null : _testCalculateDistance,
              icon: const Icon(Icons.straighten),
              label: const Text('Calculate Distance (Mumbai)'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 20),

            const Text(
              'Permission Tests:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            ElevatedButton.icon(
              onPressed: _testCheckPermission,
              icon: const Icon(Icons.security),
              label: const Text('Check Permission Status'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                backgroundColor: Colors.orange,
              ),
            ),
            const SizedBox(height: 8),

            ElevatedButton.icon(
              onPressed: _testRequestPermission,
              icon: const Icon(Icons.verified_user),
              label: const Text('Request Permission'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                backgroundColor: Colors.green,
              ),
            ),
            const SizedBox(height: 20),

            // Results Display
            if (_currentPosition != null) ...[
              const Divider(),
              const Text(
                'Results:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _buildResultCard(
                  'Coordinates',
                  'Lat: ${_currentPosition!.latitude.toStringAsFixed(6)}\n'
                      'Lng: ${_currentPosition!.longitude.toStringAsFixed(6)}'),
              if (_city != null) _buildResultCard('City', _city!),
              if (_country != null) _buildResultCard('Country', _country!),
              if (_address != null) _buildResultCard('Address', _address!),
              if (_fullDetails != null)
                _buildResultCard('Full Details', _formatFullDetails()),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(String title, String content) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.check_circle, color: Colors.green),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(content),
      ),
    );
  }

  Future<void> _testGetCurrentLocation() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Fetching current location...';
    });

    try {
      Position? position = await _locationService.getCurrentLocation();

      if (position != null) {
        setState(() {
          _currentPosition = position;
          _statusMessage = '✅ Location fetched successfully!';
        });
        _showSuccessSnackbar(
            'Location: ${position.latitude}, ${position.longitude}');
      } else {
        setState(() {
          _statusMessage = '❌ Unable to get location. Check permissions.';
        });
        _showErrorSnackbar('Location access denied or unavailable');
      }
    } catch (e) {
      setState(() {
        _statusMessage = '❌ Error: $e';
      });
      _showErrorSnackbar(e.toString());
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testGetCityCountry() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Getting city and country...';
    });

    try {
      String? city = await _locationService.getCurrentCity();
      String? country = await _locationService.getCurrentCountry();

      setState(() {
        _city = city;
        _country = country;
        _statusMessage = '✅ City and country fetched!';
      });

      if (city != null && country != null) {
        _showSuccessSnackbar('You are in: $city, $country');
      }
    } catch (e) {
      setState(() {
        _statusMessage = '❌ Error: $e';
      });
      _showErrorSnackbar(e.toString());
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testGetAddress() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Getting address...';
    });

    try {
      Position? position = await _locationService.getCurrentLocation();

      if (position != null) {
        String? address = await _locationService.getAddressFromCoordinates(
          position.latitude,
          position.longitude,
        );

        setState(() {
          _currentPosition = position;
          _address = address;
          _statusMessage = '✅ Address fetched!';
        });

        if (address != null) {
          _showSuccessSnackbar('Address: $address');
        }
      }
    } catch (e) {
      setState(() {
        _statusMessage = '❌ Error: $e';
      });
      _showErrorSnackbar(e.toString());
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testGetFullDetails() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Getting full location details...';
    });

    try {
      Map<String, dynamic>? details =
          await _locationService.getCurrentLocationDetails();

      setState(() {
        _fullDetails = details;
        if (details != null) {
          _currentPosition = Position(
            latitude: details['latitude'],
            longitude: details['longitude'],
            timestamp: details['timestamp'],
            accuracy: details['accuracy'],
            altitude: details['altitude'],
            heading: details['heading'],
            speed: details['speed'],
            speedAccuracy: 0,
            altitudeAccuracy: 0,
            headingAccuracy: 0,
          );
        }
        _statusMessage = '✅ All details fetched!';
      });

      _showSuccessSnackbar('Full location details loaded');
    } catch (e) {
      setState(() {
        _statusMessage = '❌ Error: $e';
      });
      _showErrorSnackbar(e.toString());
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testCalculateDistance() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Calculating distance to Mumbai...';
    });

    try {
      Position? position = await _locationService.getCurrentLocation();

      if (position != null) {
        // Mumbai coordinates
        const mumbaiLat = 19.0760;
        const mumbaiLng = 72.8777;

        double distance = _locationService.calculateDistance(
          position.latitude,
          position.longitude,
          mumbaiLat,
          mumbaiLng,
        );

        String formatted = _locationService.formatDistance(distance);

        setState(() {
          _currentPosition = position;
          _statusMessage = '✅ Distance calculated!';
        });

        _showSuccessSnackbar('Distance to Mumbai: $formatted');
      }
    } catch (e) {
      setState(() {
        _statusMessage = '❌ Error: $e';
      });
      _showErrorSnackbar(e.toString());
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testCheckPermission() async {
    bool hasPermission = await _locationService.isLocationPermissionGranted();
    LocationPermission permission =
        await _locationService.getPermissionStatus();

    String permissionText = permission.toString().split('.').last;

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Permission Status'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Granted: ${hasPermission ? '✅ Yes' : '❌ No'}'),
              const SizedBox(height: 8),
              Text('Status: $permissionText'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _testRequestPermission() async {
    bool granted = await _locationService.requestLocationPermission();

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(granted ? '✅ Success' : '❌ Denied'),
          content: Text(
            granted
                ? 'Location permission granted! You can now use location features.'
                : 'Location permission denied. Some features may not work.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  String _formatFullDetails() {
    if (_fullDetails == null) return '';

    return '''
Coordinates: ${_fullDetails!['latitude']}, ${_fullDetails!['longitude']}
Street: ${_fullDetails!['street'] ?? 'N/A'}
City: ${_fullDetails!['locality'] ?? 'N/A'}
State: ${_fullDetails!['administrativeArea'] ?? 'N/A'}
Country: ${_fullDetails!['country'] ?? 'N/A'}
Postal: ${_fullDetails!['postalCode'] ?? 'N/A'}
Accuracy: ${_fullDetails!['accuracy']} meters
    ''';
  }

  void _showSuccessSnackbar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showErrorSnackbar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}
