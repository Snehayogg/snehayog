import 'package:flutter/material.dart';
import 'package:vayug/features/profile/core/presentation/managers/profile_state_manager.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';

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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isWarning ? AppColors.error.withOpacity(0.12) : AppColors.primary.withOpacity(0.12),
        border: Border(
          bottom: BorderSide(
            color: isWarning ? AppColors.error.withOpacity(0.3) : AppColors.primary.withOpacity(0.3),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isWarning ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
            color: isWarning ? AppColors.error : AppColors.primary,
            size: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              notice.title,
              style: AppTypography.bodySmall.copyWith(
                color: isWarning ? AppColors.error : AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
