import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:file_picker/file_picker.dart';
import 'package:snehayog/model/video_model.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final _formKey = GlobalKey<FormState>();
  File? _videoFile;
  String? _videoName;
  String? _description;
  String? _userLink;
  bool _isUploading = false;
  VideoPlayerController? _previewController;
  String? _videoType;

  Future<void> _pickVideo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = File(result.files.first.path!);
        final controller = VideoPlayerController.file(file);
        await controller.initialize();

        // Get video duration
        final duration = controller.value.duration;

        // Get video aspect ratio
        final aspectRatio = controller.value.aspectRatio;

        // Determine video type based on duration and aspect ratio
        String videoType;
        if (duration.inMinutes < 2 && aspectRatio < 1) {
          videoType = 'yog'; // Short vertical video
        } else {
          videoType = 'sneha'; // Long horizontal video
        }

        setState(() {
          _videoFile = file;
          _previewController = controller;
          _videoName = result.files.first.name;
          _videoType = videoType;
          // Generate a unique link for the video
          _userLink =
              'https://snehayog.com/videos/${DateTime.now().millisecondsSinceEpoch}';
        });

        // Show video type to user
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Video type detected: ${videoType.toUpperCase()}'),
            backgroundColor: const Color(0xFF268BD2),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error picking video: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _uploadVideo() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save(); // Save form values first

      if (_videoFile == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a video first'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      setState(() => _isUploading = true);

      try {
        // TODO: Implement actual video upload to server
        await Future.delayed(const Duration(seconds: 2)); // Simulate upload

        // Create a new VideoModel instance with null checks
        final videoModel = VideoModel(
          videoName: _videoName ?? 'Untitled Video',
          description: _description ?? 'No description provided',
          videoUrl: _userLink ??
              'https://snehayog.com/videos/${DateTime.now().millisecondsSinceEpoch}',
          views: 0,
          likes: 0,
          uploader: "Current User", // TODO: Replace with actual user
          uploadedAt: DateTime.now(),
          videoType: _videoType ?? 'sneha', // Default to 'sneha' if not set
          duration:
              _previewController?.value.duration ?? const Duration(seconds: 0),
        );

        // TODO: Save videoModel to database/backend

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Video uploaded successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        // Clear form
        _formKey.currentState!.reset();
        setState(() {
          _videoFile = null;
          _videoName = null;
          _description = null;
          _userLink = null;
          _videoType = null;
          _previewController?.dispose();
          _previewController = null;
        });
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error uploading video: $e'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  void dispose() {
    _previewController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF002B36),
      appBar: AppBar(
        backgroundColor: const Color(0xFF002B36),
        title: const Text('Upload Video'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Video Upload Section
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF073642),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      if (_previewController != null)
                        AspectRatio(
                          aspectRatio: _previewController!.value.aspectRatio,
                          child: VideoPlayer(_previewController!),
                        )
                      else
                        const Icon(
                          Icons.cloud_upload,
                          size: 60,
                          color: Color(0xFF268BD2),
                        ),
                      const SizedBox(height: 20),
                      const Text(
                        'Upload Your Video',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Supported formats: MP4, MOV, AVI',
                        style: TextStyle(
                          color: Color(0xFF586E75),
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: _pickVideo,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF268BD2),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 30,
                            vertical: 15,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: const Text('Choose Video'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Video Details Section
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF073642),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'Video Name',
                          labelStyle: TextStyle(color: Colors.white),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFF586E75)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFF268BD2)),
                          ),
                        ),
                        style: const TextStyle(color: Colors.white),
                        onSaved: (value) => _videoName = value,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a video name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          labelStyle: TextStyle(color: Colors.white),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFF586E75)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFF268BD2)),
                          ),
                        ),
                        style: const TextStyle(color: Colors.white),
                        maxLines: 3,
                        onSaved: (value) => _description = value,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a description';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'Your Link (Website/Social Media)',
                          hintText:
                              'Enter your website URL or social media handle (e.g., @username)',
                          labelStyle: TextStyle(color: Colors.white),
                          hintStyle: TextStyle(color: Color(0xFF586E75)),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFF586E75)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFF268BD2)),
                          ),
                        ),
                        style: const TextStyle(color: Colors.white),
                        onSaved: (value) {
                          if (value != null && value.isNotEmpty) {
                            _userLink = value;
                          }
                        },
                        validator: (value) {
                          if (value != null && value.isNotEmpty) {
                            if (value.startsWith('@')) {
                              return null;
                            }
                            if (!value.startsWith('http://') &&
                                !value.startsWith('https://')) {
                              return 'Please enter a valid URL or social media handle (starting with @)';
                            }
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Upload Button
                ElevatedButton(
                  onPressed: _isUploading ? null : _uploadVideo,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF268BD2),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: _isUploading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Upload Video'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
