import 'package:flutter/material.dart';
import 'package:vayu/features/video/video_model.dart';
import 'package:vayu/features/video/data/services/video_service.dart';
import 'package:vayu/shared/theme/app_theme.dart';
import 'package:vayu/shared/utils/app_logger.dart';

class EditVideoTitle extends StatefulWidget {
  final VideoModel video;
  const EditVideoTitle({super.key, required this.video});

  @override
  State<EditVideoTitle> createState() => _EditVideoTitleState();
}

class _EditVideoTitleState extends State<EditVideoTitle> {
  late TextEditingController _titleController;
  final VideoService _videoService = VideoService();
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.video.videoName);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    final newTitle = _titleController.text.trim();
    if (newTitle.isEmpty) {
      setState(() => _error = 'Video title cannot be empty');
      return;
    }

    if (newTitle == widget.video.videoName) {
      // No changes made
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final success = await _videoService.updateVideoMetadata(widget.video.id, newTitle);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Video title updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(newTitle); // Return the new title
      }
    } catch (e) {
      AppLogger.log('❌ EditVideoTitle: Failed to save changes: $e');
      if (mounted) {
        setState(() {
          _isSaving = false;
          _error = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfacePrimary,
      appBar: AppBar(
        title: const Text('Edit Video Title'),
        backgroundColor: AppTheme.surfacePrimary,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        actions: [
          if (_isSaving)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _saveChanges,
              child: const Text(
                'SAVE',
                style: TextStyle(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Video Title',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleController,
              autofocus: true,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
              ),
              decoration: InputDecoration(
                hintText: 'Enter video title',
                hintStyle: const TextStyle(color: Colors.grey),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: AppTheme.primary),
                ),
                errorText: _error,
              ),
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 32),
            const Text(
              'Tip: A catchy title helps your video reach more people.',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
