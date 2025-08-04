import 'package:flutter/material.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/services/video_service.dart';
import 'package:provider/provider.dart';
import 'package:snehayog/controller/google_sign_in_controller.dart';

class CommentsSheetWidget extends StatefulWidget {
  final VideoModel video;
  final VideoService videoService;
  final ValueChanged<List<Comment>> onCommentsUpdated;

  const CommentsSheetWidget({
    Key? key,
    required this.video,
    required this.videoService,
    required this.onCommentsUpdated,
  }) : super(key: key);

  @override
  State<CommentsSheetWidget> createState() => _CommentsSheetWidgetState();
}

class _CommentsSheetWidgetState extends State<CommentsSheetWidget> {
  late List<Comment> _comments;
  final TextEditingController _controller = TextEditingController();
  final bool _isLoading = false;
  bool _isPosting = false;

  @override
  void initState() {
    super.initState();
    _comments = List<Comment>.from(widget.video.comments);
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
      final updatedComments = await widget.videoService.addComment(
        widget.video.id,
        _controller.text.trim(),
        userId,
      );
      setState(() {
        _comments = updatedComments;
        _controller.clear();
      });
      widget.onCommentsUpdated(updatedComments);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to post comment')),
      );
    } finally {
      setState(() => _isPosting = false);
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
                itemCount: _comments.length,
                itemBuilder: (context, index) {
                  final comment = _comments[index];
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
    super.dispose();
  }
}
