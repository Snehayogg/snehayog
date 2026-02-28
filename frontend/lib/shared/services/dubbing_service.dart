import 'dart:io';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:vayu/shared/config/app_config.dart';
import 'package:vayu/shared/services/http_client_service.dart';
import 'package:vayu/shared/utils/app_logger.dart';

class DubbingService {
  static final DubbingService instance = DubbingService._internal();
  DubbingService._internal();

  /// Start smart dubbing for an existing video or a new gallery video
  Future<String?> startSmartDub({
    String? videoId,
    File? videoFile,
  }) async {
    try {
      final url = '${NetworkHelper.apiBaseUrl}/dubbing/process';
      
      final Map<String, dynamic> fields = {
        if (videoId != null) 'videoId': videoId,
      };

      final List<MapEntry<String, MultipartFile>> files = [];
      if (videoFile != null) {
        files.add(MapEntry(
          'video',
          await MultipartFile.fromFile(videoFile.path, filename: 'video_to_dub.mp4'),
        ));
      }

      final response = await httpClientService.postMultipart(
        url,
        fields: fields,
        files: files,
      );

      if (response.statusCode == 202) {
        return response.data['taskId'];
      }
      return null;
    } catch (e) {
      AppLogger.log('❌ DubbingService Error: $e');
      return null;
    }
  }

  /// Get the status of a dubbing task
  Future<Map<String, dynamic>?> getTaskStatus(String taskId) async {
    try {
      final url = Uri.parse('${NetworkHelper.apiBaseUrl}/dubbing/status/$taskId');
      final response = await httpClientService.get(url);
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      AppLogger.log('❌ DubbingService Status Error: $e');
      return null;
    }
  }

  /// Upload a finished dubbed video to the server for global caching
  Future<String?> uploadDubbedVideo({
    required String videoId,
    required String language,
    required File dubbedFile,
  }) async {
    try {
      final url = '${NetworkHelper.apiBaseUrl}/dubbing/upload';
      
      final Map<String, dynamic> fields = {
        'videoId': videoId,
        'language': language,
      };

      final List<MapEntry<String, MultipartFile>> files = [
        MapEntry(
          'video',
          await MultipartFile.fromFile(dubbedFile.path, filename: 'dubbed_${videoId}_$language.mp4'),
        ),
      ];

      AppLogger.log('🌐 Starting Global Upload: $url');
      AppLogger.log('   VideoID: $videoId, Language: $language');
      AppLogger.log('   File Size: ${dubbedFile.lengthSync()} bytes');

      final response = await httpClientService.postMultipart(
        url,
        fields: fields,
        files: files,
      );

      AppLogger.log('🌐 Global Upload Response: ${response.statusCode} - ${response.data}');

      if (response.statusCode == 200) {
        return response.data['url'];
      }
      return null;
    } catch (e) {
      AppLogger.log('❌ uploadDubbedVideo Error: $e');
      return null;
    }
  }
}

final dubbingService = DubbingService.instance;
