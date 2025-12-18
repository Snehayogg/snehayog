import 'package:flutter/material.dart';
import 'package:vayu/core/constants/interests.dart';

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
              'Advanced Settings',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'Optional: configure metadata, tags, and external links',
              style: TextStyle(fontSize: 12),
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
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAutoFillNotice(),
                    const SizedBox(height: 16),
                    _buildTitleField(),
                    const SizedBox(height: 16),
                    _buildCategorySelector(),
                    const SizedBox(height: 16),
                    _buildLinkField(),
                    const SizedBox(height: 16),
                    _buildTagInput(),
                    ValueListenableBuilder<List<String>>(
                      valueListenable: tags,
                      builder: (context, currentTags, _) {
                        if (currentTags.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 12),
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
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAutoFillNotice() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.flash_on, size: 16, color: Colors.blue),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Quick uploads auto-fill the title from the filename and use your default category. Update below if you need custom metadata.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.blueGrey.shade700,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTitleField() {
    return TextField(
      controller: titleController,
      decoration: const InputDecoration(
        labelText: 'Video Title',
        hintText: 'Update the auto-generated title',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.title),
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
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.category),
            helperText: 'Choose a category to improve targeting',
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
        labelText: 'External Link (Visit Now)',
        hintText: 'Add product or website URL (e.g. https://yourstore.com)',
        helperText:
            'Optional for normal videos. Required if you upload a product image so users can Visit Now.',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.link),
      ),
      keyboardType: TextInputType.url,
    );
  }

  Widget _buildTagInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tags (optional)',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: tagInputController,
          decoration: InputDecoration(
            hintText: 'Type a tag and press Add',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.tag),
            suffixIcon: IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => onAddTag(tagInputController.text),
            ),
          ),
          onSubmitted: onAddTag,
        ),
      ],
    );
  }
}
