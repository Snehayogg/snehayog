import 'package:flutter/material.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/shared/widgets/app_button.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/features/video/quiz/presentation/screens/create_quiz_screen.dart';

class UploadAdvancedSettingsSection extends StatefulWidget {
  final ValueNotifier<bool> isExpanded;
  final VoidCallback onToggle;
  final TextEditingController titleController;
  final TextEditingController linkController;
  final TextEditingController tagInputController;
  final ValueNotifier<List<String>> tags;
  final void Function(String) onAddTag;
  final void Function(String) onRemoveTag;
  final VoidCallback onMakeEpisode;
  final ValueNotifier<List<QuizModel>> quizzes;
  final double videoDuration;

  const UploadAdvancedSettingsSection({
    super.key,
    required this.isExpanded,
    required this.onToggle,
    required this.titleController,
    required this.linkController,
    required this.tagInputController,
    required this.tags,
    required this.onAddTag,
    required this.onRemoveTag,
    required this.onMakeEpisode,
    required this.quizzes,
    this.videoDuration = 0.0,
  });

  @override
  State<UploadAdvancedSettingsSection> createState() => _UploadAdvancedSettingsSectionState();
}

class _UploadAdvancedSettingsSectionState extends State<UploadAdvancedSettingsSection> {
  final ValueNotifier<int> _currentStep = ValueNotifier<int>(0);
  static const int _totalSteps = 3;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          leading: const Icon(Icons.tune, color: AppColors.primary),
          title: Text(
            'Advanced Options',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          trailing: ValueListenableBuilder<bool>(
            valueListenable: widget.isExpanded,
            builder: (context, expanded, _) {
              return Icon(
                expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                color: AppColors.primary,
              );
            },
          ),
          onTap: widget.onToggle,
        ),
        ValueListenableBuilder<bool>(
          valueListenable: widget.isExpanded,
          builder: (context, expanded, _) {
            if (!expanded) {
              return const SizedBox.shrink();
            }

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStepProgress(),
                  const SizedBox(height: 20),
                  ValueListenableBuilder<int>(
                    valueListenable: _currentStep,
                    builder: (context, step, _) {
                      return Column(
                        children: [
                          if (step == 0) _buildStep1Basic(),
                          if (step == 1) _buildStep2TagsAndSeries(),
                          if (step == 2) _buildStep3Quiz(),
                          const SizedBox(height: 24),
                          _buildNavigationButtons(),
                        ],
                      );
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildStepProgress() {
    return ValueListenableBuilder<int>(
      valueListenable: _currentStep,
      builder: (context, step, _) {
        return Row(
          children: List.generate(_totalSteps, (index) {
            final isActive = index == step;
            final isCompleted = index < step;
            return Expanded(
              child: Container(
                height: 4,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: isCompleted
                      ? AppColors.primary
                      : (isActive ? AppColors.primary.withValues(alpha: 0.5) : AppColors.borderPrimary),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildStep1Basic() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Basic Info', Icons.info_outline),
        AppSpacing.vSpace12,
        _buildTitleField(context),
        AppSpacing.vSpace12,
        _buildLinkField(context),
      ],
    );
  }

  Widget _buildStep2TagsAndSeries() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Discovery & Series', Icons.explore_outlined),
        AppSpacing.vSpace12,
        _buildTagInput(context),
        AppSpacing.vSpace12,
        _buildMakeEpisodeOption(context),
      ],
    );
  }

  Widget _buildStep3Quiz() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Interactive Quizzes', Icons.quiz_outlined),
        AppSpacing.vSpace12,
        InkWell(
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
            if (result != null) {
              widget.quizzes.value = result;
            }
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add_task_rounded, color: AppColors.primary),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Manage Quizzes',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 2),
                      ValueListenableBuilder<List<QuizModel>>(
                        valueListenable: widget.quizzes,
                        builder: (context, current, _) {
                          if (current.isEmpty) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 2.0),
                            child: Text(
                              '${current.length} quizzes added',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.textTertiary),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNavigationButtons() {
    return ValueListenableBuilder<int>(
      valueListenable: _currentStep,
      builder: (context, step, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (step > 0)
              Expanded(
                child: AppButton(
                  onPressed: () => _currentStep.value--,
                  label: 'Back',
                  variant: AppButtonVariant.outline,
                ),
              )
            else
              const Spacer(),
            const SizedBox(width: 16),
            if (step < _totalSteps - 1)
              Expanded(
                child: AppButton(
                  onPressed: () => _currentStep.value++,
                  label: 'Next',
                  variant: AppButtonVariant.primary,
                ),
              )
            else
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Center(
                    child: Text(
                      'All Set!',
                      style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildTitleField(BuildContext context) {
    return TextField(
      controller: widget.titleController,
      minLines: 2,
      maxLines: 2,
      decoration: InputDecoration(
        labelText: 'Video Title',
        labelStyle: Theme.of(context).textTheme.bodyMedium,
        hintText: 'Write a catchy title',
        hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary.withValues(alpha: 0.4),
            ),
        prefixIcon: const Icon(Icons.title, size: 20),
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _buildLinkField(BuildContext context) {
    return TextField(
      controller: widget.linkController,
      decoration: const InputDecoration(
        labelText: 'Website Link',
        hintText: 'https://example.com',
        helperText: 'Promote your external link',
        prefixIcon: Icon(Icons.link, size: 20),
        border: OutlineInputBorder(),
      ),
      keyboardType: TextInputType.url,
    );
  }

  Widget _buildTagInput(BuildContext context) {
    return InkWell(
      onTap: () => _showAddTagsBottomSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.borderPrimary),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            const Icon(Icons.tag, size: 20, color: AppColors.textPrimary),
            const SizedBox(width: 8),
            Expanded(
              child: ValueListenableBuilder<List<String>>(
                valueListenable: widget.tags,
                builder: (context, currentTags, _) {
                  return Text(
                    currentTags.isEmpty ? 'Add Tags' : '${currentTags.length} tags added',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  );
                },
              ),
            ),
            const Icon(Icons.add, size: 20),
          ],
        ),
      ),
    );
  }

  void _showAddTagsBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.backgroundPrimary,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Add Discovery Tags',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: widget.tagInputController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Type and press Add',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.tag),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => widget.onAddTag(widget.tagInputController.text),
                  ),
                ),
                onSubmitted: widget.onAddTag,
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder<List<String>>(
                valueListenable: widget.tags,
                builder: (context, currentTags, _) {
                  if (currentTags.isEmpty) {
                    return const SizedBox(
                      height: 50,
                      child: Center(child: Text('No tags added yet')),
                    );
                  }
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: currentTags
                        .map((tag) => Chip(
                              label: Text(tag),
                              onDeleted: () => widget.onRemoveTag(tag),
                            ))
                        .toList(),
                  );
                },
              ),
              const SizedBox(height: 16),
              AppButton(
                onPressed: () => Navigator.pop(context),
                label: 'Done',
                variant: AppButtonVariant.primary,
                isFullWidth: true,
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMakeEpisodeOption(BuildContext context) {
    return InkWell(
      onTap: widget.onMakeEpisode,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.borderPrimary),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Row(
          children: [
            Icon(Icons.playlist_play, color: AppColors.textPrimary),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Make a Episode', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(
                    'Link this to a series',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 14),
          ],
        ),
      ),
    );
  }
}

