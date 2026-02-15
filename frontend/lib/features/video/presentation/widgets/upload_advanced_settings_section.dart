import 'package:flutter/material.dart';
import 'package:vayu/shared/theme/app_theme.dart';
import 'package:vayu/features/video/presentation/screens/make_episode_screen.dart';
import 'package:vayu/shared/constants/interests.dart';


class UploadAdvancedSettingsSection extends StatelessWidget {
  final ValueNotifier<bool> isExpanded;
  final VoidCallback onToggle;
  final TextEditingController titleController;
  final ValueNotifier<String?> selectedCategory;
  final String defaultCategory;
  final void Function(String?) onCategoryChanged;
  final TextEditingController linkController;
  final TextEditingController tagInputController;
  final ValueNotifier<List<String>> tags;
  final void Function(String) onAddTag;
  final void Function(String) onRemoveTag;

  const UploadAdvancedSettingsSection({
    super.key,
    required this.isExpanded,
    required this.onToggle,
    required this.titleController,
    required this.selectedCategory,
    required this.defaultCategory,
    required this.onCategoryChanged,
    required this.linkController,
    required this.tagInputController,
    required this.tags,
    required this.onAddTag,
    required this.onRemoveTag,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8), // **FIX: Reduce header padding**
            leading: const Icon(Icons.tune, color: AppTheme.primary),
            title: Text(
              'Advanced Options',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),

            trailing: ValueListenableBuilder<bool>(
              valueListenable: isExpanded,
              builder: (context, expanded, _) {
                return Icon(
                  expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: AppTheme.primary,
                );
              },
            ),
            onTap: onToggle,
          ),
          ValueListenableBuilder<bool>(
            valueListenable: isExpanded,
            builder: (context, expanded, _) {
              if (!expanded) {
                return const SizedBox.shrink();
              }

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0), // Add slight internal padding for aesthetics
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    _buildTitleField(context),
                    const SizedBox(height: 16),
                    _buildCategorySelector(),
                    const SizedBox(height: 16),
                    _buildLinkField(context),
                    const SizedBox(height: 16),
                    _buildTagInput(context),
                    const SizedBox(height: 16),
                    _buildMakeEpisodeOption(context),

                  ],
                ),
              );
            },
          ),
        ],
      );
  }


  Widget _buildTitleField(BuildContext context) {
    return TextField(
      controller: titleController,
      minLines: 2,
      maxLines: 2,
      decoration: InputDecoration(
        labelText: '',
        floatingLabelBehavior: FloatingLabelBehavior.always,
        labelStyle: Theme.of(context).textTheme.bodyMedium,
        hintText: 'Write a title',
        hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppTheme.textSecondary.withValues(alpha: 0.4),
            ),
        filled: false,
        fillColor: Colors.transparent,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), // Standardized padding
        prefixIcon: const Icon(Icons.title, size: 20),
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _buildCategorySelector() {
    return ValueListenableBuilder<String?>(
      valueListenable: selectedCategory,
      builder: (context, currentValue, _) {
        final options = [
          ...kInterestOptions.where((c) => c != 'Custom Interest'),
          if (!kInterestOptions.contains(defaultCategory)) defaultCategory,
        ];
        final effectiveValue = currentValue ??
            (options.contains(defaultCategory)
                ? defaultCategory
                : options.first);
        return DropdownButtonFormField<String>(
          initialValue: effectiveValue,
          decoration: const InputDecoration(
            labelText: 'Video Category',
            filled: false,
            fillColor: Colors.transparent,
            border: OutlineInputBorder(),
            helperText: null,
            labelStyle: TextStyle(color: AppTheme.textSecondary),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10), // Standardized padding
          ),
          items: options
              .map(
                (c) => DropdownMenuItem<String>(
                  value: c,
                  child: Text(c),
                ),
              )
              .toList(),
          onChanged: onCategoryChanged,
        );
      },
    );
  }

  Widget _buildLinkField(BuildContext context) {
    return TextField(
      controller: linkController,
      decoration: InputDecoration(
        labelText: '',
        floatingLabelBehavior: FloatingLabelBehavior.always,
        hintText: 'Add a website link',
        hintStyle: Theme.of(context).textTheme.bodySmall,
        helperText: 'Promote your business',
        labelStyle: Theme.of(context).textTheme.bodySmall,
        filled: false,
        fillColor: Colors.transparent,
        border:  const OutlineInputBorder(),
        prefixIcon:  const Icon(Icons.link, size: 20),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), // Standardized padding
      ),
      keyboardType: TextInputType.url,
    );
  }

  Widget _buildTagInput(BuildContext context) {
    return InkWell(
      onTap: () => _showAddTagsBottomSheet(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.0),
        child: Row(
          children: [
            const SizedBox(width: 8), // **FIX: Reduced spacer**
            Expanded(
              child: Text(
                'Add Tags',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add, color: AppTheme.textPrimary),
              onPressed: () => _showAddTagsBottomSheet(context),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddTagsBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.backgroundPrimary,
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
                    'Add Tags',
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
                controller: tagInputController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Type a tag and press Add',
                  hintStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.4)),
                  filled: false,
                  fillColor: Colors.transparent,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.tag),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () {
                      onAddTag(tagInputController.text);
                      // Keep the bottom sheet open for adding more tags
                    },
                  ),
                ),
                onSubmitted: (value) {
                  onAddTag(value);
                  // Keep the bottom sheet open
                },
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder<List<String>>(
                valueListenable: tags,
                builder: (context, currentTags, _) {
                  if (currentTags.isEmpty) {
                    return const SizedBox(
                      height: 50,
                      child: Center(
                        child: Text(
                          'No tags added yet',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      ),
                    );
                  }
                  return Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: currentTags
                            .map(
                              (tag) => Chip(
                                label: Text(tag),
                                onDeleted: () => onRemoveTag(tag),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Done'),
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
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const MakeEpisodeScreen(),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.0),
        child: Row(
          children: [
            const Icon(Icons.playlist_play, color: AppTheme.textPrimary),
            const SizedBox(width: 8), // **FIX: Reduced spacer**
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                    Text(
                    'Make a Episode',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const Text(
                    'Create a series by selecting multiple videos',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
           const Icon(Icons.arrow_forward_ios, size: 16, color: AppTheme.textPrimary),
          ],
        ),
      ),
    );
  }
}
