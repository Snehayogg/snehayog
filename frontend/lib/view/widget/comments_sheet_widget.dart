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
    try {
      final controller =
          Provider.of<GoogleSignInController>(context, listen: false);
      // **FIX: Use googleId first, then fallback to id**
      return controller.userData?['googleId'] ?? controller.userData?['id'];
    } catch (e) {
      print('❌ CommentsSheet: Error getting user ID: $e');
      return null;
    }
  }

  Future<void> _postComment() async {
    if (_controller.text.trim().isEmpty || _isPosting) return;

    setState(() => _isPosting = true);
    try {
      // **FIX: Check if user is signed in first**
      final userId = await _getCurrentUserId();
      if (userId == null || userId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please sign in to comment'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isPosting = false);
        return;
      }

      print(
          '💬 CommentsSheet: Posting comment with userId: ${userId.substring(0, 8)}...');

      if (widget.dataSource != null) {
        // Generic path (ads or videos via data source)
        print('💬 CommentsSheet: Using data source to post comment');
        await widget.dataSource!.postComment(content: _controller.text.trim());
        _controller.clear();

        // Refresh comments after posting
        final (items, hasNext) =
            await widget.dataSource!.fetchComments(page: 1);
        setState(() {
          _comments = items.map((item) => Comment.fromJson(item)).toList();
        });
        _scrollToLatestComment();
        print('✅ CommentsSheet: Comment posted successfully via data source');
      } else if (widget.videoService != null && widget.video != null) {
        // Legacy video path
        print('💬 CommentsSheet: Using legacy video service to post comment');
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
        print('✅ CommentsSheet: Comment posted successfully via legacy path');
      } else {
        throw Exception('No data source or video service available');
      }
    } catch (e) {
      print('❌ CommentsSheet: Error posting comment: $e');
      // **FIX: Show actual error message**
      String errorMessage = 'Failed to post comment';
      final errorString = e.toString();

      if (errorString.contains('sign in') ||
          errorString.contains('authenticated')) {
        errorMessage = 'Please sign in to comment';
      } else if (errorString.contains('User not found')) {
        errorMessage = 'User not found. Please sign in again.';
      } else if (errorString.contains('User ID not found')) {
        errorMessage = 'User ID not found. Please sign in again.';
      } else if (errorString.length > 100) {
        errorMessage = errorString.substring(0, 100);
      } else {
        errorMessage = errorString.replaceAll('Exception: ', '');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
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
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.7; // 70% of screen height

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text(
                  'Comments',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Comment input - Moved to top for better visibility
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[50],
              border: Border(
                bottom: BorderSide(color: Colors.grey[200]!),
              ),
            ),
            padding: const EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: 8,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Add a comment...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    minLines: 1,
                    maxLines: 3,
                  ),
                ),
                const SizedBox(width: 8),
                _isPosting
                    ? const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: Icon(
                          Icons.send,
                          color: _controller.text.trim().isNotEmpty
                              ? Colors.blue
                              : Colors.grey,
                        ),
                        onPressed:
                            _controller.text.trim().isNotEmpty && !_isPosting
                                ? _postComment
                                : null,
                      ),
              ],
            ),
          ),
          // Comments list or empty state - Flexible to allow text field to show
          Flexible(
            child: _isLoading
                ? const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _comments.isEmpty
                    ? const SizedBox(
                        height: 200,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 64,
                                color: Colors.grey,
                              ),
                              SizedBox(height: 16),
                              Text(
                                'No comments yet.',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _comments.length,
                        itemBuilder: (context, index) {
                          final comment = _comments[index];
                          final currentUserId =
                              Provider.of<GoogleSignInController>(context,
                                          listen: false)
                                      .userData?['googleId'] ??
                                  Provider.of<GoogleSignInController>(context,
                                          listen: false)
                                      .userData?['id'];
                          final isOwnComment = currentUserId != null &&
                              comment.userId == currentUserId;

                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundImage:
                                      comment.userProfilePic.isNotEmpty
                                          ? NetworkImage(comment.userProfilePic)
                                          : null,
                                  child: comment.userProfilePic.isEmpty
                                      ? const Icon(Icons.person)
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            comment.userName.isNotEmpty
                                                ? comment.userName
                                                : 'User',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            _getTimeAgo(comment.createdAt),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        comment.text,
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isOwnComment)
                                  PopupMenuButton<String>(
                                    icon: Icon(
                                      Icons.more_vert,
                                      size: 18,
                                      color: Colors.grey[600],
                                    ),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
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
                                            Icon(Icons.delete,
                                                color: Colors.red, size: 20),
                                            SizedBox(width: 8),
                                            Text('Delete',
                                                style: TextStyle(
                                                    color: Colors.red)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  String _getTimeAgo(DateTime? dateTime) {
    if (dateTime == null) return '';
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 365) {
      return '${(difference.inDays / 365).floor()}y ago';
    } else if (difference.inDays > 30) {
      return '${(difference.inDays / 30).floor()}mo ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
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
