import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:vayug/core/interfaces/i_video_upload_service.dart';
import 'package:vayug/core/interfaces/i_video_service.dart';

enum UploadStatus { idle, preparing, uploading, validation, processing, finalizing, success, error }

class UploadStateManager extends ChangeNotifier {
  final IVideoUploadService _uploadService;
  final IVideoService _videoService; // For status polling

  UploadStateManager({
    required IVideoUploadService uploadService,
    required IVideoService videoService,
  }) : _uploadService = uploadService, _videoService = videoService;

  // --- Core State ---
  File? _selectedVideo;
  File? get selectedVideo => _selectedVideo;

  File? _selectedThumbnail;
  File? get selectedThumbnail => _selectedThumbnail;

  UploadStatus _status = UploadStatus.idle;
  UploadStatus get status => _status;

  double _progress = 0.0;
  double get progress => _progress;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  String _currentPhase = 'preparation';
  String get currentPhase => _currentPhase;

  // --- Metadata State ---
  String? _selectedCategory;
  String? get selectedCategory => _selectedCategory;
  String? get category => _selectedCategory;

  List<String> _tags = [];
  List<String> get tags => _tags;

  Map<String, String> _crossPostStatus = {};
  Map<String, String> get crossPostStatus => _crossPostStatus;

  // --- Setters ---
  void setVideo(File video) {
    _selectedVideo = video;
    notifyListeners();
  }

  void setThumbnail(File? thumbnail) {
    _selectedThumbnail = thumbnail;
    notifyListeners();
  }

  void setCategory(String? category) {
    _selectedCategory = category;
    notifyListeners();
  }

  void setTags(List<String> tags) {
    _tags = tags;
    notifyListeners();
  }

  // --- Actions ---

  Future<void> startUpload({
    required String title,
    required String description,
    String? link,
    File? thumbnailFile,
    List<String>? tags,
    List<String>? platforms,
  }) async {
    if (_selectedVideo == null) {
      _setError('Please select a video first');
      return;
    }

    _status = UploadStatus.preparing;
    _currentPhase = 'preparation';
    _errorMessage = null;
    _progress = 0.0;
    notifyListeners();

    // 1. Validate
    final isValid = await _uploadService.validateVideo(_selectedVideo!);
    if (!isValid) {
      _setError('Invalid video file or size too large (Max 700MB)');
      return;
    }

    // 2. Setup Progress Listener
    final progressSubscription = _uploadService.uploadProgress.listen((p) {
      if (_status == UploadStatus.uploading) {
        _progress = 0.1 + (p * 0.4); // Upload is 10% to 50% of total
        notifyListeners();
      }
    });

    try {
      // 3. Upload
      _status = UploadStatus.uploading;
      _currentPhase = 'upload';
      notifyListeners();

      final videoId = await _uploadService.uploadVideo(
        videoFile: _selectedVideo!,
        thumbnailFile: thumbnailFile ?? _selectedThumbnail,
        title: title,
        description: description,
        metadata: {
          'link': link,
          'tags': tags ?? _tags,
          'crossPostPlatforms': platforms,
          'category': _selectedCategory,
        },
      );

      if (videoId != null) {
        // 4. Wait for Processing
        _status = UploadStatus.processing;
        _currentPhase = 'processing';
        _progress = 0.5;
        notifyListeners();

        final isProcessed = await _waitForProcessing(videoId);
        if (isProcessed) {
          _status = UploadStatus.success;
          _currentPhase = 'completed';
          _progress = 1.0;
        } else {
          _setError('Video processing failed or timed out.');
        }
      } else {
        _setError('Upload failed. Please try again.');
      }
    } catch (e) {
      _setError('An unexpected error occurred: $e');
    } finally {
      await progressSubscription.cancel();
      notifyListeners();
    }
  }

  Future<bool> _waitForProcessing(String videoId) async {
    const maxAttempts = 60; // 5 minutes with 5s delay
    int attempts = 0;

    while (attempts < maxAttempts) {
      try {
        final statusData = await _videoService.getVideoProcessingStatus(videoId);
        final processingStatus = statusData?['processingStatus']?.toString().toLowerCase();

        if (processingStatus == 'completed' || processingStatus == 'ready') {
          return true;
        } else if (processingStatus == 'failed') {
          return false;
        }

        // Update progress slightly during polling
        _progress = 0.5 + (attempts / maxAttempts * 0.4);
        notifyListeners();
      } catch (e) {
        // Ignore single polling errors
      }

      await Future.delayed(const Duration(seconds: 5));
      attempts++;
    }
    return false;
  }

  void cancelUpload() {
    _uploadService.cancelUpload();
    _status = UploadStatus.idle;
    _currentPhase = 'preparation';
    _progress = 0.0;
    notifyListeners();
  }

  void _setError(String message) {
    _status = UploadStatus.error;
    _errorMessage = message;
    notifyListeners();
  }

  void reset() {
    _selectedVideo = null;
    _selectedThumbnail = null;
    _selectedCategory = null;
    _tags = [];
    _status = UploadStatus.idle;
    _progress = 0.0;
    _errorMessage = null;
    _currentPhase = 'preparation';
    _crossPostStatus = {};
    notifyListeners();
  }
}
