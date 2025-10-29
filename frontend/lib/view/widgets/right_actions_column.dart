import 'package:flutter/material.dart';
import 'package:vayu/view/widgets/vertical_action_button.dart';

class RightActionsColumn extends StatelessWidget {
  final bool isLiked;
  final int likes;
  final int comments;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback onSwipe;

  const RightActionsColumn({
    super.key,
    required this.isLiked,
    required this.likes,
    required this.comments,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    required this.onSwipe,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: 20,
      child: Column(
        children: [
          VerticalActionButton(
            icon: isLiked ? Icons.favorite : Icons.favorite_border,
            color: isLiked ? Colors.red : Colors.white,
            count: likes,
            onTap: onLike,
          ),
          const SizedBox(height: 12),
          VerticalActionButton(
            icon: Icons.chat_bubble_outline,
            count: comments,
            onTap: onComment,
          ),
          const SizedBox(height: 12),
          VerticalActionButton(
            icon: Icons.share,
            onTap: onShare,
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onSwipe,
            child: const Column(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.black54,
                  radius: 20,
                  child: Icon(Icons.arrow_forward_ios,
                      color: Colors.white, size: 20),
                ),
                SizedBox(height: 4),
                Text(
                  'Swipe',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
