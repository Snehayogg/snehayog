import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:snehayog/config/app_config.dart';
import 'package:snehayog/services/authservices.dart';

class CloudinaryService {
  static final CloudinaryService _instance = CloudinaryService._internal();
  factory CloudinaryService() => _instance;
  CloudinaryService._internal();

  /// Upload image through your backend (which handles Cloudinary)
  Future<String> uploadImage(File imageFile, {String? folder}) async {
    try {
      // Get user data for authentication
      final authService = AuthService();
      final userData = await authService.getUserData();

      if (userData == null) {
        throw Exception('User not authenticated');
      }

      // Create multipart request to your backend
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${AppConfig.baseUrl}/api/upload/image'),
      );

      // Add authorization header
      request.headers['Authorization'] = 'Bearer ${userData['token']}';

      // Add the image file
      request.files.add(
        await http.MultipartFile.fromPath('image', imageFile.path),
      );

      // Add folder if specified
      if (folder != null) {
        request.fields['folder'] = folder;
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return data['url'] ?? '';
        } else {
          throw Exception('Upload failed: ${data['error'] ?? 'Unknown error'}');
        }
      } else {
        final errorData = json.decode(response.body);
        throw Exception(
            'Failed to upload image: ${errorData['error'] ?? response.body}');
      }
    } catch (e) {
      throw Exception('Error uploading image: $e');
    }
  }

  /// Upload video through your backend with custom streaming profile
  Future<Map<String, dynamic>> uploadVideo(
    File videoFile, {
    String? folder,
    String profile = 'portrait_reels',
    bool enableHLS = true,
  }) async {
    try {
      // Get user data for authentication
      final authService = AuthService();
      final userData = await authService.getUserData();

      if (userData == null) {
        throw Exception('User not authenticated');
      }

      // Use the correct endpoint based on upload type
      // For user videos, use /videos/upload (which has HLS enabled by default)
      // For ads/creatives, use /upload/video
      const endpoint = '/videos/upload';

      // Create multipart request to your backend
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${AppConfig.baseUrl}/api$endpoint'),
      );

      // Add authorization header
      request.headers['Authorization'] = 'Bearer ${userData['token']}';

      // Add the video file
      request.files.add(
        await http.MultipartFile.fromPath('video', videoFile.path),
      );

      // Add folder if specified
      if (folder != null) {
        request.fields['folder'] = folder;
      }

      // Add profile if not using HLS endpoint
      if (!enableHLS && profile.isNotEmpty) {
        request.fields['profile'] = profile;
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return data;
        } else {
          throw Exception('Upload failed: ${data['error'] ?? 'Unknown error'}');
        }
      } else {
        final errorData = json.decode(response.body);
        throw Exception(
            'Failed to upload video: ${errorData['error'] ?? response.body}');
      }
    } catch (e) {
      throw Exception('Error uploading video: $e');
    }
  }

  /// Upload video with HLS streaming profile (portrait reels optimized)
  Future<Map<String, dynamic>> uploadVideoHLS(
    File videoFile, {
    String? folder,
  }) async {
    return await uploadVideo(
      videoFile,
      folder: folder,
      profile: 'portrait_reels',
      enableHLS: true,
    );
  }

  /// Upload video for ads/creatives (uses different endpoint)
  Future<Map<String, dynamic>> uploadVideoForAd(
    File videoFile, {
    String? folder,
    String profile = 'portrait_reels',
  }) async {
    try {
      // Get user data for authentication
      final authService = AuthService();
      final userData = await authService.getUserData();

      if (userData == null) {
        throw Exception('User not authenticated');
      }

      // Use the ads/creatives endpoint
      const endpoint = '/upload/video';

      // Create multipart request to your backend
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${AppConfig.baseUrl}/api$endpoint'),
      );

      // Add authorization header
      request.headers['Authorization'] = 'Bearer ${userData['token']}';

      // Add the video file
      request.files.add(
        await http.MultipartFile.fromPath('video', videoFile.path),
      );

      // Add folder if specified
      if (folder != null) {
        request.fields['folder'] = folder;
      }

      // Add profile
      if (profile.isNotEmpty) {
        request.fields['profile'] = profile;
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return data;
        } else {
          throw Exception('Upload failed: ${data['error'] ?? 'Unknown error'}');
        }
      } else {
        final errorData = json.decode(response.body);
        throw Exception(
            'Failed to upload video: ${errorData['error'] ?? response.body}');
      }
    } catch (e) {
      throw Exception('Error uploading video for ad: $e');
    }
  }

  /// Get streaming URLs for existing video
  Future<Map<String, dynamic>> getVideoStreamingUrls(
    String publicId, {
    String profile = 'portrait_reels',
  }) async {
    try {
      // Get user data for authentication
      final authService = AuthService();
      final userData = await authService.getUserData();

      if (userData == null) {
        throw Exception('User not authenticated');
      }

      final response = await http.get(
        Uri.parse(
            '${AppConfig.baseUrl}/api/upload/video-streaming-urls/$publicId?profile=$profile'),
        headers: {
          'Authorization': 'Bearer ${userData['token']}',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return data;
        } else {
          throw Exception(
              'Failed to get streaming URLs: ${data['error'] ?? 'Unknown error'}');
        }
      } else {
        final errorData = json.decode(response.body);
        throw Exception(
            'Failed to get streaming URLs: ${errorData['error'] ?? response.body}');
      }
    } catch (e) {
      throw Exception('Error getting streaming URLs: $e');
    }
  }

  /// Delete media through your backend
  Future<bool> deleteMedia(String publicId, String resourceType) async {
    try {
      final response = await http.delete(
        Uri.parse('${AppConfig.baseUrl}/api/upload/delete'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'public_id': publicId,
          'resource_type': resourceType,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Error deleting media: $e');
      return false;
    }
  }

  /// Get optimized URL for different screen sizes
  String getOptimizedUrl(String originalUrl, {int? width, int? height}) {
    if (originalUrl.isEmpty) return originalUrl;

    // If it's a Cloudinary URL, apply transformations
    if (originalUrl.contains('cloudinary.com')) {
      final uri = Uri.parse(originalUrl);
      final pathSegments = List<String>.from(uri.pathSegments);

      if (pathSegments.length >= 3 && pathSegments[1] == 'upload') {
        // Insert transformation before 'upload'
        String transformation = 'f_auto,q_auto';
        if (width != null) transformation += ',w_$width';
        if (height != null) transformation += ',h_$height';
        transformation += ',c_fill';

        pathSegments.insert(2, transformation);
        return uri.replace(pathSegments: pathSegments).toString();
      }
    }

    return originalUrl;
  }

  /// Get thumbnail URL for videos
  String getVideoThumbnailUrl(String videoUrl) {
    if (videoUrl.isEmpty) return videoUrl;

    // If it's a Cloudinary URL, apply thumbnail transformation
    if (videoUrl.contains('cloudinary.com')) {
      final uri = Uri.parse(videoUrl);
      final pathSegments = List<String>.from(uri.pathSegments);

      if (pathSegments.length >= 3 && pathSegments[1] == 'upload') {
        // Insert thumbnail transformation
        pathSegments.insert(2, 'f_jpg,w_400,h_600,c_fill');
        return uri.replace(pathSegments: pathSegments).toString();
      }
    }

    return videoUrl;
  }

  /// Get HLS streaming URL for video
  String getHLSStreamingUrl(String publicId,
      {String profile = 'portrait_reels'}) {
    if (publicId.isEmpty) return '';

    // Generate HLS URL based on profile
    switch (profile.toLowerCase()) {
      case 'portrait_reels':
        return 'https://res.cloudinary.com/${AppConfig.cloudinaryCloudName}/video/upload/w_1080,h_1920,c_fill,vc_h264,b_3.5m,ac_aac,ab_128k,fps_30,ki_60,du_2,sp_hd,q_auto:best/w_720,h_1280,c_fill,vc_h264,b_1.8m,ac_aac,ab_128k,fps_30,ki_60,du_2,sp_hd,q_auto:good/w_480,h_854,c_fill,vc_h264,b_0.9m,ac_aac,ab_96k,fps_30,ki_60,du_2,sp_sd,q_auto:eco/w_360,h_640,c_fill,vc_h264,b_0.6m,ac_aac,ab_64k,fps_30,ki_60,du_2,sp_sd,q_auto:low/fl_sanitize,fl_attachment,fl_hlsv3,fl_sep,fl_dpr_auto,fl_quality_auto/$publicId.m3u8';

      case 'landscape_standard':
        return 'https://res.cloudinary.com/${AppConfig.cloudinaryCloudName}/video/upload/w_1920,h_1080,c_fill,vc_h264,b_4.0m,ac_aac,ab_128k,fps_30,ki_60,du_2,sp_hd,q_auto:best/w_1280,h_720,c_fill,vc_h264,b_2.0m,ac_aac,ab_128k,fps_30,ki_60,du_2,sp_hd,q_auto:good/w_854,h_480,c_fill,vc_h264,b_1.0m,ac_aac,ab_96k,fps_30,ki_60,du_2,sp_sd,q_auto:eco/fl_sanitize,fl_attachment,fl_hlsv3,fl_sep,fl_dpr_auto,fl_quality_auto/$publicId.m3u8';

      default:
        return 'https://res.cloudinary.com/${AppConfig.cloudinaryCloudName}/video/upload/w_720,h_1280,c_fill,vc_h264,b_1.8m,ac_aac,ab_128k,fps_30,ki_60,du_2,sp_hd,q_auto:good/fl_sanitize,fl_attachment,fl_hlsv3,fl_sep,fl_dpr_auto,fl_quality_auto/$publicId.m3u8';
    }
  }

  /// Get master playlist URL for ABR
  String getMasterPlaylistUrl(String publicId,
      {String profile = 'portrait_reels'}) {
    if (publicId.isEmpty) return '';

    // Generate master playlist URL for ABR
    switch (profile.toLowerCase()) {
      case 'portrait_reels':
        return 'https://res.cloudinary.com/${AppConfig.cloudinaryCloudName}/video/upload/w_1080,h_1920,c_fill,vc_h264,b_3.5m,ac_aac,ab_128k,fps_30,ki_60,du_2,sp_hd,q_auto:best/w_720,h_1280,c_fill,vc_h264,b_1.8m,ac_aac,ab_128k,fps_30,ki_60,du_2,sp_hd,q_auto:good/w_480,h_854,c_fill,vc_h264,b_0.9m,ac_aac,ab_96k,fps_30,ki_60,du_2,sp_sd,q_auto:eco/w_360,h_640,c_fill,vc_h264,b_0.6m,ac_aac,ab_64k,fps_30,ki_60,du_2,sp_sd,q_auto:low/fl_sanitize,fl_attachment,fl_hlsv3,fl_sep,fl_dpr_auto,fl_quality_auto,fl_master_playlist/$publicId.m3u8';

      case 'landscape_standard':
        return 'https://res.cloudinary.com/${AppConfig.cloudinaryCloudName}/video/upload/w_1920,h_1080,c_fill,vc_h264,b_4.0m,ac_aac,ab_128k,fps_30,ki_60,du_2,sp_hd,q_auto:best/w_1280,h_720,c_fill,vc_h264,b_2.0m,ac_aac,ab_128k,fps_30,ki_60,du_2,sp_hd,q_auto:good/w_854,h_480,c_fill,vc_h264,b_1.0m,ac_aac,ab_96k,fps_30,ki_60,du_2,sp_sd,q_auto:eco/fl_sanitize,fl_attachment,fl_hlsv3,fl_sep,fl_dpr_auto,fl_quality_auto,fl_master_playlist/$publicId.m3u8';

      default:
        return 'https://res.cloudinary.com/${AppConfig.cloudinaryCloudName}/video/upload/w_720,h_1280,c_fill,vc_h264,b_1.8m,ac_aac,ab_128k,fps_30,ki_60,du_2,sp_hd,q_auto:good/fl_sanitize,fl_attachment,fl_hlsv3,fl_sep,fl_dpr_auto,fl_quality_auto,fl_master_playlist/$publicId.m3u8';
    }
  }

  /// Get optimized thumbnail URL for video
  String getOptimizedThumbnailUrl(String publicId,
      {int width = 400, int height = 600}) {
    if (publicId.isEmpty) return '';

    return 'https://res.cloudinary.com/${AppConfig.cloudinaryCloudName}/video/upload/w_$width,h_$height,c_fill,fl_sanitize/$publicId.jpg';
  }

  /// **NEW: Check if backend upload endpoints are available**
  Future<bool> isBackendUploadAvailable() async {
    try {
      final response = await http
          .get(
            Uri.parse('${AppConfig.baseUrl}/api/upload/health'),
          )
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Get streaming profile information
  Map<String, dynamic> getStreamingProfileInfo(String profile) {
    switch (profile.toLowerCase()) {
      case 'portrait_reels':
        return {
          'name': 'Portrait Reels',
          'aspect_ratio': '9:16',
          'quality_levels': [
            {'resolution': '1080x1920', 'bitrate': '3.5 Mbps', 'profile': 'HD'},
            {'resolution': '720x1280', 'bitrate': '1.8 Mbps', 'profile': 'HD'},
            {'resolution': '480x854', 'bitrate': '0.9 Mbps', 'profile': 'SD'},
            {'resolution': '360x640', 'bitrate': '0.6 Mbps', 'profile': 'SD'},
          ],
          'segment_duration': 2,
          'keyframe_interval': 2,
          'optimized_for': 'Mobile Scrolling',
          'description': 'Optimized for Instagram Reels style vertical videos'
        };

      case 'landscape_standard':
        return {
          'name': 'Landscape Standard',
          'aspect_ratio': '16:9',
          'quality_levels': [
            {'resolution': '1920x1080', 'bitrate': '4.0 Mbps', 'profile': 'HD'},
            {'resolution': '1280x720', 'bitrate': '2.0 Mbps', 'profile': 'HD'},
            {'resolution': '854x480', 'bitrate': '1.0 Mbps', 'profile': 'SD'},
          ],
          'segment_duration': 2,
          'keyframe_interval': 2,
          'optimized_for': 'Standard Video',
          'description': 'Optimized for traditional landscape videos'
        };

      default:
        return {
          'name': 'Default Profile',
          'aspect_ratio': '16:9',
          'quality_levels': [
            {'resolution': '720x1280', 'bitrate': '1.8 Mbps', 'profile': 'HD'},
          ],
          'segment_duration': 2,
          'keyframe_interval': 2,
          'optimized_for': 'General Use',
          'description': 'Default streaming profile'
        };
    }
  }
}
