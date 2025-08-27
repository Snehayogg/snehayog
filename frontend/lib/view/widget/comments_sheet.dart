import 'package:flutter/material.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/services/instagram_video_service.dart';
import 'package:snehayog/controller/google_sign_in_controller.dart';
import 'package:provider/provider.dart';

/// Bottom sheet widget for displaying and adding comments to a video
class CommentsSheet extends StatefulWidget {
  final VideoModel video; // Video to show comments for
  final InstagramVideoService
      videoService; // Service to handle comment operations
  final ValueChanged<List<Comment>>
      onCommentsUpdated; // Callback when comments change

  const CommentsSheet({
    Key? key,
    required this.video,
    required this.videoService,
    required this.onCommentsUpdated,
  }) : super(key: key);

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

/// State class for CommentsSheet that manages comment display and posting
class _CommentsSheetState extends State<CommentsSheet> {
  // Local copy of comments to manage state
  late List<Comment> _comments;

  // Text controller for the comment input field
  final TextEditingController _controller = TextEditingController();

  // Loading states
  final bool _isLoading = false; // Loading comments state
  bool _isPosting = false; // Posting comment state

  @override
  void initState() {
    super.initState();
    // Initialize with comments from the video
    _comments = List<Comment>.from(widget.video.comments);
  }

  /// Get the current user ID from the Google Sign-In controller
  Future<String?> _getCurrentUserId() async {
    final controller =
        Provider.of<GoogleSignInController>(context, listen: false);
    return controller.userData?['id'];
  }

  /// Post a new comment to the video
  Future<void> _postComment() async {
    // Validate input and prevent multiple simultaneous posts
    if (_controller.text.trim().isEmpty || _isPosting) return;

    setState(() => _isPosting = true);

    try {
      // Get current user ID for the comment
      final userId = await _getCurrentUserId();
      if (userId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in to comment')),
        );
        setState(() => _isPosting = false);
        return;
      }

      // Add comment via API
      final updatedComments = await widget.videoService.addComment(
        widget.video.id,
        _controller.text.trim(),
        userId,
      );

      // Update local state and clear input
      setState(() {
        // Convert Map<String, dynamic> back to Comment objects
        _comments = updatedComments
            .map((commentMap) => Comment.fromJson(commentMap))
            .toList();
        _controller.clear();
      });

      // Notify parent widget of comment update
      // Convert Map<String, dynamic> back to Comment objects
      final commentObjects = updatedComments
          .map((commentMap) => Comment.fromJson(commentMap))
          .toList();
      widget.onCommentsUpdated(commentObjects);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add comment: $e')),
      );
    } finally {
      setState(() => _isPosting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom:
            MediaQuery.of(context).viewInsets.bottom, // Account for keyboard
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle for the bottom sheet
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title
          const Text('Comments',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          // Comments list or loading/empty states
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_comments.isEmpty)
            const Center(child: Text('No comments yet.'))
          else
            SizedBox(
              height: 250,
              child: ListView.builder(
                itemCount: _comments.length,
                itemBuilder: (context, index) {
                  final comment = _comments[index];
                  return ListTile(
                    // User avatar
                    leading: comment.userProfilePic.isNotEmpty
                        ? CircleAvatar(
                            backgroundImage:
                                NetworkImage(comment.userProfilePic))
                        : const CircleAvatar(child: Icon(Icons.person)),
                    // User name
                    title: Text(comment.userName.isNotEmpty
                        ? comment.userName
                        : 'User'),
                    // Comment text
                    subtitle: Text(comment.text),
                  );
                },
              ),
            ),
          const SizedBox(height: 12),

          // Comment input field and send button
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    hintText: 'Add a comment...',
                    border: OutlineInputBorder(),
                  ),
                  minLines: 1,
                  maxLines: 3,
                ),
              ),
              const SizedBox(width: 8),

              // Show loading indicator or send button
              _isPosting
                  ? const CircularProgressIndicator(strokeWidth: 2)
                  : IconButton(
                      icon: const Icon(Icons.send),
                      onPressed: _postComment,
                    ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Clean up text controller
    _controller.dispose();
    super.dispose();
  }
}
