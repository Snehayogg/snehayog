import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// **CitySearchService - Handles dynamic city search using OpenStreetMap Nominatim API**
class CitySearchService {
  static const String _baseUrl = 'https://nominatim.openstreetmap.org/search';
  // Nominatim requires an identifiable User-Agent per usage policy
  static const String _userAgent =
      'VayugApp/1.0 (contact: factshorts1@gmail.com)';

  /// Search for cities in India using OpenStreetMap Nominatim API
  static Future<List<String>> searchCities(String query) async {
    if (query.length < 3) return [];

    try {
      final encodedQuery = Uri.encodeComponent('$query, India');
      final response = await http.get(
        Uri.parse('$_baseUrl?'
            'q=$encodedQuery&'
            'format=jsonv2&'
            'addressdetails=1&'
            'limit=10&'
            'countrycodes=in&'
            'dedupe=1'),
        headers: {
          'User-Agent': _userAgent,
          'Accept-Language': 'en',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final List<String> cities = [];

        for (var place in data) {
          final displayName = place['display_name'] as String? ?? '';
          final address = place['address'] as Map<String, dynamic>?;
          final city = address?['city'] ??
              address?['town'] ??
              address?['village'] ??
              _extractCityName(displayName);
          if (city.isNotEmpty && !cities.contains(city)) {
            cities.add(city);
          }
        }

        return cities;
      }
    } catch (e) {
      print('Error searching cities: $e');
    }

    return [];
  }

  /// Extract city name from display name like "Mumbai, Maharashtra, India"
  static String _extractCityName(String displayName) {
    final parts = displayName.split(',');
    if (parts.isNotEmpty) {
      return parts[0].trim();
    }
    return displayName;
  }

  /// **ENHANCED: Search for cities with more specific parameters**
  /// Uses OpenStreetMap Nominatim API for professional location search
  static Future<List<Map<String, dynamic>>> searchCitiesDetailed(
      String query) async {
    if (query.length < 3) return [];

    print('🔍 CitySearchService: Searching for "$query"');

    try {
      final encodedQuery = Uri.encodeComponent('$query, India');
      final url = '$_baseUrl?'
          'q=$encodedQuery&'
          'format=jsonv2&'
          'addressdetails=1&'
          'limit=15&' // **INCREASED: More results for better UX**
          'countrycodes=in&'
          'dedupe=1';

      print('🔍 CitySearchService: API URL: $url');

      // **ENHANCED: Add timeout for better UX**
      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              'User-Agent': _userAgent,
              'Accept-Language': 'en',
            },
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              print('⏱️ CitySearchService: Request timeout');
              throw TimeoutException('Location search request timed out');
            },
          );

      print('🔍 CitySearchService: Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final List<Map<String, dynamic>> cities = [];

        print('🔍 CitySearchService: Found ${data.length} results');

        for (var place in data) {
          try {
            final displayName = place['display_name'] as String? ?? '';
            final address = place['address'] as Map<String, dynamic>?;
            
            // **ENHANCED: Better city name extraction**
            final city = address?['city'] ??
                address?['town'] ??
                address?['village'] ??
                address?['municipality'] ??
                _extractCityName(displayName);
            
            // **ENHANCED: Better state extraction**
            final state = address?['state'] ?? 
                address?['state_district'] ??
                _extractState(displayName);

            // **ENHANCED: Skip if city name is too generic or empty**
            if (city.isNotEmpty && 
                city.length >= 2 && 
                !cities.any((c) => c['name'] == city)) {
              cities.add({
                'name': city,
                'state': state.isNotEmpty ? state : 'India',
                'displayName': displayName,
                'lat': place['lat'] ?? '0',
                'lon': place['lon'] ?? '0',
              });
            }
          } catch (e) {
            print('⚠️ CitySearchService: Error processing place: $e');
            continue; // Skip invalid entries
          }
        }

        print('✅ CitySearchService: Returning ${cities.length} cities');
        return cities;
      } else {
        print(
            '❌ CitySearchService: API error - Status: ${response.statusCode}');
        throw Exception('API returned status ${response.statusCode}');
      }
    } on TimeoutException catch (e) {
      print('⏱️ CitySearchService: Timeout error: $e');
      rethrow;
    } catch (e) {
      print('❌ CitySearchService: Error searching cities: $e');
      rethrow; // **ENHANCED: Re-throw to let widget handle fallback**
    }
  }

  /// Extract state name from display name
  static String _extractState(String displayName) {
    final parts = displayName.split(',');
    if (parts.length >= 2) {
      return parts[1].trim();
    }
    return '';
  }
}
