import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snehayog/core/managers/profile_state_manager.dart';
import 'package:snehayog/core/services/auto_scroll_settings.dart';
import 'package:snehayog/view/screens/creator_payment_setup_screen.dart';
import 'package:snehayog/view/screens/creator_revenue_screen.dart';
import 'package:snehayog/view/screens/creator_payout_dashboard.dart';
import 'package:snehayog/view/widget/feedback/feedback_dialog_widget.dart';
import 'package:snehayog/view/widget/report/report_dialog_widget.dart';

class ProfileDialogsWidget {
  static void showSettingsBottomSheet(
    BuildContext context, {
    required ProfileStateManager stateManager,
    required Future<bool> Function() checkPaymentSetupStatus,
  }) {
    print('🔧 ProfileScreen: Opening Settings Bottom Sheet');
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.settings, color: Colors.black87, size: 24),
                  const SizedBox(width: 12),
                  const Text(
                    'Settings',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.black54),
                  ),
                ],
              ),
            ),
            Divider(color: Colors.grey[300], height: 1),

            // Settings options
            Consumer<ProfileStateManager>(
              builder: (context, stateManager, child) {
                if (stateManager.userData != null) {
                  return Column(
                    children: [
                      _buildSettingsTile(
                        icon: Icons.swap_vert_circle,
                        title: 'Auto Scroll',
                        subtitle: 'Auto-scroll to next video after finish',
                        onTap: () async {
                          // Toggle the preference
                          final enabled = await AutoScrollSettings.isEnabled();
                          await AutoScrollSettings.setEnabled(!enabled);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Auto Scroll: ${!enabled ? 'ON' : 'OFF'}'),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          }
                          Navigator.pop(context);
                        },
                        iconColor: Colors.grey,
                      ),
                      _buildSettingsTile(
                        icon: Icons.edit,
                        title: 'Edit Profile',
                        subtitle: 'Update your profile information',
                        onTap: () {
                          Navigator.pop(context);
                          // Handle edit profile
                        },
                      ),
                      _buildSettingsTile(
                        icon: Icons.video_library,
                        title: 'Manage Videos',
                        subtitle: 'View and manage your videos',
                        onTap: () {
                          Navigator.pop(context);
                          // Already on profile screen, just scroll to videos
                        },
                      ),
                      _buildSettingsTile(
                        icon: Icons.dashboard,
                        title: 'Creator Dashboard',
                        subtitle: 'View earnings and analytics',
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const CreatorPayoutDashboard(),
                            ),
                          );
                        },
                      ),
                      _buildSettingsTile(
                        icon: Icons.payment,
                        title: 'Payment Setup',
                        subtitle: 'Configure payment details for earnings',
                        onTap: () async {
                          Navigator.pop(context);
                          final hasSetup = await checkPaymentSetupStatus();
                          if (hasSetup) {
                            // Show current payment details or allow editing
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content:
                                    Text('✅ Payment setup already completed'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } else {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const CreatorPaymentSetupScreen(),
                              ),
                            );
                          }
                        },
                      ),
                      _buildSettingsTile(
                        icon: Icons.analytics,
                        title: 'Revenue Analytics',
                        subtitle: 'Track your earnings',
                        onTap: () async {
                          Navigator.pop(context);
                          final hasPaymentSetup =
                              await checkPaymentSetupStatus();
                          if (hasPaymentSetup) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const CreatorRevenueScreen(),
                              ),
                            );
                          } else {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const CreatorPaymentSetupScreen(),
                              ),
                            );
                          }
                        },
                      ),
                      _buildSettingsTile(
                        icon: Icons.help_outline,
                        title: 'Help & Support',
                        subtitle: 'Get help with your account',
                        onTap: () {
                          Navigator.pop(context);
                          showHelpDialog(context);
                        },
                      ),
                      _buildSettingsTile(
                        icon: Icons.feedback_outlined,
                        title: 'Feedback',
                        subtitle: 'Share ideas or report a problem',
                        onTap: () {
                          Navigator.pop(context);
                          showFeedbackDialog(context);
                        },
                      ),
                    ],
                  );
                } else {
                  return Column(
                    children: [
                      _buildSettingsTile(
                        icon: Icons.login,
                        title: 'Sign In',
                        subtitle: 'Sign in to access your profile',
                        onTap: () {
                          Navigator.pop(context);
                          // Handle sign in
                        },
                      ),
                      _buildSettingsTile(
                        icon: Icons.help_outline,
                        title: 'Help & Support',
                        subtitle: 'Get help with your account',
                        onTap: () {
                          Navigator.pop(context);
                          showHelpDialog(context);
                        },
                      ),
                    ],
                  );
                }
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  static Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: (iconColor ?? Colors.grey).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: iconColor ?? Colors.grey,
          size: 20,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: Colors.black54,
          fontSize: 14,
        ),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
    );
  }

  static void showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: Colors.black87),
            SizedBox(width: 12),
            Text(
              'Help & Support',
              style: TextStyle(color: Colors.black87),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Need help? Here are some common solutions:',
              style: TextStyle(color: Colors.black54, fontSize: 16),
            ),
            SizedBox(height: 16),
            Text(
              '• Profile Issues: Try refreshing your profile',
              style: TextStyle(color: Colors.black87, fontSize: 14),
            ),
            Text(
              '• Video Problems: Check if videos need HLS conversion',
              style: TextStyle(color: Colors.black87, fontSize: 14),
            ),
            Text(
              '• Payment Setup: Complete payment setup for earnings',
              style: TextStyle(color: Colors.black87, fontSize: 14),
            ),
            Text(
              '• Account Issues: Try signing out and back in',
              style: TextStyle(color: Colors.black87, fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.black54)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Handle debug info
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Debug Info'),
          ),
        ],
      ),
    );
  }

  static void showFeedbackDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const FeedbackDialogWidget(),
    );
  }

  static void showReportDialog(
    BuildContext context, {
    required String targetType,
    required String targetId,
  }) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => ReportDialogWidget(
        targetType: targetType,
        targetId: targetId,
      ),
    );
  }

  static void showFAQDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.help_outline,
                      color: Colors.blue.shade700,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Frequently Asked Questions',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Everything you need to know about Snehayog',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // FAQ Content
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFAQItem(
                        question:
                            "Why should I use Snehayog instead of Instagram?",
                        answer:
                            "Because on Snehayog, you can start earning from day one, not after months of growth. And unlike Instagram, you'll see relevant, meaningful content, not adult or sexual material. It's a platform built to reward real creators and protect genuine viewers.",
                        icon: Icons.compare_arrows,
                        color: Colors.green,
                      ),
                      _buildFAQItem(
                        question:
                            "YouTube already lets creators earn money. Why switch to Snehayog?",
                        answer:
                            "YouTube has strict monetization rules — you need 1,000 subscribers and 4,000 watch hours. On Snehayog, there's no barrier — creators start earning from the first upload. It's a platform that values your effort, not your follower count.",
                        icon: Icons.video_library,
                        color: Colors.red,
                      ),
                      _buildFAQItem(
                        question:
                            "Does Snehayog really give 80% ad revenue? Sounds too good to be true.",
                        answer:
                            "Yes — creators get 80% of ad revenue directly. The system automatically credits it to your bank account based on your views and engagement. Our goal is to make creators financially independent, not exploit their content.",
                        icon: Icons.account_balance_wallet,
                        color: Colors.orange,
                      ),
                      _buildFAQItem(
                        question:
                            "What's the point of joining a new app if my followers are on Instagram and YouTube?",
                        answer:
                            "That's exactly why now is the best time — you can be an early creator on a growing platform. Early creators get more reach, visibility, and partnership opportunities. On Snehayog, you're not lost in the crowd — your content actually gets discovered.",
                        icon: Icons.trending_up,
                        color: Colors.purple,
                      ),
                      _buildFAQItem(
                        question:
                            "How will I get views or reach on Snehayog? New platforms usually have low traffic.",
                        answer:
                            "We're actively promoting creators through in-app boosts and personalized recommendations. Because fewer creators are competing right now, your chances to go viral are much higher. Early users always benefit the most — just like YouTubers who started in 2010.",
                        icon: Icons.visibility,
                        color: Colors.blue,
                      ),
                    ],
                  ),
                ),
              ),

              // Bottom Action Button
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Got it, thanks!'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.blue.shade600,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildFAQItem({
    required String question,
    required String answer,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.grey.shade200,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Question Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  question,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Answer
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.grey.shade200,
                width: 1,
              ),
            ),
            child: Text(
              answer,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade700,
                height: 1.5,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static void showHowToEarnDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.8,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) => Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              controller: scrollController,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.workspace_premium,
                            color: Colors.blue.shade700),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'How to earn on Snehayog',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      )
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Points
                  _buildHowToEarnPoint(
                    title: '1. Upload quality videos',
                    body:
                        'Create engaging Yog or Sneha content. Use clear titles and relevant categories/tags for better reach.',
                  ),
                  _buildHowToEarnPoint(
                    title: '2. Earn from ad revenue',
                    body:
                        'You earn a share when ads are shown with your videos. Higher engagement increases your earnings.',
                  ),
                  _buildHowToEarnPoint(
                    title: '3. Payout schedule',
                    body:
                        'Balances are credited on the 1st of every month to your preferred payment method after verification.',
                  ),
                  _buildHowToEarnPoint(
                    title: '4. Complete payment setup',
                    body:
                        'Set up your payout details in Creator Dashboard to receive monthly payments without delays.',
                  ),
                  _buildHowToEarnPoint(
                    title: '5. Follow content guidelines',
                    body:
                        'Avoid copyrighted or restricted content. Repeated violations may impact earnings and account status.',
                  ),

                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Got it'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: Colors.blue.shade600,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static Widget _buildHowToEarnPoint(
      {required String title, required String body}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade800,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
