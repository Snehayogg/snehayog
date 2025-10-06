import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snehayog/config/app_config.dart';
import 'package:snehayog/model/report_model.dart';

class ReportService {
  static const String _baseUrl = '/api/reports';

  // Get authorization headers
  Future<Map<String, String>> _getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');

    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Create new report
  Future<ReportModel> createReport(ReportCreationRequest request) async {
    try {
      print('🚨 Creating report: ${request.type}');

      final headers = await _getHeaders();
      final response = await http
          .post(
            Uri.parse('${AppConfig.baseUrl}$_baseUrl'),
            headers: headers,
            body: jsonEncode(request.toJson()),
          )
          .timeout(const Duration(seconds: 30));

      print('📡 Report creation response: ${response.statusCode}');

      if (response.statusCode == 201) {
        final responseData = jsonDecode(response.body);
        if (responseData['success'] == true) {
          final report = ReportModel.fromJson(responseData['data']);
          print('✅ Report created successfully: ${report.id}');
          return report;
        } else {
          throw Exception(responseData['message'] ?? 'Failed to create report');
        }
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to create report');
      }
    } catch (e) {
      print('❌ Error creating report: $e');
      rethrow;
    }
  }

  /// Get report by ID
  Future<ReportModel> getReportById(String id) async {
    try {
      print('🔍 Getting report: $id');

      final headers = await _getHeaders();
      final response = await http
          .get(
            Uri.parse('${AppConfig.baseUrl}$_baseUrl/$id'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));

      print('📡 Get report response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['success'] == true) {
          return ReportModel.fromJson(responseData['data']);
        } else {
          throw Exception(responseData['message'] ?? 'Failed to get report');
        }
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to get report');
      }
    } catch (e) {
      print('❌ Error getting report: $e');
      rethrow;
    }
  }

  /// Get reports list with filters and pagination (Admin/Moderator only)
  Future<Map<String, dynamic>> getReportsList({
    int page = 1,
    int limit = 10,
    String? status,
    String? type,
    String? priority,
    String? severity,
    String? assignedModerator,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? sortBy,
    String? sortOrder,
  }) async {
    try {
      print('📋 Getting reports list (page: $page, limit: $limit)');

      final headers = await _getHeaders();
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
        if (status != null) 'status': status,
        if (type != null) 'type': type,
        if (priority != null) 'priority': priority,
        if (severity != null) 'severity': severity,
        if (assignedModerator != null) 'assignedModerator': assignedModerator,
        if (dateFrom != null) 'dateFrom': dateFrom.toIso8601String(),
        if (dateTo != null) 'dateTo': dateTo.toIso8601String(),
        if (sortBy != null) 'sortBy': sortBy,
        if (sortOrder != null) 'sortOrder': sortOrder,
      };

      final uri = Uri.parse('${AppConfig.baseUrl}$_baseUrl').replace(
        queryParameters: queryParams,
      );

      final response = await http
          .get(
            uri,
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));

      print('📡 Get reports list response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['success'] == true) {
          final reportsList = (responseData['data'] as List)
              .map((item) => ReportModel.fromJson(item))
              .toList();

          return {
            'reports': reportsList,
            'pagination': responseData['pagination'],
          };
        } else {
          throw Exception(
              responseData['message'] ?? 'Failed to get reports list');
        }
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to get reports list');
      }
    } catch (e) {
      print('❌ Error getting reports list: $e');
      rethrow;
    }
  }

  /// Get reports by user
  Future<List<ReportModel>> getReportsByUser(String userId,
      {int limit = 10}) async {
    try {
      print('👤 Getting reports for user: $userId');

      final headers = await _getHeaders();
      final response = await http
          .get(
            Uri.parse(
                '${AppConfig.baseUrl}$_baseUrl/user/$userId?limit=$limit'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));

      print('📡 Get user reports response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['success'] == true) {
          return (responseData['data'] as List)
              .map((item) => ReportModel.fromJson(item))
              .toList();
        } else {
          throw Exception(
              responseData['message'] ?? 'Failed to get user reports');
        }
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to get user reports');
      }
    } catch (e) {
      print('❌ Error getting user reports: $e');
      rethrow;
    }
  }

  /// Get reports by video (Admin/Moderator only)
  Future<List<ReportModel>> getReportsByVideo(String videoId,
      {int limit = 10}) async {
    try {
      print('🎥 Getting reports for video: $videoId');

      final headers = await _getHeaders();
      final response = await http
          .get(
            Uri.parse(
                '${AppConfig.baseUrl}$_baseUrl/video/$videoId?limit=$limit'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));

      print('📡 Get video reports response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['success'] == true) {
          return (responseData['data'] as List)
              .map((item) => ReportModel.fromJson(item))
              .toList();
        } else {
          throw Exception(
              responseData['message'] ?? 'Failed to get video reports');
        }
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to get video reports');
      }
    } catch (e) {
      print('❌ Error getting video reports: $e');
      rethrow;
    }
  }

  /// Update report status (Admin/Moderator only)
  Future<ReportModel> updateReportStatus(
    String id,
    String status, {
    String? moderatorNotes,
    String? actionTaken,
  }) async {
    try {
      print('📝 Updating report status: $id -> $status');

      final headers = await _getHeaders();
      final body = {
        'status': status,
        if (moderatorNotes != null) 'moderatorNotes': moderatorNotes,
        if (actionTaken != null) 'actionTaken': actionTaken,
      };

      final response = await http
          .patch(
            Uri.parse('${AppConfig.baseUrl}$_baseUrl/$id/status'),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      print('📡 Update report status response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['success'] == true) {
          return ReportModel.fromJson(responseData['data']);
        } else {
          throw Exception(
              responseData['message'] ?? 'Failed to update report status');
        }
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(
            errorData['message'] ?? 'Failed to update report status');
      }
    } catch (e) {
      print('❌ Error updating report status: $e');
      rethrow;
    }
  }

  /// Assign report to moderator (Admin only)
  Future<ReportModel> assignToModerator(String id, String moderatorId) async {
    try {
      print('👨‍💼 Assigning report to moderator: $id -> $moderatorId');

      final headers = await _getHeaders();
      final body = {'moderatorId': moderatorId};

      final response = await http
          .patch(
            Uri.parse('${AppConfig.baseUrl}$_baseUrl/$id/assign'),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      print('📡 Assign report response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['success'] == true) {
          return ReportModel.fromJson(responseData['data']);
        } else {
          throw Exception(responseData['message'] ?? 'Failed to assign report');
        }
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to assign report');
      }
    } catch (e) {
      print('❌ Error assigning report: $e');
      rethrow;
    }
  }

  /// Find related reports (Admin/Moderator only)
  Future<List<ReportModel>> findRelatedReports(String id) async {
    try {
      print('🔗 Finding related reports: $id');

      final headers = await _getHeaders();
      final response = await http
          .get(
            Uri.parse('${AppConfig.baseUrl}$_baseUrl/$id/related'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));

      print('📡 Find related reports response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['success'] == true) {
          return (responseData['data'] as List)
              .map((item) => ReportModel.fromJson(item))
              .toList();
        } else {
          throw Exception(
              responseData['message'] ?? 'Failed to find related reports');
        }
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(
            errorData['message'] ?? 'Failed to find related reports');
      }
    } catch (e) {
      print('❌ Error finding related reports: $e');
      rethrow;
    }
  }

  /// Escalate report (Moderator/Admin only)
  Future<ReportModel> escalateReport(String id, String escalationReason) async {
    try {
      print('⬆️ Escalating report: $id');

      final headers = await _getHeaders();
      final body = {'escalationReason': escalationReason};

      final response = await http
          .patch(
            Uri.parse('${AppConfig.baseUrl}$_baseUrl/$id/escalate'),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      print('📡 Escalate report response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['success'] == true) {
          return ReportModel.fromJson(responseData['data']);
        } else {
          throw Exception(
              responseData['message'] ?? 'Failed to escalate report');
        }
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to escalate report');
      }
    } catch (e) {
      print('❌ Error escalating report: $e');
      rethrow;
    }
  }

  /// Get report statistics (Admin/Moderator only)
  Future<ReportStats> getReportStats() async {
    try {
      print('📊 Getting report statistics');

      final headers = await _getHeaders();
      final response = await http
          .get(
            Uri.parse('${AppConfig.baseUrl}$_baseUrl/stats/overview'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));

      print('📡 Get report stats response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['success'] == true) {
          return ReportStats.fromJson(responseData['data']);
        } else {
          throw Exception(
              responseData['message'] ?? 'Failed to get report stats');
        }
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to get report stats');
      }
    } catch (e) {
      print('❌ Error getting report stats: $e');
      rethrow;
    }
  }

  /// Delete report (Admin only)
  Future<void> deleteReport(String id) async {
    try {
      print('🗑️ Deleting report: $id');

      final headers = await _getHeaders();
      final response = await http
          .delete(
            Uri.parse('${AppConfig.baseUrl}$_baseUrl/$id'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));

      print('📡 Delete report response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['success'] == true) {
          print('✅ Report deleted successfully');
        } else {
          throw Exception(responseData['message'] ?? 'Failed to delete report');
        }
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to delete report');
      }
    } catch (e) {
      print('❌ Error deleting report: $e');
      rethrow;
    }
  }
}
