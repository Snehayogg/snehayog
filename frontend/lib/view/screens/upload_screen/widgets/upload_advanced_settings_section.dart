import 'package:flutter/material.dart';

class UploadAdvancedSettingsSection extends StatelessWidget {
  final ValueNotifier<bool> isExpanded;
  final VoidCallback onToggle;
  final ValueNotifier<String?> videoType;
  final void Function(String?) onVideoTypeChanged;
  final TextEditingController linkController;
  final TextEditingController tagInputController;
  final ValueNotifier<List<String>> tags;
  final void Function(String) onAddTag;
  final void Function(String) onRemoveTag;

  const UploadAdvancedSettingsSection({
    super.key,
    required this.isExpanded,
    required this.onToggle,
    required this.videoType,
    required this.onVideoTypeChanged,
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
              'Optional: configure paid videos, tags, and external links',
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
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade100),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline,
                              size: 18, color: Colors.blue),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Paid videos appear in the Vayu tab. Free videos stay in Yug. '
                              'Use tags and link to help viewers discover your content.',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                color: Colors.blueGrey,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildVideoTypeSelector(),
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

  Widget _buildVideoTypeSelector() {
    return ValueListenableBuilder<String?>(
      valueListenable: videoType,
      builder: (context, selectedType, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Video Type',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            _buildVideoTypeTile(
              value: 'free',
              selectedValue: selectedType,
              title: 'Free (Yug tab)',
              subtitle: 'Video is available for everyone in the Yug feed.',
            ),
            _buildVideoTypeTile(
              value: 'paid',
              selectedValue: selectedType,
              title: 'Paid (Vayu tab)',
              subtitle:
                  'Video is reserved for paying users and shows under Vayu.',
            ),
            if (selectedType != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => onVideoTypeChanged(null),
                  icon: const Icon(Icons.undo, size: 18),
                  label: const Text('Reset to default (Yug)'),
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildVideoTypeTile({
    required String value,
    required String? selectedValue,
    required String title,
    required String subtitle,
  }) {
    return RadioListTile<String>(
      value: value,
      groupValue: selectedValue,
      onChanged: onVideoTypeChanged,
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12),
      ),
    );
  }

  Widget _buildLinkField() {
    return TextField(
      controller: linkController,
      decoration: const InputDecoration(
        labelText: 'External Link (optional)',
        hintText: 'Add a website, social media, etc.',
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
