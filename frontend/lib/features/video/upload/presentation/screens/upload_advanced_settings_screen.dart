import 'package:flutter/material.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/shared/widgets/app_button.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/features/video/quiz/presentation/screens/create_quiz_screen.dart';

class UploadAdvancedSettingsScreen extends StatefulWidget {
  final TextEditingController linkController;
  final TextEditingController tagInputController;
  final ValueNotifier<List<String>> tags;
  final void Function(String) onAddTag;
  final void Function(String) onRemoveTag;
  final VoidCallback onMakeEpisode;
  final ValueNotifier<List<QuizModel>> quizzes;
  final ValueNotifier<List<String>> selectedPlatforms;
  final double videoDuration;

  const UploadAdvancedSettingsScreen({
    super.key,
    required this.linkController,
    required this.tagInputController,
    required this.tags,
    required this.onAddTag,
    required this.onRemoveTag,
    required this.onMakeEpisode,
    required this.quizzes,
    required this.selectedPlatforms,
    this.videoDuration = 0.0,
  });

  @override
  State<UploadAdvancedSettingsScreen> createState() => _UploadAdvancedSettingsScreenState();
}

class _UploadAdvancedSettingsScreenState extends State<UploadAdvancedSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        title: const Text('Advanced Settings', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: AppColors.backgroundPrimary,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _buildSettingRow(
                  icon: Icons.help_outline_rounded,
                  title: 'Quizzes',
                  subtitle: 'Add interactive questions',
                  trailing: ValueListenableBuilder<List<QuizModel>>(
                    valueListenable: widget.quizzes,
                    builder: (context, current, _) {
                      return Text(
                        current.isEmpty ? 'None' : '${current.length} added',
                        style: TextStyle(
                          color: current.isEmpty ? AppColors.textTertiary : AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      );
                    },
                  ),
                  onTap: () async {
                    final List<QuizModel>? result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CreateQuizScreen(
                          initialQuizzes: widget.quizzes.value,
                          videoDurationInSeconds: widget.videoDuration,
                        ),
                      ),
                    );
                    if (result != null) widget.quizzes.value = result;
                  },
                ),

                _buildSettingRow(
                  icon: Icons.tag_rounded,
                  title: 'Discovery Tags',
                  subtitle: 'Help people find your video',
                  trailing: ValueListenableBuilder<List<String>>(
                    valueListenable: widget.tags,
                    builder: (context, current, _) {
                      return Text(
                        current.isEmpty ? 'Add' : '${current.length} tags',
                        style: TextStyle(
                          color: current.isEmpty ? AppColors.textTertiary : AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    },
                  ),
                  onTap: () => _showAddTagsBottomSheet(context),
                ),
                
                _buildSettingRow(
                  icon: Icons.link_rounded,
                  title: 'Promotional Link',
                  subtitle: 'Website or purchase link',
                  trailing: AnimatedBuilder(
                    animation: widget.linkController,
                    builder: (context, _) {
                      final hasLink = widget.linkController.text.isNotEmpty;
                      return Text(
                        hasLink ? 'Added' : 'None',
                        style: TextStyle(
                          color: !hasLink ? AppColors.textTertiary : AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    },
                  ),
                  onTap: () => _showLinkEditor(context),
                ),

                _buildSettingRow(
                  icon: Icons.video_collection_outlined,
                  title: 'Make an Episode',
                  subtitle: 'Add to a series or playlist',
                  onTap: widget.onMakeEpisode,
                ),

                _buildCrossPostingTile(),
                
                const SizedBox(height: 40),
              ],
            ),
          ),
          
          Container(
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: AppColors.backgroundPrimary,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: AppButton(
              onPressed: () => Navigator.pop(context),
              label: 'Done',
              variant: AppButtonVariant.primary,
              isFullWidth: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8, left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: AppColors.textTertiary.withValues(alpha: 0.7),
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(height: 1, thickness: 1, color: AppColors.borderPrimary.withValues(alpha: 0.4));
  }

  Widget _buildSettingRow({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.backgroundSecondary.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 22, color: AppColors.textPrimary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[
              trailing,
              const SizedBox(width: 8),
            ],
            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

  void _showLinkEditor(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.backgroundPrimary,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          left: 24, right: 24, top: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Promotional Link', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            const SizedBox(height: 8),
            const Text('Add a website or product link to your video details.', style: TextStyle(color: AppColors.textTertiary, fontSize: 13)),
            const SizedBox(height: 24),
            TextField(
              controller: widget.linkController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'https://...',
                prefixIcon: const Icon(Icons.link),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 24),
            AppButton(onPressed: () => Navigator.pop(context), label: 'Save Link', variant: AppButtonVariant.primary, isFullWidth: true),
          ],
        ),
      ),
    );
  }

  Widget _buildCrossPostingTile() {
    return ValueListenableBuilder<List<String>>(
      valueListenable: widget.selectedPlatforms,
      builder: (context, selected, _) {
        final isActive = selected.contains('youtube');
        return _buildSettingRow(
          icon: Icons.share_rounded,
          title: 'Post to YouTube',
          subtitle: 'Sync upload with YouTube Shorts',
          trailing: Switch(
            value: isActive,
            onChanged: (val) {
              final current = List<String>.from(widget.selectedPlatforms.value);
              if (val) { if (!current.contains('youtube')) current.add('youtube'); }
              else { current.remove('youtube'); }
              widget.selectedPlatforms.value = current;
            },
            activeColor: AppColors.primary,
          ),
          onTap: () {},
        );
      },
    );
  }

  void _showAddTagsBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.backgroundPrimary,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Search Tags',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: widget.tagInputController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Type tag and press Add',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add_box_rounded, color: AppColors.primary),
                    onPressed: () {
                      if (widget.tagInputController.text.isNotEmpty) {
                        widget.onAddTag(widget.tagInputController.text);
                        widget.tagInputController.clear();
                      }
                    },
                  ),
                ),
                onSubmitted: (value) {
                  if (value.isNotEmpty) {
                    widget.onAddTag(value);
                    widget.tagInputController.clear();
                  }
                },
              ),
              const SizedBox(height: 20),
              ValueListenableBuilder<List<String>>(
                valueListenable: widget.tags,
                builder: (context, currentTags, _) {
                  if (currentTags.isEmpty) {
                    return Container(
                      height: 100,
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSecondary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(child: Text('No tags added yet')),
                    );
                  }
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: currentTags
                        .map((tag) => Chip(
                              label: Text(tag),
                              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                              side: BorderSide.none,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              onDeleted: () => widget.onRemoveTag(tag),
                              deleteIcon: const Icon(Icons.cancel, size: 16),
                            ))
                        .toList(),
                  );
                },
              ),
              const SizedBox(height: 24),
              AppButton(
                onPressed: () => Navigator.pop(context),
                label: 'Done',
                variant: AppButtonVariant.primary,
                isFullWidth: true,
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMakeEpisodeOption(BuildContext context) {
    return InkWell(
      onTap: widget.onMakeEpisode,
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Make an Episode',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

