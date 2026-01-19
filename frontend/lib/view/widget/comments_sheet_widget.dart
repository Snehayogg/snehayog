import 'package:flutter/material.dart';
import 'package:vayu/model/video_model.dart';
import 'package:vayu/services/video_service.dart';
import 'package:vayu/services/comments/comments_data_source.dart';
import 'package:provider/provider.dart';
import 'package:vayu/controller/google_sign_in_controller.dart';
import 'dart:math' as math;

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
    // **FIX: Use MediaQuery to handle keyboard view insets**
    final viewInsets = MediaQuery.of(context).viewInsets;
    final padding = MediaQuery.of(context).padding;
    final screenHeight = MediaQuery.of(context).size.height;
    
    // Calculate Safe Bottom Padding:
    // When keyboard is visible (viewInsets.bottom > 0), typically the sheet is pushed up,
    // so we might not need extra safe area padding, OR we need to be careful not to double pad.
    // However, usually ModalBottomSheet in `isScrollControlled: true` sits on the keyboard.
    // Ideally, we want: BottomInset (Keyboard) + Safe Area (if keyboard closed) + Extra Padding.
    
    final bottomPadding = math.max(viewInsets.bottom, padding.bottom);

    // Limit height but allow expansion
    // When keyboard is open, add its height to the base 50% height
    // so the meaningful content area stays at 50% of the screen.
    final maxHeight = (screenHeight * 0.5) + viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 48,
              height: 5,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
          ),
          
          // **NEW: Enhanced Header with Video Metadata**
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey[100]!)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Comments',
                      style: TextStyle(
                        fontSize: 18, // Slightly refined size
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    if (widget.video != null && widget.video!.comments.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          '${widget.video!.comments.length}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      splashRadius: 20,
                    ),
                  ],
                ),
                // **NEW: Video Stats (Views & Date)**
                if (widget.video != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Icon(Icons.play_circle_outline, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          '${widget.video!.views} views',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        const SizedBox(width: 12),
                        Icon(Icons.calendar_today_outlined, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                         Text(
                          _getFormattedDate(widget.video!.uploadedAt),
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // **Comments List**
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _comments.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 48,
                                color: Colors.grey[400],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No comments yet',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[800],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Be the first to share your thoughts!',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80), // Extra bottom padding for input
                        itemCount: _comments.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 20),
                        itemBuilder: (context, index) {
                          final comment = _comments[index];
                          return _buildCommentItem(comment);
                        },
                      ),
          ),

          // **NEW: Professional Input Area (Fixed at Bottom)**
          Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: bottomPadding > 0 ? bottomPadding + 12 : 34, // Safe area + padding
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  offset: const Offset(0, -4),
                  blurRadius: 16,
                ),
              ],
              border: Border(top: BorderSide(color: Colors.grey[100]!)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.transparent),
                    ),
                    child: TextField(
                      controller: _controller,
                      maxLines: 4,
                      minLines: 1,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        hintText: 'Add a comment...',
                        hintStyle: TextStyle(color: Colors.grey),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12, // Comfortable vertical padding
                        ),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 15),
                      cursorColor: Colors.blue,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _isPosting
                    ? const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      )
                    : Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _controller.text.trim().isNotEmpty
                              ? Colors.blue
                              : Colors.grey[200],
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                          color: _controller.text.trim().isNotEmpty
                              ? Colors.white
                              : Colors.grey[400],
                          onPressed: _controller.text.trim().isNotEmpty && !_isPosting
                              ? _postComment
                              : null,
                          constraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 40,
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // **Helper to build comment item (extracted for cleanliness)**
  Widget _buildCommentItem(Comment comment) {
                          final currentUserId =
                              Provider.of<GoogleSignInController>(context,
                                          listen: false)
                                      .userData?['googleId'] ??
                                  Provider.of<GoogleSignInController>(context,
                                          listen: false)
                                      .userData?['id'];
                          final isOwnComment = currentUserId != null &&
                              comment.userId == currentUserId;

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 18, // Slightly smaller
                                backgroundColor: Colors.grey[200],
                                backgroundImage:
                                    comment.userProfilePic.isNotEmpty
                                        ? NetworkImage(comment.userProfilePic)
                                        : null,
                                child: comment.userProfilePic.isEmpty
                                    ? Icon(Icons.person, color: Colors.grey[400], size: 20)
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
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                            color: Colors.grey[800]
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          _getTimeAgo(comment.createdAt),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[500],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      comment.text,
                                      style: TextStyle(
                                        fontSize: 14, 
                                        color: Colors.grey[800], 
                                        height: 1.3
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    // Reply action placeholder (can be implemented later)
                                    Text(
                                      'Reply',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                                if (isOwnComment)
                                  PopupMenuButton<String>(
                                    icon: Icon(
                                      Icons.more_vert,
                                      size: 16,
                                      color: Colors.grey[400],
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
                                        height: 32,
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete_outline,
                                                color: Colors.red, size: 18),
                                            SizedBox(width: 8),
                                            Text('Delete',
                                                style: TextStyle(
                                                    color: Colors.red, fontSize: 14)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                            ],
                          );
  }

  // **Helper for date formatting**
  String _getFormattedDate(DateTime? date) {
    if (date == null || date.year == 1970) return '';
    return "${date.day}/${date.month}/${date.year}";
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
