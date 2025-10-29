import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:vayu/controller/main_controller.dart';
import 'package:vayu/utils/banner_image_processor.dart';

/// **MediaUploaderWidget - Handles media file uploads for ads**
class MediaUploaderWidget extends StatefulWidget {
  final String selectedAdType;
  final File? selectedImage;
  final File? selectedVideo;
  final List<File> selectedImages;
  final Function(File?) onImageSelected;
  final Function(File?) onVideoSelected;
  final Function(List<File>) onImagesSelected;
  final Function(String) onError;

  // **NEW: Validation states**
  final bool? isMediaValid;
  final String? mediaError;

  const MediaUploaderWidget({
    Key? key,
    required this.selectedAdType,
    required this.selectedImage,
    required this.selectedVideo,
    required this.selectedImages,
    required this.onImageSelected,
    required this.onVideoSelected,
    required this.onImagesSelected,
    required this.onError,
    // **NEW: Optional validation parameters**
    this.isMediaValid,
    this.mediaError,
  }) : super(key: key);

  @override
  State<MediaUploaderWidget> createState() => _MediaUploaderWidgetState();
}

class _MediaUploaderWidgetState extends State<MediaUploaderWidget> {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Media Content',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: (widget.isMediaValid == false)
                          ? Colors.red
                          : Colors.grey.shade300,
                      width: (widget.isMediaValid == false) ? 2.0 : 1.0,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _buildMediaPreview(),
                ),
                if (widget.isMediaValid == false && widget.mediaError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      widget.mediaError!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.image),
                    label: Text(_getImageButtonLabel()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isVideoAllowed() ? _pickVideo : null,
                    icon: const Icon(Icons.video_library),
                    label: Text(_getVideoButtonLabel()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _isVideoAllowed() ? Colors.green : Colors.grey,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _getMediaHelpText(),
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
            // Add tips based on ad type
            if (widget.selectedAdType == 'video feed ad') _buildVideoTip(),
            if (widget.selectedAdType == 'carousel') _buildCarouselTip(),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaPreview() {
    if (widget.selectedAdType == 'carousel' &&
        widget.selectedImages.isNotEmpty) {
      return ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: widget.selectedImages.length,
        itemBuilder: (context, index) {
          return Container(
            width: 150,
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    widget.selectedImages[index],
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: () => _removeImageFromCarousel(index),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 4,
                  left: 4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    } else if (widget.selectedImage != null) {
      // **NEW: Special preview for banner ads**
      if (widget.selectedAdType == 'banner') {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Banner preview with correct aspect ratio
              Container(
                width: 320,
                height: 100,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.blue, width: 2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: Image.file(
                    widget.selectedImage!,
                    fit: BoxFit.cover,
                    width: 320,
                    height: 100,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: const Text(
                  'Banner Preview (320x100)',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        );
      } else {
        // Regular preview for other ad types
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            widget.selectedImage!,
            fit: BoxFit.cover,
            width: double.infinity,
          ),
        );
      }
    } else if (widget.selectedVideo != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          color: Colors.black,
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.video_file, size: 48, color: Colors.white),
                Text(
                  'Video Selected',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            widget.selectedAdType == 'banner'
                ? Icons.image
                : Icons.add_photo_alternate,
            size: 48,
            color: Colors.grey,
          ),
          Text(
            _getPlaceholderText(),
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _getPlaceholderSubtext(),
            style: const TextStyle(
              color: Colors.red,
              fontSize: 12,
            ),
          ),
        ],
      );
    }
  }

  Widget _buildVideoTip() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.video_library, size: 16, color: Colors.green.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '🎬 Video Tip: For best results, use MP4 videos with H.264 encoding. Keep file size under 100MB for faster uploads.',
              style: TextStyle(
                color: Colors.green.shade700,
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCarouselTip() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.view_carousel, size: 16, color: Colors.orange.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '🎠 Carousel Tip: Choose either multiple images (up to 3) OR a single video for your carousel. This creates a cleaner, more focused ad experience.',
              style: TextStyle(
                color: Colors.orange.shade700,
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getImageButtonLabel() {
    switch (widget.selectedAdType) {
      case 'banner':
        return 'Select Image *';
      case 'carousel':
        return widget.selectedImages.isNotEmpty
            ? 'Add More Images (${widget.selectedImages.length}/3)'
            : 'Add Images (up to 3)';
      default:
        return 'Select Image';
    }
  }

  String _getVideoButtonLabel() {
    switch (widget.selectedAdType) {
      case 'banner':
        return 'Video Not Allowed';
      case 'carousel':
        return widget.selectedVideo != null ? 'Video Selected' : 'Add Video';
      default:
        return 'Select Video';
    }
  }

  String _getMediaHelpText() {
    switch (widget.selectedAdType) {
      case 'banner':
        return 'Banner ads only support images (will be cropped to 320x100 pixels)';
      case 'carousel':
        return 'Carousel ads: choose either up to 3 images OR 1 video (not both)';
      default:
        return 'Video feed ads support both images and videos';
    }
  }

  String _getPlaceholderText() {
    switch (widget.selectedAdType) {
      case 'banner':
        return 'Select Image *';
      case 'carousel':
        return 'Select Images OR Video *';
      default:
        return 'Select Image or Video *';
    }
  }

  String _getPlaceholderSubtext() {
    switch (widget.selectedAdType) {
      case 'banner':
        return 'Banner ads require an image';
      case 'carousel':
        return 'Carousel ads: either up to 3 images OR 1 video';
      default:
        return 'Video feed ads support both';
    }
  }

  bool _isVideoAllowed() {
    return widget.selectedAdType != 'banner';
  }

  Future<void> _pickImage() async {
    try {
      if (widget.selectedAdType == 'banner') {
        await _pickSingleImage();
      } else if (widget.selectedAdType == 'carousel') {
        await _handleCarouselImageSelection();
      } else {
        await _pickSingleImage();
      }
    } catch (e) {
      widget.onError('Error picking image: $e');
    }
  }

  Future<void> _pickSingleImage() async {
    final ImagePicker picker = ImagePicker();
    // prevent autoplay on resume
    if (mounted) {
      Provider.of<MainController>(context, listen: false)
          .setMediaPickerActive(true);
    }
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 85,
    );
    if (mounted) {
      Provider.of<MainController>(context, listen: false)
          .setMediaPickerActive(false);
    }

    if (image != null) {
      final file = File(image.path);
      if (await _validateImageFile(file)) {
        // **NEW: For banner ads, show cropping dialog**
        if (widget.selectedAdType == 'banner') {
          if (mounted) {
            final croppedFile = await BannerImageProcessor.showBannerCropDialog(
              context,
              file,
            );

            if (croppedFile != null) {
              widget.onImageSelected(croppedFile);
            }
          }
        } else {
          // For other ad types, use image directly
          widget.onImageSelected(file);
        }
      }
    }
  }

  Future<void> _handleCarouselImageSelection() async {
    String? choice;

    if (widget.selectedImages.isNotEmpty) {
      choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Switch to Video?'),
          content: const Text(
              'You currently have images selected. Would you like to switch to video? This will remove all selected images.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'switch_to_video'),
              child: const Text('Switch to Video'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'keep_images'),
              child: const Text('Keep Images'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );

      if (choice == 'switch_to_video') {
        widget.onImagesSelected([]);
        await _pickVideo();
        return;
      } else if (choice == 'keep_images') {
        if (widget.selectedImages.length < 3) {
          await _pickMultipleImages();
        } else {
          widget.onError('Maximum 3 images already selected');
        }
        return;
      } else {
        return;
      }
    }

    if (widget.selectedVideo != null) {
      choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Switch to Images?'),
          content: const Text(
              'You currently have a video selected. Would you like to switch to images? This will remove the selected video.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'switch_to_images'),
              child: const Text('Switch to Images'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'keep_video'),
              child: const Text('Keep Video'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );

      if (choice == 'switch_to_images') {
        widget.onVideoSelected(null);
        await _pickMultipleImages();
        return;
      } else {
        return;
      }
    }

    choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Media Type'),
        content: const Text(
            'Carousel ads support either multiple images (up to 3) OR a single video. Choose one:'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'multiple_images'),
            child: const Text('Add Images (up to 3)'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'video'),
            child: const Text('Add Video'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (choice == 'multiple_images') {
      await _pickMultipleImages();
    } else if (choice == 'video') {
      await _pickVideo();
    }
  }

  Future<void> _pickMultipleImages() async {
    if (widget.selectedImages.length >= 3) {
      widget.onError('Maximum 3 images allowed for carousel ads');
      return;
    }

    final ImagePicker picker = ImagePicker();
    if (mounted) {
      Provider.of<MainController>(context, listen: false)
          .setMediaPickerActive(true);
    }
    final List<XFile> images = await picker.pickMultiImage(
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 85,
    );
    if (mounted) {
      Provider.of<MainController>(context, listen: false)
          .setMediaPickerActive(false);
    }

    if (images.isNotEmpty) {
      final List<File> validImages = [];
      for (final image in images) {
        if (widget.selectedImages.length + validImages.length >= 3) break;

        final file = File(image.path);
        if (await _validateImageFile(file)) {
          validImages.add(file);
        }
      }

      if (validImages.isNotEmpty) {
        final List<File> newImages = List.from(widget.selectedImages)
          ..addAll(validImages);
        widget.onImagesSelected(newImages);
      } else {
        widget.onError(
            'No valid images selected. Please ensure files are valid image formats under 10MB.');
      }
    }
  }

  Future<void> _pickVideo() async {
    if (widget.selectedAdType == 'banner') {
      widget.onError(
          'Banner ads only support images. Please select an image instead.');
      return;
    }

    // Restrict to gallery videos only
    final ImagePicker picker = ImagePicker();
    if (mounted) {
      Provider.of<MainController>(context, listen: false)
          .setMediaPickerActive(true);
    }
    final XFile? picked = await picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 5),
    );
    if (mounted) {
      Provider.of<MainController>(context, listen: false)
          .setMediaPickerActive(false);
    }

    if (picked != null) {
      final file = File(picked.path);
      if (await _validateVideoFile(file)) {
        widget.onVideoSelected(file);
      }
    }
  }

  void _removeImageFromCarousel(int index) {
    final List<File> newImages = List.from(widget.selectedImages)
      ..removeAt(index);
    widget.onImagesSelected(newImages);
  }

  Future<bool> _validateImageFile(File file) async {
    try {
      final fileName = file.path.split('/').last.toLowerCase();
      if (!fileName.endsWith('.jpg') &&
          !fileName.endsWith('.jpeg') &&
          !fileName.endsWith('.png') &&
          !fileName.endsWith('.gif') &&
          !fileName.endsWith('.webp')) {
        widget.onError(
            'Please select a valid image file (JPG, PNG, GIF, or WebP)');
        return false;
      }

      final fileSize = await file.length();
      if (fileSize > 10 * 1024 * 1024) {
        widget.onError('Image file size must be less than 10MB');
        return false;
      }

      return true;
    } catch (e) {
      widget.onError('Error validating image file: $e');
      return false;
    }
  }

  Future<bool> _validateVideoFile(File file) async {
    try {
      final fileName = file.path.split('/').last.toLowerCase();
      final supportedExtensions = ['.mp4', '.webm', '.avi', '.mov', '.mkv'];

      if (!supportedExtensions.any((ext) => fileName.endsWith(ext))) {
        widget.onError(
            'Unsupported video format. Please select MP4, WebM, AVI, MOV, or MKV');
        return false;
      }

      final fileSize = await file.length();
      if (fileSize > 100 * 1024 * 1024) {
        widget.onError('Video file size must be less than 100MB');
        return false;
      }

      return true;
    } catch (e) {
      widget.onError('Error validating video file: $e');
      return false;
    }
  }
}
