import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:vayu/controller/google_sign_in_controller.dart';
import 'package:vayu/controller/main_controller.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:vayu/services/video_service.dart';
import 'package:vayu/services/authservices.dart';
import 'package:vayu/services/logout_service.dart';
import 'package:vayu/core/services/http_client_service.dart';
import 'package:vayu/view/screens/create_ad_screen_refactored.dart';
import 'package:vayu/view/screens/ad_management_screen.dart';
import 'package:vayu/view/screens/upload_screen/widgets/upload_advanced_settings_section.dart';
import 'package:vayu/utils/app_logger.dart';
import 'package:vayu/config/app_config.dart';
import 'package:video_player/video_player.dart';
import 'package:vayu/utils/app_text.dart';

class UploadScreen extends StatefulWidget {
  final VoidCallback? onVideoUploaded; // Add callback for video upload success

  const UploadScreen({super.key, this.onVideoUploaded});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  // **OPTIMIZED: Use ValueNotifiers for granular updates (no setState)**
  final ValueNotifier<File?> _selectedVideo = ValueNotifier<File?>(null);
  final ValueNotifier<bool> _isUploading = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isProcessing = ValueNotifier<bool>(false);
  final ValueNotifier<String?> _errorMessage = ValueNotifier<String?>(null);
  final ValueNotifier<bool> _showUploadForm = ValueNotifier<bool>(false);

  // **UNIFIED PROGRESS TRACKING** - Single progress bar for entire flow
  final ValueNotifier<double> _unifiedProgress = ValueNotifier<double>(0.0);
  final ValueNotifier<String> _currentPhase = ValueNotifier<String>('');
  final ValueNotifier<String> _phaseDescription = ValueNotifier<String>('');
  int _uploadStartTime = 0;
  final ValueNotifier<int> _elapsedSeconds = ValueNotifier<int>(0);

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _linkController = TextEditingController();
  final VideoService _videoService = VideoService();
  final AuthService _authService = AuthService();

  // Timer for unified progress tracking
  Timer? _progressTimer;

  // **UNIFIED PROGRESS PHASES** - Complete video processing flow
  Map<String, Map<String, dynamic>> get _progressPhases => {
        'preparation': {
          'name': AppText.get('upload_preparing_video'),
          'description': AppText.get('upload_preparing_desc'),
          'progress': 0.1,
          'icon': Icons.video_file,
        },
        'upload': {
          'name': AppText.get('upload_uploading_video'),
          'description': AppText.get('upload_uploading_desc'),
          'progress': 0.4,
          'icon': Icons.cloud_upload,
        },
        'validation': {
          'name': AppText.get('upload_validating_video'),
          'description': AppText.get('upload_validating_desc'),
          'progress': 0.5,
          'icon': Icons.verified,
        },
        'processing': {
          'name': AppText.get('upload_processing_video_name'),
          'description': AppText.get('upload_processing_desc'),
          'progress': 0.8,
          'icon': Icons.settings,
        },
        'completed': {
          'name': AppText.get('upload_complete'),
          'description': AppText.get('upload_complete_desc'),
          'progress': 1.0,
          'icon': Icons.check_circle,
        },
        'finalizing': {
          'name': AppText.get('upload_finalizing'),
          'description': AppText.get('upload_finalizing_desc'),
          'progress': 0.95,
          'icon': Icons.check_circle,
        },
      };

  // NEW: Category, video type, and tags to align with ad targeting interests
  static const String _defaultCategory = 'Others';
  final ValueNotifier<String?> _selectedCategory = ValueNotifier<String?>(null);
  final ValueNotifier<List<String>> _tags = ValueNotifier<List<String>>([]);
  final ValueNotifier<bool> _showAdvancedSettings = ValueNotifier<bool>(false);
  final TextEditingController _tagInputController = TextEditingController();

  // **UNIFIED PROGRESS TRACKING METHODS**

  /// Start unified progress tracking for complete video processing flow
  void _startUnifiedProgress() {
    _uploadStartTime = DateTime.now().millisecondsSinceEpoch;
    // **BATCHED UPDATE: Update progress state**
    _unifiedProgress.value = 0.0;
    _currentPhase.value = 'preparation';
    _phaseDescription.value =
        _progressPhases['preparation']!['description'] as String;

    _progressTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        // **OPTIMIZED: Update only elapsed seconds, no setState**
        _elapsedSeconds.value =
            (DateTime.now().millisecondsSinceEpoch - _uploadStartTime) ~/ 1000;
      }
    });
  }

  /// Update progress phase with smooth transitions
  void _updateProgressPhase(String phase) {
    if (mounted && _progressPhases.containsKey(phase)) {
      // **BATCHED UPDATE: Update all progress values at once**
      _currentPhase.value = phase;
      _phaseDescription.value =
          _progressPhases[phase]!['description'] as String;
      _unifiedProgress.value = _progressPhases[phase]!['progress'] as double;
    }
  }

  /// Stop unified progress tracking
  void _stopUnifiedProgress() {
    _progressTimer?.cancel();
    _progressTimer = null;
    if (mounted) {
      // **BATCHED UPDATE: Update all progress values at once**
      _unifiedProgress.value = 1.0;
      _currentPhase.value = 'completed';
      _phaseDescription.value = AppText.get('upload_video_ready');
    }
  }

  /// Get current phase icon
  IconData _getCurrentPhaseIcon(String currentPhase) {
    return _progressPhases[currentPhase]?['icon'] ?? Icons.upload;
  }

  /// Get current phase color
  Color _getCurrentPhaseColor(String currentPhase) {
    switch (currentPhase) {
      case 'preparation':
        return Colors.blue;
      case 'upload':
        return Colors.orange;
      case 'validation':
        return Colors.purple;
      case 'processing':
        return Colors.indigo;
      case 'finalizing':
        return Colors.teal;
      case 'completed':
        return Colors.green;
      default:
        return Colors.blue;
    }
  }

  /// **UNIFIED PROGRESS WIDGET** - Beautiful progress display
  Widget _buildUnifiedProgressWidget() {
    return ValueListenableBuilder<String>(
      valueListenable: _currentPhase,
      builder: (context, currentPhase, _) {
        return ValueListenableBuilder<String>(
          valueListenable: _phaseDescription,
          builder: (context, phaseDescription, _) {
            return ValueListenableBuilder<double>(
              valueListenable: _unifiedProgress,
              builder: (context, unifiedProgress, _) {
                return ValueListenableBuilder<int>(
                  valueListenable: _elapsedSeconds,
                  builder: (context, elapsedSeconds, _) {
                    return Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // Phase Icon and Name
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _getCurrentPhaseColor(currentPhase)
                                      .withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  _getCurrentPhaseIcon(currentPhase),
                                  color: _getCurrentPhaseColor(currentPhase),
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _progressPhases[currentPhase]?['name'] ??
                                          'Processing',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      phaseDescription,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 20),

                          // Progress Bar
                          Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    AppText.get('upload_progress'),
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  Text(
                                    '${(unifiedProgress * 100).toInt()}%',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color:
                                          _getCurrentPhaseColor(currentPhase),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: LinearProgressIndicator(
                                  value: unifiedProgress,
                                  backgroundColor: Colors.grey[200],
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      _getCurrentPhaseColor(currentPhase)),
                                  minHeight: 8,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // Time Information
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.access_time,
                                    size: 16,
                                    color: Colors.grey[600],
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${AppText.get('upload_time')} ${_formatTime(elapsedSeconds)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
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
                      Expanded(
                        child: Text(
                          AppText.get('upload_terms_title'),
                          style: const TextStyle(
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
                    title: AppText.get('upload_terms_user_responsibility'),
                    body: AppText.get('upload_terms_user_responsibility_desc'),
                  ),
                  _buildNoticePoint(
                    title: AppText.get('upload_terms_copyright'),
                    body: AppText.get('upload_terms_copyright_desc'),
                  ),
                  _buildNoticePoint(
                    title: AppText.get('upload_terms_reporting'),
                    body: AppText.get('upload_terms_reporting_desc'),
                  ),
                  _buildNoticePoint(
                    title: AppText.get('upload_terms_payment'),
                    body: AppText.get('upload_terms_payment_desc'),
                  ),
                  _buildNoticePoint(
                    title: AppText.get('upload_terms_strike'),
                    body: AppText.get('upload_terms_strike_desc'),
                  ),
                  _buildNoticePoint(
                    title: AppText.get('upload_terms_liability'),
                    body: AppText.get('upload_terms_liability_desc'),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.check_circle_outline),
                      label: Text(AppText.get('btn_i_understand')),
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

  void _toggleAdvancedSettings() {
    _showAdvancedSettings.value = !_showAdvancedSettings.value;
  }

  void _handleAddTag(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final currentTags = List<String>.from(_tags.value);
    if (!currentTags.contains(trimmed)) {
      currentTags.add(trimmed);
      _tags.value = currentTags;
    }
    _tagInputController.clear();
  }

  void _handleRemoveTag(String tag) {
    final currentTags = List<String>.from(_tags.value);
    if (currentTags.remove(tag)) {
      _tags.value = currentTags;
    }
  }

  @override
  void initState() {
    _selectedCategory.value = _defaultCategory;
    super.initState();
  }

  String _deriveTitleFromFile(File file) {
    final normalizedPath = file.path.replaceAll('\\', '/');
    final fileName = normalizedPath.split('/').last;
    final dotIndex = fileName.lastIndexOf('.');
    final baseName = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
    final cleaned = baseName.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
    return cleaned.isEmpty ? 'Untitled video' : cleaned;
  }

  /// **NEW: Calculate SHA-256 hash of video file for duplicate detection**
  Future<String> _calculateFileHash(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final hash = sha256.convert(bytes);
      return hash.toString();
    } catch (e) {
      AppLogger.log('❌ UploadScreen: Error calculating file hash: $e');
      rethrow;
    }
  }

  /// **UPLOAD VIDEO METHOD** - Handles video upload with progress tracking
  Future<void> _uploadVideo() async {
    final userData = await _authService.getUserData();
    if (userData == null) {
      _showLoginPrompt();
      return;
    }

    // **BATCHED UPDATE: Use ValueNotifiers instead of setState**
    if (_selectedVideo.value == null) {
      _errorMessage.value = AppText.get('upload_error_select_video');
      return;
    }

    if (_titleController.text.isEmpty) {
      _errorMessage.value = AppText.get('upload_error_enter_title');
      return;
    }

    // **BATCHED UPDATE: Update both values at once**
    _isUploading.value = true;
    _errorMessage.value = null;

    // Validate category selection before uploading
    if (_selectedCategory.value == null || _selectedCategory.value!.isEmpty) {
      _isUploading.value = false;
      _errorMessage.value = AppText.get('upload_error_select_category');
      return;
    }

    try {
      AppLogger.log('🚀 Starting HLS video upload...');
      AppLogger.log('📁 Video path: ${_selectedVideo.value?.path}');
      AppLogger.log('📝 Title: ${_titleController.text}');
      AppLogger.log(
        '🔗 Link: ${_linkController.text.isNotEmpty ? _linkController.text : 'None'}',
      );
      AppLogger.log(
        '🎬 Note: Video will be converted to HLS (.m3u8) format for optimal streaming',
      );

      // Start unified progress tracking
      _startUnifiedProgress();

      // Check if file exists and is readable
      if (!await _selectedVideo.value!.exists()) {
        throw Exception('Selected video file does not exist');
      }

      // Update to preparation phase
      _updateProgressPhase('preparation');

      // Check file size
      final fileSize = await _selectedVideo.value!.length();
      AppLogger.log(
        'File size: $fileSize bytes (${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB)',
      );
      if (fileSize > 100 * 1024 * 1024) {
        // 100MB limit
        throw Exception(AppText.get('upload_error_file_too_large'));
      }

      // Check file extension
      final fileName = _selectedVideo.value!.path.split('/').last.toLowerCase();
      final allowedExtensions = ['mp4', 'avi', 'mov', 'wmv', 'flv', 'webm'];
      final fileExtension = fileName.split('.').last;

      if (!allowedExtensions.contains(fileExtension)) {
        throw Exception(
          AppText.get('upload_error_invalid_format',
                  fallback:
                      'Invalid video format. Supported formats: {formats}')
              .replaceAll(
                  '{formats}', allowedExtensions.join(', ').toUpperCase()),
        );
      }

      // Update to upload phase
      _updateProgressPhase('upload');

      // All uploads are currently treated as free (Yug tab) content.
      const String serverVideoType = 'yog';

      AppLogger.log(
          '🎯 UploadScreen: Using videoType=$serverVideoType (free/Yug by default)');

      final uploadedVideo = await runZoned(
        () => _videoService.uploadVideo(
          _selectedVideo.value!,
          _titleController.text,
          '', // description
          _linkController.text.isNotEmpty ? _linkController.text : '', // link
        ),
        zoneValues: {
          'upload_metadata': {
            'category': _selectedCategory.value,
            'tags': _tags.value,
            'videoType': serverVideoType,
          }
        },
      ).timeout(
        const Duration(
          minutes: 10,
        ), // Increased timeout for large video uploads
        onTimeout: () {
          throw TimeoutException(
            AppText.get('upload_error_timeout'),
          );
        },
      );

      AppLogger.log('✅ Video upload started successfully!');
      AppLogger.log('🎬 Uploaded video details: $uploadedVideo');

      // **FIX: Handle correct response structure from VideoService**
      AppLogger.log(
          '🔄 Processing status: ${uploadedVideo['processingStatus']}');
      AppLogger.log('🆔 Video ID: ${uploadedVideo['id']}');

      // Update to validation phase
      _updateProgressPhase('validation');

      // Update to processing phase
      _updateProgressPhase('processing');

      // Wait for processing to complete
      String? videoId;
      videoId = uploadedVideo['id']?.toString();

      if (videoId == null) {
        throw Exception('Video ID not found in upload response');
      }

      final completedVideo = await _waitForProcessingCompletion(videoId);

      if (completedVideo != null) {
        // Update to finalizing phase
        _updateProgressPhase('finalizing');

        AppLogger.log('✅ Video processing completed successfully!');
        AppLogger.log('🔗 HLS Playlist URL: ${completedVideo['videoUrl']}');
        AppLogger.log('🖼️ Thumbnail URL: ${completedVideo['thumbnailUrl']}');

        // Call the callback to refresh video list first
        AppLogger.log('🔄 UploadScreen: Calling onVideoUploaded callback');
        if (widget.onVideoUploaded != null) {
          widget.onVideoUploaded!();
          AppLogger.log(
              '✅ UploadScreen: onVideoUploaded callback called successfully');
        } else {
          AppLogger.log('❌ UploadScreen: onVideoUploaded callback is null');
        }

        // **BATCHED UPDATE: Clear form using ValueNotifiers**
        _selectedVideo.value = null;
        _titleController.clear();
        _linkController.clear();
        _selectedCategory.value = null;
        _tags.value = [];
        // Video type selection removed; all uploads default to free (Yug).
        _showAdvancedSettings.value = false;

        // Stop unified progress tracking
        _stopUnifiedProgress();

        // Show beautiful success dialog
        await _showSuccessDialog();

        // **NEW: Trigger video feed refresh after successful upload**
        if (widget.onVideoUploaded != null) {
          AppLogger.log(
              '🔄 Triggering video feed refresh after upload completion');
          widget.onVideoUploaded!();
        }
      } else {
        throw Exception('Video processing failed or timed out');
      }
    } on TimeoutException catch (e) {
      AppLogger.log('Upload timeout error: $e');
      // **NO setState: Use ValueNotifier**
      _errorMessage.value =
          'Upload timed out. Please check your internet connection and try again.';
    } on FileSystemException catch (e) {
      AppLogger.log('File system error: $e');
      // **NO setState: Use ValueNotifier**
      _errorMessage.value = AppText.get('upload_error_file_access');
    } catch (e, stackTrace) {
      AppLogger.log('Error uploading video: $e');
      AppLogger.log('Stack trace: $stackTrace');

      // Handle specific error types
      String userFriendlyError;
      if (e.toString().contains('User not authenticated') ||
          e.toString().contains('Authentication token not found')) {
        userFriendlyError = AppText.get('upload_error_sign_in_again');
      } else if (e.toString().contains('Server is not responding')) {
        userFriendlyError = AppText.get('upload_error_server_not_responding');
      } else if (e.toString().contains(
            'Failed to upload video to cloud service',
          )) {
        userFriendlyError = AppText.get('upload_error_service_unavailable');
      } else if (e.toString().contains('File too large')) {
        userFriendlyError = AppText.get('upload_error_file_too_large_short');
      } else if (e.toString().contains('Invalid file type')) {
        userFriendlyError = AppText.get('upload_error_invalid_file_type');
      } else {
        userFriendlyError = 'Error uploading video: ${e.toString()}';
      }

      // **NO setState: Use ValueNotifier**
      _errorMessage.value = userFriendlyError;
    } finally {
      if (mounted) {
        // **NO setState: Use ValueNotifier**
        _isUploading.value = false;
        // Stop unified progress tracking
        _stopUnifiedProgress();
      }
    }
  }

  /// **NEW: Wait for video processing to complete**
  Future<Map<String, dynamic>?> _waitForProcessingCompletion(
      String videoId) async {
    const maxWaitTime = Duration(minutes: 30); // Maximum wait time (30m)
    const checkInterval = Duration(seconds: 3); // Poll faster to avoid UI stall
    final startTime = DateTime.now();

    AppLogger.log('🔄 Waiting for video processing to complete...');
    AppLogger.log('📹 Video ID: $videoId');

    while (DateTime.now().difference(startTime) < maxWaitTime) {
      try {
        // Check processing status using the correct endpoint
        final response = await _videoService.getVideoProcessingStatus(videoId);

        if (response != null && response['success'] == true) {
          final videoData = response['video'];
          final processingStatus =
              (videoData?['processingStatus'] ?? '').toString();
          final processingProgress =
              (videoData?['processingProgress'] ?? 0) as int;
          final videoUrl = (videoData?['videoUrl'] ?? '').toString();
          final errorMsg = (videoData?['processingError'] ?? '').toString();

          AppLogger.log(
              '🔄 Processing status: $processingStatus ($processingProgress%)');
          if (errorMsg.isNotEmpty) {
             AppLogger.log('⚠️ Processing error reported: $errorMsg');
          }

          // **NO setState: Update progress using ValueNotifier**
          if (mounted) {
            final clamped = processingProgress.clamp(0, 100);
            _unifiedProgress.value = 0.8 + (clamped / 100.0 * 0.15);
          }

          final hasAbsoluteUrl =
              videoUrl.startsWith('http://') || videoUrl.startsWith('https://');

          if (processingStatus == 'completed' || hasAbsoluteUrl) {
            AppLogger.log('✅ Processing complete signal received');

            // **BATCHED UPDATE: Update all progress values at once**
            if (mounted) {
              _unifiedProgress.value = 1.0;
              _currentPhase.value = 'completed';
              _phaseDescription.value =
                  'Video processing completed successfully!';
            }

            await Future.delayed(const Duration(seconds: 1));
            return {
              'videoUrl': videoUrl,
              'thumbnailUrl': (videoData?['thumbnailUrl'] ?? '').toString(),
              'processingStatus': 'completed',
              'processingProgress': 100,
            };
          } else if (processingStatus == 'failed') {
            AppLogger.log(
                '❌ Video processing failed: $errorMsg');
            throw Exception('Processing failed: $errorMsg');
          }
        } else {
          AppLogger.log(
              '❌ Failed to get processing status: ${response?['error'] ?? 'Unknown error'}');
        }

        // Wait before checking again
        await Future.delayed(checkInterval);
      } catch (e) {
        if (e.toString().contains('Processing failed:')) rethrow;
        AppLogger.log('⚠️ Error checking processing status: $e');
        await Future.delayed(checkInterval);
      }
    }

    AppLogger.log('⏰ Processing timeout - maximum wait time exceeded');
    throw Exception('Video processing timed out after 30 minutes.');
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
                Text(
                  AppText.get('upload_success_title'),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                // Success message
                Text(
                  AppText.get('upload_success_message'),
                  style: const TextStyle(
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
                          AppText.get('upload_processed_ready'),
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
                        child: Text(
                          AppText.get('btn_upload_another'),
                          style: const TextStyle(
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
                        child: Text(
                          AppText.get('btn_view_in_feed'),
                          style: const TextStyle(
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

  void _showLoginPrompt() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppText.get('upload_login_required')),
        content: Text(AppText.get('upload_please_sign_in_upload')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppText.get('btn_cancel')),
          ),
          TextButton(
            onPressed: () async {
              final authController = Provider.of<GoogleSignInController>(
                context,
                listen: false,
              );
              Navigator.pop(context);
              final user = await authController.signIn();
              if (user != null && mounted) {
                await LogoutService.refreshAllState(this.context);
              }
            },
            child: Text(AppText.get('btn_sign_in')),
          ),
        ],
      ),
    );
  }

  Future<void> _pickVideo() async {
    final userData = await _authService.getUserData();
    if (userData == null) {
      _showLoginPrompt();
      return;
    }

    try {
      if (mounted) {
        Provider.of<MainController>(context, listen: false)
            .setMediaPickerActive(true);
      }
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowMultiple: false,
        allowedExtensions: [
          'mp4',
          'avi',
          'mov',
          'wmv',
          'flv',
          'webm',
        ],
      );
      if (mounted) {
        Provider.of<MainController>(context, listen: false)
            .setMediaPickerActive(false);
      }

      if (result != null) {
        // **BATCHED UPDATE: Use ValueNotifiers**
        _isProcessing.value = true;
        _errorMessage.value = null;

        final filePath = result.files.single.path!;
        final pickedFile = File(filePath);
        final normalizedPath = filePath.replaceAll('\\', '/');
        final fileNameLower = normalizedPath.split('/').last.toLowerCase();
        final extension =
            fileNameLower.contains('.') ? fileNameLower.split('.').last : '';

        const videoExtensions = [
          'mp4',
          'avi',
          'mov',
          'wmv',
          'flv',
          'webm',
        ];

        final bool isVideo = videoExtensions.contains(extension);

        if (!isVideo) {
          _errorMessage.value = AppText.get('upload_error_invalid_file');
          _isProcessing.value = false;
          return;
        }

        final fileSize = await pickedFile.length();

        if (isVideo) {
          const maxVideoSize = 100 * 1024 * 1024;
          if (fileSize > maxVideoSize) {
            _errorMessage.value =
                AppText.get('upload_error_file_too_large_short');
            _isProcessing.value = false;
            return;
          }

          // **NEW: Enforce minimum duration (8 seconds) for user uploads**
          try {
            final controller = VideoPlayerController.file(pickedFile);
            await controller.initialize();
            final durationSeconds = controller.value.duration.inSeconds;
            await controller.dispose();

            if (durationSeconds < 8) {
              _errorMessage.value = AppText.get('upload_error_video_too_short');
              _isProcessing.value = false;
              return;
            }
          } catch (e) {
            AppLogger.log('❌ UploadScreen: Error checking video duration: $e');
            // On error, just fall through and allow upload instead of blocking.
          }

          // **NEW: Calculate video hash and check for duplicates**
          AppLogger.log(
              '🔍 UploadScreen: Calculating video hash for duplicate detection...');
          try {
            final videoHash = await _calculateFileHash(pickedFile);
            AppLogger.log(
                '✅ UploadScreen: Video hash calculated: ${videoHash.substring(0, 16)}...');

            // **NEW: Check with backend if this video already exists**
            final token = userData['token'];
            if (token != null) {
              try {
                final baseUrl = await AppConfig.getBaseUrlWithFallback();
                final response = await httpClientService.post(
                  Uri.parse('$baseUrl/api/videos/check-duplicate'),
                  headers: {
                    'Authorization': 'Bearer $token',
                    'Content-Type': 'application/json',
                  },
                  body: json.encode({'videoHash': videoHash}),
                  timeout: const Duration(seconds: 10),
                );

                if (response.statusCode == 200) {
                  final data = json.decode(response.body);
                  if (data['isDuplicate'] == true) {
                    final existingVideoName =
                        data['existingVideoName'] ?? 'Unknown';
                    _errorMessage.value = AppText.get('upload_error_duplicate',
                            fallback:
                                'You have already uploaded this video: "{name}". Please select a different video.')
                        .replaceAll('{name}', existingVideoName);
                    _isProcessing.value = false;
                    AppLogger.log(
                        '⚠️ UploadScreen: Duplicate video detected: $existingVideoName');
                    return;
                  }
                  AppLogger.log(
                      '✅ UploadScreen: No duplicate found, proceeding with upload');
                } else {
                  AppLogger.log(
                      '⚠️ UploadScreen: Duplicate check failed with status ${response.statusCode}, continuing anyway');
                  // Continue with upload if check fails
                }
              } catch (e) {
                AppLogger.log('⚠️ UploadScreen: Error checking duplicate: $e');
                // Continue with upload if check fails (don't block user)
              }
            }
          } catch (e) {
            AppLogger.log('⚠️ UploadScreen: Error calculating hash: $e');
            // Continue with upload if hash calculation fails (don't block user)
          }
        }

        // **BATCHED UPDATE: Update media selection**
        _selectedVideo.value = pickedFile;
        _titleController.text = _deriveTitleFromFile(pickedFile);
        _selectedCategory.value ??= _defaultCategory;
        _isProcessing.value = false;

        AppLogger.log('✅ Media selected: ${pickedFile.path}');
        AppLogger.log(
          '📏 File size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB',
        );
      }
    } catch (e) {
      // **BATCHED UPDATE: Update error state**
      _errorMessage.value = 'Error picking video: $e';
      _isProcessing.value = false;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _linkController.dispose();
    _stopUnifiedProgress();
    _tagInputController.dispose();
    // **OPTIMIZED: Dispose ValueNotifiers**
    _selectedVideo.dispose();
    _isUploading.dispose();
    _isProcessing.dispose();
    _errorMessage.dispose();
    _showUploadForm.dispose();
    _unifiedProgress.dispose();
    _currentPhase.dispose();
    _phaseDescription.dispose();
    _elapsedSeconds.dispose();
    _selectedCategory.dispose();
    _tags.dispose();
    _showAdvancedSettings.dispose();
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
            title: Text(AppText.get('upload_title')),
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
                  tooltip: AppText.get('btn_manage_ads'),
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
                          Expanded(
                            child: Text(
                              AppText.get('upload_please_sign_in'),
                              style: const TextStyle(color: Colors.orange),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              final authController =
                                  Provider.of<GoogleSignInController>(
                                context,
                                listen: false,
                              );
                              final user = await authController.signIn();
                              if (user != null) {
                                await LogoutService.refreshAllState(context);
                              }
                            },
                            child: Text(AppText.get('btn_sign_in')),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 32),

                  // T&C card moved into a modal; show entry point above in AppBar

                  // Main Options Section
                  Text(
                    AppText.get('upload_choose_what_create'),
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.bold),
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
                                    // **NO setState: Use ValueNotifier**
                                    _showUploadForm.value =
                                        !_showUploadForm.value;
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
                                  Text(
                                    AppText.get('upload_video'),
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    AppText.get('upload_video_desc'),
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
                                  Text(
                                    AppText.get('upload_create_ad'),
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    AppText.get('upload_create_ad_desc'),
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
                  ValueListenableBuilder<bool>(
                    valueListenable: _showUploadForm,
                    builder: (context, showUploadForm, _) {
                      if (!showUploadForm) return const SizedBox.shrink();
                      return Card(
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
                                    'Upload',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    onPressed: () {
                                      // **NO setState: Use ValueNotifier**
                                      _showUploadForm.value = false;
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
                                child: ValueListenableBuilder<bool>(
                                  valueListenable: _isProcessing,
                                  builder: (context, isProcessing, _) {
                                    return ValueListenableBuilder<File?>(
                                      valueListenable: _selectedVideo,
                                      builder: (context, selectedVideo, _) {
                                        if (isProcessing) {
                                          return Center(
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                const CircularProgressIndicator(),
                                                const SizedBox(height: 16),
                                                Text(
                                                  AppText.get(
                                                      'upload_processing_video'),
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        } else if (selectedVideo != null) {
                                          return Center(
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                const Icon(
                                                  Icons.perm_media,
                                                  size: 48,
                                                  color: Colors.blue,
                                                ),
                                                const SizedBox(height: 16),
                                                Text(
                                                  selectedVideo.path
                                                      .split('/')
                                                      .last,
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        } else {
                                          return const Center(
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.perm_media,
                                                  size: 48,
                                                  color: Colors.grey,
                                                ),
                                                SizedBox(height: 16),
                                                Text(
                                                  'No video selected',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }
                                      },
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 24),
                              UploadAdvancedSettingsSection(
                                isExpanded: _showAdvancedSettings,
                                onToggle: _toggleAdvancedSettings,
                                titleController: _titleController,
                                defaultCategory: _defaultCategory,
                                selectedCategory: _selectedCategory,
                                onCategoryChanged: (value) {
                                  _selectedCategory.value =
                                      value ?? _defaultCategory;
                                },
                                linkController: _linkController,
                                tagInputController: _tagInputController,
                                tags: _tags,
                                onAddTag: _handleAddTag,
                                onRemoveTag: _handleRemoveTag,
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _showWhatToUploadDialog,
                                  icon: const Icon(Icons.help_outline),
                                  label: Text(
                                      AppText.get('upload_what_to_upload')),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                    side: BorderSide(
                                      color: Colors.blue.shade300,
                                    ),
                                    foregroundColor: Colors.blue.shade700,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),

                              // **UNIFIED PROGRESS INDICATOR** - Shows complete upload + processing flow
                              ValueListenableBuilder<bool>(
                                valueListenable: _isUploading,
                                builder: (context, isUploading, _) {
                                  if (!isUploading) {
                                    return const SizedBox.shrink();
                                  }
                                  return Column(
                                    children: [
                                      _buildUnifiedProgressWidget(),
                                      const SizedBox(height: 16),
                                    ],
                                  );
                                },
                              ),

                              ValueListenableBuilder<String?>(
                                valueListenable: _errorMessage,
                                builder: (context, errorMessage, _) {
                                  if (errorMessage == null) {
                                    return const SizedBox.shrink();
                                  }
                                  return ValueListenableBuilder<bool>(
                                    valueListenable: _isUploading,
                                    builder: (context, isUploading, _) {
                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 16.0),
                                        child: Column(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.all(12.0),
                                              decoration: BoxDecoration(
                                                color: Colors.red.shade50,
                                                borderRadius:
                                                    BorderRadius.circular(8.0),
                                                border: Border.all(
                                                  color: Colors.red.shade200,
                                                  width: 1,
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.error_outline,
                                                    color: Colors.red.shade700,
                                                    size: 20,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      errorMessage,
                                                      style: TextStyle(
                                                        color:
                                                            Colors.red.shade700,
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            // Retry button
                                            SizedBox(
                                              width: double.infinity,
                                              child: ElevatedButton.icon(
                                                onPressed: isUploading
                                                    ? null
                                                    : () {
                                                        // Clear error and retry upload
                                                        _errorMessage.value =
                                                            null;
                                                        _uploadVideo();
                                                      },
                                                icon: const Icon(Icons.refresh),
                                                label: Text(AppText.get(
                                                    'btn_retry_upload')),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.blue,
                                                  foregroundColor: Colors.white,
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    vertical: 12,
                                                  ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () => _pickVideo(),
                                      icon: const Icon(Icons.video_library),
                                      label:
                                          Text(AppText.get('btn_select_media')),
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 16,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: ValueListenableBuilder<bool>(
                                      valueListenable: _isUploading,
                                      builder: (context, isUploading, _) {
                                        return ElevatedButton.icon(
                                          onPressed:
                                              isUploading ? null : _uploadVideo,
                                          icon: isUploading
                                              ? const SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    valueColor:
                                                        AlwaysStoppedAnimation<
                                                            Color>(
                                                      Colors.white,
                                                    ),
                                                  ),
                                                )
                                              : const Icon(Icons.cloud_upload),
                                          label: Text(
                                            isUploading
                                                ? AppText.get(
                                                    'upload_uploading')
                                                : AppText.get(
                                                    'btn_upload_media'),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.blue,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 16,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
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
