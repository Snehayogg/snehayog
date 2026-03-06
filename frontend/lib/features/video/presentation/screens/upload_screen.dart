import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:vayu/features/auth/presentation/controllers/google_sign_in_controller.dart';
import 'package:vayu/features/video/presentation/managers/main_controller.dart';
import 'package:vayu/features/profile/presentation/managers/profile_state_manager.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:vayu/features/video/data/services/video_service.dart';
import 'package:vayu/features/auth/data/services/authservices.dart';
import 'package:vayu/features/auth/data/services/logout_service.dart';
import 'package:vayu/shared/services/http_client_service.dart';
import 'package:dio/dio.dart';
import 'package:vayu/features/ads/presentation/screens/create_ad_screen_refactored.dart';
import 'package:vayu/features/ads/presentation/screens/ad_management_screen.dart';
import 'package:vayu/shared/utils/app_logger.dart';
import 'package:vayu/shared/config/app_config.dart';
import 'package:video_player/video_player.dart';
import 'package:vayu/shared/utils/app_text.dart';
import 'package:vayu/core/design/colors.dart';
import 'package:vayu/core/design/typography.dart';
import 'package:vayu/core/design/spacing.dart';
import 'package:vayu/shared/managers/activity_recovery_manager.dart';
import 'package:vayu/shared/models/app_activity.dart';
import 'package:vayu/shared/widgets/app_button.dart';
import 'package:vayu/features/video/presentation/widgets/upload_advanced_settings_section.dart';
import 'package:vayu/features/video/presentation/screens/make_episode_screen.dart';



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
  final ValueNotifier<bool> _isMinimizing = ValueNotifier<bool>(false);

  // **UNIFIED PROGRESS TRACKING** - Single progress bar for entire flow
  final ValueNotifier<double> _unifiedProgress = ValueNotifier<double>(0.0);
  final ValueNotifier<String> _currentPhase = ValueNotifier<String>('');
  final ValueNotifier<String> _phaseDescription = ValueNotifier<String>('');
  int _uploadStartTime = 0;
  final ValueNotifier<int> _elapsedSeconds = ValueNotifier<int>(0);
  double _lastUploadNetworkProgress = 0.0;

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _linkController = TextEditingController();
  final VideoService _videoService = VideoService();
  final AuthService _authService = AuthService();

  // Timer for unified progress tracking
  Timer? _progressTimer;
  CancelToken? _uploadCancelToken;

  /// Cancel current upload
  void _cancelUpload() {
    if (_uploadCancelToken != null && !_isUploading.value) return;
    
    _uploadCancelToken?.cancel('User cancelled upload');
    _isUploading.value = false;
    _stopUnifiedProgress();
    
    // Clear activity from disk
    ActivityRecoveryManager().clearActivity();
    
    // Clear selection so user starts fresh
    _deselectVideo();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppText.get('upload_cancelled', fallback: 'Upload cancelled')),
        backgroundColor: AppColors.backgroundSecondary,
      ),
    );
  }

  /// Deselect current video and reset related fields
  void _deselectVideo() {
    _selectedVideo.value = null;
    _titleController.clear();
    _errorMessage.value = null;
    _showUploadForm.value = false;
  }

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
          'progress': 0.1,
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
    _lastUploadNetworkProgress = 0.0;
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
              fontWeight: AppTypography.weightBold,
            ),
          ),
          AppSpacing.vSpace4,
          Text(
            body,
            style: AppTypography.bodySmall.copyWith(fontSize: 13),
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
      backgroundColor: AppColors.backgroundPrimary,
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
            padding: AppSpacing.edgeInsetsAll16,
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
                          color: AppColors.error.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.gavel, color: AppColors.error),
                      ),
                      AppSpacing.hSpace12,
                      Expanded(
                        child: Text(
                          AppText.get('upload_terms_title'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: AppTypography.weightBold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: AppColors.textSecondary),
                        onPressed: () => Navigator.pop(context),
                      )
                    ],
                  ),
                  AppSpacing.vSpace12,
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
                  AppSpacing.vSpace16,
                  SizedBox(
                    width: double.infinity,
                    child: AppButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.check_circle_outline),
                      label: AppText.get('btn_i_understand'),
                      variant: AppButtonVariant.danger,
                      isFullWidth: true,
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

    // Listeners for activity recovery
    _titleController.addListener(_onFieldChanged);
    _linkController.addListener(_onFieldChanged);
    _selectedVideo.addListener(_onFieldChanged);
    _selectedCategory.addListener(_onFieldChanged);
    _tags.addListener(_onFieldChanged);

    // Check for saved activity
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkSavedActivity();
    });
  }

  void _onFieldChanged() {
    // Only save if not currently uploading
    if (!_isUploading.value && !_isProcessing.value) {
      _saveCurrentActivity();

      // [REMOVED] Auto-trigger upload
      // _uploadVideo();
    }
  }

  void _handleMakeEpisode() {
    if (_selectedVideo.value == null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const MakeEpisodeScreen(),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MakeEpisodeScreen(
            initialFile: _selectedVideo.value,
          ),
        ),
      );
    }
  }

  Future<void> _saveCurrentActivity() async {
    if (_selectedVideo.value == null &&
        _titleController.text.isEmpty &&
        _linkController.text.isEmpty) {
      // Don't save empty states
      return;
    }

    final data = {
      'videoPath': _selectedVideo.value?.path,
      'title': _titleController.text,
      'link': _linkController.text,
      'category': _selectedCategory.value,
      'tags': _tags.value,
    };

    await ActivityRecoveryManager().saveActivity(ActivityType.videoUpload, data);
  }

  Future<void> _checkSavedActivity() async {
    final activity = await ActivityRecoveryManager().getSavedActivity();
    if (activity != null && activity.type == ActivityType.videoUpload) {
      if (!mounted) return;

      final data = activity.data;
      final videoPath = data['videoPath'] as String?;
      
      AppLogger.log('🚀 UploadScreen: Automatically resuming saved upload activity');

      if (videoPath != null && videoPath.isNotEmpty) {
        _selectedVideo.value = File(videoPath);
      }
      _titleController.text = data['title'] ?? '';
      _linkController.text = data['link'] ?? '';
      _selectedCategory.value = data['category'] ?? _defaultCategory;
      if (data['tags'] != null) {
        _tags.value = List<String>.from(data['tags']);
      }
      _showUploadForm.value = true;
      
      // Notify user via a small snackbar instead of a disruptive dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppText.get('upload_resumed', fallback: 'Upload progress restored')),
          backgroundColor: AppColors.success.withValues(alpha: 0.8),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
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
      // Stream hashing avoids loading entire video into memory.
      final digest = await sha256.bind(file.openRead()).first;
      return digest.toString();
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
      if (fileSize > 700 * 1024 * 1024) {
        // 700MB limit
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

      // Create new cancel token for this upload
      _uploadCancelToken = CancelToken();

      final uploadedVideo = await runZoned(
        () => _videoService.uploadVideo(
          _selectedVideo.value!,
          _titleController.text,
          '', // description
          _linkController.text.isNotEmpty ? _linkController.text : '', // link
          (progress) {
             // Handle precise progress from Dio
             // We map Dio progress (0.0 to 1.0) into the 'upload' phase window
             // upload phase is from 0.1 to 0.4 in _progressPhases
             if (_currentPhase.value == 'upload') {
               final normalizedProgress = progress.clamp(0.0, 1.0).toDouble();
               if (normalizedProgress > _lastUploadNetworkProgress) {
                 _lastUploadNetworkProgress = normalizedProgress;
               }
               _unifiedProgress.value = 0.1 + (_lastUploadNetworkProgress * 0.3);
             }
          },
          _uploadCancelToken,
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

      // **FIX: Robustly extract video data (backend often nests it under \'video\')**
      final Map<String, dynamic> videoDetails = (uploadedVideo['video'] is Map)
          ? Map<String, dynamic>.from(uploadedVideo['video'] as Map)
          : uploadedVideo;

      // **FIX: Robustly extract ID (handle \'id\' vs \'_id\' and nesting)**
      final String? videoId = videoDetails['id']?.toString() ?? 
                            videoDetails['_id']?.toString();
      
      AppLogger.log('🆔 Resolved Video ID: $videoId');
      
      if (videoId == null) {
        AppLogger.log('❌ Error: Video ID not found in: $videoDetails');
        throw Exception('Video ID not found in upload response');
      }

      // Update to validation phase
      _updateProgressPhase('validation');

      // **NEW: Handle Immediate Queue Success**
      // The backend returns processingStatus: 'queued'
      // We should NOT wait here. We should close the screen and let the user know.
      
      // Update to processing phase
      _updateProgressPhase('processing');

      final String processingStatus =
          videoDetails['processingStatus']?.toString().toLowerCase() ?? '';

      // **OPTIMISTIC UPDATE: Inject processing video into ProfileStateManager immediately**
      try {
        final optimisticVideoPayload = Map<String, dynamic>.from(videoDetails);
        // Ensure ID is present as \'id\' for VideoModel/Manager compatibility
        optimisticVideoPayload['id'] ??= videoId;
        final uploaderId =
            userData['googleId']?.toString() ?? userData['id']?.toString() ?? '';
        optimisticVideoPayload['processingStatus'] =
            processingStatus.isEmpty ? 'pending' : processingStatus;
        optimisticVideoPayload['processingProgress'] =
            (optimisticVideoPayload['processingProgress'] as num?)?.toInt() ?? 0;
        optimisticVideoPayload['uploadedAt'] ??= DateTime.now().toIso8601String();
        optimisticVideoPayload['videoName'] =
            optimisticVideoPayload['videoName']?.toString().trim().isNotEmpty == true
                ? optimisticVideoPayload['videoName']
                : _titleController.text.trim();

        if (optimisticVideoPayload['uploader'] is! Map) {
          optimisticVideoPayload['uploader'] = {
            'id': uploaderId,
            '_id': uploaderId,
            'googleId': uploaderId,
            'name': userData['name']?.toString() ?? 'You',
            'profilePic': userData['profilePic']?.toString() ?? '',
          };
        }

        Provider.of<ProfileStateManager>(context, listen: false)
            .addVideoOptimistically(optimisticVideoPayload);
      } catch (e) {
        AppLogger.log('⚠️ UploadScreen: Error injecting optimistic video: $e');
      }

      // Call the callback to refresh other tabs
      if (widget.onVideoUploaded != null) {
        widget.onVideoUploaded!();
      }

      // **UNIFIED FLOW: Always wait for processing completion on this screen**
      // This gives better UX as the user sees the progress bar go from 0 to 100%
      // videoId is already validated above

      final completedVideo = await _waitForProcessingCompletion(videoId);

      if (completedVideo != null) {
        // **MINIMIZING EARLY EXIT: User tapped "Run in BG" during the processing wait**
        // The optimistic video is already in ProfileStateManager. Just reset the screen.
        if (completedVideo['processingStatus'] == 'minimizing') {
          AppLogger.log('🏃 UploadScreen: User minimized — resetting upload screen without clearing optimistic profile entry');
          _selectedVideo.value = null;
          _titleController.clear();
          _linkController.clear();
          _selectedCategory.value = _defaultCategory;
          _tags.value = [];
          _showAdvancedSettings.value = false;
          _isMinimizing.value = false;
          ActivityRecoveryManager().clearActivity();
          return;
        }

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
        
        // Clear activity after successful completion
        ActivityRecoveryManager().clearActivity();
        _tags.value = [];
        // Video type selection removed; all uploads default to free (Yug).
        _showAdvancedSettings.value = false;

        // Stop unified progress tracking
        _stopUnifiedProgress();

        // **FIX: Skip success dialog if user chose to run in background**
        // (This is a safety fallback — primary handling is done above via processingStatus check)
        if (_isMinimizing.value) {
          AppLogger.log('🏃 UploadScreen: Safety fallback minimizing handler');
          _selectedVideo.value = null;
          _isMinimizing.value = false;
          ActivityRecoveryManager().clearActivity();
          return;
        }

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
      if (e is DioException && e.type == DioExceptionType.cancel) {
        AppLogger.log('🚫 UploadScreen: Catching cancellation in UI');
        return; // Don't show error message for manual cancellation
      }

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
    const checkInterval = Duration(seconds: 5); // Polling slower to reduce server load
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

        // Check if user clicked "Finish in Background"
        if (_isMinimizing.value) {
          AppLogger.log('🏃 User chose to finish in background');
          // Return a special sentinel — do NOT return null (that would throw an exception)
          return {
            'videoUrl': '',
            'thumbnailUrl': '',
            'processingStatus': 'minimizing',
            'processingProgress': 0,
          };
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
              color: AppColors.backgroundPrimary,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: AppColors.shadowPrimary,
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
                    color: AppColors.success.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    color: AppColors.success,
                    size: 50,
                  ),
                ),
                AppSpacing.vSpace24,

                // Success title
                Text(
                  AppText.get('upload_success_title'),
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: AppTypography.weightBold,
                  ),
                  textAlign: TextAlign.center,
                ),
                AppSpacing.vSpace16,

                // Success message
                Text(
                  AppText.get('upload_success_message'),
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                AppSpacing.vSpace24,

                // Processing info
                Container(
                  padding: AppSpacing.edgeInsetsAll16,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                  child: Row(
                    children:  [
                      const Icon(Icons.check_circle_outline,
                          color: AppColors.success, size: 20),
                      AppSpacing.hSpace12,
                      Expanded(
                        child: Text(
                          AppText.get('upload_processed_ready'),
                          style: const TextStyle(
                            color: AppColors.success,
                            fontSize: 14,
                            fontWeight: AppTypography.weightMedium,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                AppSpacing.vSpace24,

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        onPressed: () {
                          Navigator.of(context).pop(); // Close dialog
                          
                          // Switch to Vayu (Feed) tab - index 1
                          try {
                            Provider.of<MainController>(context, listen: false).changeIndex(1);
                            // Navigator.of(context).pop(); // REMOVED: Pops MainScreen as UploadScreen is a tab
                          } catch (e) {
                            AppLogger.log('❌ UploadScreen: Error switching to feed: $e');
                            // Navigator.of(context).pop(); // REMOVED: Safety pop
                          }
                        },
                        label: AppText.get('btn_view_in_feed'),
                        variant: AppButtonVariant.primary,
                        isFullWidth: true,
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
          AppButton(
            onPressed: () => Navigator.pop(context),
            label: AppText.get('btn_cancel'),
            variant: AppButtonVariant.text,
          ),
          AppButton(
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
            label: AppText.get('btn_sign_in'),
            variant: AppButtonVariant.primary,
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
          const maxVideoSize = 700 * 1024 * 1024;
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
        
        // **AUTO-TRIGGER REMOVED** - User now clicks "Start Upload"
        // _uploadVideo();

        AppLogger.log('✅ Media selected: ${pickedFile.path}');
        AppLogger.log(
          '📏 File size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB',
        );
      } else {
        // **NEW: If picker cancelled and no video currently selected, hide form**
        if (_selectedVideo.value == null) {
          _showUploadForm.value = false;
        }
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
    _isMinimizing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GoogleSignInController>(
      builder: (context, authController, _) {
        final isSignedIn = authController.isSignedIn;

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
          body: ValueListenableBuilder<bool>(
            valueListenable: _isProcessing,
            builder: (context, isProcessing, _) {
              // State 1.5: Analyzing video (hashing/duplicate check) — shown immediately
              // after gallery pick, before _selectedVideo is even set.
              if (isProcessing) {
                return _buildAnalyzingVideoView(context);
              }

              return ValueListenableBuilder<bool>(
                valueListenable: _isUploading,
                builder: (context, isUploading, _) {
                  return ValueListenableBuilder<File?>(
                    valueListenable: _selectedVideo,
                    builder: (context, selectedVideo, _) {
                      // State 1: Nothing selected yet → show choice cards
                      if (!isUploading && selectedVideo == null) {
                        return _buildInitialChoiceView(context, isSignedIn, authController);
                      }
                      // State 2: Upload progress dashboard
                      return _buildUploadProgressDashboard(context);
                    },
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  /// **State 1.5: Full-screen loading shown while video is being analyzed**
  Widget _buildAnalyzingVideoView(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 80,
              height: 80,
              child: CircularProgressIndicator(
                strokeWidth: 6,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Analyzing Video...',
              style: AppTypography.headlineSmall.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'Checking for duplicates and validating your video. Please wait.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInitialChoiceView(BuildContext context, bool isSignedIn, GoogleSignInController authController) {
    if (!isSignedIn) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 64, color: AppColors.textTertiary),
              const SizedBox(height: 24),
              Text(
                AppText.get('upload_login_required_title', fallback: 'Login Required'),
                style: AppTypography.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                AppText.get('upload_login_required_desc', fallback: 'Please login to share your creativity with the world.'),
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 32),
              AppButton(
                onPressed: () async {
                  final user = await authController.signIn();
                  if (user != null) {
                    await LogoutService.refreshAllState(context);
                  }
                },
                label: AppText.get('btn_login', fallback: 'Login with Google'),
                variant: AppButtonVariant.primary,
                isFullWidth: true,
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          children: [
            Text(
              AppText.get('upload_choose_what_create'),
              style: AppTypography.headlineLarge.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
           const SizedBox(height: 48),
            
            // Visual Choice: Video
            _buildChoiceCard(
              context: context,
              icon: Icons.video_library,
              title: AppText.get('upload_video'),
              desc: AppText.get('upload_video_desc'),
              color: AppColors.primary,
              onTap: _pickVideo,
            ),
            
            const SizedBox(height: 24),
            
            // Visual Choice: Ad
            _buildChoiceCard(
              context: context,
              icon: Icons.campaign,
              title: AppText.get('upload_create_ad'),
              desc: AppText.get('upload_create_ad_desc'),
              color: AppColors.success,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const CreateAdScreenRefactored()),
                );
              },
            ),
            
           const SizedBox(height: 40),
            
            // Policy Note
            TextButton.icon(
              onPressed: _showWhatToUploadDialog,
              icon: const Icon(Icons.help_outline, size: 16),
              label: Text(
                AppText.get('upload_what_to_upload'),
                style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary, decoration: TextDecoration.underline),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChoiceCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String desc,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.1), width: 1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: color),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.headlineSmall.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    desc,
                    style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: color.withValues(alpha: 0.3)),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadProgressDashboard(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Visual Video Preview / Progress Ring
          Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                ValueListenableBuilder<double>(
                  valueListenable: _unifiedProgress,
                  builder: (context, progress, _) {
                    return SizedBox(
                      width: 180,
                      height: 180,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 8,
                        backgroundColor: AppColors.borderPrimary,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                      ),
                    );
                  },
                ),
                Container(
                  width: 156,
                  height: 156,
                  decoration: BoxDecoration(
                    color: AppColors.backgroundSecondary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.movie_outlined, size: 72, color: AppColors.primary),
                ),
                // Done indicator
                ValueListenableBuilder<String>(
                  valueListenable: _currentPhase,
                  builder: (context, phase, _) {
                    if (phase != 'completed') return SizedBox.shrink();
                    return Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.check_circle, size: 80, color: AppColors.success),
                    );
                  },
                ),
              ],
            ),
          ),
          
          SizedBox(height: 32),
          
          // Current Status
          ValueListenableBuilder<String>(
            valueListenable: _currentPhase,
            builder: (context, phase, _) {
              return Text(
                _progressPhases[phase]?['name'] ?? 'Processing...',
                style: AppTypography.headlineSmall.copyWith(fontWeight: FontWeight.bold),
              );
            },
          ),
          
          ValueListenableBuilder<String>(
            valueListenable: _phaseDescription,
            builder: (context, desc, _) {
              return Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text(
                  desc,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
                ),
              );
            },
          ),

          SizedBox(height: 48),

          // Advanced Settings Section (Integrated)
          UploadAdvancedSettingsSection(
            isExpanded: _showAdvancedSettings,
            onToggle: _toggleAdvancedSettings,
            titleController: _titleController,
            selectedCategory: _selectedCategory,
            defaultCategory: _defaultCategory,
            onCategoryChanged: (val) => _selectedCategory.value = val,
            linkController: _linkController,
            tagInputController: _tagInputController,
            tags: _tags,
            onAddTag: _handleAddTag,
            onRemoveTag: _handleRemoveTag,
            onMakeEpisode: _handleMakeEpisode,
          ),
          
          SizedBox(height: 48),

          // Error Message Display
          ValueListenableBuilder<String?>(
            valueListenable: _errorMessage,
            builder: (context, error, _) {
              if (error == null) return SizedBox.shrink();
              return Container(
                margin: EdgeInsets.only(bottom: 24),
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: AppColors.error),
                    SizedBox(width: 12),
                    Expanded(child: Text(error, style: TextStyle(color: AppColors.error))),
                  ],
                ),
              );
            },
          ),

          // Action Buttons
          ValueListenableBuilder<String>(
            valueListenable: _currentPhase,
            builder: (context, phase, _) {
              final isComplete = phase == 'completed' || phase == 'finalizing';
              final isError = _errorMessage.value != null;
              final hasSelected = _selectedVideo.value != null;
              final isUploading = _isUploading.value;

              if (isError) {
                return AppButton(
                  onPressed: () {
                    _errorMessage.value = null;
                    _uploadVideo();
                  },
                  label: 'Retry Upload',
                  variant: AppButtonVariant.primary,
                  isFullWidth: true,
                );
              }

              // Show "Start Upload" + "Change Video" if video selected but not uploading
              if (hasSelected && !isUploading && !isComplete) {
                return Column(
                  children: [
                    AppButton(
                      onPressed: _uploadVideo,
                      label: 'Start Upload',
                      variant: AppButtonVariant.primary,
                      isFullWidth: true,
                      icon: const Icon(Icons.cloud_upload_outlined),
                    ),
                    const SizedBox(height: 12),
                    AppButton(
                      onPressed: _deselectVideo,
                      label: 'Change Video',
                      variant: AppButtonVariant.outline,
                      isFullWidth: true,
                    ),
                  ],
                );
              }

              return Column(
                children: [
                  if (!isComplete)
                    Row(
                      children: [
                        Expanded(
                          child: AppButton(
                            onPressed: _cancelUpload,
                            label: 'Cancel',
                            variant: AppButtonVariant.outline,
                          ),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: AppButton(
                            onPressed: () {
                              _isMinimizing.value = true;
                              // Navigate to Profile/Account tab (index 4) so user can track upload status
                              Provider.of<MainController>(context, listen: false).changeIndex(4);
                              // Re-notify listeners so the Consumer in ProfileVideosWidget
                              // immediately rebuilds and shows the optimistic video already
                              // injected by addVideoOptimistically().
                              try {
                                Provider.of<ProfileStateManager>(context, listen: false)
                                    .notifyListenersSafe();
                              } catch (_) {}
                            },
                            label: 'Run in BG',
                            variant: AppButtonVariant.primary,
                          ),
                        ),
                      ],
                    ),
                  if (isComplete)
                    AppButton(
                      onPressed: () {
                        widget.onVideoUploaded?.call();
                        Navigator.pop(context);
                      },
                      label: 'Done',
                      variant: AppButtonVariant.primary,
                      isFullWidth: true,
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}


