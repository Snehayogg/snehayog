import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
// Removed camera/gallery picking as per async-only Files selection
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
// import 'package:snehayog/services/video_service.dart'; // unused in async-only
import 'package:snehayog/services/authservices.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snehayog/view/screens/create_ad_screen_refactored.dart';
import 'package:snehayog/view/screens/ad_management_screen.dart';
import 'package:snehayog/core/constants/interests.dart';
import 'package:snehayog/config/app_config.dart';
import 'package:snehayog/services/network_service.dart';
import 'package:snehayog/services/video_processing_service.dart';
import 'package:snehayog/view/widget/video_processing_progress.dart';

class UploadScreen extends StatefulWidget {
  final VoidCallback? onVideoUploaded; // Add callback for video upload success

  const UploadScreen({super.key, this.onVideoUploaded});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  File? _selectedVideo;
  bool _isUploading = false;
  bool _isProcessing = false;
  String? _errorMessage;
  bool _showUploadForm = false;

  double _uploadProgress = 0.0;
  int _uploadStartTime = 0;
  int _elapsedSeconds = 0;
  String _uploadStatus = '';

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _linkController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  // final VideoService _videoService = VideoService(); // not used in async-only flow
  final AuthService _authService = AuthService();

  // Timer for upload progress
  Timer? _uploadTimer;

  // NEW: Category and Tags to align with ad targeting interests
  String? _selectedCategory;
  final List<String> _tags = [];
  final TextEditingController _tagInputController = TextEditingController();

  // Video type selection
  String _selectedVideoType =
      'yog'; // 'yog' for short videos, 'vayu' for images

  // Advanced options toggle
  bool _showAdvancedOptions = false;

  // Professional helper to render a notice bullet point
  Widget _buildNoticePoint({required String title, required String body}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade800,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  // Show Terms & Conditions (What to Upload?) in a professional bottom sheet
  void _showWhatToUploadDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) => Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              controller: scrollController,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.gavel, color: Colors.red.shade700),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'What to Upload? \nSnehayog Terms & Conditions (Copyright Policy)',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      )
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildNoticePoint(
                    title: '1. User Responsibility',
                    body:
                        'By uploading, you confirm you are the original creator or have legal rights/permission to use this content. Do not upload media that infringes on others\' copyright, trademark, or intellectual property.',
                  ),
                  _buildNoticePoint(
                    title: '2. Copyright Infringement',
                    body:
                        'If you upload content belonging to someone else without permission, you (the uploader) will be fully responsible for any legal consequences. Snehayog acts only as a platform and does not own or endorse user-uploaded content.',
                  ),
                  _buildNoticePoint(
                    title: '3. Reporting Copyright Violation',
                    body:
                        'Copyright owners may submit a takedown request by emailing: copyright@snehayog.com with proof of ownership. Upon receiving a valid request, Snehayog will remove the infringing content within 48 hours.',
                  ),
                  _buildNoticePoint(
                    title: '4. Payment & Revenue Sharing',
                    body:
                        'All creator payments are subject to a 30-day hold for copyright checks and disputes. If a video is found infringing during this period, the payout will be cancelled and may be withheld.',
                  ),
                  _buildNoticePoint(
                    title: '5. Strike Policy',
                    body:
                        '1st Strike → Warning & content removal.  2nd Strike → Payment account on hold for 60 days.  3rd Strike → Permanent ban, with forfeiture of unpaid earnings.',
                  ),
                  _buildNoticePoint(
                    title: '6. Limitation of Liability',
                    body:
                        'Snehayog, as an intermediary platform, is not liable for user-uploaded content under the IT Act 2000 (India) and DMCA (international). All responsibility for copyright compliance lies with the content uploader.',
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('I Understand'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: Colors.red.shade600,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
  }

  Future<void> _pickMedia() async {
    final userData = await _authService.getUserData();
    if (userData == null) {
      _showLoginPrompt();
      return;
    }

    try {
      FilePickerResult? result;

      if (_selectedVideoType == 'vayu') {
        // For images
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowMultiple: false,
          allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'webp'],
        );
      } else {
        // For videos
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowMultiple: false,
          allowedExtensions: [
            'mp4',
            'avi',
            'mov',
            'wmv',
            'flv',
            'webm',
            'm4v',
            'mkv',
            '3gp',
            'mpeg',
            'mpg'
          ],
        );
      }

      if (result != null) {
        setState(() {
          _isProcessing = true;
          _errorMessage = null;
        });

        final videoFile = File(result.files.single.path!);

        final fileSize = await videoFile.length();

        // Different size limits for images vs videos
        final maxSize = _selectedVideoType == 'vayu'
            ? 10 * 1024 * 1024 // 10MB for images
            : 100 * 1024 * 1024; // 100MB for videos

        if (fileSize > maxSize) {
          setState(() {
            _errorMessage = _selectedVideoType == 'vayu'
                ? 'Image file is too large. Maximum size is 10MB'
                : 'Video file is too large. Maximum size is 100MB';
            _isProcessing = false;
          });
          return;
        }

        // Validate file extension
        final fileName = videoFile.path.split('/').last.toLowerCase();
        final allowedExtensions = _selectedVideoType == 'vayu'
            ? ['.jpg', '.jpeg', '.png', '.gif', '.webp']
            : [
                '.mp4',
                '.avi',
                '.mov',
                '.wmv',
                '.flv',
                '.webm',
                '.m4v',
                '.mkv',
                '.3gp',
                '.mpeg',
                '.mpg'
              ];

        if (!allowedExtensions.any((ext) => fileName.endsWith(ext))) {
          setState(() {
            _errorMessage = _selectedVideoType == 'vayu'
                ? 'Invalid file type. Please select an image file (.jpg, .png, .gif, etc.)'
                : 'Invalid file type. Please select a video file (.mp4, .avi, .mov, etc.)';
            _isProcessing = false;
          });
          return;
        }

        setState(() {
          _selectedVideo = videoFile;
          _isProcessing = false;
        });

        print(
            '✅ ${_selectedVideoType == 'vayu' ? 'Image' : 'Video'} selected: ${videoFile.path}');
        print(
            '📏 File size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');
        print('📋 File extension: ${fileName.split('.').last}');
      }
    } catch (e) {
      setState(() {
        _errorMessage =
            'Error picking ${_selectedVideoType == 'vayu' ? 'image' : 'video'}: $e';
        _isProcessing = false;
      });
    }
  }

  // Camera/Gallery selection removed per async-only Files requirement

  void _showLoginPrompt() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Login Required'),
        content: const Text('Please sign in to upload videos.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _authService.signInWithGoogle();
            },
            child: const Text('Sign In'),
          ),
        ],
      ),
    );
  }

  /// Check server connectivity before upload
  Future<bool> _checkServerConnectivity() async {
    try {
      // Use NetworkService directly to ensure proper initialization
      final networkService = NetworkService.instance;
      await networkService.initialize();

      final response = await http.get(
        Uri.parse('${networkService.baseUrl}/health'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      print(
          '✅ Server connectivity check successful: ${networkService.baseUrl}');
      return response.statusCode == 200;
    } catch (e) {
      print('❌ Server connectivity check failed: $e');
      print('🔍 Current base URL: ${AppConfig.baseUrl}');

      // Try fallback URLs (local first, then production)
      final fallbackUrls = [
        'http://192.168.0.199:5001',
        'http://localhost:5001',
        'https://snehayog-production.up.railway.app',
      ];

      for (final url in fallbackUrls) {
        try {
          final response = await http.get(
            Uri.parse('$url/health'),
            headers: {'Content-Type': 'application/json'},
          ).timeout(const Duration(seconds: 5));

          if (response.statusCode == 200) {
            print('✅ Fallback server working: $url');
            return true;
          }
        } catch (e) {
          print('❌ Fallback server failed: $url - $e');
        }
      }

      return false;
    }
  }

  /// Synchronous video upload method (restored)
  Future<void> _uploadVideoSync() async {
    final userData = await _authService.getUserData();
    if (userData == null) {
      _showLoginPrompt();
      return;
    }

    if (_selectedVideo == null) {
      setState(() {
        _errorMessage = 'Please select a video first';
      });
      return;
    }

    if (_titleController.text.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a title for the video';
      });
      return;
    }

    setState(() {
      _isUploading = true;
      _errorMessage = null;
    });

    try {
      print('🚀 Starting synchronous video upload...');
      print('📁 Video path: ${_selectedVideo!.path}');
      print('📝 Title: ${_titleController.text}');

      // Start upload progress tracking
      _startUploadProgress();

      // Check server connectivity first
      print('🔍 Checking server connectivity...');
      final isServerOnline = await _checkServerConnectivity();
      if (!isServerOnline) {
        setState(() {
          _errorMessage =
              'Server is not reachable. Please check your internet connection and try again.';
          _isUploading = false;
        });
        return;
      }
      print('✅ Server is online, proceeding with upload...');

      // Get auth token
      final authToken = await _getAuthToken();
      if (authToken == null) {
        setState(() {
          _errorMessage = 'Please login to upload videos';
          _isUploading = false;
        });
        return;
      }

      // Upload video synchronously using the original upload endpoint
      final result = await _uploadVideoSyncRequest(
        videoFile: _selectedVideo!,
        videoName: _titleController.text.trim(),
        authToken: authToken,
        description: _linkController.text.trim().isNotEmpty
            ? _linkController.text.trim()
            : null,
      );

      if (result['success'] == true) {
        print('✅ Video upload completed successfully!');

        final responseVideo = result['video'];
        final processingStatus = responseVideo['processingStatus'];

        if (processingStatus == 'completed') {
          // Video fully processed
          setState(() {
            _uploadStatus = '🎉 Video uploaded and processed successfully!';
            _uploadProgress = 1.0;
          });
          await _showSuccessDialog();
        } else {
          // Video uploaded, processing in background
          setState(() {
            _uploadStatus = '✅ Video uploaded! Processing in background...';
            _uploadProgress = 0.8; // 80% for upload completion
          });

          // Show different dialog for background processing
          await _showBackgroundProcessingDialog(responseVideo['id']);
        }

        // Call the callback to refresh video list
        if (widget.onVideoUploaded != null) {
          widget.onVideoUploaded!();
        }

        // Clear form
        setState(() {
          _selectedVideo = null;
          _titleController.clear();
          _linkController.clear();
          _urlController.clear();
          _selectedCategory = null;
          _tags.clear();
          _showAdvancedOptions = false;
        });
      } else {
        setState(() {
          _errorMessage = result['error'] ?? 'Upload failed';
          _isUploading = false;
        });
      }
    } catch (e) {
      print('Error uploading video: $e');
      setState(() {
        _errorMessage = 'Error uploading video: ${e.toString()}';
        _isUploading = false;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
        _stopUploadProgress();
      }
    }
  }

  /// Synchronous upload request to original endpoint with retry logic
  Future<Map<String, dynamic>> _uploadVideoSyncRequest({
    required File videoFile,
    required String videoName,
    required String authToken,
    String? description,
  }) async {
    const maxRetries = 3;
    const retryDelay = Duration(seconds: 2);

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        print('🚀 Starting upload request (Attempt $attempt/$maxRetries)...');
        print('📁 Video file path: ${videoFile.path}');
        print('📝 Video name: $videoName');
        print('🔑 Auth token: ${authToken.substring(0, 20)}...');

        // Ensure NetworkService is initialized
        final networkService = NetworkService.instance;
        await networkService.initialize();

        final request = http.MultipartRequest(
          'POST',
          Uri.parse('${networkService.baseUrl}/api/videos/upload'),
        );

        // Optimized connection settings for faster uploads
        request.headers['Authorization'] = 'Bearer $authToken';
        request.headers['Connection'] = 'keep-alive';
        request.headers['Cache-Control'] = 'no-cache';
        request.headers['Accept-Encoding'] =
            'gzip, deflate'; // Enable compression
        request.headers['User-Agent'] = 'Snehayog-App/1.0';

        // Add video file with explicit MIME type
        final videoMultipartFile = await http.MultipartFile.fromPath(
          'video',
          videoFile.path,
          filename: videoFile.path.split('/').last,
          contentType: MediaType('video', 'mp4'), // Explicit MIME type
        );

        print('📎 Multipart file details:');
        print('   Field name: ${videoMultipartFile.field}');
        print('   Filename: ${videoMultipartFile.filename}');
        print('   Content type: ${videoMultipartFile.contentType}');

        request.files.add(videoMultipartFile);
        request.fields['videoName'] = videoName;
        request.fields['videoType'] = _selectedVideoType;
        if (description != null && description.isNotEmpty) {
          request.fields['description'] = description;
        }

        // Optimized timeout based on file size (faster for smaller files)
        final fileSize = await videoFile.length();
        final timeoutDuration = fileSize < 10 * 1024 * 1024 // 10MB
            ? const Duration(minutes: 5) // 5 minutes for files < 10MB
            : const Duration(minutes: 15); // 15 minutes for larger files

        final streamedResponse = await request.send().timeout(
          timeoutDuration,
          onTimeout: () {
            throw TimeoutException(
                'Upload timeout after ${timeoutDuration.inMinutes} minutes',
                timeoutDuration);
          },
        );

        final responseBody =
            await streamedResponse.stream.bytesToString().timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            throw TimeoutException('Response timeout after 30 seconds',
                const Duration(seconds: 30));
          },
        );

        print('📡 Upload response status: ${streamedResponse.statusCode}');
        print('📄 Upload response body: $responseBody');

        final responseData = json.decode(responseBody);

        if (streamedResponse.statusCode == 201) {
          return {
            'success': true,
            'video': responseData['video'],
          };
        } else {
          final errorMessage = responseData['message'] ??
              responseData['error'] ??
              'Upload failed';
          print('❌ Upload failed: $errorMessage');

          // Don't retry on client errors (4xx)
          if (streamedResponse.statusCode >= 400 &&
              streamedResponse.statusCode < 500) {
            return {
              'success': false,
              'error': errorMessage,
            };
          }

          // Retry on server errors (5xx) or network issues
          if (attempt < maxRetries) {
            print('🔄 Retrying upload in ${retryDelay.inSeconds} seconds...');
            await Future.delayed(retryDelay);
            continue;
          }

          return {
            'success': false,
            'error': errorMessage,
          };
        }
      } catch (e) {
        print('❌ Upload attempt $attempt failed: $e');

        // Check if it's a network error that should be retried
        final errorString = e.toString().toLowerCase();
        final isRetryableError = errorString.contains('broken pipe') ||
            errorString.contains('connection') ||
            errorString.contains('timeout') ||
            errorString.contains('socket') ||
            errorString.contains('network');

        if (isRetryableError && attempt < maxRetries) {
          print(
              '🔄 Network error detected, retrying in ${retryDelay.inSeconds} seconds...');
          await Future.delayed(retryDelay);
          continue;
        }

        // Return error on last attempt or non-retryable errors
        return {
          'success': false,
          'error': _getUserFriendlyErrorMessage(e),
        };
      }
    }

    return {
      'success': false,
      'error': 'Upload failed after $maxRetries attempts',
    };
  }

  /// Convert technical errors to user-friendly messages
  String _getUserFriendlyErrorMessage(dynamic error) {
    final errorString = error.toString().toLowerCase();

    if (errorString.contains('broken pipe')) {
      return 'Connection lost during upload. Please check your internet connection and try again.';
    } else if (errorString.contains('timeout')) {
      return 'Upload timed out. Please try again with a smaller file or better internet connection.';
    } else if (errorString.contains('connection')) {
      return 'Network connection error. Please check your internet connection and try again.';
    } else if (errorString.contains('socket')) {
      return 'Network error occurred. Please try again.';
    } else {
      return 'Upload failed: ${error.toString()}';
    }
  }

  /// Get auth token (implement based on your auth system)
  Future<String?> _getAuthToken() async {
    try {
      // Use existing AuthService which persists JWT in SharedPreferences
      final user = await _authService.getUserData();
      if (user != null && (user['token'] as String?)?.isNotEmpty == true) {
        return user['token'] as String;
      }
      // Fallback direct read in case user is signed-in but user object couldn't load
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      return (token != null && token.isNotEmpty) ? token : null;
    } catch (_) {
      return null;
    }
  }

  // (removed body)

  /// Start upload progress tracking
  void _startUploadProgress() {
    _uploadProgress = 0.0;
    _elapsedSeconds = 0;
    _uploadStartTime = DateTime.now().millisecondsSinceEpoch;
    _uploadStatus = 'Preparing upload...';

    // Start timer for progress updates
    _uploadTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _elapsedSeconds =
              (DateTime.now().millisecondsSinceEpoch - _uploadStartTime) ~/
                  1000;
        });
      }
    });

    // Simulate realistic upload progress based on file size
    _simulateRealisticProgress();
  }

  /// Simulate realistic upload progress
  void _simulateRealisticProgress() {
    if (_selectedVideo == null) return;

    // Progress updates every 2 seconds
    Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted || !_isUploading) {
        timer.cancel();
        return;
      }

      setState(() {
        if (_uploadProgress < 0.85) {
          // Upload phase (0-85%)
          _uploadProgress += 0.15;
          if (_uploadProgress < 0.3) {
            _uploadStatus =
                'Uploading video file... (${(_uploadProgress * 100).toStringAsFixed(0)}%)';
          } else if (_uploadProgress < 0.6) {
            _uploadStatus =
                'Uploading video file... (${(_uploadProgress * 100).toStringAsFixed(0)}%)';
          } else if (_uploadProgress < 0.85) {
            _uploadStatus =
                'Uploading video file... (${(_uploadProgress * 100).toStringAsFixed(0)}%)';
          }
        } else if (_uploadProgress < 0.95) {
          // Processing phase (85-95%)
          _uploadProgress += 0.02;
          _uploadStatus = 'Processing video... (Converting to HLS)';
        } else if (_uploadProgress < 0.97) {
          // Finalizing phase (95-97%) – keep a small headroom for real processing
          _uploadProgress += 0.005;
          _uploadStatus = 'Finalizing... (Almost done!)';
        } else {
          // Hold at ~97% until server-side processing completes
          _uploadProgress = 0.97;
          _uploadStatus = 'Processing video on server...';
        }
      });
    });
  }

  /// Stop upload progress tracking
  void _stopUploadProgress() {
    _uploadTimer?.cancel();
    _uploadTimer = null;
    _uploadProgress = 0.0;
    _elapsedSeconds = 0;
    _uploadStatus = '';
  }

  // Removed legacy wait method (async-only uses polling above)

  // Removed async-start dialog; we now show success only when URL present

  /// **Show background processing dialog**
  Future<void> _showBackgroundProcessingDialog(String videoId) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return _BackgroundProcessingDialog(videoId: videoId);
      },
    );
  }

  /// **Show beautiful success dialog**
  Future<void> _showSuccessDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Success animation icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    color: Colors.green,
                    size: 50,
                  ),
                ),
                const SizedBox(height: 24),

                // Success title
                const Text(
                  'Upload Successful! 🎉',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                // Success message
                const Text(
                  'Your video has been uploaded and processed successfully! It is now available in your feed.',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.black54,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // Processing info
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline,
                          color: Colors.green, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Video has been processed and is ready for streaming!',
                          style: TextStyle(
                            color: Colors.green.shade700,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: Colors.grey.withOpacity(0.3),
                            ),
                          ),
                        ),
                        child: const Text(
                          'Upload Another',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          // The callback already handles navigation to video tab
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'View in Feed',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Format time in MM:SS format
  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  /// Calculate upload speed
  String _calculateUploadSpeed() {
    if (_elapsedSeconds > 0 && _selectedVideo != null) {
      final fileSizeMB = _selectedVideo!.lengthSync() / (1024 * 1024);
      final speedMBps = fileSizeMB / _elapsedSeconds;
      return '${speedMBps.toStringAsFixed(2)} MB/s';
    }
    return '0.00 MB/s';
  }

  /// Estimate upload time based on file size
  String _estimateUploadTime() {
    if (_selectedVideo == null) return 'Unknown';

    final fileSizeMB = _selectedVideo!.lengthSync() / (1024 * 1024);

    // Assume average upload speed of 3 MB/s
    final estimatedSeconds = (fileSizeMB / 3.0).round();

    if (estimatedSeconds < 60) {
      return '${estimatedSeconds}s';
    } else if (estimatedSeconds < 3600) {
      final minutes = estimatedSeconds ~/ 60;
      return '${minutes}m';
    } else {
      final hours = estimatedSeconds ~/ 3600;
      final minutes = (estimatedSeconds % 3600) ~/ 60;
      return '${hours}h ${minutes}m';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _linkController.dispose();
    _urlController.dispose();
    _stopUploadProgress();
    _tagInputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _authService.getUserData(),
      builder: (context, snapshot) {
        final isSignedIn = snapshot.hasData && snapshot.data != null;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Upload & Create'),
            centerTitle: true,
            actions: [
              if (isSignedIn)
                IconButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AdManagementScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.campaign),
                  tooltip: 'Manage Ads',
                ),
            ],
          ),
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!isSignedIn)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.orange,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Please sign in to upload videos and create ads',
                              style: TextStyle(color: Colors.orange),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              await _authService.signInWithGoogle();
                            },
                            child: const Text('Sign In'),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 32),

                  // T&C card moved into a modal; show entry point above in AppBar

                  // Main Options Section
                  const Text(
                    'Choose what you want to create',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 32),

                  // Two Main Options
                  Row(
                    children: [
                      // Upload Video Option
                      Expanded(
                        child: Card(
                          elevation: 4,
                          child: InkWell(
                            onTap: isSignedIn
                                ? () {
                                    setState(() {
                                      _showUploadForm = !_showUploadForm;
                                    });
                                  }
                                : () {
                                    _showLoginPrompt();
                                  },
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade100,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.video_library,
                                      size: 48,
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'Upload Video',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Share your video content with the community',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 14,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 16),

                      // Create Ad Option
                      Expanded(
                        child: Card(
                          elevation: 4,
                          child: InkWell(
                            onTap: isSignedIn
                                ? () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const CreateAdScreenRefactored(),
                                      ),
                                    );
                                  }
                                : () {
                                    _showLoginPrompt();
                                  },
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade100,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.campaign,
                                      size: 48,
                                      color: Colors.green.shade700,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'Create Ad',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Promote your content with targeted advertisements',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 14,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // Video Upload Form (Conditional)
                  if (_showUploadForm)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.video_library,
                                  color: Colors.blue,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Upload Video',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  onPressed: () {
                                    setState(() {
                                      _showUploadForm = false;
                                    });
                                  },
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                            Container(
                              height: 200,
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: _isProcessing
                                  ? const Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          CircularProgressIndicator(),
                                          SizedBox(height: 16),
                                          Text(
                                            'Processing video...',
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : _selectedVideo != null
                                      ? Center(
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              if (_selectedVideoType == 'vayu')
                                                Container(
                                                  width: 120,
                                                  height: 120,
                                                  decoration: BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                    border: Border.all(
                                                        color: Colors
                                                            .grey.shade300),
                                                  ),
                                                  child: ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                    child: Image.file(
                                                      _selectedVideo!,
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (context,
                                                          error, stackTrace) {
                                                        return const Icon(
                                                          Icons.image,
                                                          size: 48,
                                                          color: Colors.blue,
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                )
                                              else
                                                const Icon(
                                                  Icons.video_file,
                                                  size: 48,
                                                  color: Colors.blue,
                                                ),
                                              const SizedBox(height: 16),
                                              Text(
                                                _selectedVideo!.path
                                                    .split('/')
                                                    .last,
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      : Center(
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                _selectedVideoType == 'vayu'
                                                    ? Icons.image
                                                    : Icons.video_library,
                                                size: 48,
                                                color: Colors.grey,
                                              ),
                                              const SizedBox(height: 16),
                                              Text(
                                                _selectedVideoType == 'vayu'
                                                    ? 'No image selected'
                                                    : 'No video selected',
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                            ),
                            const SizedBox(height: 24),
                            TextField(
                              controller: _titleController,
                              decoration: InputDecoration(
                                labelText: _selectedVideoType == 'vayu'
                                    ? 'Product Name'
                                    : 'Video Title',
                                hintText: _selectedVideoType == 'vayu'
                                    ? 'Enter product name'
                                    : 'Enter a title for your video',
                                border: const OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Video Type Selector
                            DropdownButtonFormField<String>(
                              value: _selectedVideoType,
                              decoration: const InputDecoration(
                                labelText: 'Content Type',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.category),
                                helperText:
                                    'Choose yog for short videos or vayu for images',
                              ),
                              items: const [
                                DropdownMenuItem<String>(
                                  value: 'yog',
                                  child: Row(
                                    children: [
                                      Icon(Icons.video_library, size: 20),
                                      SizedBox(width: 8),
                                      Text('Yog (Short Videos)'),
                                    ],
                                  ),
                                ),
                                DropdownMenuItem<String>(
                                  value: 'vayu',
                                  child: Row(
                                    children: [
                                      Icon(Icons.image, size: 20),
                                      SizedBox(width: 8),
                                      Text('Vayu (Product Images)'),
                                    ],
                                  ),
                                ),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _selectedVideoType = val;
                                    // Clear selected file when type changes
                                    _selectedVideo = null;
                                    _errorMessage = null;
                                  });
                                }
                              },
                            ),

                            const SizedBox(height: 16),
                            // Category selector (only show for yog type)
                            if (_selectedVideoType == 'yog')
                              DropdownButtonFormField<String>(
                                initialValue: _selectedCategory,
                                decoration: const InputDecoration(
                                  labelText: 'Video Category',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.category),
                                  helperText:
                                      'Choose a category to improve ad targeting',
                                ),
                                items: kInterestOptions
                                    .where((c) => c != 'Custom Interest')
                                    .map((c) => DropdownMenuItem<String>(
                                          value: c,
                                          child: Text(c),
                                        ))
                                    .toList(),
                                onChanged: (val) {
                                  setState(() => _selectedCategory = val);
                                },
                              ),
                            const SizedBox(height: 16),

                            // Advanced Options Toggle Button
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _showAdvancedOptions =
                                        !_showAdvancedOptions;
                                  });
                                },
                                icon: Icon(_showAdvancedOptions
                                    ? Icons.expand_less
                                    : Icons.expand_more),
                                label: Text(_showAdvancedOptions
                                    ? 'Hide Advanced Options'
                                    : 'Show Advanced Options'),
                                style: OutlinedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  side: BorderSide(color: Colors.grey.shade400),
                                  foregroundColor: Colors.grey.shade700,
                                ),
                              ),
                            ),

                            // Advanced Options (Conditionally Shown)
                            if (_showAdvancedOptions) ...[
                              const SizedBox(height: 16),

                              // Description field only for vayu (product images)
                              if (_selectedVideoType == 'vayu')
                                TextField(
                                  controller: _linkController,
                                  decoration: const InputDecoration(
                                    labelText: 'Brand and Product Description',
                                    hintText:
                                        'Enter brand name and detailed product description',
                                    border: OutlineInputBorder(),
                                  ),
                                  maxLines: 3,
                                  keyboardType: TextInputType.multiline,
                                ),

                              // URL field for both yog and vayu
                              TextField(
                                controller: _urlController,
                                decoration: const InputDecoration(
                                  labelText: 'URL (Optional)',
                                  hintText:
                                      'Enter website URL, social media link, etc.',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.link),
                                ),
                                keyboardType: TextInputType.url,
                              ),

                              const SizedBox(height: 16),

                              // Tags input
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Tags (optional)',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _tagInputController,
                                    decoration: InputDecoration(
                                      hintText: 'Type a tag and press Add',
                                      border: const OutlineInputBorder(),
                                      prefixIcon: const Icon(Icons.tag),
                                      suffixIcon: IconButton(
                                        icon: const Icon(Icons.add),
                                        onPressed: () {
                                          final text =
                                              _tagInputController.text.trim();
                                          if (text.isNotEmpty &&
                                              !_tags.contains(text)) {
                                            setState(() {
                                              _tags.add(text);
                                              _tagInputController.clear();
                                            });
                                          }
                                        },
                                      ),
                                    ),
                                    onSubmitted: (_) {
                                      final text =
                                          _tagInputController.text.trim();
                                      if (text.isNotEmpty &&
                                          !_tags.contains(text)) {
                                        setState(() {
                                          _tags.add(text);
                                          _tagInputController.clear();
                                        });
                                      }
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                  if (_tags.isNotEmpty)
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: _tags
                                          .map((t) => Chip(
                                                label: Text(t),
                                                onDeleted: () {
                                                  setState(() {
                                                    _tags.remove(t);
                                                  });
                                                },
                                              ))
                                          .toList(),
                                    ),
                                ],
                              ),

                              const SizedBox(height: 16),
                            ],
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _showWhatToUploadDialog,
                                icon: const Icon(Icons.help_outline),
                                label: const Text('What to Upload?'),
                                style: OutlinedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  side: BorderSide(
                                    color: Colors.blue.shade300,
                                  ),
                                  foregroundColor: Colors.blue.shade700,
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Upload Progress Indicator
                            if (_isUploading) ...[
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.blue.withOpacity(0.3),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.upload_file,
                                          color: Colors.blue[600],
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _uploadStatus,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.blue[800],
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),

                                    // File Size & Estimated Time Info
                                    if (_selectedVideo != null) ...[
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withOpacity(0.05),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.info_outline,
                                              size: 16,
                                              color: Colors.blue[600],
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'File: ${(_selectedVideo!.lengthSync() / (1024 * 1024)).toStringAsFixed(1)} MB • Est. Time: ${_estimateUploadTime()}',
                                                style: TextStyle(
                                                  color: Colors.blue[700],
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                    ],

                                    // Progress Bar
                                    LinearProgressIndicator(
                                      value: _uploadProgress,
                                      backgroundColor: Colors.blue.withOpacity(
                                        0.2,
                                      ),
                                      valueColor:
                                          const AlwaysStoppedAnimation<Color>(
                                        Colors.blue,
                                      ),
                                    ),

                                    const SizedBox(height: 8),

                                    // Progress Details
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          '${(_uploadProgress * 100).toStringAsFixed(0)}%',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue[800],
                                          ),
                                        ),
                                        Text(
                                          'Time: ${_formatTime(_elapsedSeconds)}',
                                          style: TextStyle(
                                            color: Colors.blue[600],
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 4),

                                    Text(
                                      'Speed: ${_calculateUploadSpeed()}',
                                      style: TextStyle(
                                        color: Colors.blue[600],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],

                            if (_errorMessage != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16.0),
                                child: Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: Colors.red.shade200),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.error_outline,
                                              color: Colors.red.shade600),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              _errorMessage!,
                                              style: TextStyle(
                                                color: Colors.red.shade700,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: _isUploading
                                                ? null
                                                : () {
                                                    setState(() {
                                                      _errorMessage = null;
                                                    });
                                                  },
                                            icon: const Icon(Icons.refresh),
                                            label: const Text('Retry Upload'),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor:
                                                  Colors.red.shade600,
                                              side: BorderSide(
                                                  color: Colors.red.shade300),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () {
                                              setState(() {
                                                _errorMessage = null;
                                                _selectedVideo = null;
                                                _titleController.clear();
                                                _linkController.clear();
                                                _urlController.clear();
                                                _selectedCategory = null;
                                                _tags.clear();
                                                _showAdvancedOptions = false;
                                              });
                                            },
                                            icon: const Icon(Icons.clear),
                                            label: const Text('Start Over'),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor:
                                                  Colors.grey.shade600,
                                              side: BorderSide(
                                                  color: Colors.grey.shade300),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            // Video Selection Button (Files only)
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _isUploading ? null : _pickMedia,
                                    icon: Icon(_selectedVideoType == 'vayu'
                                        ? Icons.image
                                        : Icons.video_library),
                                    label: Text(_selectedVideoType == 'vayu'
                                        ? 'Select Product Image'
                                        : 'Select Video'),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Upload Button (Synchronous - restored)
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed:
                                    _isUploading ? null : _uploadVideoSync,
                                icon: _isUploading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                            Colors.white,
                                          ),
                                        ),
                                      )
                                    : const Icon(Icons.upload_file),
                                label: Text(
                                  _isUploading ? 'Uploading...' : 'Upload',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          bottomNavigationBar: null,
        );
      },
    );
  }
}

/// Background processing dialog with real-time progress tracking
class _BackgroundProcessingDialog extends StatefulWidget {
  final String videoId;

  const _BackgroundProcessingDialog({
    Key? key,
    required this.videoId,
  }) : super(key: key);

  @override
  State<_BackgroundProcessingDialog> createState() =>
      _BackgroundProcessingDialogState();
}

class _BackgroundProcessingDialogState
    extends State<_BackgroundProcessingDialog> {
  final VideoProcessingService _processingService =
      VideoProcessingService.instance;
  VideoProcessingStatus? _currentStatus;
  bool _isPolling = false;

  @override
  void initState() {
    super.initState();
    _startProgressPolling();
  }

  @override
  void dispose() {
    _stopProgressPolling();
    super.dispose();
  }

  void _startProgressPolling() {
    _isPolling = true;
    _processingService.pollProgress(widget.videoId).listen(
      (status) {
        if (mounted) {
          setState(() {
            _currentStatus = status;
          });

          // Close dialog when processing is complete
          if (status.isCompleted) {
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) {
                Navigator.of(context).pop();
              }
            });
          }
        }
      },
      onError: (error) {
        print('❌ BackgroundProcessingDialog: Polling error: $error');
      },
      onDone: () {
        if (mounted) {
          setState(() {
            _isPolling = false;
          });
        }
      },
    );
  }

  void _stopProgressPolling() {
    if (_isPolling) {
      _processingService.stopPolling(widget.videoId);
      _isPolling = false;
    }
  }

  void _retryProcessing() {
    // TODO: Implement retry functionality
    print('🔄 Retrying video processing for: ${widget.videoId}');
  }

  void _cancelProcessing() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Video Processing'),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 20),

            // Progress indicator
            VideoProcessingProgress(
              progress: _currentStatus?.processingProgress.toDouble() ?? 0.0,
              statusText: _getStatusText(),
              showPlayButton: _currentStatus?.isCompleted ?? false,
              size: 120.0,
              progressColor: _getProgressColor(),
            ),

            const SizedBox(height: 24),

            // Status message
            Text(
              _getStatusMessage(),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),

            // Error message if any
            if (_currentStatus?.processingError != null) ...[
              const SizedBox(height: 8),
              Text(
                _currentStatus!.processingError!,
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],

            const SizedBox(height: 24),

            // Progress bar
            LinearProgressIndicator(
              value: (_currentStatus?.processingProgress ?? 0) / 100.0,
              backgroundColor: Colors.grey.shade300,
              valueColor: AlwaysStoppedAnimation<Color>(_getProgressColor()),
            ),

            const SizedBox(height: 8),

            Text(
              '${_currentStatus?.processingProgress ?? 0}% complete',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (_currentStatus?.isFailed == true) ...[
          TextButton(
            onPressed: _retryProcessing,
            child: const Text('Retry'),
          ),
        ],
        TextButton(
          onPressed:
              _currentStatus?.isCompleted == true ? _cancelProcessing : null,
          child: Text(
              _currentStatus?.isCompleted == true ? 'Done' : 'Processing...'),
        ),
      ],
    );
  }

  String _getStatusText() {
    if (_currentStatus == null) return 'Starting...';

    switch (_currentStatus!.processingStatus) {
      case 'pending':
        return 'Preparing...';
      case 'processing':
        return 'Processing...';
      case 'completed':
        return 'Ready!';
      case 'failed':
        return 'Failed';
      default:
        return 'Unknown';
    }
  }

  String _getStatusMessage() {
    if (_currentStatus == null) {
      return 'Your video is being prepared for processing';
    }

    switch (_currentStatus!.processingStatus) {
      case 'pending':
        return 'Your video is being prepared for processing';
      case 'processing':
        return 'Video is being processed. Please wait...';
      case 'completed':
        return 'Video processing completed successfully!';
      case 'failed':
        return 'Video processing failed. Please try again.';
      default:
        return 'Processing status unknown';
    }
  }

  Color _getProgressColor() {
    if (_currentStatus == null) return Colors.orange;

    switch (_currentStatus!.processingStatus) {
      case 'pending':
        return Colors.orange;
      case 'processing':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      case 'failed':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
