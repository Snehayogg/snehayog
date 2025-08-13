import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:snehayog/config/app_config.dart';

class CloudinaryService {
  static final CloudinaryService _instance = CloudinaryService._internal();
  factory CloudinaryService() => _instance;
  CloudinaryService._internal();

  static String get cloudName => AppConfig.cloudinaryCloudName;
  static String get apiKey => AppConfig.cloudinaryApiKey;
  static String get apiSecret => AppConfig.cloudinaryApiSecret;
  static String get uploadPreset => AppConfig.cloudinaryUploadPreset;

  /// Upload image to Cloudinary
  Future<String> uploadImage(File imageFile, {String? folder}) async {
    try {
      // Create multipart request
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload'),
      );

      // Add upload preset
      request.fields['upload_preset'] = uploadPreset;
      
      // Add folder if specified
      if (folder != null) {
        request.fields['folder'] = folder;
      }

      // Add image file
      request.files.add(
        await http.MultipartFile.fromPath('file', imageFile.path),
      );

      // Add transformation parameters for optimization
      request.fields['transformation'] = 'f_auto,q_auto,w_1920,h_1080,c_fill';

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['secure_url'];
      } else {
        throw Exception('Failed to upload image: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error uploading image to Cloudinary: $e');
    }
  }

  /// Upload video to Cloudinary
  Future<String> uploadVideo(File videoFile, {String? folder}) async {
    try {
      // Create multipart request
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/video/upload'),
      );

      // Add upload preset
      request.fields['upload_preset'] = uploadPreset;
      
      // Add folder if specified
      if (folder != null) {
        request.fields['folder'] = folder;
      }

      // Add video file
      request.files.add(
        await http.MultipartFile.fromPath('file', videoFile.path),
      );

      // Add transformation parameters for optimization
      request.fields['transformation'] = 'f_auto,q_auto,w_1080,h_1920,c_fill';

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['secure_url'];
      } else {
        throw Exception('Failed to upload video: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error uploading video to Cloudinary: $e');
    }
  }

  /// Delete media from Cloudinary
  Future<bool> deleteMedia(String publicId, String resourceType) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final signature = _generateSignature(publicId, timestamp);

      final response = await http.post(
        Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/$resourceType/destroy'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'public_id': publicId,
          'timestamp': timestamp,
          'api_key': apiKey,
          'signature': signature,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Error deleting media from Cloudinary: $e');
      return false;
    }
  }

  /// Generate signature for authenticated requests
  String _generateSignature(String publicId, int timestamp) {
    final params = {
      'public_id': publicId,
      'timestamp': timestamp.toString(),
    };

    // Sort parameters alphabetically
    final sortedParams = params.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    // Create query string
    final queryString = sortedParams
        .map((e) => '${e.key}=${e.value}')
        .join('&');

    // Add API secret
    final signatureString = queryString + apiSecret;

    // Generate SHA1 hash
    final bytes = utf8.encode(signatureString);
    final digest = sha1.convert(bytes);

    return digest.toString();
  }

  /// Get optimized URL for different screen sizes
  String getOptimizedUrl(String originalUrl, {int? width, int? height}) {
    if (originalUrl.isEmpty) return originalUrl;
    
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
    
    return originalUrl;
  }

  /// Get thumbnail URL for videos
  String getVideoThumbnailUrl(String videoUrl) {
    if (videoUrl.isEmpty) return videoUrl;
    
    final uri = Uri.parse(videoUrl);
    final pathSegments = List<String>.from(uri.pathSegments);
    
    if (pathSegments.length >= 3 && pathSegments[1] == 'upload') {
      // Insert thumbnail transformation
      pathSegments.insert(2, 'f_jpg,w_400,h_600,c_fill');
      return uri.replace(pathSegments: pathSegments).toString();
    }
    
    return videoUrl;
  }
}
