import 'package:flutter/material.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:file_picker/file_picker.dart';
import 'package:vayug/shared/services/file_picker_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/core/providers/auth_providers.dart';
import 'package:vayug/core/providers/video_providers.dart';
import 'package:vayug/core/providers/navigation_providers.dart';
import 'package:vayug/core/providers/profile_providers.dart';
import 'package:vayug/features/auth/presentation/controllers/google_sign_in_controller.dart';
import 'dart:io';
import 'dart:async';
import 'package:hugeicons/hugeicons.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:vayug/features/video/core/data/services/video_service.dart';
import 'package:vayug/features/auth/data/services/authservices.dart';
import 'package:vayug/features/auth/data/services/logout_service.dart';
import 'package:vayug/shared/services/http_client_service.dart';
import 'package:dio/dio.dart';
import 'package:vayug/features/ads/presentation/screens/create_ad_screen_refactored.dart';
import 'package:vayug/features/ads/presentation/screens/ad_management_screen.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/shared/config/app_config.dart';
import 'package:video_player/video_player.dart';
import 'package:vayug/shared/utils/app_text.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/shared/widgets/app_button.dart';
import 'package:vayug/features/video/upload/presentation/screens/upload_advanced_settings_screen.dart';
import 'package:vayug/features/video/upload/presentation/screens/make_episode_screen.dart';
import 'package:vayug/features/profile/core/presentation/screens/linked_accounts_screen.dart';
import 'package:vayug/features/video/upload/presentation/screens/shorts_generator_screen.dart';
import 'package:vayug/shared/widgets/vayu_snackbar.dart';
import 'package:vayug/shared/constants/interests.dart';
import 'package:vayug/features/video/upload/presentation/widgets/short_video_creator_dialog.dart';

class UploadScreen extends ConsumerStatefulWidget {
  final VoidCallback? onVideoUploaded; // Add callback for video upload success

  const UploadScreen({super.key, this.onVideoUploaded});

  @override
  ConsumerState<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends ConsumerState<UploadScreen> {
  // **OPTIMIZED: Use ValueNotifiers for granular updates (no setState)**
  final ValueNotifier<File?> _selectedVideo = ValueNotifier<File?>(null);
  final ValueNotifier<bool> _isUploading = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isProcessing = ValueNotifier<bool>(false);
  final ValueNotifier<String?> _errorMessage = ValueNotifier<String?>(null);
  final ValueNotifier<bool> _isAuthError = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _showUploadForm = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isMinimizing = ValueNotifier<bool>(false);

  // **UNIFIED PROGRESS TRACKING** - Single progress bar for entire flow
  final ValueNotifier<double> _unifiedProgress = ValueNotifier<double>(0.0);
  final ValueNotifier<String> _currentPhase = ValueNotifier<String>('');
  final ValueNotifier<String> _phaseDescription = ValueNotifier<String>('');
  final ValueNotifier<Map<String, String>> _crossPostStatusMap = ValueNotifier<Map<String, String>>({});
  final ValueNotifier<Map<String, int>> _crossPostProgressMap = ValueNotifier<Map<String, int>>({});
  int _uploadStartTime = 0;
  final ValueNotifier<int> _elapsedSeconds = ValueNotifier<int>(0);
  double _lastUploadNetworkProgress = 0.0;
  final GlobalKey _categoryKey = GlobalKey();

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _linkController = TextEditingController();
  late final VideoService _videoService;
  late final AuthService _authService;
  late final FilePickerService _filePickerService;

  // Timer for unified progress tracking
  Timer? _progressTimer;
  CancelToken? _uploadCancelToken;

  /// Cancel current upload
  void _cancelUpload() {
    if (_uploadCancelToken != null && !_isUploading.value) return;

    _uploadCancelToken?.cancel('User cancelled upload');
    _isUploading.value = false;
    _stopUnifiedProgress();

    // Clear selection so user starts fresh
    _deselectVideo();

    if (mounted) {
      VayuSnackBar.showInfo(context, AppText.get('upload_cancelled', fallback: 'Upload cancelled'));
    }
  }

  /// Deselect current video and reset related fields
  void _deselectVideo() {
    _resetScreenState();
  }

  /// **NEW: Reset the entire screen state to its initial selection view**
  void _resetScreenState() {
    if (mounted) {
      _selectedVideo.value = null;
      _isUploading.value = false;
      _isProcessing.value = false;
      _errorMessage.value = null;
      _isAuthError.value = false;
      _showUploadForm.value = false;
      _isMinimizing.value = false;
      _unifiedProgress.value = 0.0;
      _currentPhase.value = 'preparation';
      _phaseDescription.value = '';
      _titleController.clear();
      _linkController.clear();
      _selectedCategory.value = null;
      _tags.value = [];
      _showAdvancedSettings.value = false;
      _selectedPlatforms.value = [];
      _tagInputController.clear();
      _crossPostStatusMap.value = {};
      _crossPostProgressMap.value = {};
      _quizzes.value = [];
      _videoDuration.value = 0.0;

      _stopUnifiedProgress();
      
      // ENSURE: Reset phase is the absolute last step so it's not overwritten
      _currentPhase.value = 'preparation';

      AppLogger.log('🔄 UploadScreen: Full state reset completed');
    }
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
        'crossposting': {
          'name': 'Cross-Posting',
          'description': 'Uploading to external platforms...',
          'progress': 0.98,
          'icon': Icons.share,
        },
      };

  // NEW: Category, video type, and tags to align with ad targeting interests
  static const String _defaultCategory = 'Others';
  final ValueNotifier<String?> _selectedCategory = ValueNotifier<String?>(null);
  final ValueNotifier<List<String>> _tags = ValueNotifier<List<String>>([]);
  final ValueNotifier<bool> _showAdvancedSettings = ValueNotifier<bool>(false);
  final TextEditingController _tagInputController = TextEditingController();
  final ValueNotifier<List<String>> _selectedPlatforms = ValueNotifier<List<String>>([]);
  final ValueNotifier<List<QuizModel>> _quizzes = ValueNotifier<List<QuizModel>>([]);
  final ValueNotifier<double> _videoDuration = ValueNotifier<double>(0.0);

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
      _unifiedProgress.value = 1.0;
      // Removed: phase setting to 'completed' here to avoid stickiness during resets
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
            style: AppTypography.bodySmall.copyWith(fontSize: 13, color: AppColors.textSecondary),
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
                        icon: const Icon(Icons.close,
                            color: AppColors.textSecondary),
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
    _videoService = ref.read(videoServiceProvider);
    _authService = ref.read(authServiceProvider);
    _filePickerService = ref.read(filePickerServiceProvider);
    _selectedCategory.value = null;
    super.initState();

    // Listeners for activity recovery
    _titleController.addListener(_onFieldChanged);
    _linkController.addListener(_onFieldChanged);
    _selectedVideo.addListener(_onFieldChanged);
    _selectedCategory.addListener(_onFieldChanged);
    _tags.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    // Only save if not currently uploading
    if (!_isUploading.value && !_isProcessing.value) {
    }
  }

  void _handleMakeEpisode() async {
    if (_selectedVideo.value == null) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const MakeEpisodeScreen(),
        ),
      );
      if (result == true) {
        _resetScreenState();
      }
    } else {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MakeEpisodeScreen(
            initialFile: _selectedVideo.value,
          ),
        ),
      );
      if (result == true) {
        _resetScreenState();
      }
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

  /// **NEW: Handle re-authentication when session expires during upload**
  Future<void> _handleReAuthentication() async {
    try {
      AppLogger.log('🔐 UploadScreen: Re-authenticating session...');
      _isUploading.value = true; // Show loading state during re-auth
      
      // Attempt to sign in again
      final userData = await _authService.signInWithGoogle();
      
      if (userData != null) {
        AppLogger.log('✅ UploadScreen: Re-authentication successful! Resuming upload...');
        _isAuthError.value = false;
        _errorMessage.value = null;
        
        // Resume upload automatically
        Future.microtask(() => _uploadVideo());
      } else {
        AppLogger.log('❌ UploadScreen: Re-authentication failed or cancelled');
        _isUploading.value = false;
        _errorMessage.value = 'Re-authentication failed. Please sign in to continue.';
      }
    } catch (e) {
      AppLogger.log('❌ UploadScreen: Error during re-authentication: $e');
      _isUploading.value = false;
      _errorMessage.value = 'Failed to sign in. Please try again.';
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
      _errorMessage.value = 'Please select a category for your video.';
      
      // Auto-scroll to category section for better UX
      if (_categoryKey.currentContext != null) {
        Scrollable.ensureVisible(
          _categoryKey.currentContext!,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
      return;
    }

    try {

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

      // **NEW: Prepare cross-posting platforms**
      final crossPostPlatforms = _selectedPlatforms.value;

      final uploadedVideo = await runZoned(
        () => _videoService.uploadVideo(
          videoFile: _selectedVideo.value!,
          title: _titleController.text,
          description: '',
          link: _linkController.text.isNotEmpty ? _linkController.text : '',
          category: _selectedCategory.value,
          tags: _tags.value,
          videoType: serverVideoType,
          onProgress: (progress) {
            if (_currentPhase.value == 'upload') {
              final normalizedProgress = progress.clamp(0.0, 1.0).toDouble();
              if (normalizedProgress > _lastUploadNetworkProgress) {
                _lastUploadNetworkProgress = normalizedProgress;
              }
              _unifiedProgress.value = 0.1 + (_lastUploadNetworkProgress * 0.3);
            }
          },
          cancelToken: _uploadCancelToken,
          crossPostPlatforms: crossPostPlatforms,
          quizzes: _quizzes.value,
        ),
        zoneValues: {
          'upload_metadata': {
            'category': _selectedCategory.value,
            'tags': _tags.value,
            'videoType': serverVideoType,
            'crossPostPlatforms': crossPostPlatforms,
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
      final String? videoId =
          videoDetails['id']?.toString() ?? videoDetails['_id']?.toString();

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
        final uploaderId = userData['googleId']?.toString() ??
            userData['id']?.toString() ??
            '';
        optimisticVideoPayload['processingStatus'] =
            processingStatus.isEmpty ? 'pending' : processingStatus;
        optimisticVideoPayload['processingProgress'] =
            (optimisticVideoPayload['processingProgress'] as num?)?.toInt() ??
                0;
        optimisticVideoPayload['uploadedAt'] ??=
            DateTime.now().toIso8601String();
        optimisticVideoPayload['videoName'] =
            optimisticVideoPayload['videoName']?.toString().trim().isNotEmpty ==
                    true
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

        ref.read(profileStateManagerProvider)
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
          AppLogger.log(
              '🏃 UploadScreen: User minimized — resetting upload screen without clearing optimistic profile entry');
          _selectedVideo.value = null;
          _titleController.clear();
          _linkController.clear();
          _selectedCategory.value = _defaultCategory;
          _tags.value = [];
          _showAdvancedSettings.value = false;
          _isMinimizing.value = false;
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

        // Mark as completed/ready before UI reset
        _updateProgressPhase('completed');
        _phaseDescription.value = AppText.get('upload_video_ready');

        // **BATCHED UPDATE: Clear form and reset state for next upload**
        _resetScreenState();

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
      bool isAuth = false;

      if (e is DioException && e.response?.statusCode == 401) {
        isAuth = true;
        userFriendlyError = 'Session expired. Please sign in again to resume upload.';
      } else if (e.toString().contains('User not authenticated') ||
          e.toString().contains('Authentication token not found')) {
        isAuth = true;
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
      _isAuthError.value = isAuth;
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
    const checkInterval =
        Duration(seconds: 5); // Polling slower to reduce server load
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

          // **NEW: Determine if video is already available via absolute URL**
          final hasAbsoluteUrl = videoUrl.startsWith('http://') || videoUrl.startsWith('https://');

          // **NO setState: Update progress using ValueNotifier**
          if (mounted) {
            final clamped = processingProgress.clamp(0, 100);
            _unifiedProgress.value = 0.8 + (clamped / 100.0 * 0.15);
          }

          // **NEW: Update Cross-Post Data**
          if (mounted) {
            final crossStatus = Map<String, String>.from(videoData?['crossPostStatus'] ?? {});
            final crossProgress = Map<String, int>.from(videoData?['crossPostProgress'] ?? {});
            
            // Only update if changed to avoid unnecessary rebuilds
            if (json.encode(crossStatus) != json.encode(_crossPostStatusMap.value)) {
              _crossPostStatusMap.value = crossStatus;
            }
            if (json.encode(crossProgress) != json.encode(_crossPostProgressMap.value)) {
              _crossPostProgressMap.value = crossProgress;
            }

            // If any platform is STILL uploading, change phase to crossposting
            final isCrossPosting = crossStatus.values.any((s) => s == 'pending' || s == 'processing');
            if (isCrossPosting && (processingStatus == 'completed' || hasAbsoluteUrl)) {
                _currentPhase.value = 'crossposting';
                _phaseDescription.value = 'Successfully uploaded to Vayu! Now cross-posting to other platforms...';
                
                // Calculate an average cross-post progress for the main ring (0.95 to 1.0)
                if (crossProgress.isNotEmpty) {
                    final totalP = crossProgress.values.fold(0, (sum, p) => sum + p);
                    final avgP = totalP / crossProgress.length;
                    _unifiedProgress.value = 0.95 + (avgP / 100.0 * 0.05);
                }
            }
          }

          if (processingStatus == 'completed' || hasAbsoluteUrl) {
            // **NEW: Explicitly wait for Cross-posting if platforms were selected**
            final selectedPlatforms = _selectedPlatforms.value;
            final crossStatus = Map<String, String>.from(videoData?['crossPostStatus'] ?? {});
            
            bool anyIncomplete = false;
            for (final p in selectedPlatforms) {
                final status = crossStatus[p];
                if (status == 'pending' || status == 'processing') {
                    anyIncomplete = true;
                    break;
                }
            }

            if (!anyIncomplete) {
              AppLogger.log('✅ All processing and cross-posting complete signal received');

              // **BATCHED UPDATE: Update all progress values at once**
              if (mounted) {
                _unifiedProgress.value = 1.0;
                _currentPhase.value = 'completed';
                _phaseDescription.value =
                    'Video released and cross-posted successfully!';
              }

              await Future.delayed(const Duration(seconds: 1));
              return {
                'videoUrl': videoUrl,
                'thumbnailUrl': (videoData?['thumbnailUrl'] ?? '').toString(),
                'processingStatus': 'completed',
                'processingProgress': 100,
              };
            } else {
               AppLogger.log('📡 Vayu processing DONE, but still waiting for cross-posting platforms...');
            }
          } else if (processingStatus == 'failed') {
            AppLogger.log('❌ Video processing failed: $errorMsg');
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
                    children: [
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
                          // 1. Reset screen state BEFORE navigating, 
                          // so if user returns to this tab, it's fresh.
                          _resetScreenState();
                          
                          Navigator.of(context).pop(); // Close dialog

                          // 2. Switch to Vayu (Feed) tab - index 1
                          try {
                            ref.read(mainControllerProvider)
                                .changeIndex(1);
                          } catch (e) {
                            AppLogger.log(
                                '❌ UploadScreen: Error switching to feed: $e');
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
              final authController = ref.read(googleSignInProvider);
              Navigator.pop(context);
              final user = await authController.signIn();
              if (user != null && mounted) {
                await LogoutService.refreshAllState(ref);
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
        ref.read(mainControllerProvider)
            .setMediaPickerActive(true);
      }

      // Revert to stable FilePicker
      FilePickerResult? result = await _filePickerService.pickFiles(
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
        ref.read(mainControllerProvider)
            .setMediaPickerActive(false);
      }

      if (result != null) {
        // **BATCHED UPDATE: Use ValueNotifiers**
        if (!mounted) return;
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
            if (!mounted) {
              await controller.dispose();
              return;
            }
            final durationSeconds = controller.value.duration.inSeconds;
            _videoDuration.value = durationSeconds.toDouble();
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
            if (!mounted) return;
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
                
                if (!mounted) return;

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

        // **BATCHED UPDATE: Update media selection and reset phase to preparation**
        _currentPhase.value = 'preparation';
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

  void _showShortsGenerator() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const ShortVideoCreatorDialog(),
    );
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
    _crossPostStatusMap.dispose();
    _crossPostProgressMap.dispose();
    _quizzes.dispose();
    _videoDuration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final authController = ref.watch(googleSignInProvider);
        final isSignedIn = authController.isSignedIn;

        return Scaffold(
          appBar: AppBar(
            title: Text(AppText.get('upload_title')),
            centerTitle: true,
            leading: ValueListenableBuilder<File?>(
              valueListenable: _selectedVideo,
              builder: (context, video, _) {
                if (video == null) return const SizedBox.shrink();
                return IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _deselectVideo,
                  tooltip: 'Cancel selection',
                );
              },
            ),
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
          body: Stack(
            children: [
              // 1. Layer: Main Content
              ValueListenableBuilder<bool>(
                valueListenable: _isUploading,
                builder: (context, isUploading, _) {
                  return ValueListenableBuilder<File?>(
                    valueListenable: _selectedVideo,
                    builder: (context, selectedVideo, _) {
                      // State 1: Nothing selected yet → show choice cards
                      if (!isUploading && selectedVideo == null) {
                        return _buildInitialChoiceView(
                            context, isSignedIn, authController);
                      }
                      // State 2: Upload progress dashboard
                      return _buildUploadProgressDashboard(context);
                    },
                  );
                },
              ),

              // 2. Layer: Analyzing Overlay (prevents assertion failure from framework by keeping tree stable)
              ValueListenableBuilder<bool>(
                valueListenable: _isProcessing,
                builder: (context, isProcessing, _) {
                  if (!isProcessing) return const SizedBox.shrink();
                  return Positioned.fill(
                    child: Container(
                      color: AppColors.backgroundPrimary,
                      child: _buildAnalyzingVideoView(context),
                    ),
                  );
                },
              ),
            ],
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
              style: AppTypography.headlineSmall
                  .copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'Checking for duplicates and validating your video. Please wait.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInitialChoiceView(BuildContext context, bool isSignedIn,
      GoogleSignInController authController) {
    if (!isSignedIn) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline,
                  size: 64, color: AppColors.textTertiary),
              const SizedBox(height: 24),
              Text(
                AppText.get('upload_login_required_title',
                    fallback: 'Login Required'),
                style: AppTypography.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                AppText.get('upload_login_required_desc',
                    fallback:
                        'Please login to share your creativity with the world.'),
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium
                    .copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 32),
              AppButton(
                onPressed: () async {
                  final user = await authController.signIn();
                  if (user != null) {
                    await LogoutService.refreshAllState(ref);
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
              style: AppTypography.headlineLarge
                  .copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),

            // Visual Choice: Video
            _buildChoiceCard(
              context: context,
              icon: Icons.video_library,
              title: AppText.get('upload_video'),
              color: AppColors.primary,
              onTap: _pickVideo,
            ),

            const SizedBox(height: 24),

            // Visual Choice: Ad
            _buildChoiceCard(
              context: context,
              icon: Icons.campaign,
              title: AppText.get('upload_create_ad'),
              color: AppColors.success,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const CreateAdScreenRefactored()),
                );
              },
            ),

            const SizedBox(height: 24),

            // Visual Choice: Shorts Generator
            _buildChoiceCard(
              context: context,
              icon: Icons.auto_awesome,
              title: "Shorts Generator",
              color: Colors.amber,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ShortsGeneratorScreen()),
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
                style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    decoration: TextDecoration.underline),
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
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.1), width: 1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.headlineSmall
                        .copyWith(fontWeight: FontWeight.bold),
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        children: [
          // **NEW: Incentive Note at the TOP for better visibility**
          _buildIncentiveNote(),
          const SizedBox(height: 12),

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
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            AppColors.primary),
                      ),
                    );
                  },
                ),
                Container(
                  width: 156,
                  height: 156,
                  decoration: const BoxDecoration(
                    color: AppColors.backgroundSecondary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.movie_outlined,
                      size: 72, color: AppColors.primary),
                ),
                // Done indicator
                ValueListenableBuilder<String>(
                  valueListenable: _currentPhase,
                  builder: (context, phase, _) {
                    if (phase != 'completed') return const SizedBox.shrink();
                    return Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_circle,
                          size: 80, color: AppColors.success),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Current Status
          ValueListenableBuilder<String>(
            valueListenable: _currentPhase,
            builder: (context, phase, _) {
              return Text(
                _progressPhases[phase]?['name'] ?? 'Processing...',
                style: AppTypography.headlineSmall
                    .copyWith(fontWeight: FontWeight.bold),
              );
            },
          ),

          ValueListenableBuilder<String>(
            valueListenable: _phaseDescription,
            builder: (context, desc, _) {
              return Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  desc,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium
                      .copyWith(color: AppColors.textSecondary),
                ),
              );
            },
          ),

          const SizedBox(height: 24),

          // **PRIMARY TITLE FIELD**
          _buildPrimaryTitleField(),

          const SizedBox(height: 24),

          // MANDATORY CATEGORY SELECTION
          _buildMandatoryCategorySelector(),

          // Conditional spacing and progress info
          ValueListenableBuilder<Map<String, String>>(
            valueListenable: _crossPostStatusMap,
            builder: (context, statusMap, _) {
              if (statusMap.isEmpty && _selectedPlatforms.value.isEmpty) {
                return const SizedBox.shrink();
              }
              return Column(
                children: [
                  const SizedBox(height: 24),
                  _buildCrossPostProgress(),
                ],
              );
            },
          ),
          
          const SizedBox(height: 24),

          // **NAVIGATION TO ADVANCED SETTINGS**
          _buildAdvancedSettingsNavigation(),

          const SizedBox(height: 32),

          // Error Message Display
          ValueListenableBuilder<String?>(
            valueListenable: _errorMessage,
            builder: (context, error, _) {
              if (error == null) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.only(bottom: 24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(24),
                  border:
                      Border.all(color: AppColors.error.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppColors.error),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(error,
                            style: const TextStyle(color: AppColors.error))),
                  ],
                ),
              );
            },
          ),

              // Action Buttons
              ValueListenableBuilder<bool>(
                valueListenable: _isAuthError,
                builder: (context, isAuthError, _) {
                  return ValueListenableBuilder<String>(
                    valueListenable: _currentPhase,
                    builder: (context, phase, _) {
                      final isComplete =
                          phase == 'completed' || phase == 'finalizing';
                      final isError = _errorMessage.value != null;
                      final hasSelected = _selectedVideo.value != null;
                      final isUploading = _isUploading.value;

                      if (isAuthError) {
                        return AppButton(
                          onPressed: _handleReAuthentication,
                          label: 'Sign In & Resume',
                          variant: AppButtonVariant.primary,
                          isFullWidth: true,
                          icon: const Icon(Icons.login),
                        );
                      }

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
                            const SizedBox(width: 16),
                            Expanded(
                              child: AppButton(
                                onPressed: () {
                                  _isMinimizing.value = true;
                                  // Navigate to Profile/Account tab (index 3) so user can track upload status
                                  ref
                                      .read(mainControllerProvider)
                                      .changeIndex(3);
                                  // Re-notify listeners so the Consumer in ProfileVideosWidget
                                  // immediately rebuilds and shows the optimistic video already
                                  // injected by addVideoOptimistically().
                                  try {
                                    ref
                                        .read(profileStateManagerProvider)
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
                            _resetScreenState();
                            widget.onVideoUploaded?.call();
                          },
                          label: 'Done',
                          variant: AppButtonVariant.primary,
                          isFullWidth: true,
                        ),
                    ],
                  );
                },
              );
            },
          ),
            ],
          ),
        );
  }

  void _showYouTubeConnectBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.backgroundPrimary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const HugeIcon(
                icon: HugeIcons.strokeRoundedYoutube,
                color: Color(0xFFFF0000),
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                AppText.get('crosspost_youtube_connect_title'),
                style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                AppText.get('crosspost_youtube_connect_desc'),
                style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              AppButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const LinkedAccountsScreen()),
                  ).then((_) {
                    // Check connection status again when returning
                    if (!mounted) return;
                    final stateManager = ref.read(profileStateManagerProvider);
                    final isConnected = stateManager.userData?['socialAccounts']?['youtube']?['connected'] ?? false;
                    if (isConnected) {
                       final current = List<String>.from(_selectedPlatforms.value);
                       if (!current.contains('youtube')) {
                         current.add('youtube');
                         _selectedPlatforms.value = current;
                         if (mounted) {
                           ScaffoldMessenger.of(context).showSnackBar(
                             SnackBar(
                               content: Text(AppText.get('crosspost_youtube_success')),
                               backgroundColor: AppColors.success,
                             ),
                           );
                         }
                       }
                    }
                  });
                },
                label: AppText.get('crosspost_youtube_connect_button'),
                variant: AppButtonVariant.primary,
                isFullWidth: true,
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  AppText.get('crosspost_youtube_connect_later'),
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        );
      },
    );
  }


  Widget _buildCrossPostProgress() {
    return ValueListenableBuilder<Map<String, String>>(
      valueListenable: _crossPostStatusMap,
      builder: (context, statusMap, _) {
        if (statusMap.isEmpty && _selectedPlatforms.value.isEmpty) {
          return const SizedBox.shrink();
        }

        final selectedPlatforms = _selectedPlatforms.value;
        if (selectedPlatforms.isEmpty) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.backgroundSecondary,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderPrimary),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.share, size: 20, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Cross-Posting Status',
                    style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...selectedPlatforms.map((platform) {
                final status = statusMap[platform] ?? 'pending';
                final progress = _crossPostProgressMap.value[platform] ?? 0;
                
                Color statusColor = AppColors.textSecondary;
                IconData statusIcon = Icons.hourglass_empty;
                
                if (status == 'processing') {
                  statusColor = AppColors.primary;
                  statusIcon = Icons.sync;
                } else if (status == 'completed') {
                  statusColor = AppColors.success;
                  statusIcon = Icons.check_circle;
                } else if (status == 'failed') {
                  statusColor = AppColors.error;
                  statusIcon = Icons.error;
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              _getPlatformIcon(platform, statusColor),
                              const SizedBox(width: 8),
                              Text(
                                platform[0].toUpperCase() + platform.substring(1),
                                style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Text(
                                status == 'processing' ? '$progress%' : status.toUpperCase(),
                                style: AppTypography.labelSmall.copyWith(color: statusColor, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 4),
                              Icon(statusIcon, size: 14, color: statusColor),
                            ],
                          ),
                        ],
                      ),
                      if (status == 'processing')
                        Padding(
                          padding: const EdgeInsets.only(top: 6.0),
                          child: LinearProgressIndicator(
                            value: progress / 100.0,
                            backgroundColor: AppColors.borderPrimary,
                            valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                            minHeight: 4,
                          ),
                        ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _getPlatformIcon(String platform, Color color) {
    switch (platform) {
      case 'youtube':
        return HugeIcon(
            icon: HugeIcons.strokeRoundedYoutube, color: color, size: 18);
      default:
        return Icon(Icons.public, color: color, size: 18);
    }
  }

  Widget _buildMandatoryCategorySelector() {
    return Column(
      key: _categoryKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.category_outlined,
                color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            Text(
              'Select Video Category',
              style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 4),
            const Text('*', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 12),
        ValueListenableBuilder<String?>(
          valueListenable: _selectedCategory,
          builder: (context, currentValue, _) {
            final options = [
              ...kInterestOptions.where((c) => c != 'Custom Interest'),
              if (!kInterestOptions.contains(_defaultCategory)) _defaultCategory,
            ];

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: currentValue == null
                      ? AppColors.error.withValues(alpha: 0.5)
                      : AppColors.borderPrimary,
                  width: currentValue == null ? 1.5 : 1,
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: currentValue,
                  hint: Text(
                    'Choose a category (Mandatory)',
                    style: TextStyle(
                      color: AppColors.textSecondary.withValues(alpha: 0.6),
                      fontSize: 14,
                    ),
                  ),
                  isExpanded: true,
                  items: options
                      .map(
                        (c) => DropdownMenuItem<String>(
                          value: c,
                          child: Text(c, style: const TextStyle(fontSize: 14)),
                        ),
                      )
                      .toList(),
                  onChanged: (val) => _selectedCategory.value = val,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildIncentiveNote() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderPrimary.withValues(alpha: 0.5)),
      ),
      child: const Row(
        children: [
          Icon(Icons.stars_rounded, color: AppColors.textSecondary, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Making educational content can significantly increase your earning potential and platform reach.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryTitleField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.title_rounded, color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            Text(
              'Video Title',
              style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 4),
            const Text('*', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<bool>(
          valueListenable: _isUploading,
          builder: (context, isUploading, _) {
            return TextField(
              controller: _titleController,
              enabled: !isUploading,
              maxLines: 2,
              minLines: 1,
              onTapOutside: (event) => FocusScope.of(context).unfocus(),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: 'What is this video about?',
                hintStyle: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.5)),
                filled: true,
                fillColor: AppColors.backgroundSecondary.withValues(alpha: 0.3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.borderPrimary),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.borderPrimary),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.borderPrimary.withValues(alpha: 0.5)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildAdvancedSettingsNavigation() {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UploadAdvancedSettingsScreen(
              linkController: _linkController,
              tagInputController: _tagInputController,
              tags: _tags,
              onAddTag: _handleAddTag,
              onRemoveTag: _handleRemoveTag,
              onMakeEpisode: _handleMakeEpisode,
              quizzes: _quizzes,
              selectedPlatforms: _selectedPlatforms,
              videoDuration: _videoDuration.value,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.tune_rounded, color: AppColors.primary, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'More Options',
                    style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tags, Links, Quizzes, and Cross-posting',
                    style: AppTypography.labelSmall.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}


