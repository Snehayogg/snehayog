import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/features/video/core/data/services/video_service.dart';
import 'package:vayug/core/providers/profile_providers.dart';
import 'package:vayug/shared/widgets/app_button.dart';
import 'package:vayug/shared/widgets/vayu_snackbar.dart';
import 'package:vayug/shared/utils/app_logger.dart';

class ShortVideoCreatorDialog extends ConsumerStatefulWidget {
  const ShortVideoCreatorDialog({super.key});

  @override
  ConsumerState<ShortVideoCreatorDialog> createState() => _ShortVideoCreatorDialogState();
}

class _ShortVideoCreatorDialogState extends ConsumerState<ShortVideoCreatorDialog> {
  VideoModel? _selectedVideo;
  final TextEditingController _startTimeController = TextEditingController(text: "0");
  final TextEditingController _durationController = TextEditingController(text: "40");
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    // Load videos if not loaded or if list is empty
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final stateManager = ref.read(profileStateManagerProvider);
      if (stateManager.userVideos.isEmpty) {
        stateManager.loadUserData(null);
      }
    });
  }

  @override
  void dispose() {
    _startTimeController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  Future<void> _generateClip() async {
    if (_selectedVideo == null) {
      VayuSnackBar.showError(context, "Please select a video first");
      return;
    }

    final startTime = double.tryParse(_startTimeController.text) ?? 0;
    final duration = double.tryParse(_durationController.text) ?? 40;

    if (duration > 60) {
      VayuSnackBar.showError(context, "Shorts must be 60 seconds or less");
      return;
    }

    setState(() => _isGenerating = true);

    try {
      final videoService = VideoService();
      await videoService.generateClip(
        videoId: _selectedVideo!.id,
        startTime: startTime,
        duration: duration,
      );

      if (mounted) {
        VayuSnackBar.showSuccess(context, "Clip generation started! It will appear in your feed shortly.");
        Navigator.pop(context);
      }
    } catch (e) {
      AppLogger.log("❌ Error generating clip: $e");
      if (mounted) {
        VayuSnackBar.showError(context, "Failed to start clip generation: $e");
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stateManager = ref.watch(profileStateManagerProvider);
    final userVideos = stateManager.userVideos;

    return Container(
      padding: const EdgeInsets.only(left: 24, right: 24, top: 12, bottom: 24),
      decoration: const BoxDecoration(
        color: AppColors.backgroundPrimary,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderPrimary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Shorts Generator",
                style: AppTypography.headlineSmall.copyWith(fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "Extract a vertical clip from your existing long-form videos with a professional blurry background effect.",
            style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),

          if (stateManager.isVideosLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: CircularProgressIndicator(),
              ),
            )
          else if (userVideos.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Text("No long-form videos found. Upload one first!"),
              ),
            )
          else ...[
            Text(
              "1. Choose Source Video",
              style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 120,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: userVideos.length,
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final video = userVideos[index];
                  final isSelected = _selectedVideo?.id == video.id;

                  return GestureDetector(
                    onTap: () => setState(() => _selectedVideo = video),
                    child: Container(
                      width: 160,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? AppColors.primary : AppColors.borderPrimary,
                          width: isSelected ? 2 : 1,
                        ),
                        boxShadow: isSelected ? [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.2),
                            blurRadius: 8,
                            spreadRadius: 1,
                          )
                        ] : null,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(isSelected ? 10 : 11),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (video.thumbnailUrl.isNotEmpty)
                              Image.network(
                                video.thumbnailUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.movie_outlined)),
                              )
                            else
                              const Center(child: Icon(Icons.movie_outlined)),
                            
                            // Overlay
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withOpacity(0.7),
                                  ],
                                ),
                              ),
                            ),
                            
                            if (isSelected)
                              const Positioned(
                                top: 8,
                                right: 8,
                                child: CircleAvatar(
                                  radius: 12,
                                  backgroundColor: AppColors.primary,
                                  child: Icon(Icons.check, size: 16, color: Colors.white),
                                ),
                              ),

                            Positioned(
                              bottom: 8,
                              left: 8,
                              right: 8,
                              child: Text(
                                video.videoName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],

          const SizedBox(height: 24),
          Text(
            "2. Set Time Range",
            style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildTimeInput(
                  label: "Start (sec)",
                  controller: _startTimeController,
                  icon: Icons.timer_outlined,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildTimeInput(
                  label: "Duration (sec)",
                  controller: _durationController,
                  icon: Icons.shutter_speed,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          AppButton(
            onPressed: (_isGenerating || _selectedVideo == null) ? null : _generateClip,
            label: _isGenerating ? "Processing..." : "Generate Magic Short ✨",
            variant: AppButtonVariant.primary,
            isFullWidth: true,
            icon: _isGenerating 
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.auto_awesome),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildTimeInput({
    required String label,
    required TextEditingController controller,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.labelSmall.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 18, color: AppColors.primary),
            filled: true,
            fillColor: AppColors.backgroundSecondary.withOpacity(0.5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.borderPrimary),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
    );
  }
}
