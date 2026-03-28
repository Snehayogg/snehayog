import 'package:flutter/material.dart';
import 'package:vayu/core/design/radius.dart';
import 'package:provider/provider.dart';
import 'package:vayu/features/auth/presentation/controllers/google_sign_in_controller.dart';
import 'package:vayu/features/profile/presentation/managers/profile_state_manager.dart';
import 'package:vayu/shared/services/auto_scroll_settings.dart';
import 'package:vayu/features/profile/presentation/screens/creator_revenue_screen.dart';
import 'package:vayu/shared/widgets/feedback/feedback_dialog_widget.dart';
import 'package:vayu/shared/widgets/report_dialog_widget.dart';
import 'package:vayu/features/profile/presentation/widgets/top_earners_bottom_sheet.dart';
import 'package:vayu/core/design/colors.dart';
import 'package:vayu/core/design/typography.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vayu/shared/widgets/app_button.dart';
import 'package:vayu/shared/widgets/vayu_bottom_sheet.dart';
import 'package:vayu/features/profile/presentation/screens/linked_accounts_screen.dart';
import 'package:vayu/shared/utils/app_text.dart';

class ProfileDialogsWidget {
  static void showSettingsBottomSheet(
    BuildContext context, {
    required ProfileStateManager stateManager,
    required Future<bool> Function() checkPaymentSetupStatus,
  }) {
    VayuBottomSheet.show(
      context: context,
      title: 'Settings',
      padding: EdgeInsets.zero,
      child: Consumer<ProfileStateManager>(
        builder: (context, stateManager, child) {
          if (stateManager.userData != null) {
            final authController = Provider.of<GoogleSignInController>(
              context,
              listen: false,
            );
            final loggedInUserId = authController.userData?['id']?.toString() ??
                authController.userData?['googleId']?.toString();
            final viewedUserId =
                stateManager.userData?['googleId']?.toString() ??
                    stateManager.userData?['id']?.toString();
            final bool isViewingOwnProfile = loggedInUserId != null &&
                loggedInUserId.isNotEmpty &&
                loggedInUserId == viewedUserId;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSettingsTile(
                  context: context,
                  icon: Icons.swap_vert_circle,
                  title: 'Auto Scroll',
                  subtitle: 'Auto-scroll to next video after finish',
                  onTap: () async {
                    final enabled = await AutoScrollSettings.isEnabled();
                    await AutoScrollSettings.setEnabled(!enabled);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Auto Scroll: ${!enabled ? 'ON' : 'OFF'}',
                          ),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    }
                    Navigator.pop(context);
                  },
                  iconColor: AppColors.textSecondary,
                ),
                _buildSettingsTile(
                  context: context,
                  icon: Icons.edit,
                  title: 'Edit Profile',
                  subtitle: 'Update your profile information',
                  onTap: () {
                    Navigator.pop(context);
                  },
                ),
                _buildSettingsTile(
                  context: context,
                  icon: Icons.video_library,
                  title: 'Manage Videos',
                  subtitle: 'View and manage your videos',
                  onTap: () {
                    Navigator.pop(context);
                  },
                ),
                if (isViewingOwnProfile)
                  _buildSettingsTile(
                    context: context,
                    icon: Icons.analytics,
                    title: 'Revenue Analytics',
                    subtitle: 'Track your performance',
                    onTap: () async {
                      Navigator.pop(context);
                      Navigator.of(context, rootNavigator: true).push(
                        MaterialPageRoute(
                          builder: (context) => const CreatorRevenueScreen(),
                        ),
                      );
                    },
                  ),
                if (isViewingOwnProfile)
                  _buildSettingsTile(
                    context: context,
                    icon: Icons.link,
                    title: AppText.get('settings_linked_accounts',
                        fallback: 'Linked Accounts'),
                    subtitle: AppText.get('linked_accounts_subtitle',
                        fallback: 'Manage social accounts'),
                    onTap: () async {
                      Navigator.pop(context);
                      Navigator.of(context, rootNavigator: true).push(
                        MaterialPageRoute(
                          builder: (context) => const LinkedAccountsScreen(),
                        ),
                      );
                    },
                  ),
                _buildSettingsTile(
                  context: context,
                  icon: Icons.help_outline,
                  title: 'Help & Support',
                  subtitle: 'Get help with your account',
                  onTap: () {
                    Navigator.pop(context);
                    showHelpDialog(context);
                  },
                ),
                _buildSettingsTile(
                  context: context,
                  icon: Icons.feedback_outlined,
                  title: 'Feedback',
                  subtitle: 'Share ideas or report a problem',
                  onTap: () {
                    Navigator.pop(context);
                    showFeedbackDialog(context);
                  },
                ),
                const SizedBox(height: 20),
              ],
            );
          } else {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSettingsTile(
                  context: context,
                  icon: Icons.login,
                  title: 'Sign In',
                  subtitle: 'Sign in to access your profile',
                  onTap: () {
                    Navigator.pop(context);
                  },
                ),
                _buildSettingsTile(
                  context: context,
                  icon: Icons.help_outline,
                  title: 'Help & Support',
                  subtitle: 'Get help with your account',
                  onTap: () {
                    Navigator.pop(context);
                    showHelpDialog(context);
                  },
                ),
                const SizedBox(height: 20),
              ],
            );
          }
        },
      ),
    );
  }

  static Widget _buildSettingsTile({
    required BuildContext context,
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
          color: (iconColor ?? AppColors.textTertiary).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Icon(icon, color: iconColor ?? AppColors.textTertiary, size: 20),
      ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
      ),
      subtitle: Text(
        subtitle,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
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
        backgroundColor: AppColors.surfacePrimary,
        title: Row(
          children: [
            const Icon(Icons.help_outline, color: AppColors.textPrimary),
            const SizedBox(width: 12),
            Text('Help & Support',
                style: Theme.of(context).textTheme.headlineSmall),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Need help? Here are some common solutions:',
              style: AppTypography.bodyMedium,
            ),
            const SizedBox(height: 16),
            Text(
              '• Profile Issues: Try refreshing your profile',
              style: AppTypography.bodySmall,
            ),
            Text(
              '• Video Problems: Check if videos need HLS conversion',
              style: AppTypography.bodySmall,
            ),
            Text(
              '• Billing Setup: Complete billing setup for rewards',
              style: AppTypography.bodySmall,
            ),
            Text(
              '• Account Issues: Try signing out and back in',
              style: AppTypography.bodySmall,
            ),
          ],
        ),
        actions: [
          AppButton(
            onPressed: () => Navigator.pop(context),
            label: 'Close',
            variant: AppButtonVariant.text,
          ),
          AppButton(
            onPressed: () {
              Navigator.pop(context);
              // Handle debug info
            },
            label: 'Debug Info',
            variant: AppButtonVariant.primary,
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
      builder: (context) =>
          ReportDialogWidget(targetType: targetType, targetId: targetId),
    );
  }

  static void showFAQDialog(BuildContext context) {
    VayuBottomSheet.show(
      context: context,
      title: 'Frequently Asked Questions',
      useDraggable: true,
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Everything you need to know about Vayug',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [
                _buildFAQItem(
                  question: "Why should I use Vayug instead of Instagram?",
                  answer:
                      "Because on Vayug, you can start growing your profile from day one, with meaningful content. And unlike Instagram, you'll see relevant, meaningful content, not adult or sexual material. It's a platform built to reward real creators and protect genuine viewers.",
                  icon: Icons.compare_arrows,
                  color: Colors.green,
                ),
                _buildFAQItem(
                  question:
                      "YouTube already has monetization. Why switch to Vayug?",
                  answer:
                      "YouTube has strict entry rules. On Vayug, there's no barrier — creators start building their engagement from the first upload. It's a platform that values your effort, not just your follower count.",
                  icon: Icons.video_library,
                  color: Colors.red,
                ),
                _buildFAQItem(
                  question: "Does Vayug have a creator support model?",
                  answer:
                      "Yes — we use a creator-first model where rewards are distributed based on engagement. The system automatically updates your score based on your views and interaction. Our goal is to make creators independent and valued.",
                  icon: Icons.account_balance_wallet,
                  color: Colors.orange,
                ),
                _buildFAQItem(
                  question:
                      "What's the point of joining a new app if my followers are on Instagram and YouTube?",
                  answer:
                      "That's exactly why now is the best time — you can be an early creator on a growing platform. Early creators get more reach, visibility, and partnership opportunities. On Vayug, you're not lost in the crowd — your content actually gets discovered.",
                  icon: Icons.trending_up,
                  color: Colors.purple,
                ),
                _buildFAQItem(
                  question:
                      "How will I get views or reach on Vayug? New platforms usually have low traffic.",
                  answer:
                      "We're actively promoting creators through in-app boosts and personalized recommendations. Because fewer creators are competing right now, your chances to go viral are much higher. Early users always benefit the most — just like YouTubers who started in 2010.",
                  icon: Icons.visibility,
                  color: Colors.blue,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AppButton(
            isFullWidth: true,
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.check_circle_outline),
            label: 'Got it, thanks!',
            variant: AppButtonVariant.primary,
          ),
        ],
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
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderPrimary, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
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
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  question,
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.textPrimary,
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
              color: AppColors.backgroundPrimary,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderPrimary, width: 1),
            ),
            child: Text(
              answer,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
                height: 1.5,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static void showLegalBottomSheet(BuildContext context) {
    VayuBottomSheet.show(
      context: context,
      title: 'Legal & About',
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Policies and contact information',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          _buildLegalItem(
            context: context,
            title: 'Privacy Policy',
            icon: Icons.privacy_tip_outlined,
            onTap: () => _launchURL('https://snehayog.site/privacy.html'),
          ),
          _buildLegalItem(
            context: context,
            title: 'Terms & Conditions',
            icon: Icons.description_outlined,
            onTap: () => _launchURL('https://snehayog.site/terms.html'),
          ),
          _buildLegalItem(
            context: context,
            title: 'Refund & Cancellation',
            icon: Icons.assignment_return_outlined,
            onTap: () => _launchURL('https://snehayog.site/refund.html'),
          ),
          _buildLegalItem(
            context: context,
            title: 'Contact Us',
            icon: Icons.contact_support_outlined,
            onTap: () => _launchURL('https://snehayog.site/contact.html'),
          ),
          _buildLegalItem(
            context: context,
            title: 'About Us',
            icon: Icons.info_outline_rounded,
            onTap: () => _launchURL('https://snehayog.site/about.html'),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'Version 1.0.0',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildLegalItem({
    required BuildContext context,
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary),
      title: Text(
        title,
        style: AppTypography.bodyMedium.copyWith(
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
      ),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textTertiary),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    );
  }

  static Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    try {
      // ignore: deprecated_member_use
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      print('Could not launch $url : $e');
    }
  }

  static Future<void> showHowToEarnDialog(
    BuildContext context, {
    required ProfileStateManager stateManager,
  }) async {
    await stateManager.ensurePaymentDetailsHydrated();

    final userData = stateManager.userData;
    String currentUpi =
        userData?['paymentDetails']?['upiId']?.toString().trim() ?? '';

    final upiController = TextEditingController(text: currentUpi);

    bool showUpiField = currentUpi.isEmpty;
    bool isSaving = false;
    String? validationMessage;

    await VayuBottomSheet.show(
      context: context,
      title: 'Creator Rewards Info',
      isScrollControlled: true,
      padding: EdgeInsets.zero,
      child: StatefulBuilder(
        builder: (context, setState) {
          final bottomInset = MediaQuery.of(context).viewInsets.bottom;

          return SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 0,
                bottom: bottomInset + 16,
              ),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHowToEarnPoint(
                      title: 'Reward distribution',
                      body:
                          'Rewards are validated and updated on the 1st of every month in your profile after verification.',
                    ),
                    _buildHowToEarnPoint(
                      title: 'Secure Identity Verification',
                      body:
                          'To maintain a fair and secure platform, we use a Billing Alias (UPI ID) for identity verification. This prevents duplicate accounts and ensures that rewards are distributed correctly to verified, unique creators.',
                    ),
                    if (!showUpiField && currentUpi.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.backgroundSecondary,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.borderPrimary),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Saved UPI ID',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              currentUpi,
                              style: const TextStyle(
                                fontSize: 15,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: AppButton(
                          onPressed: () {
                            setState(() {
                              showUpiField = true;
                              validationMessage = null;
                              upiController.text = currentUpi;
                            });
                          },
                          label: 'Update UPI ID',
                          variant: AppButtonVariant.text,
                        ),
                      ),
                    ],
                    if (showUpiField) ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: upiController,
                        decoration: const InputDecoration(
                          labelText: 'Enter your UPI ID',
                          hintText: 'example@bank',
                          border: OutlineInputBorder(),
                        ),
                        textInputAction: TextInputAction.done,
                      ),
                      if (validationMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          validationMessage!,
                          style: TextStyle(
                            color: Colors.red.shade600,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 16),
                    AppButton(
                      isFullWidth: true,
                      isDisabled: isSaving,
                      onPressed: () async {
                        if (!showUpiField) {
                          Navigator.pop(context);
                          return;
                        }

                        final upiId = upiController.text.trim();
                        final regex = RegExp(
                          r'^[a-zA-Z0-9.\-_]{2,}@[a-zA-Z]{2,}$',
                        );

                        if (upiId.isEmpty || !regex.hasMatch(upiId)) {
                          setState(() {
                            validationMessage =
                                'Enter a valid UPI ID (for example: creator@bank).';
                          });
                          return;
                        }

                        FocusScope.of(context).unfocus();
                        setState(() {
                          isSaving = true;
                          validationMessage = null;
                        });

                        try {
                          await stateManager.saveUpiIdQuick(upiId);
                          currentUpi = upiId;
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Billing info updated successfully. Scores will be updated on the 1st of every month.',
                                ),
                                duration: Duration(seconds: 3),
                              ),
                            );
                          }
                          setState(() {
                            isSaving = false;
                            showUpiField = false;
                            validationMessage =
                                'Information saved successfully! Your rewards will update on the 1st.';
                          });
                        } catch (e) {
                          setState(() {
                            isSaving = false;
                            validationMessage =
                                e.toString().replaceFirst('Exception: ', '');
                          });
                        }
                      },
                      label: isSaving
                          ? 'Saving...'
                          : showUpiField
                              ? 'Verify & Save'
                              : 'Done',
                      variant: AppButtonVariant.primary,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    upiController.dispose();

    if (stateManager.hasUpiId) {
      await stateManager.refreshData();
    }
  }

  static Widget _buildHowToEarnPoint({
    required String title,
    required String body,
  }) {
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
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  static void showTopEarnersBottomSheet(BuildContext context) {
    VayuBottomSheet.show(
      context: context,
      title: 'Top Earners',
      child: const TopEarnersBottomSheet(),
    );
  }
}
