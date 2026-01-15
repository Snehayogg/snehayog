import 'package:flutter/material.dart';
import 'package:vayu/services/ad_comment_service.dart';
import 'package:vayu/model/carousel_ad_model.dart';
import 'package:vayu/utils/app_logger.dart';

class AdCommentsSheetWidget extends StatefulWidget {
  final CarouselAdModel carouselAd;
  final Function(List<Map<String, dynamic>>)? onCommentsUpdated;

  const AdCommentsSheetWidget({
    Key? key,
    required this.carouselAd,
    this.onCommentsUpdated,
  }) : super(key: key);

  @override
  _AdCommentsSheetWidgetState createState() => _AdCommentsSheetWidgetState();
}

class _AdCommentsSheetWidgetState extends State<AdCommentsSheetWidget> {
  final AdCommentService _adCommentService = AdCommentService();
  final TextEditingController _commentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _comments = [];
  bool _isLoading = false;
  bool _isPosting = false;
  int _currentPage = 1;
  bool _hasMoreComments = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// **LOAD COMMENTS: Fetch comments for the ad**
  Future<void> _loadComments({bool refresh = false}) async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      if (refresh) {
        _currentPage = 1;
        _hasMoreComments = true;
      }
    });

    try {
      final response = await _adCommentService.getAdComments(
        adId: widget.carouselAd.id,
        page: _currentPage,
        limit: 20,
      );

      if (response['success'] == true) {
        final newComments =
            List<Map<String, dynamic>>.from(response['comments'] ?? []);

        setState(() {
          if (refresh) {
            _comments = newComments;
          } else {
            _comments.addAll(newComments);
          }
          _hasMoreComments = response['pagination']?['hasNextPage'] ?? false;
          _currentPage++;
        });

        // Notify parent of comments update
        widget.onCommentsUpdated?.call(_comments);
      } else {
        throw Exception(response['message'] ?? 'Failed to load comments');
      }
    } catch (e) {
      AppLogger.log('❌ Error loading ad comments: $e');
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// **POST COMMENT: Add a new comment**
  Future<void> _postComment() async {
    final content = _commentController.text.trim();
    if (content.isEmpty || _isPosting) return;

    setState(() {
      _isPosting = true;
    });

    try {
      final response = await _adCommentService.addAdComment(
        adId: widget.carouselAd.id,
        content: content,
      );

      if (response['success'] == true) {
        _commentController.clear();

        // Refresh comments to show the new one
        await _loadComments(refresh: true);

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Comment posted successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        throw Exception(response['message'] ?? 'Failed to post comment');
      }
    } catch (e) {
      AppLogger.log('❌ Error posting ad comment: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to post comment: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      setState(() {
        _isPosting = false;
      });
    }
  }

  /// **DELETE COMMENT: Delete a comment**
  Future<void> _deleteComment(String commentId) async {
    try {
      final response = await _adCommentService.deleteAdComment(
        adId: widget.carouselAd.id,
        commentId: commentId,
      );

      if (response['success'] == true) {
        // Remove comment from local list
        setState(() {
          _comments.removeWhere((comment) => comment['_id'] == commentId);
        });

        // Notify parent of comments update
        widget.onCommentsUpdated?.call(_comments);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Comment deleted successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        throw Exception(response['message'] ?? 'Failed to delete comment');
      }
    } catch (e) {
      AppLogger.log('❌ Error deleting ad comment: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete comment: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// **LIKE COMMENT: Like/unlike a comment**
  Future<void> _likeComment(String commentId) async {
    try {
      final response = await _adCommentService.likeAdComment(
        adId: widget.carouselAd.id,
        commentId: commentId,
      );

      if (response['success'] == true) {
        // Update comment in local list
        setState(() {
          final commentIndex =
              _comments.indexWhere((comment) => comment['_id'] == commentId);
          if (commentIndex != -1) {
            _comments[commentIndex] = response['comment'];
          }
        });
      } else {
        throw Exception(response['message'] ?? 'Failed to like comment');
      }
    } catch (e) {
      AppLogger.log('❌ Error liking ad comment: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to like comment: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                const Text(
                  'Comments',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),

          // Comments list
          Expanded(
            child: _buildCommentsList(),
          ),

          // Comment input
          _buildCommentInput(),
        ],
      ),
    );
  }

  Widget _buildCommentsList() {
    if (_isLoading && _comments.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Failed to load comments',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _loadComments(refresh: true),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_comments.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No comments yet',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Be the first to comment!',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadComments(refresh: true),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _comments.length + (_hasMoreComments ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _comments.length) {
            // Load more indicator
            return _buildLoadMoreIndicator();
          }

          final comment = _comments[index];
          return _buildCommentItem(comment);
        },
      ),
    );
  }

  Widget _buildLoadMoreIndicator() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : TextButton(
                onPressed: () => _loadComments(),
                child: const Text('Load more comments'),
              ),
      ),
    );
  }

  Widget _buildCommentItem(Map<String, dynamic> comment) {
    final user = comment['user'] ?? {};
    final userName = user['name'] ?? 'Unknown User';
    final userProfilePic = user['profilePic'] ?? '';
    final content = comment['content'] ?? '';
    final likes = comment['likes'] ?? 0;

    final createdAt = comment['createdAt'] ?? '';
    final commentId = comment['_id'] ?? '';

    // Check if current user liked this comment (you'll need to get current user ID)
    const isLiked = false; 
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User avatar
          CircleAvatar(
            radius: 16,
            backgroundImage:
                userProfilePic.isNotEmpty ? NetworkImage(userProfilePic) : null,
            child: userProfilePic.isEmpty
                ? Text(
                    userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),

          // Comment content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // User name and time
                Row(
                  children: [
                    Text(
                      userName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatTime(createdAt),
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),

                // Comment text
                Text(
                  content,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 8),

                // Like button and count
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => _likeComment(commentId),
                      child: const Icon(
                        isLiked ? Icons.favorite : Icons.favorite_border,
                        color: isLiked ? Colors.red : Colors.grey,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      likes > 0 ? likes.toString() : '',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Delete button (only for own comments)
                    GestureDetector(
                      onTap: () => _deleteComment(commentId),
                      child: Text(
                        'Delete',
                        style: TextStyle(
                          color: Colors.red[600],
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border(
          top: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _commentController,
              decoration: const InputDecoration(
                hintText: 'Write a comment...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
              maxLines: null,
              textInputAction: TextInputAction.newline,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _isPosting ? null : _postComment,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _isPosting ? Colors.grey : Colors.blue,
                shape: BoxShape.circle,
              ),
              child: _isPosting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(
                      Icons.send,
                      color: Colors.white,
                      size: 16,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(String? createdAt) {
    if (createdAt == null || createdAt.isEmpty) return '';

    try {
      final date = DateTime.parse(createdAt);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays > 0) {
        return '${difference.inDays}d ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m ago';
      } else {
        return 'Just now';
      }
    } catch (e) {
      return '';
    }
  }
}
