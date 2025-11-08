import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class BannerImageProcessor {
  // Mobile banner specifications - Updated for better mobile banner sizing
  static const int bannerWidth = 320;
  static const int bannerHeight =
      100; // Changed from 50 to 100 for better visibility
  static const double bannerAspectRatio =
      3.2; // 320:100 = 3.2:1 (more mobile-friendly)

  /// Process image for banner ad - crop and resize to 320x100 pixels
  static Future<File> processBannerImage(File originalImage) async {
    try {
      print('🔍 BannerImageProcessor: Processing image for banner ad');
      print('   Original path: ${originalImage.path}');

      // Read the original image
      final bytes = await originalImage.readAsBytes();
      final originalImg = img.decodeImage(bytes);

      if (originalImg == null) {
        throw Exception('Failed to decode image');
      }

      print(
          '   Original dimensions: ${originalImg.width}x${originalImg.height}');

      // Create banner-sized image with proper cropping
      final processedImg = _createBannerImage(originalImg);

      // Save the processed image
      final processedFile =
          await _saveProcessedImage(processedImg, originalImage.path);

      print('✅ BannerImageProcessor: Image processed successfully');
      print(
          '   Final dimensions: ${processedImg.width}x${processedImg.height}');
      print('   Processed path: ${processedFile.path}');

      return processedFile;
    } catch (e) {
      print('❌ BannerImageProcessor: Error processing image: $e');
      throw Exception('Failed to process banner image: $e');
    }
  }

  /// Create banner image with smart cropping and resizing
  static img.Image _createBannerImage(img.Image originalImg) {
    final originalWidth = originalImg.width;
    final originalHeight = originalImg.height;
    final originalAspectRatio = originalWidth / originalHeight;

    print(
        '   Original aspect ratio: ${originalAspectRatio.toStringAsFixed(2)}:1');
    print('   Target aspect ratio: $bannerAspectRatio:1');

    img.Image processedImg;

    if (originalAspectRatio > bannerAspectRatio) {
      // Image is wider than banner ratio - crop width, keep height
      final targetWidth = (originalHeight * bannerAspectRatio).round();
      final cropX = ((originalWidth - targetWidth) / 2).round();

      print(
          '   Cropping width: $originalWidth -> $targetWidth (crop from x=$cropX)');

      processedImg = img.copyCrop(
        originalImg,
        x: cropX,
        y: 0,
        width: targetWidth,
        height: originalHeight,
      );
    } else {
      // Image is taller than banner ratio - crop height, keep width
      final targetHeight = (originalWidth / bannerAspectRatio).round();
      final cropY = ((originalHeight - targetHeight) / 2).round();

      print(
          '   Cropping height: $originalHeight -> $targetHeight (crop from y=$cropY)');

      processedImg = img.copyCrop(
        originalImg,
        x: 0,
        y: cropY,
        width: originalWidth,
        height: targetHeight,
      );
    }

    // **FIX: Use non-deprecated resize method with precise control**
    processedImg = img.copyResize(
      processedImg,
      width: bannerWidth,
      height: bannerHeight,
      interpolation:
          img.Interpolation.cubic, // **FIX: Better quality than linear**
      maintainAspect:
          false, // **FIX: Ensure exact dimensions without precision loss**
    );

    // **FIX: Use non-deprecated drawing method with precise control**
    processedImg = img.drawRect(
      processedImg,
      x1: 0,
      y1: 0,
      x2: bannerWidth - 1,
      y2: bannerHeight - 1,
      color: img.ColorRgb8(200, 200, 200),
      thickness: 1,
    );

    return processedImg;
  }

  /// Save processed image to temporary file
  static Future<File> _saveProcessedImage(
      img.Image processedImg, String originalPath) async {
    try {
      // Get temporary directory
      final tempDir = await getTemporaryDirectory();

      // Create unique filename for processed banner
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final originalName = originalPath.split('/').last.split('.').first;
      final processedPath =
          '${tempDir.path}/banner_${originalName}_$timestamp.jpg';

      // **FIX: Use non-deprecated encoding with precise quality control**
      final jpegBytes = img.encodeJpg(
        processedImg,
        quality: 90,
        chroma: img.JpegChroma
            .yuv444, // **FIX: Best chroma subsampling for precision**
      );

      // Save to file
      final processedFile = File(processedPath);
      await processedFile.writeAsBytes(jpegBytes);

      print('   Processed image saved: $processedPath');
      print('   File size: ${(jpegBytes.length / 1024).toStringAsFixed(1)} KB');

      return processedFile;
    } catch (e) {
      print('❌ Error saving processed image: $e');
      throw Exception('Failed to save processed banner image: $e');
    }
  }

  /// Validate if image is suitable for banner processing
  static bool validateImageForBanner(File imageFile) {
    try {
      // Check file size (should be reasonable for processing)
      final fileSizeBytes = imageFile.lengthSync();
      final fileSizeMB = fileSizeBytes / (1024 * 1024);

      if (fileSizeMB > 50) {
        print(
            '❌ Image too large for banner processing: ${fileSizeMB.toStringAsFixed(1)}MB');
        return false;
      }

      return true;
    } catch (e) {
      print('❌ Error validating banner image: $e');
      return false;
    }
  }

  /// Get preview dimensions for banner image in UI
  static Map<String, double> getBannerPreviewDimensions(double maxWidth) {
    // Calculate preview dimensions maintaining banner aspect ratio
    final previewWidth = maxWidth.clamp(100.0, 320.0);
    final previewHeight = previewWidth / bannerAspectRatio;

    return {
      'width': previewWidth,
      'height': previewHeight,
    };
  }

  /// Create a preview overlay showing banner crop area
  static Widget createBannerCropPreview(File imageFile, double containerWidth) {
    final previewDims =
        getBannerPreviewDimensions(containerWidth - 32); // Account for padding

    return Container(
      width: previewDims['width'],
      height: previewDims['height'],
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF2196F3), width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: Image.file(
          imageFile,
          fit: BoxFit.cover,
          width: previewDims['width'],
          height: previewDims['height'],
        ),
      ),
    );
  }

  static Future<File?> showBannerCropDialog(
    BuildContext context,
    File imageFile,
  ) async {
    double cropOffsetX = 0.5; // Horizontal offset (0.0 = left, 1.0 = right)
    double cropOffsetY = 0.5; // Vertical offset (0.0 = top, 1.0 = bottom)

    return await showDialog<File?>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: const Text(
                'Adjust Banner Image',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(null),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    try {
                      final croppedFile = await _cropImageWithOffsets(
                        imageFile,
                        cropOffsetX,
                        cropOffsetY,
                      );
                      Navigator.of(context).pop(croppedFile);
                    } catch (e) {
                      Navigator.of(context).pop(null);
                    }
                  },
                  child: const Text(
                    'DONE',
                    style: TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            body: Column(
              children: [
                // Instructions
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: Colors.grey[900],
                  child: const Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.crop, color: Colors.blue, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Banner Crop (3.2:1)',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Drag the banner frame to position your image',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Banner will be 320x100 pixels',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

                // Image with crop overlay
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    child: _buildInteractiveCropArea(
                      imageFile: imageFile,
                      offsetX: cropOffsetX,
                      offsetY: cropOffsetY,
                      onOffsetChanged: (newOffset) {
                        setState(() {
                          cropOffsetX = newOffset.dx;
                          cropOffsetY = newOffset.dy;
                        });
                      },
                    ),
                  ),
                ),

                // Interaction info
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: Colors.grey[900],
                  child: Column(
                    children: const [
                      Row(
                        children: [
                          Icon(Icons.pan_tool, color: Colors.blue, size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Drag the blue banner box to adjust the focus. It stays locked to 3.2:1.',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Tip: You can move it in any direction. Double-tap the banner box to reset.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// **NEW: Build interactive crop area with draggable banner box**
  static Widget _buildInteractiveCropArea({
    required File imageFile,
    required double offsetX,
    required double offsetY,
    required ValueChanged<Offset> onOffsetChanged,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final containerWidth = constraints.maxWidth;
        final containerHeight = constraints.maxHeight;

        // Determine banner area size while maintaining aspect ratio
        final availableWidth = containerWidth * 0.9;
        final availableHeight = containerHeight * 0.8;

        double bannerAreaWidth = availableWidth;
        double bannerAreaHeight = bannerAreaWidth / bannerAspectRatio;

        if (bannerAreaHeight > availableHeight) {
          bannerAreaHeight = availableHeight;
          bannerAreaWidth = bannerAreaHeight * bannerAspectRatio;
        }

        final maxOffsetX =
            (containerWidth - bannerAreaWidth).clamp(0.0, double.infinity);
        final maxOffsetY =
            (containerHeight - bannerAreaHeight).clamp(0.0, double.infinity);

        final bannerLeft = maxOffsetX == 0
            ? (containerWidth - bannerAreaWidth) / 2
            : offsetX * maxOffsetX;
        final bannerTop = maxOffsetY == 0
            ? (containerHeight - bannerAreaHeight) / 2
            : offsetY * maxOffsetY;

        return Stack(
          children: [
            // Background image
            Positioned.fill(
              child: Image.file(
                imageFile,
                fit: BoxFit.contain,
              ),
            ),

            // Dark overlay
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.6),
              ),
            ),

            // Draggable crop area
            Positioned(
              left: bannerLeft,
              top: bannerTop,
              width: bannerAreaWidth,
              height: bannerAreaHeight,
              child: GestureDetector(
                onPanUpdate: (details) {
                  double newOffsetX = offsetX;
                  double newOffsetY = offsetY;

                  if (maxOffsetX > 0) {
                    final currentX = offsetX * maxOffsetX;
                    final updatedX =
                        (currentX + details.delta.dx).clamp(0.0, maxOffsetX);
                    newOffsetX = updatedX / maxOffsetX;
                  }

                  if (maxOffsetY > 0) {
                    final currentY = offsetY * maxOffsetY;
                    final updatedY =
                        (currentY + details.delta.dy).clamp(0.0, maxOffsetY);
                    newOffsetY = updatedY / maxOffsetY;
                  }

                  onOffsetChanged(Offset(newOffsetX, newOffsetY));
                },
                onDoubleTap: () => onOffsetChanged(const Offset(0.5, 0.5)),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.blue, width: 3),
                    borderRadius: BorderRadius.circular(4),
                    color: Colors.transparent,
                  ),
                ),
              ),
            ),

            // Banner label
            Positioned(
              left: bannerLeft,
              top: (bannerTop - 30).clamp(8.0, double.infinity),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Banner Area (320x100)',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// **NEW: Crop image with adjustable offsets**
  static Future<File> _cropImageWithOffsets(
    File imageFile,
    double offsetX,
    double offsetY,
  ) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final originalImg = img.decodeImage(bytes);

      if (originalImg == null) {
        throw Exception('Failed to decode image');
      }

      final originalWidth = originalImg.width;
      final originalHeight = originalImg.height;

      // Calculate crop dimensions maintaining aspect ratio
      int cropWidth = originalWidth;
      int cropHeight = (cropWidth / bannerAspectRatio).round();

      if (cropHeight > originalHeight) {
        cropHeight = originalHeight;
        cropWidth = (cropHeight * bannerAspectRatio).round();
      }

      final maxCropX = originalWidth - cropWidth;
      final maxCropY = originalHeight - cropHeight;

      final cropX =
          maxCropX > 0 ? (maxCropX * offsetX).round().clamp(0, maxCropX) : 0;
      final cropY =
          maxCropY > 0 ? (maxCropY * offsetY).round().clamp(0, maxCropY) : 0;

      // Crop the image
      final croppedImg = img.copyCrop(
        originalImg,
        x: cropX,
        y: cropY,
        width: cropWidth,
        height: cropHeight,
      );

      // Resize to exact banner dimensions
      final resizedImg = img.copyResize(
        croppedImg,
        width: bannerWidth,
        height: bannerHeight,
        interpolation: img.Interpolation.cubic,
        maintainAspect: false,
      );

      // Save to temporary file
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final croppedPath = '${tempDir.path}/banner_cropped_$timestamp.jpg';

      final jpegBytes = img.encodeJpg(resizedImg, quality: 95);
      final croppedFile = File(croppedPath);
      await croppedFile.writeAsBytes(jpegBytes);

      print(
          '✅ Banner image cropped and resized to ${bannerWidth}x$bannerHeight');
      return croppedFile;
    } catch (e) {
      throw Exception('Failed to crop banner image: $e');
    }
  }
}
