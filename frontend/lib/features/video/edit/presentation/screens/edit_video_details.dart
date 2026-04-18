import 'package:flutter/material.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/features/video/core/data/services/video_service.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/features/video/upload/presentation/widgets/quiz_editor_widget.dart';
import 'package:vayug/features/video/quiz/presentation/screens/create_quiz_screen.dart';

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
  late List<Map<String, dynamic>> _episodes;
  late List<QuizModel> _quizzes;
  String? _seriesId;
  final VideoService _videoService = VideoService();
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.video.videoName);
    _linkController = TextEditingController(text: widget.video.link ?? '');
    _tagsController = TextEditingController(text: widget.video.tags?.join(', ') ?? '');
    
    _quizzes = widget.video.quizzes != null ? List<QuizModel>.from(widget.video.quizzes!) : [];
    
    // Initialize episodes and ensure the current video is IN the list
    final episodesFromVideo = widget.video.episodes ?? [];
    _episodes = List<Map<String, dynamic>>.from(episodesFromVideo);
    
    // If the current video isn't in its own episodes list (happens for new series), add it!
    final bool currentIncluded = _episodes.any((e) => e['id'] == widget.video.id || e['_id'] == widget.video.id);
    if (!currentIncluded) {
      _episodes.insert(0, {
        'id': widget.video.id,
        'videoName': widget.video.videoName,
        'thumbnailUrl': widget.video.thumbnailUrl,
      });
    }
    
    _seriesId = widget.video.seriesId;
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

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      // 1. Update main video basic metadata (title, link, tags)
      final updatedMainVideo = await _videoService.updateVideoMetadata(
        widget.video.id, 
        newTitle,
        link: newLink,
        tags: newTags,
        quizzes: _quizzes,
      );

      // 2. Handle Series Linking (Bulk Update)
      if (_episodes.length > 1) {
        final List<String> episodeIds = _episodes
            .map((e) => (e['id'] ?? e['_id']).toString())
            .toList();
            
        final seriesResult = await _videoService.updateVideoSeries(
          widget.video.id, 
          episodeIds,
          seriesId: _seriesId,
        );
        
        // Update local state with the returned episodes from the refined bulk update
        if (mounted) {
          setState(() => _isSaving = false);
          Navigator.of(context).pop({
            'videoName': updatedMainVideo.videoName,
            'link': updatedMainVideo.link,
            'tags': updatedMainVideo.tags,
            'episodes': seriesResult['episodes'], // Full list from backend
            'seriesId': seriesResult['seriesId'],
          });
        }
      } else {
        // Not a series anymore OR never was. 
        // If it was a series before (widget.video.seriesId != null), we must explicitly unlink it.
        VideoModel finalVideo = updatedMainVideo;
        
        if (widget.video.seriesId != null && widget.video.seriesId!.isNotEmpty) {
          AppLogger.log('🔄 EditVideoDetails: Unlinking video from series...');
          finalVideo = await _videoService.updateVideoMetadata(
            widget.video.id, 
            newTitle,
            link: newLink,
            tags: newTags,
            seriesId: '', // Explicitly clear
            episodeNumber: 0, // Explicitly clear
            quizzes: _quizzes,
          );
        }

        if (mounted) {
          setState(() => _isSaving = false);
          Navigator.of(context).pop({
            'videoName': finalVideo.videoName,
            'link': finalVideo.link,
            'tags': finalVideo.tags,
            'episodes': finalVideo.episodes,
            'seriesId': finalVideo.seriesId,
          });
        }
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
              child: const Text(
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
            AppSpacing.vSpace8,
            _buildTextField(
              controller: _titleController,
              hintText: 'Give your video a catchy title',
              maxLines: 2,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontSize: 11),
                ),
              ),
            
            AppSpacing.vSpace24,
            _buildSectionHeader('Link (CTA Button)', Icons.link_rounded),
            AppSpacing.vSpace8,
            _buildTextField(
              controller: _linkController,
              hintText: 'https://example.com',
              keyboardType: TextInputType.url,
            ),
            
            AppSpacing.vSpace24,
            _buildSectionHeader('Tags', Icons.tag_rounded),
            AppSpacing.vSpace8,
            _buildTextField(
              controller: _tagsController,
              hintText: 'Add tags...',
              maxLines: null,
            ),

            AppSpacing.vSpace24,
            _buildSectionHeader('Episodes (Series)', Icons.layers_rounded),
            AppSpacing.vSpace8,
            _buildEpisodeManager(),
            
            AppSpacing.vSpace24,
            InkWell(
              onTap: () async {
                final List<QuizModel>? result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CreateQuizScreen(
                      initialQuizzes: _quizzes,
                      videoDurationInSeconds: widget.video.duration.inSeconds.toDouble(),
                    ),
                  ),
                );
                if (result != null) {
                  setState(() {
                    _quizzes = result;
                  });
                }
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.backgroundSecondary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderPrimary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add_task_rounded, color: AppColors.primary, size: 20),
                    ),
                    AppSpacing.hSpace12,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Manage Quizzes',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            _quizzes.isEmpty 
                                ? 'Add questions to the video' 
                                : '${_quizzes.length} quizzes added',
                            style: TextStyle(
                              fontSize: 12, 
                              color: _quizzes.isEmpty ? AppColors.textSecondary : AppColors.primary,
                              fontWeight: _quizzes.isEmpty ? FontWeight.normal : FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textTertiary),
                  ],
                ),
              ),
            ),
            
            AppSpacing.vSpace32,
          ],
        ),
      ),
    );
  }

  Widget _buildEpisodeManager() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderPrimary.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          if (_episodes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text('No episodes linked.', style: AppTypography.bodySmall.copyWith(color: AppColors.textTertiary)),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _episodes.length,
              itemBuilder: (context, index) {
                final ep = _episodes[index];
                final bool isCurrent = ep['id'] == widget.video.id || ep['_id'] == widget.video.id;
                
                return ListTile(
                  dense: true,
                  leading: Text('${index + 1}', style: AppTypography.titleSmall.copyWith(color: isCurrent ? AppColors.primary : AppColors.textTertiary)),
                  title: Text(ep['videoName'] ?? 'Untitled', style: AppTypography.bodySmall.copyWith(color: isCurrent ? AppColors.textPrimary : AppColors.textSecondary, fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal), maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: isCurrent 
                    ? Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)), child: const Text('CURRENT', style: TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.bold)))
                    : IconButton(icon: const Icon(Icons.remove_circle_outline_rounded, size: 18, color: Colors.redAccent), onPressed: () => setState(() => _episodes.removeAt(index))),
                );
              },
            ),
          const Divider(height: 1, color: AppColors.divider),
          TextButton.icon(
            onPressed: _showVideoPicker,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add Existing Video'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 12),
              minimumSize: const Size(double.infinity, 44),
            ),
          ),
        ],
      ),
    );
  }

  void _showVideoPicker() async {
    // Show a bottom sheet to pick videos
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.backgroundPrimary,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => _VideoPickerSheet(
        videoType: widget.video.videoType,
        videoService: _videoService,
        currentUserId: widget.video.uploader.id,
        onSelected: (video) {
          Navigator.pop(context);
          setState(() {
            // Check if already in episodes
            if (!_episodes.any((e) => e['id'] == video.id || e['_id'] == video.id)) {
               _episodes.add({
                 'id': video.id,
                 'videoName': video.videoName,
                 'thumbnailUrl': video.thumbnailUrl,
               });
            }
          });
        },
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

class _VideoPickerSheet extends StatefulWidget {
  final String videoType;
  final VideoService videoService;
  final String currentUserId;
  final Function(VideoModel) onSelected;

  const _VideoPickerSheet({
    required this.videoType,
    required this.videoService,
    required this.currentUserId,
    required this.onSelected,
  });

  @override
  State<_VideoPickerSheet> createState() => _VideoPickerSheetState();
}

class _VideoPickerSheetState extends State<_VideoPickerSheet> {
  List<VideoModel>? _videos;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVideos();
  }

  void _loadVideos() async {
    try {
      final allVideos = await widget.videoService.getUserVideos(
        widget.currentUserId,
        videoType: widget.videoType, // Server-side filtering
        limit: 50, // Fetch a larger batch for the picker
        forceRefresh: true, // Always get latest for picker
      );
      
      setState(() {
        _videos = allVideos;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: EdgeInsets.all(AppSpacing.spacing4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Select a ${widget.videoType.toUpperCase()} video',
                style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.bold),
              ),
              IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
            ],
          ),
          AppSpacing.vSpace12,
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : _videos == null || _videos!.isEmpty
                ? const Center(child: Text('No videos found.'))
                : ListView.separated(
                    itemCount: _videos!.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final v = _videos![index];
                      return ListTile(
                        onTap: () => widget.onSelected(v),
                        leading: Container(width: 60, height: 40, decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: AppColors.backgroundSecondary), child: ClipRRect(borderRadius: BorderRadius.circular(4), child: v.thumbnailUrl.isNotEmpty ? Image.network(v.thumbnailUrl, fit: BoxFit.cover) : const Icon(Icons.videocam_rounded))),
                        title: Text(v.videoName, style: AppTypography.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(v.videoType.toUpperCase(), style: AppTypography.labelSmall),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
