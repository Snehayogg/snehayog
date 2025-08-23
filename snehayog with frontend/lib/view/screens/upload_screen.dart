import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:async';
import 'package:snehayog/services/video_service.dart';
import 'package:snehayog/services/authservices.dart';
// Removed video_compress import - not needed for HLS processing
import 'package:snehayog/view/screens/create_ad_screen.dart';
import 'package:snehayog/view/screens/ad_management_screen.dart';

class UploadScreen extends StatefulWidget {
  final VoidCallback? onVideoUploaded; // Add callback for video upload success

  const UploadScreen({super.key, this.onVideoUploaded});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  File? _selectedVideo;
  bool _isUploading = false;
  bool _isProcessing = false; // Renamed from _isCompressing
  String? _errorMessage;
  bool _showUploadForm = false; // New state variable to control form visibility

  // Upload progress tracking
  double _uploadProgress = 0.0;
  int _uploadStartTime = 0;
  int _elapsedSeconds = 0;
  String _uploadStatus = '';

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController =
      TextEditingController(); // Add description controller
  final TextEditingController _linkController = TextEditingController();
  final VideoService _videoService = VideoService();
  final AuthService _authService = AuthService();

  // Timer for upload progress
  Timer? _uploadTimer;

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

        // For HLS processing, we don't need to compress the video
        // The backend will handle the conversion to HLS format
        final videoFile = File(result.files.single.path!);

        // Check file size
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
            '📏 File size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');
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

    try {
      print('🚀 Starting HLS video upload...');
      print('📁 Video path: ${_selectedVideo!.path}');
      print('📝 Title: ${_titleController.text}');
      print(
          '🔗 Link: ${_linkController.text.isNotEmpty ? _linkController.text : 'None'}');
      print(
          '🎬 Note: Video will be converted to HLS (.m3u8) format for optimal streaming');

      // Start upload progress tracking
      _startUploadProgress();

      // Check if file exists and is readable
      if (!await _selectedVideo!.exists()) {
        throw Exception('Selected video file does not exist');
      }

      // Check file size
      final fileSize = await _selectedVideo!.length();
      print(
          'File size: $fileSize bytes (${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB)');
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
            'Invalid video format. Supported formats: ${allowedExtensions.join(', ').toUpperCase()}');
      }

      final uploadedVideo = await _videoService
          .uploadVideo(
        _selectedVideo!,
        _titleController.text,
        _descriptionController.text.isNotEmpty
            ? _descriptionController.text
            : null, // Add description
        _linkController.text.isNotEmpty ? _linkController.text : null,
      )
          .timeout(
        const Duration(
            minutes: 10), // Increased timeout for large video uploads
        onTimeout: () {
          throw TimeoutException(
              'Upload timed out. Please check your internet connection and try again.');
        },
      );

      print('✅ HLS video upload completed successfully!');
      print('🎬 Uploaded video details: $uploadedVideo');
      print('🔗 HLS Playlist URL: ${uploadedVideo['videoUrl']}');
      print('🖼️ Thumbnail URL: ${uploadedVideo['thumbnail']}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Video uploaded successfully! Converting to HLS format...',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );

        // Call the callback to refresh video list
        widget.onVideoUploaded?.call();

        setState(() {
          _selectedVideo = null;
          _titleController.clear();
          _descriptionController.clear(); // Clear description controller
          _linkController.clear();
        });

        // Stop progress tracking
        _stopUploadProgress();
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
      } else if (e
          .toString()
          .contains('Failed to upload video to cloud service')) {
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

    // Estimate upload time based on file size (assuming 2-5 MB/s upload speed)
    final estimatedUploadSeconds = fileSizeMB / 3.0; // 3 MB/s average

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
    _descriptionController.dispose(); // Dispose description controller
    _linkController.dispose();
    _stopUploadProgress();
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
                          const Icon(Icons.warning_amber_rounded,
                              color: Colors.orange),
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

                  // Main Options Section
                  const Text(
                    'Choose what you want to create',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
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
                                            const CreateAdScreen(),
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
                                const Icon(Icons.video_library,
                                    color: Colors.blue),
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
                            // HLS Processing Info
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: Colors.blue.withOpacity(0.3)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.info_outline,
                                          color: Colors.blue[600]),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'HLS Video Processing',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue[800],
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Your video will be automatically converted to HLS (.m3u8) format for optimal streaming performance across all devices.',
                                    style: TextStyle(
                                      color: Colors.blue[700],
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                          color:
                                              Colors.orange.withOpacity(0.3)),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.speed,
                                            size: 16,
                                            color: Colors.orange[600]),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '💡 Tip: Use WiFi for faster uploads. Large videos may take several minutes.',
                                            style: TextStyle(
                                              color: Colors.orange[700],
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _titleController,
                              decoration: const InputDecoration(
                                labelText: 'Video Title',
                                hintText: 'Enter a title for your video',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Description field removed - not needed for the app
                            const SizedBox(height: 16),
                            TextField(
                              controller: _descriptionController,
                              decoration: const InputDecoration(
                                labelText: 'Description (optional)',
                                hintText: 'Add a description for your video',
                                border: OutlineInputBorder(),
                              ),
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
                            const SizedBox(height: 24),

                            // Upload Progress Indicator
                            if (_isUploading) ...[
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: Colors.blue.withOpacity(0.3)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.upload_file,
                                            color: Colors.blue[600]),
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
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(Icons.info_outline,
                                                size: 16,
                                                color: Colors.blue[600]),
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
                                      backgroundColor:
                                          Colors.blue.withOpacity(0.2),
                                      valueColor: const AlwaysStoppedAnimation<Color>(
                                          Colors.blue),
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
                                          vertical: 16),
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
                                                      Colors.white),
                                            ),
                                          )
                                        : const Icon(Icons.cloud_upload),
                                    label: Text(_isUploading
                                        ? 'Uploading...'
                                        : 'Upload Video'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 16),
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
        );
      },
    );
  }
}
