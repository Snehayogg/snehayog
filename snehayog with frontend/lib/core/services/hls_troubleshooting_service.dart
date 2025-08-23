import 'dart:async';
import 'package:http/http.dart' as http;

/// HLS Troubleshooting Service to diagnose and fix common HLS issues
class HLSTroubleshootingService {
  static final HLSTroubleshootingService _instance =
      HLSTroubleshootingService._internal();
  factory HLSTroubleshootingService() => _instance;
  HLSTroubleshootingService._internal();

  /// Diagnose HLS loading issues
  Future<Map<String, dynamic>> diagnoseHLSIssues(String hlsUrl) async {
    final diagnosis = <String, dynamic>{
      'url': hlsUrl,
      'timestamp': DateTime.now().toIso8601String(),
      'issues': <String>[],
      'recommendations': <String>[],
      'networkTest': <String, dynamic>{},
      'playlistTest': <String, dynamic>{},
      'overallHealth': 'unknown',
    };

    try {
      print('🔍 HLS Troubleshooting: Starting diagnosis for $hlsUrl');

      // Test 1: Network connectivity
      final networkTest = await _testNetworkConnectivity(hlsUrl);
      diagnosis['networkTest'] = networkTest;

      if (networkTest['status'] == 'failed') {
        diagnosis['issues'].add('Network connectivity issue');
        diagnosis['recommendations'].add('Check internet connection');
        diagnosis['recommendations'].add('Verify server is accessible');
      }

      // Test 2: HLS playlist accessibility
      final playlistTest = await _testHLSPlaylist(hlsUrl);
      diagnosis['playlistTest'] = playlistTest;

      if (playlistTest['status'] == 'failed') {
        diagnosis['issues'].add('HLS playlist not accessible');
        diagnosis['recommendations'].add('Check HLS server configuration');
        diagnosis['recommendations'].add('Verify playlist URL is correct');
      }

      // Test 3: Segment accessibility
      if (playlistTest['status'] == 'success' &&
          playlistTest['segments'] != null) {
        final segmentTest =
            await _testHLSSegments(hlsUrl, playlistTest['segments']);
        diagnosis['segmentTest'] = segmentTest;

        if (segmentTest['status'] == 'failed') {
          diagnosis['issues'].add('HLS segments not accessible');
          diagnosis['recommendations'].add('Check segment file permissions');
          diagnosis['recommendations'].add('Verify segment URLs are correct');
        }
      }

      // Test 4: Content-Type validation
      final contentTypeTest = await _testContentType(hlsUrl);
      diagnosis['contentTypeTest'] = contentTypeTest;

      if (contentTypeTest['status'] == 'failed') {
        diagnosis['issues'].add('Invalid content type');
        diagnosis['recommendations']
            .add('Check server MIME type configuration');
        diagnosis['recommendations']
            .add('Verify .m3u8 files are served correctly');
      }

      // Determine overall health
      diagnosis['overallHealth'] = _determineOverallHealth(diagnosis);

      // Add general recommendations based on issues found
      _addGeneralRecommendations(diagnosis);

      print(
          '🔍 HLS Troubleshooting: Diagnosis completed - ${diagnosis['overallHealth']}');
      return diagnosis;
    } catch (e) {
      print('❌ HLS Troubleshooting: Error during diagnosis: $e');
      diagnosis['issues'].add('Diagnosis failed: $e');
      diagnosis['overallHealth'] = 'error';
      return diagnosis;
    }
  }

  /// Test network connectivity to HLS server
  Future<Map<String, dynamic>> _testNetworkConnectivity(String hlsUrl) async {
    try {
      final uri = Uri.parse(hlsUrl);
      final stopwatch = Stopwatch()..start();

      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      stopwatch.stop();

      return {
        'status': response.statusCode == 200 ? 'success' : 'failed',
        'statusCode': response.statusCode,
        'responseTime': stopwatch.elapsedMilliseconds,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return {
        'status': 'failed',
        'error': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }

  /// Test HLS playlist accessibility
  Future<Map<String, dynamic>> _testHLSPlaylist(String hlsUrl) async {
    try {
      final uri = Uri.parse(hlsUrl);
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return {
          'status': 'failed',
          'statusCode': response.statusCode,
          'error': 'HTTP ${response.statusCode}',
          'timestamp': DateTime.now().toIso8601String(),
        };
      }

      final content = response.body;
      final segments = <String>[];

      // Parse playlist for segments
      final lines = content.split('\n');
      for (final line in lines) {
        if (line.trim().isNotEmpty && !line.startsWith('#')) {
          segments.add(line.trim());
        }
      }

      return {
        'status': 'success',
        'contentLength': content.length,
        'segments': segments,
        'segmentCount': segments.length,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return {
        'status': 'failed',
        'error': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }

  /// Test HLS segments accessibility
  Future<Map<String, dynamic>> _testHLSSegments(
      String hlsUrl, List<String> segments) async {
    try {
      final baseUrl = hlsUrl.substring(0, hlsUrl.lastIndexOf('/') + 1);
      int accessibleSegments = 0;
      int totalSegments = segments.length;

      // Test first few segments (don't test all to avoid long delays)
      final segmentsToTest = segments.take(3).toList();

      for (final segment in segmentsToTest) {
        try {
          final segmentUrl =
              segment.startsWith('http') ? segment : '$baseUrl$segment';
          final response = await http
              .get(Uri.parse(segmentUrl))
              .timeout(const Duration(seconds: 5));

          if (response.statusCode == 200) {
            accessibleSegments++;
          }
        } catch (e) {
          // Segment failed, continue with next
        }
      }

      return {
        'status': accessibleSegments > 0 ? 'success' : 'failed',
        'accessibleSegments': accessibleSegments,
        'totalSegments': totalSegments,
        'testedSegments': segmentsToTest.length,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return {
        'status': 'failed',
        'error': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }

  /// Test content type validation
  Future<Map<String, dynamic>> _testContentType(String hlsUrl) async {
    try {
      final uri = Uri.parse(hlsUrl);
      final response =
          await http.head(uri).timeout(const Duration(seconds: 10));

      final contentType = response.headers['content-type'] ?? '';
      final isValid = contentType.contains('application/vnd.apple.mpegurl') ||
          contentType.contains('application/x-mpegURL') ||
          contentType.contains('text/plain');

      return {
        'status': isValid ? 'success' : 'failed',
        'contentType': contentType,
        'isValid': isValid,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return {
        'status': 'failed',
        'error': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }

  /// Determine overall health based on test results
  String _determineOverallHealth(Map<String, dynamic> diagnosis) {
    final issues = diagnosis['issues'] as List<String>;

    if (issues.isEmpty) {
      return 'excellent';
    } else if (issues.length <= 2) {
      return 'good';
    } else if (issues.length <= 4) {
      return 'fair';
    } else {
      return 'poor';
    }
  }

  /// Add general recommendations based on common issues
  void _addGeneralRecommendations(Map<String, dynamic> diagnosis) {
    final recommendations = diagnosis['recommendations'] as List<String>;

    // Add performance recommendations
    recommendations.add('Use CDN for global content delivery');
    recommendations.add('Implement adaptive bitrate streaming');
    recommendations.add('Optimize HLS segment duration (2-4 seconds)');
    recommendations.add('Enable HTTP/2 for better multiplexing');
    recommendations.add('Use proper caching headers');

    // Add monitoring recommendations
    recommendations.add('Monitor HLS server performance');
    recommendations.add('Track segment loading times');
    recommendations.add('Monitor network conditions');
    recommendations.add('Implement error tracking and alerting');
  }

  /// Get quick HLS health check
  Future<String> getQuickHLSHealth(String hlsUrl) async {
    try {
      final diagnosis = await diagnoseHLSIssues(hlsUrl);
      return diagnosis['overallHealth'] as String;
    } catch (e) {
      return 'error';
    }
  }

  /// Get specific issue recommendations
  List<String> getIssueSpecificRecommendations(List<String> issues) {
    final recommendations = <String>[];

    for (final issue in issues) {
      if (issue.contains('Network')) {
        recommendations.add('Check firewall settings');
        recommendations.add('Verify DNS resolution');
        recommendations.add('Test with different network');
      } else if (issue.contains('Playlist')) {
        recommendations.add('Verify playlist file exists');
        recommendations.add('Check file permissions');
        recommendations.add('Validate playlist format');
      } else if (issue.contains('Segment')) {
        recommendations.add('Check segment file paths');
        recommendations.add('Verify encoding completed');
        recommendations.add('Check storage permissions');
      } else if (issue.contains('Content-Type')) {
        recommendations.add('Configure server MIME types');
        recommendations.add('Add .m3u8 file association');
        recommendations.add('Check web server configuration');
      }
    }

    return recommendations;
  }

  /// Generate troubleshooting report
  String generateTroubleshootingReport(Map<String, dynamic> diagnosis) {
    final report = StringBuffer();
    report.writeln('🔍 HLS Troubleshooting Report');
    report.writeln('=====================================');
    report.writeln('URL: ${diagnosis['url']}');
    report.writeln('Timestamp: ${diagnosis['timestamp']}');
    report.writeln(
        'Overall Health: ${diagnosis['overallHealth']?.toUpperCase()}');
    report.writeln('');

    if (diagnosis['issues'].isNotEmpty) {
      report.writeln('🚨 Issues Found:');
      for (final issue in diagnosis['issues']) {
        report.writeln('  • $issue');
      }
      report.writeln('');
    }

    if (diagnosis['recommendations'].isNotEmpty) {
      report.writeln('💡 Recommendations:');
      for (final recommendation in diagnosis['recommendations']) {
        report.writeln('  • $recommendation');
      }
      report.writeln('');
    }

    // Add test results
    report.writeln('📊 Test Results:');
    if (diagnosis['networkTest'] != null) {
      final network = diagnosis['networkTest'];
      report.writeln(
          '  Network: ${network['status']} (${network['responseTime'] ?? 'N/A'}ms)');
    }

    if (diagnosis['playlistTest'] != null) {
      final playlist = diagnosis['playlistTest'];
      report.writeln(
          '  Playlist: ${playlist['status']} (${playlist['segmentCount'] ?? 'N/A'} segments)');
    }

    if (diagnosis['contentTypeTest'] != null) {
      final contentType = diagnosis['contentTypeTest'];
      report.writeln(
          '  Content-Type: ${contentType['status']} (${contentType['contentType'] ?? 'N/A'})');
    }

    return report.toString();
  }
}
