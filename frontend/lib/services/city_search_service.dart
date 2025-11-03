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

  /// Search for cities with more specific parameters
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
          'limit=10&'
          'countrycodes=in&'
          'dedupe=1';

      print('🔍 CitySearchService: API URL: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': _userAgent,
          'Accept-Language': 'en',
        },
      );

      print('🔍 CitySearchService: Response status: ${response.statusCode}');
      print('🔍 CitySearchService: Response body: ${response.body}');

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final List<Map<String, dynamic>> cities = [];

        print('🔍 CitySearchService: Found ${data.length} results');

        for (var place in data) {
          final displayName = place['display_name'] as String? ?? '';
          final address = place['address'] as Map<String, dynamic>?;
          final city = address?['city'] ??
              address?['town'] ??
              address?['village'] ??
              _extractCityName(displayName);
          final state = address?['state'] ?? _extractState(displayName);

          print('🔍 CitySearchService: Processing: $city, $state');

          if (city.isNotEmpty && !cities.any((c) => c['name'] == city)) {
            cities.add({
              'name': city,
              'state': state,
              'displayName': displayName,
              'lat': place['lat'],
              'lon': place['lon'],
            });
          }
        }

        print('🔍 CitySearchService: Returning ${cities.length} cities');
        return cities;
      } else {
        print(
            '❌ CitySearchService: API error - Status: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ CitySearchService: Error searching cities: $e');
    }

    return [];
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
