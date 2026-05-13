import 'package:flutter/material.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/features/profile/core/presentation/managers/profile_state_manager.dart';
import 'package:vayug/shared/utils/format_utils.dart';
import 'package:vayug/features/profile/core/presentation/widgets/profile_dialogs_widget.dart';
import 'package:hugeicons/hugeicons.dart';

class NotificationPerformanceScreen extends StatelessWidget {
  final ProfileStateManager manager;

  const NotificationPerformanceScreen({super.key, required this.manager});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: const Text('Direct Alerts Performance', style: TextStyle(fontWeight: FontWeight.bold)),
            centerTitle: true,
            backgroundColor: AppColors.backgroundPrimary,
            floating: true,
            snap: true,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.primary),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedHelpCircle,
                  color: AppColors.primary,
                  size: 22,
                ),
                onPressed: () => ProfileDialogsWidget.showNotificationGuide(context),
              ),
              const SizedBox(width: 8),
            ],
          ),
          if (manager.creatorAlertStats.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: Text(
                  'No alerts sent yet',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final alert = manager.creatorAlertStats[index];
                    final clickCount = alert['clickCount'] ?? 0;
                    final message = alert['message'] ?? '';
                    final title = alert['title'];
                    final createdAt = alert['createdAt'];
                    
                    DateTime? date;
                    if (createdAt != null) {
                      try {
                        date = DateTime.parse(createdAt.toString());
                      } catch (_) {}
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSecondary,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.textSecondary.withValues(alpha: 0.1)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (title != null && title.toString().isNotEmpty) ...[
                                      Text(
                                        title.toString(),
                                        style: AppTypography.titleSmall.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      AppSpacing.vSpace4,
                                    ],
                                    Text(
                                      message,
                                      style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.success.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  "$clickCount views",
                                  style: const TextStyle(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (date != null) ...[
                            AppSpacing.vSpace12,
                            Row(
                              children: [
                                const Icon(Icons.access_time_rounded, size: 12, color: AppColors.textTertiary),
                                const SizedBox(width: 4),
                                Text(
                                  FormatUtils.formatTimeAgo(date),
                                  style: AppTypography.labelSmall.copyWith(color: AppColors.textTertiary),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                  childCount: manager.creatorAlertStats.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
