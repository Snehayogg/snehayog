import 'package:flutter/material.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/features/video/core/data/services/video_service.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/shared/utils/app_logger.dart';

class EditVideoDetails extends StatefulWidget {
  final VideoModel video;
  const EditVideoDetails({super.key, required this.video});

  @override
  State<EditVideoDetails> createState() => _EditVideoDetailsState();
}

class _EditVideoDetailsState extends State<EditVideoDetails> {
  late TextEditingController _titleController;
  late TextEditingController _linkController;
  late TextEditingController _tagsController;
  final VideoService _videoService = VideoService();
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.video.videoName);
    _linkController = TextEditingController(text: widget.video.link ?? '');
    _tagsController = TextEditingController(text: widget.video.tags?.join(', ') ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _linkController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    final newTitle = _titleController.text.trim();
    final newLink = _linkController.text.trim();
    final newTagsStr = _tagsController.text.trim();
    
    if (newTitle.isEmpty) {
      setState(() => _error = 'Video title cannot be empty');
      return;
    }

    final List<String> newTags = newTagsStr
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    // Check if anything changed
    final bool titleChanged = newTitle != widget.video.videoName;
    final bool linkChanged = newLink != (widget.video.link ?? '');
    final bool tagsChanged = _areTagsDifferent(newTags, widget.video.tags);

    if (!titleChanged && !linkChanged && !tagsChanged) {
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final success = await _videoService.updateVideoMetadata(
        widget.video.id, 
        newTitle,
        link: newLink, // Pass empty string to clear link if needed
        tags: newTags,
      );
      
      if (success && mounted) {
        setState(() => _isSaving = false);
        Navigator.of(context).pop({
          'videoName': newTitle,
          'link': newLink,
          'tags': newTags,
        });
      }
    } catch (e) {
      AppLogger.log('❌ EditVideoDetails: Failed to save changes: $e');
      if (mounted) {
        setState(() {
          _isSaving = false;
          _error = e.toString().contains('Exception: ') 
              ? e.toString().split('Exception: ').last 
              : e.toString();
        });
      }
    }
  }

  bool _areTagsDifferent(List<String> newTags, List<String>? oldTags) {
    if (oldTags == null) return newTags.isNotEmpty;
    if (newTags.length != oldTags.length) return true;
    for (int i = 0; i < newTags.length; i++) {
      if (newTags[i].toLowerCase() != oldTags[i].toLowerCase()) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        title: Text(
          'Edit Video Details',
          style: TextStyle(
            fontSize: AppTypography.fontSizeLG,
            fontWeight: AppTypography.weightSemiBold,
          ),
        ),
        backgroundColor: AppColors.backgroundPrimary,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
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
                     color: AppColors.primary,
                   ),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _saveChanges,
              child: Text(
                'SAVE',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: AppTypography.weightBold,
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Video Title', Icons.title_rounded),
            AppSpacing.vSpace12,
            _buildTextField(
              controller: _titleController,
              hintText: 'Give your video a catchy title',
              maxLines: 2,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
            
            AppSpacing.vSpace32,
            _buildSectionHeader('Link (Visit Now Button)', Icons.link_rounded),
            AppSpacing.vSpace8,
            Text(
              'Add a URL to show a "Visit Now" button on your video.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: AppTypography.fontSizeXS,
              ),
            ),
            AppSpacing.vSpace12,
            _buildTextField(
              controller: _linkController,
              hintText: 'https://example.com',
              keyboardType: TextInputType.url,
            ),
            
            AppSpacing.vSpace32,
            _buildSectionHeader('Tags', Icons.tag_rounded),
            AppSpacing.vSpace8,
            Text(
              'Separate tags with commas (e.g. fashion, tech, vlog)',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: AppTypography.fontSizeXS,
              ),
            ),
            AppSpacing.vSpace12,
            _buildTextField(
              controller: _tagsController,
              hintText: 'Add tags...',
              maxLines: null,
            ),
            
            AppSpacing.vSpace48,
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.backgroundSecondary.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderPrimary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                   const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.textSecondary),
                   AppSpacing.hSpace12,
                   const Expanded(
                     child: Text(
                       'Updated details will be visible to everyone immediately.',
                       style: TextStyle(
                         color: AppColors.textSecondary,
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
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        AppSpacing.hSpace8,
        Text(
          title,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: AppTypography.fontSizeSM,
            fontWeight: AppTypography.weightSemiBold,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    int? maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      style: TextStyle(
        color: AppColors.textPrimary,
        fontSize: AppTypography.fontSizeBase,
      ),
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.5)),
        filled: true,
        fillColor: AppColors.backgroundSecondary.withValues(alpha: 0.3),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.borderPrimary.withValues(alpha: 0.5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.borderPrimary.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }
}
