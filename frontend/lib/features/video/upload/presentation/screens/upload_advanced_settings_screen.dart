import 'package:flutter/material.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/shared/widgets/app_button.dart';
import 'package:vayug/features/video/quiz/presentation/screens/create_quiz_screen.dart';
import 'package:vayug/features/profile/core/data/services/user_service.dart';
import 'package:vayug/shared/utils/app_logger.dart';

class UploadAdvancedSettingsScreen extends StatefulWidget {
  final TextEditingController linkController;
  final TextEditingController tagInputController;
  final ValueNotifier<List<String>> tags;
  final void Function(String) onAddTag;
  final void Function(String) onRemoveTag;
  final VoidCallback onMakeEpisode;
  final ValueNotifier<List<QuizModel>> quizzes;
  final ValueNotifier<List<String>> selectedPlatforms;
  final ValueNotifier<List<String>> selectedSubscribers;
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
    required this.selectedSubscribers,
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

                _buildSubscriberOnlyTile(),

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
            activeTrackColor: AppColors.primary,
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

  Widget _buildSubscriberOnlyTile() {
    return ValueListenableBuilder<List<String>>(
      valueListenable: widget.selectedSubscribers,
      builder: (context, selected, _) {
        return _buildSettingRow(
          icon: Icons.lock_person,
          title: 'Subscriber Only',
          subtitle: selected.isEmpty
              ? 'Share with specific subscribers'
              : '${selected.length} subscriber${selected.length == 1 ? '' : 's'} selected',
          trailing: selected.isEmpty
              ? null
              : Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${selected.length}',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
          onTap: () => _showSubscriberSelectionBottomSheet(context),
        );
      },
    );
  }

  void _showSubscriberSelectionBottomSheet(BuildContext context) {
    Navigator.push(
      context,
        MaterialPageRoute(
          builder: (context) => SubscriberSelectionSheet(
            selectedSubscribers: widget.selectedSubscribers,
          ),
      ),
    );
  }
}

class SubscriberSelectionSheet extends StatefulWidget {
  final ValueNotifier<List<String>> selectedSubscribers;

  const SubscriberSelectionSheet({
    super.key,
    required this.selectedSubscribers,
  });

  @override
  State<SubscriberSelectionSheet> createState() => _SubscriberSelectionSheetState();
}

class _SubscriberSelectionSheetState extends State<SubscriberSelectionSheet> {
  final TextEditingController _searchController = TextEditingController();
  final ValueNotifier<List<Subscriber>> _subscribers = ValueNotifier<List<Subscriber>>([]);
  final ValueNotifier<bool> _isLoading = ValueNotifier<bool>(true);
  final ValueNotifier<String?> _error = ValueNotifier<String?>(null);
  final UserService _userService = UserService();

  @override
  void initState() {
    super.initState();
    _fetchSubscribers();
  }

  Future<void> _fetchSubscribers() async {
    try {
      _isLoading.value = true;
      _error.value = null;

      AppLogger.log('📡 Fetching subscribers from backend...');
      final subscribers = await _userService.getSubscribers();
      _subscribers.value = subscribers;
      AppLogger.log('✅ Fetched ${subscribers.length} subscribers');
    } catch (e) {
      AppLogger.log('❌ Failed to fetch subscribers: $e');
      _error.value = 'Failed to load subscribers: $e';
    } finally {
      _isLoading.value = false;
    }
  }

  List<Subscriber> get _filteredSubscribers {
    final query = _searchController.text.toLowerCase().trim();
    if (query.isEmpty) return _subscribers.value;

    return _subscribers.value.where((sub) {
      return sub.name.toLowerCase().contains(query) ||
             sub.email.toLowerCase().contains(query);
    }).toList();
  }

  bool _isSelected(String subscriberId) {
    return widget.selectedSubscribers.value.contains(subscriberId);
  }

  void _toggleSelection(String subscriberId) {
    final current = List<String>.from(widget.selectedSubscribers.value);
    if (current.contains(subscriberId)) {
      current.remove(subscriberId);
    } else {
      current.add(subscriberId);
    }
    widget.selectedSubscribers.value = current;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _subscribers.dispose();
    _isLoading.dispose();
    _error.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.borderPrimary),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_person, color: AppColors.primary),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Select Subscribers',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name or email',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: AppColors.backgroundSecondary,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),

          // Selected subscribers chips
          ValueListenableBuilder<List<String>>(
            valueListenable: widget.selectedSubscribers,
            builder: (context, selected, _) {
              if (selected.isEmpty) return const SizedBox.shrink();

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Selected',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: selected.map((id) {
                    final subscriber = _subscribers.value.firstWhere(
                      (s) => s.id == id,
                      orElse: () => Subscriber(id: id, name: 'Unknown', email: '', profilePic: null),
                    );
                    return Chip(
                      label: Text(subscriber.name),
                      deleteIcon: const Icon(Icons.close, size: 18),
                      onDeleted: () => _toggleSelection(id),
                      avatar: subscriber.profilePic != null
                          ? CircleAvatar(
                              backgroundImage: NetworkImage(subscriber.profilePic!),
                              radius: 12,
                            )
                          : CircleAvatar(
                              radius: 12,
                              child: Text(
                                subscriber.name.isNotEmpty ? subscriber.name[0].toUpperCase() : '?',
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                    );
                  }).toList(),
                ),
                    const Divider(height: 24),
                  ],
                ),
              );
            },
          ),

          // Subscribers list
          Expanded(
            child: ValueListenableBuilder<bool>(
              valueListenable: _isLoading,
              builder: (context, loading, _) {
                if (loading) {
                  return const Center(child: CircularProgressIndicator());
                }

                return ValueListenableBuilder<String?>(
                  valueListenable: _error,
                  builder: (context, error, _) {
                    if (error != null) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                            const SizedBox(height: 16),
                            Text(error, textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            AppButton(
                              onPressed: _fetchSubscribers,
                              label: 'Retry',
                              variant: AppButtonVariant.outline,
                            ),
                          ],
                        ),
                      );
                    }

                    final filtered = _filteredSubscribers;

                    if (filtered.isEmpty) {
                      return const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_off, size: 48, color: AppColors.textSecondary),
                            SizedBox(height: 16),
                             Text('No subscribers found'),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final subscriber = filtered[index];
                        final isSelected = _isSelected(subscriber.id);

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: subscriber.profilePic != null
                                ? NetworkImage(subscriber.profilePic!)
                                : null,
                            child: subscriber.profilePic == null
                                ? Text(
                                    subscriber.name.isNotEmpty ? subscriber.name[0].toUpperCase() : '?',
                                  )
                                : null,
                          ),
                          title: Text(subscriber.name),
                          subtitle: Text(subscriber.email),
                          trailing: Checkbox(
                            value: isSelected,
                            onChanged: (_) => _toggleSelection(subscriber.id),
                          ),
                          onTap: () => _toggleSelection(subscriber.id),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),

          // Bottom action bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: AppColors.backgroundPrimary,
              border: Border(
                top: BorderSide(color: AppColors.borderPrimary),
              ),
            ),
            child: ValueListenableBuilder<List<String>>(
              valueListenable: widget.selectedSubscribers,
              builder: (context, selected, _) {
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${selected.length} subscriber${selected.length == 1 ? '' : 's'} selected',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    AppButton(
                      onPressed: selected.isEmpty ? null : () => Navigator.pop(context),
                      label: 'Done',
                      variant: AppButtonVariant.primary,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

