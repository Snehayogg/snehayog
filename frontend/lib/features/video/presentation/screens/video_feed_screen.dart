import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/video_provider.dart';
import '../widgets/video_loading_states.dart';
import '../../../../core/di/dependency_injection.dart';

/// Video feed screen that demonstrates the new modular architecture
/// This screen uses the VideoProvider for state management
class VideoFeedScreen extends StatefulWidget {
  const VideoFeedScreen({super.key});

  @override
  State<VideoFeedScreen> createState() => _VideoFeedScreenState();
}

class _VideoFeedScreenState extends State<VideoFeedScreen> {
  late VideoProvider _videoProvider;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Get the VideoProvider from the service locator
    _videoProvider = serviceLocator.createVideoProvider();

    // Load initial videos
    _videoProvider.loadVideos();

    // Add scroll listener for pagination
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      // Load more videos when user is near the bottom
      if (!_videoProvider.isLoading && _videoProvider.hasMore) {
        _videoProvider.loadMoreVideos();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _videoProvider,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Snehayog Videos'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _videoProvider.refreshVideos(),
            ),
          ],
        ),
        body: Consumer<VideoProvider>(
          builder: (context, provider, child) {
            // Show error if any
            if (provider.error != null) {
              return _buildErrorWidget(provider);
            }

            // Show loading state
            if (provider.videos.isEmpty && provider.isLoading) {
              return const VideoLoadingStates();
            }

            // Show videos
            return RefreshIndicator(
              onRefresh: provider.refreshVideos,
              child: ListView.builder(
                controller: _scrollController,
                itemCount: provider.videos.length + (provider.hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == provider.videos.length) {
                    // Show loading indicator at the bottom
                    return _buildLoadingIndicator();
                  }

                  final video = provider.videos[index];
                  return Card(
                    margin: const EdgeInsets.all(8.0),
                    child: ListTile(
                      title: Text(video.title),
                      subtitle: Text(video.description),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.favorite_border),
                            onPressed: () => provider.toggleLike(
                                video.id, 'current_user_id'),
                          ),
                          IconButton(
                            icon: const Icon(Icons.comment_outlined),
                            onPressed: () => provider.addComment(
                              videoId: video.id,
                              text: 'Comment',
                              userId: 'current_user_id',
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showUploadDialog(context),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildErrorWidget(VideoProvider provider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.red,
          ),
          const SizedBox(height: 16),
          Text(
            'Error loading videos',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            provider.error!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              provider.clearError();
              provider.loadVideos(refresh: true);
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return const Padding(
      padding: EdgeInsets.all(16.0),
      child: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }

  void _showUploadDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const VideoUploadDialog(),
    );
  }
}

/// Dialog for uploading videos
class VideoUploadDialog extends StatefulWidget {
  const VideoUploadDialog({super.key});

  @override
  State<VideoUploadDialog> createState() => _VideoUploadDialogState();
}

class _VideoUploadDialogState extends State<VideoUploadDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _linkController = TextEditingController();
  String? _selectedVideoPath;
  bool _isUploading = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Upload Video'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'Enter video title',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a title';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Enter video description',
              ),
              maxLines: 3,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a description';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _linkController,
              decoration: const InputDecoration(
                labelText: 'Link (Optional)',
                hintText: 'Enter related link',
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isUploading ? null : _selectVideo,
              child: Text(_selectedVideoPath != null
                  ? 'Video Selected'
                  : 'Select Video'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isUploading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isUploading ? null : _uploadVideo,
          child: _isUploading
              ? const CircularProgressIndicator(strokeWidth: 2)
              : const Text('Upload'),
        ),
      ],
    );
  }

  void _selectVideo() async {
    // TODO: Implement video selection
    // This would typically use image_picker or file_picker
    setState(() {
      _selectedVideoPath = '/path/to/selected/video.mp4';
    });
  }

  void _uploadVideo() async {
    if (!_formKey.currentState!.validate() || _selectedVideoPath == null) {
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      final provider = context.read<VideoProvider>();
      final success = await provider.uploadVideo(
        videoPath: _selectedVideoPath!,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        link: _linkController.text.trim().isEmpty
            ? null
            : _linkController.text.trim(),
      );

      if (success && mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video uploaded successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }
}
