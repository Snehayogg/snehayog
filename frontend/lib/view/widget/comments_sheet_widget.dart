import 'package:flutter/material.dart';
import 'package:vayu/model/video_model.dart';
import 'package:vayu/services/video_service.dart';
import 'package:vayu/services/comments/comments_data_source.dart';
import 'package:provider/provider.dart';
import 'package:vayu/controller/google_sign_in_controller.dart';

class CommentsSheetWidget extends StatefulWidget {
  final VideoModel? video;
  final VideoService? videoService;
  final ValueChanged<List<Comment>>? onCommentsUpdated;
  final CommentsDataSource? dataSource; // NEW: pluggable data source

  const CommentsSheetWidget({
    Key? key,
    this.video,
    this.videoService,
    this.onCommentsUpdated,
    this.dataSource,
  }) : super(key: key);

  @override
  State<CommentsSheetWidget> createState() => _CommentsSheetWidgetState();
}

class _CommentsSheetWidgetState extends State<CommentsSheetWidget> {
  late List<Comment> _comments;
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  bool _isPosting = false;

  @override
  void initState() {
    super.initState();
    _comments = widget.video != null
        ? List<Comment>.from(widget.video!.comments)
        : <Comment>[];
    if (widget.dataSource != null) {
      // load first page from data source (ads or videos)
      _loadInitial();
    }
  }

  Future<void> _loadInitial() async {
    setState(() => _isLoading = true);
    try {
      final (items, hasNext) = await widget.dataSource!.fetchComments(page: 1);
      // Map raw maps into lightweight Comment model if available; else skip
      // For now, just ignore mapping and show basic text via fallback path
      // Existing UI relies on Comment type; keep for video path
      // For ads, we will only show newly fetched via simple transform
      // To maintain compatibility, we won't break existing comment model rendering
      // So we won't render fetched raw maps in legacy UI list.
      // However, the primary reuse goal is posting flow; listing stays for video path.
      // hasNext is available but not used in this widget
      setState(() {
        _comments = items.map((item) => Comment.fromJson(item)).toList();
      });
      _scrollToLatestComment();
    } catch (_) {}
    setState(() => _isLoading = false);
  }

  Future<String?> _getCurrentUserId() async {
    final controller =
        Provider.of<GoogleSignInController>(context, listen: false);
    return controller.userData?['id'];
  }

  Future<void> _postComment() async {
    if (_controller.text.trim().isEmpty || _isPosting) return;
    setState(() => _isPosting = true);
    try {
      final userId = await _getCurrentUserId();
      if (userId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in')),
        );
        setState(() => _isPosting = false);
        return;
      }
      if (widget.dataSource != null) {
        // Generic path (ads or videos via data source)
        await widget.dataSource!.postComment(content: _controller.text.trim());
        _controller.clear();

        // Refresh comments after posting
        final (items, hasNext) =
            await widget.dataSource!.fetchComments(page: 1);
        setState(() {
          _comments = items.map((item) => Comment.fromJson(item)).toList();
        });
        _scrollToLatestComment();
      } else {
        // Legacy video path
        final updatedComments = await widget.videoService!.addComment(
          widget.video!.id,
          _controller.text.trim(),
          userId,
        );
        setState(() {
          _comments = updatedComments;
          _controller.clear();
        });
        _scrollToLatestComment();
        widget.onCommentsUpdated?.call(updatedComments);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to post comment')),
      );
    } finally {
      setState(() => _isPosting = false);
    }
  }

  /// **Delete comment method**
  Future<void> _deleteComment(String commentId) async {
    try {
      // Show confirmation dialog
      final shouldDelete = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Comment'),
          content: const Text('Are you sure you want to delete this comment?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );

      if (shouldDelete != true) return;

      // Show loading state
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 12),
              Text('Deleting comment...'),
            ],
          ),
          duration: Duration(seconds: 2),
        ),
      );

      if (widget.dataSource != null) {
        // Use data source for deletion
        await widget.dataSource!.deleteComment(commentId: commentId);

        // Refresh comments from data source
        final (items, hasNext) =
            await widget.dataSource!.fetchComments(page: 1);
        setState(() {
          _comments = items.map((item) => Comment.fromJson(item)).toList();
        });
      } else if (widget.videoService != null && widget.video != null) {
        // Use legacy video service for deletion
        final updatedComments = await widget.videoService!.deleteComment(
          widget.video!.id,
          commentId,
        );

        setState(() {
          _comments = updatedComments;
        });

        // Notify parent widget
        widget.onCommentsUpdated?.call(updatedComments);
      }

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Text('Comment deleted successfully'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      print('❌ Error deleting comment: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Failed to delete comment: ${e.toString()}'),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Text('Comments',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_comments.isEmpty)
            const Center(child: Text('No comments yet.'))
          else
            SizedBox(
              height: 250,
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _comments.length,
                itemBuilder: (context, index) {
                  final comment = _comments[index];
                  final currentUserId = Provider.of<GoogleSignInController>(
                              context,
                              listen: false)
                          .userData?['googleId'] ??
                      Provider.of<GoogleSignInController>(context,
                              listen: false)
                          .userData?['id'];
                  final isOwnComment =
                      currentUserId != null && comment.userId == currentUserId;

                  return ListTile(
                    leading: comment.userProfilePic.isNotEmpty
                        ? CircleAvatar(
                            backgroundImage:
                                NetworkImage(comment.userProfilePic))
                        : const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(comment.userName.isNotEmpty
                        ? comment.userName
                        : 'User'),
                    subtitle: Text(comment.text),
                    trailing: isOwnComment
                        ? PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'delete') {
                                _deleteComment(comment.id);
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete, color: Colors.red),
                                    SizedBox(width: 8),
                                    Text('Delete',
                                        style: TextStyle(color: Colors.red)),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : null,
                  );
                },
              ),
            ),
          const SizedBox(height: 12),
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
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToLatestComment() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }
}
