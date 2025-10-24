import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:async';
import 'package:vayu/services/video_service.dart';
import 'package:vayu/services/authservices.dart';
import 'package:vayu/view/screens/create_ad_screen_refactored.dart';
import 'package:vayu/view/screens/ad_management_screen.dart';
import 'package:vayu/core/constants/interests.dart';

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

  // **UNIFIED PROGRESS TRACKING** - Single progress bar for entire flow
  double _unifiedProgress = 0.0;
  String _currentPhase = '';
  String _phaseDescription = '';
  int _uploadStartTime = 0;
  int _elapsedSeconds = 0;

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _linkController = TextEditingController();
  final VideoService _videoService = VideoService();
  final AuthService _authService = AuthService();

  // Timer for unified progress tracking
  Timer? _progressTimer;

  // **UNIFIED PROGRESS PHASES** - Complete video processing flow
  static const Map<String, Map<String, dynamic>> _progressPhases = {
    'preparation': {
      'name': 'Preparing Video',
      'description': 'Validating file and preparing for upload...',
      'progress': 0.1,
      'icon': Icons.video_file,
    },
    'upload': {
      'name': 'Uploading Video',
      'description': 'Transferring video to server...',
      'progress': 0.4,
      'icon': Icons.cloud_upload,
    },
    'validation': {
      'name': 'Validating Video',
      'description': 'Checking video format and quality...',
      'progress': 0.5,
      'icon': Icons.verified,
    },
    'processing': {
      'name': 'Processing Video',
      'description': 'Converting to optimized format...',
      'progress': 0.8,
      'icon': Icons.settings,
    },
    'completed': {
      'name': 'Upload Complete!',
      'description': 'Video processing completed successfully!',
      'progress': 1.0,
      'icon': Icons.check_circle,
    },
    'finalizing': {
      'name': 'Finalizing',
      'description': 'Generating thumbnails and completing...',
      'progress': 0.95,
      'icon': Icons.check_circle,
    },
  };

  // NEW: Category and Tags to align with ad targeting interests
  String? _selectedCategory;
  final List<String> _tags = [];
  final TextEditingController _tagInputController = TextEditingController();

  // **UNIFIED PROGRESS TRACKING METHODS**

  /// Start unified progress tracking for complete video processing flow
  void _startUnifiedProgress() {
    _uploadStartTime = DateTime.now().millisecondsSinceEpoch;
    _unifiedProgress = 0.0;
    _currentPhase = 'preparation';
    _phaseDescription = _progressPhases['preparation']!['description'];

    _progressTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _elapsedSeconds =
              (DateTime.now().millisecondsSinceEpoch - _uploadStartTime) ~/
                  1000;
        });
      }
    });
  }

  /// Update progress phase with smooth transitions
  void _updateProgressPhase(String phase) {
    if (mounted && _progressPhases.containsKey(phase)) {
      setState(() {
        _currentPhase = phase;
        _phaseDescription = _progressPhases[phase]!['description'];
        _unifiedProgress = _progressPhases[phase]!['progress'];
      });
    }
  }

  /// Stop unified progress tracking
  void _stopUnifiedProgress() {
    _progressTimer?.cancel();
    _progressTimer = null;
    if (mounted) {
      setState(() {
        _unifiedProgress = 1.0;
        _currentPhase = 'completed';
        _phaseDescription = 'Video is ready!';
      });
    }
  }

  /// Get current phase icon
  IconData _getCurrentPhaseIcon() {
    return _progressPhases[_currentPhase]?['icon'] ?? Icons.upload;
  }

  /// Get current phase color
  Color _getCurrentPhaseColor() {
    switch (_currentPhase) {
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
                  color: _getCurrentPhaseColor().withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getCurrentPhaseIcon(),
                  color: _getCurrentPhaseColor(),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _progressPhases[_currentPhase]?['name'] ?? 'Processing',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _phaseDescription,
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Progress',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[700],
                    ),
                  ),
                  Text(
                    '${(_unifiedProgress * 100).toInt()}%',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _getCurrentPhaseColor(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _unifiedProgress,
                  backgroundColor: Colors.grey[200],
                  valueColor:
                      AlwaysStoppedAnimation<Color>(_getCurrentPhaseColor()),
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
                    'Time: ${_formatTime(_elapsedSeconds)}',
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
                      const Expanded(
                        child: Text(
                          'What to Upload? \nVayu Terms & Conditions (Copyright Policy)',
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
                        'If you upload content belonging to someone else without permission, you (the uploader) will be fully responsible for any legal consequences. Vayu acts only as a platform and does not own or endorse user-uploaded content.',
                  ),
                  _buildNoticePoint(
                    title: '3. Reporting Copyright Violation',
                    body:
                        'Copyright owners may submit a takedown request by emailing: copyright@vayu.app with proof of ownership. Upon receiving a valid request, Vayu will remove the infringing content within 48 hours.',
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
                        'Vayu, as an intermediary platform, is not liable for user-uploaded content under the IT Act 2000 (India) and DMCA (international). All responsibility for copyright compliance lies with the content uploader.',
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

  /// **UPLOAD VIDEO METHOD** - Handles video upload with progress tracking
  Future<void> _uploadVideo() async {
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

    // Validate category selection before uploading
    if (_selectedCategory == null || _selectedCategory!.isEmpty) {
      setState(() {
        _isUploading = false;
        _errorMessage = 'Please select a video category';
      });
      return;
    }

    try {
      print('🚀 Starting HLS video upload...');
      print('📁 Video path: ${_selectedVideo!.path}');
      print('📝 Title: ${_titleController.text}');
      print(
        '🔗 Link: ${_linkController.text.isNotEmpty ? _linkController.text : 'None'}',
      );
      print(
        '🎬 Note: Video will be converted to HLS (.m3u8) format for optimal streaming',
      );

      // Start unified progress tracking
      _startUnifiedProgress();

      // Check if file exists and is readable
      if (!await _selectedVideo!.exists()) {
        throw Exception('Selected video file does not exist');
      }

      // Update to preparation phase
      _updateProgressPhase('preparation');

      // Check file size
      final fileSize = await _selectedVideo!.length();
      print(
        'File size: $fileSize bytes (${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB)',
      );
      if (fileSize > 100 * 1024 * 1024) {
        // 100MB limit
        throw Exception('Video file is too large. Maximum size is 100MB');
      }

      // Check file extension
      final fileName = _selectedVideo!.path.split('/').last.toLowerCase();
      final allowedExtensions = ['mp4', 'avi', 'mov', 'wmv', 'flv', 'webm'];
      final fileExtension = fileName.split('.').last;

      if (!allowedExtensions.contains(fileExtension)) {
        throw Exception(
          'Invalid video format. Supported formats: ${allowedExtensions.join(', ').toUpperCase()}',
        );
      }

      // Update to upload phase
      _updateProgressPhase('upload');

      final uploadedVideo = await runZoned(
        () => _videoService.uploadVideo(
          _selectedVideo!,
          _titleController.text,
          '', // description
          _linkController.text.isNotEmpty ? _linkController.text : '', // link
        ),
        zoneValues: {
          'upload_metadata': {
            'category': _selectedCategory,
            'tags': _tags,
          }
        },
      ).timeout(
        const Duration(
          minutes: 10,
        ), // Increased timeout for large video uploads
        onTimeout: () {
          throw TimeoutException(
            'Upload timed out. Please check your internet connection and try again.',
          );
        },
      );

      print('✅ Video upload started successfully!');
      print('🎬 Uploaded video details: $uploadedVideo');

      // **FIX: Handle correct response structure from VideoService**
      print('🔄 Processing status: ${uploadedVideo['processingStatus']}');
      print('🆔 Video ID: ${uploadedVideo['id']}');

      // Update to validation phase
      _updateProgressPhase('validation');

      // **FIXED: Wait for processing to complete**
      if (mounted) {
        setState(() {});

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

          print('✅ Video processing completed successfully!');
          print('🔗 HLS Playlist URL: ${completedVideo['videoUrl']}');
          print('🖼️ Thumbnail URL: ${completedVideo['thumbnailUrl']}');

          // Call the callback to refresh video list first
          print('🔄 UploadScreen: Calling onVideoUploaded callback');
          if (widget.onVideoUploaded != null) {
            widget.onVideoUploaded!();
            print(
                '✅ UploadScreen: onVideoUploaded callback called successfully');
          } else {
            print('❌ UploadScreen: onVideoUploaded callback is null');
          }

          // Clear form
          setState(() {
            _selectedVideo = null;
            _titleController.clear();
            _linkController.clear();
            _selectedCategory = null;
            _tags.clear();
          });

          // Stop unified progress tracking
          _stopUnifiedProgress();

          // Show beautiful success dialog
          await _showSuccessDialog();

          // **NEW: Trigger video feed refresh after successful upload**
          if (widget.onVideoUploaded != null) {
            print('🔄 Triggering video feed refresh after upload completion');
            widget.onVideoUploaded!();
          }
        } else {
          throw Exception('Video processing failed or timed out');
        }
      }
    } on TimeoutException catch (e) {
      print('Upload timeout error: $e');
      setState(() {
        _errorMessage =
            'Upload timed out. Please check your internet connection and try again.';
      });
    } on FileSystemException catch (e) {
      print('File system error: $e');
      setState(() {
        _errorMessage =
            'Error accessing video file. Please try selecting the video again.';
      });
    } catch (e, stackTrace) {
      print('Error uploading video: $e');
      print('Stack trace: $stackTrace');

      // Handle specific error types
      String userFriendlyError;
      if (e.toString().contains('User not authenticated') ||
          e.toString().contains('Authentication token not found')) {
        userFriendlyError =
            'Please sign in again to upload videos. Your session may have expired.';
      } else if (e.toString().contains('Server is not responding')) {
        userFriendlyError =
            'Server is not responding. Please check your connection and try again.';
      } else if (e.toString().contains(
            'Failed to upload video to cloud service',
          )) {
        userFriendlyError =
            'Video upload service is temporarily unavailable. Please try again later.';
      } else if (e.toString().contains('File too large')) {
        userFriendlyError = 'Video file is too large. Maximum size is 100MB.';
      } else if (e.toString().contains('Invalid file type')) {
        userFriendlyError =
            'Invalid video format. Please upload a supported video file.';
      } else {
        userFriendlyError = 'Error uploading video: ${e.toString()}';
      }

      setState(() {
        _errorMessage = userFriendlyError;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });

        // Stop unified progress tracking
        _stopUnifiedProgress();
      }
    }
  }

  /// **NEW: Wait for video processing to complete**
  Future<Map<String, dynamic>?> _waitForProcessingCompletion(
      String videoId) async {
    const maxWaitTime = Duration(minutes: 10); // Maximum wait time
    const checkInterval = Duration(seconds: 3); // Poll faster to avoid UI stall
    final startTime = DateTime.now();

    print('🔄 Waiting for video processing to complete...');
    print('📹 Video ID: $videoId');

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

          print(
              '🔄 Processing status: $processingStatus ($processingProgress%)');
          print('🔗 Current videoUrl: $videoUrl');

          // Update UI with progress (map 0-100% server progress to 80-95% UI)
          if (mounted) {
            setState(() {
              final clamped = processingProgress.clamp(0, 100);
              _unifiedProgress = 0.8 + (clamped / 100.0 * 0.15);
            });
          }

          final hasAbsoluteUrl =
              videoUrl.startsWith('http://') || videoUrl.startsWith('https://');

          if (processingStatus == 'completed' || hasAbsoluteUrl) {
            print('✅ Processing complete signal received');

            if (mounted) {
              setState(() {
                _unifiedProgress = 1.0;
                _currentPhase = 'completed';
                _phaseDescription = 'Video processing completed successfully!';
              });
            }

            await Future.delayed(const Duration(seconds: 1));

            return {
              'videoUrl': videoUrl,
              'thumbnailUrl': (videoData?['thumbnailUrl'] ?? '').toString(),
              'processingStatus': 'completed',
              'processingProgress': 100,
            };
          } else if (processingStatus == 'failed') {
            print(
                '❌ Video processing failed: ${videoData?['processingError']}');
            return null;
          }
        } else {
          print(
              '❌ Failed to get processing status: ${response?['error'] ?? 'Unknown error'}');
        }

        // Wait before checking again
        await Future.delayed(checkInterval);
      } catch (e) {
        print('⚠️ Error checking processing status: $e');
        await Future.delayed(checkInterval);
      }
    }

    print('⏰ Processing timeout - maximum wait time exceeded');
    return null;
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

  Future<void> _pickVideo() async {
    final userData = await _authService.getUserData();
    if (userData == null) {
      _showLoginPrompt();
      return;
    }

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowMultiple: false,
        allowedExtensions: ['mp4', 'avi', 'mov', 'wmv', 'flv', 'webm'],
      );

      if (result != null) {
        setState(() {
          _isProcessing = true;
          _errorMessage = null;
        });

        final videoFile = File(result.files.single.path!);

        final fileSize = await videoFile.length();
        const maxSize = 100 * 1024 * 1024;

        if (fileSize > maxSize) {
          setState(() {
            _errorMessage = 'Video file is too large. Maximum size is 100MB';
            _isProcessing = false;
          });
          return;
        }

        setState(() {
          _selectedVideo = videoFile;
          _isProcessing = false;
        });

        print('✅ Video selected: ${videoFile.path}');
        print(
          '📏 File size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB',
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error picking video: $e';
        _isProcessing = false;
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _linkController.dispose();
    _stopUnifiedProgress();
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
                                      : const Center(
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.video_library,
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
                                        ),
                            ),
                            const SizedBox(height: 24),
                            TextField(
                              controller: _titleController,
                              decoration: const InputDecoration(
                                labelText: 'Video Title',
                                hintText: 'Enter a title for your video',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 16),
                            // NEW: Category selector
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
                            // Description removed per request
                            // NEW: Tags input
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
                            TextField(
                              controller: _linkController,
                              decoration: const InputDecoration(
                                labelText: 'Link (optional)',
                                hintText: 'Add a website, social media, etc.',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.url,
                            ),
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

                            // **UNIFIED PROGRESS INDICATOR** - Shows complete upload + processing flow
                            if (_isUploading) ...[
                              _buildUnifiedProgressWidget(),
                              const SizedBox(height: 16),
                            ],

                            if (_errorMessage != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16.0),
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontSize: 14,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _isUploading ? null : _pickVideo,
                                    icon: const Icon(Icons.video_library),
                                    label: const Text('Select Video'),
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
                                const SizedBox(width: 16),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed:
                                        _isUploading ? null : _uploadVideo,
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
                                        : const Icon(Icons.cloud_upload),
                                    label: Text(
                                      _isUploading
                                          ? 'Uploading...'
                                          : 'Upload Video',
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue,
                                      foregroundColor: Colors.white,
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
