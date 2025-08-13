import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:async';
import 'package:snehayog/services/video_service.dart';
import 'package:snehayog/services/google_auth_service.dart';
import 'package:video_compress/video_compress.dart';
import 'package:snehayog/view/screens/create_ad_screen.dart';
import 'package:snehayog/view/screens/ad_management_screen.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  File? _selectedVideo;
  bool _isUploading = false;
  bool _isCompressing = false;
  String? _errorMessage;
  bool _showUploadForm = false; // New state variable to control form visibility
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _linkController = TextEditingController();
  final VideoService _videoService = VideoService();

  @override
  void initState() {
    super.initState();
  }

  Future<void> _pickVideo() async {
    final googleAuthService = GoogleAuthService();
    final userData = await googleAuthService.getUserData();
    if (userData == null) {
      _showLoginPrompt();
      return;
    }

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
      );

      if (result != null) {
        setState(() {
          _isCompressing = true;
        });

        final compressedVideo = await VideoCompress.compressVideo(
          result.files.single.path!,
          quality: VideoQuality.MediumQuality,
          deleteOrigin: false,
        );

        setState(() {
          _selectedVideo = compressedVideo?.file;
          _errorMessage = null;
          _isCompressing = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error picking video: $e';
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
              final googleAuthService = GoogleAuthService();
              await googleAuthService.signInWithGoogle();
            },
            child: const Text('Sign In'),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadVideo() async {
    final googleAuthService = GoogleAuthService();
    final userData = await googleAuthService.getUserData();
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
      print('Starting video upload...');
      print('Video path: ${_selectedVideo!.path}');
      print('Title: ${_titleController.text}');
      print('Description: ${_descriptionController.text}');

      // Check if file exists and is readable
      if (!await _selectedVideo!.exists()) {
        throw Exception('Selected video file does not exist');
      }

      // Check file size
      final fileSize = await _selectedVideo!.length();
      print('File size: $fileSize bytes');
      if (fileSize > 100 * 1024 * 1024) {
        // 100MB limit
        throw Exception('Video file is too large. Maximum size is 100MB');
      }

      final uploadedVideo = await _videoService
          .uploadVideo(
        _selectedVideo!,
        _titleController.text,
        _descriptionController.text,
        _linkController.text.isNotEmpty ? _linkController.text : null,
      )
          .timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          throw TimeoutException(
              'Upload timed out. Please check your internet connection and try again.');
        },
      );

      print('Video upload completed successfully');
      print('Uploaded video details: $uploadedVideo');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Video uploaded successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {
          _selectedVideo = null;
          _titleController.clear();
          _descriptionController.clear();
          _linkController.clear();
        });
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
      setState(() {
        _errorMessage = 'Error uploading video: ${e.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: GoogleAuthService().getUserData(),
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
                              final googleAuthService = GoogleAuthService();
                              await googleAuthService.signInWithGoogle();
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
                              child: _isCompressing
                                  ? const Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          CircularProgressIndicator(),
                                          SizedBox(height: 16),
                                          Text(
                                            'Compressing video...',
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
                            TextField(
                              controller: _descriptionController,
                              decoration: const InputDecoration(
                                labelText: 'Description',
                                hintText: 'Enter a description for your video',
                                border: OutlineInputBorder(),
                              ),
                              maxLines: 3,
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
