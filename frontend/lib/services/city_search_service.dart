import 'dart:convert';
import 'package:http/http.dart' as http;

/// **CitySearchService - Handles dynamic city search using OpenStreetMap Nominatim API**
class CitySearchService {
  static const String _baseUrl = 'https://nominatim.openstreetmap.org/search';
  // Nominatim requires an identifiable User-Agent per usage policy
  static const String _userAgent =
      'SnehayogApp/1.0 (contact: factshorts1@gmail.com)';

  /// Search for cities in India using OpenStreetMap Nominatim API
  static Future<List<String>> searchCities(String query) async {
    if (query.length < 3) return [];

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl?'
            'q=$query, India&'
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

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl?'
            'q=$query, India&'
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
        final List<Map<String, dynamic>> cities = [];

        for (var place in data) {
          final displayName = place['display_name'] as String? ?? '';
          final address = place['address'] as Map<String, dynamic>?;
          final city = address?['city'] ??
              address?['town'] ??
              address?['village'] ??
              _extractCityName(displayName);
          final state = address?['state'] ?? _extractState(displayName);

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

        return cities;
      }
    } catch (e) {
      print('Error searching cities: $e');
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
