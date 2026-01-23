import 'package:flutter/material.dart';
import 'package:vayu/core/constants/interests.dart';
import 'package:vayu/view/screens/make_episode_screen.dart';

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
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Icons.tune, color: Colors.blue),
            title: const Text(
              'Advanced Options',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),

            trailing: ValueListenableBuilder<bool>(
              valueListenable: isExpanded,
              builder: (context, expanded, _) {
                return Icon(
                  expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: Colors.blue,
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    _buildTitleField(),
                    const SizedBox(height: 16),
                    _buildCategorySelector(),
                    const SizedBox(height: 16),
                    _buildLinkField(),
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
      ),
    );
  }



  Widget _buildTitleField() {
    return TextField(
      controller: titleController,
      decoration: InputDecoration(
        labelText: 'Video Title',
        labelStyle: const TextStyle(color: Colors.black87),
        hintText: 'Update the auto-generated title',
        hintStyle: TextStyle(color: Colors.grey.withOpacity(0.4)),
        filled: false,
        fillColor: Colors.transparent,
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.title),
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
            prefixIcon: Icon(Icons.category),
            helperText: null,
            labelStyle: const TextStyle(color: Colors.black87),
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

  Widget _buildLinkField() {
    return TextField(
      controller: linkController,
      decoration: const InputDecoration(
        labelText: '',
        hintText: 'Add a website link',
        hintStyle:  TextStyle(color: Colors.grey, fontSize: 12),
        helperText: 'Promote your business',
        labelStyle:  TextStyle(color: Colors.grey, fontSize: 12),
        filled: false,
        fillColor: Colors.transparent,
        border:  OutlineInputBorder(),
        prefixIcon:  Icon(Icons.link),
      ),
      keyboardType: TextInputType.url,
    );
  }

  Widget _buildTagInput(BuildContext context) {
    return InkWell(
      onTap: () => _showAddTagsBottomSheet(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          children: [
            const Icon(Icons.tag, color: Colors.black),
            const SizedBox(width: 16),
            const Expanded(
              child: Text(
                'Add Tags',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.black87,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add, color: Colors.black),
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
                  const Text(
                    'Add Tags',
                    style: TextStyle(
                      fontSize: 18,
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
                  hintStyle: TextStyle(color: Colors.grey.withOpacity(0.4)),
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
                          style: TextStyle(color: Colors.grey),
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
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          children: [
            const Icon(Icons.playlist_play, color: Colors.black),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Make a Episode',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  ),
                  Text(
                    'Create a series by selecting multiple videos',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.black),
          ],
        ),
      ),
    );
  }
}
