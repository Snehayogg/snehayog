import 'package:flutter/material.dart';
import 'package:vayu/features/profile/core/presentation/managers/profile_state_manager.dart';

class NoticeBannerWidget extends StatelessWidget {
  final ProfileStateManager manager;

  const NoticeBannerWidget({
    super.key,
    required this.manager,
  });

  @override
  Widget build(BuildContext context) {
    final notice = manager.activeNotice;
    if (notice == null) return const SizedBox.shrink();

    final isWarning = notice.isWarning;

    // Mark as seen once displayed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (notice.firstSeenAt == null) {
        manager.markNoticeAsSeen();
      }
    });

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isWarning ? Colors.red.shade50 : Colors.blue.shade50,
        border: Border(
          bottom: BorderSide(
            color: isWarning ? Colors.red.shade200 : Colors.blue.shade200,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isWarning ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
            color: isWarning ? Colors.red.shade700 : Colors.blue.shade700,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              notice.title,
              style: TextStyle(
                color: isWarning ? Colors.red.shade900 : Colors.blue.shade900,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
