import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:async';
import 'package:snehayog/services/video_service.dart';
import 'package:snehayog/services/authservices.dart';
import 'package:snehayog/view/screens/create_ad_screen_refactored.dart';
import 'package:snehayog/view/screens/ad_management_screen.dart';
import 'package:snehayog/core/constants/interests.dart';

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
  final VideoService _videoService = VideoService();
  final AuthService _authService = AuthService();

  // Timer for upload progress
  Timer? _uploadTimer;

  // NEW: Category and Tags to align with ad targeting interests
  String? _selectedCategory;
  final List<String> _tags = [];
  final TextEditingController _tagInputController = TextEditingController();

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

      // Start upload progress tracking
      _startUploadProgress();

      // Check if file exists and is readable
      if (!await _selectedVideo!.exists()) {
        throw Exception('Selected video file does not exist');
      }

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

      final uploadedVideo = await runZoned(
        () => _videoService.uploadVideo(
          _selectedVideo!,
          _titleController.text,
          null,
          _linkController.text.isNotEmpty ? _linkController.text : null,
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
      print(
          '🔄 Processing status: ${uploadedVideo['video']['processingStatus']}');

      // **FIXED: Wait for processing to complete**
      if (mounted) {
        setState(() {
          _uploadStatus = 'Processing video... Please wait...';
        });

        // Wait for processing to complete
        final completedVideo =
            await _waitForProcessingCompletion(uploadedVideo['video']['id']);

        if (completedVideo != null) {
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

          // Stop progress tracking
          _stopUploadProgress();

          // Show beautiful success dialog
          await _showSuccessDialog();
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

        // Stop progress tracking
        _stopUploadProgress();
      }
    }
  }

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

    final fileSizeMB = _selectedVideo!.lengthSync() / (1024 * 1024);

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
        } else if (_uploadProgress < 0.98) {
          // Finalizing phase (95-98%)
          _uploadProgress += 0.01;
          _uploadStatus = 'Finalizing... (Almost done!)';
        } else {
          // Complete (98-100%)
          _uploadProgress = 1.0;
          _uploadStatus = 'Upload complete!';
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

  /// **NEW: Wait for video processing to complete**
  Future<Map<String, dynamic>?> _waitForProcessingCompletion(
      String videoId) async {
    const maxWaitTime = Duration(minutes: 10); // Maximum wait time
    const checkInterval = Duration(seconds: 10); // Check every 10 seconds
    final startTime = DateTime.now();

    print('🔄 Waiting for video processing to complete...');
    print('📹 Video ID: $videoId');

    while (DateTime.now().difference(startTime) < maxWaitTime) {
      try {
        // Check processing status
        final response = await _videoService.getVideoById(videoId);

        if (response != null) {
          final processingStatus = response['processingStatus'];
          final processingProgress = response['processingProgress'] ?? 0;

          print(
              '🔄 Processing status: $processingStatus (${processingProgress}%)');

          // Update UI with progress
          if (mounted) {
            setState(() {
              _uploadStatus = 'Processing video... $processingProgress%';
              _uploadProgress =
                  0.85 + (processingProgress / 100 * 0.15); // 85-100%
            });
          }

          if (processingStatus == 'completed') {
            print('✅ Video processing completed successfully!');
            return response;
          } else if (processingStatus == 'failed') {
            print('❌ Video processing failed');
            return null;
          }
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
