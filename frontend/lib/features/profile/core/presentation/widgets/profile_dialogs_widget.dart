import 'package:flutter/material.dart';
import 'package:vayug/core/design/radius.dart';
import 'package:provider/provider.dart';
import 'package:vayug/features/auth/presentation/controllers/google_sign_in_controller.dart';
import 'package:vayug/features/profile/core/presentation/managers/profile_state_manager.dart';
import 'package:vayug/shared/services/auto_scroll_settings.dart';
import 'package:vayug/features/profile/analytics/presentation/screens/creator_revenue_screen.dart';
import 'package:vayug/shared/widgets/feedback/feedback_dialog_widget.dart';
import 'package:vayug/shared/widgets/report_dialog_widget.dart';
import 'package:vayug/features/profile/core/presentation/widgets/top_earners_bottom_sheet.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vayug/shared/widgets/app_button.dart';
import 'package:vayug/shared/widgets/vayu_bottom_sheet.dart';
import 'package:vayug/features/profile/core/presentation/screens/linked_accounts_screen.dart';
import 'package:vayug/shared/utils/app_text.dart';
import 'package:vayug/shared/utils/url_utils.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/shared/widgets/vayu_snackbar.dart';

class ProfileDialogsWidget {
  static void showSettingsBottomSheet(
    BuildContext context, {
    required ProfileStateManager stateManager,
    required Future<bool> Function() checkPaymentSetupStatus,
  }) {
    VayuBottomSheet.show(
      context: context,
      title: 'Settings',
      icon: Icons.settings_outlined,
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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

  static Future<bool> showDeleteConfirmationDialog(
    BuildContext context, {
    String title = 'Delete Content?',
    String message = 'Are you sure you want to delete this? This action cannot be undone.',
    String confirmLabel = 'Delete',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfacePrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: AppTypography.titleLarge.copyWith(color: AppColors.textPrimary),
        ),
        content: Text(
          message,
          style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold),
            ),
          ),
          AppButton(
            onPressed: () => Navigator.pop(context, true),
            label: confirmLabel,
            variant: AppButtonVariant.danger,
          ),
        ],
      ),
    );
    return result ?? false;
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
    VayuBottomSheet.show(
      context: context,
      title: 'Report ${targetType[0].toUpperCase()}${targetType.substring(1)}',
      icon: Icons.report_problem_outlined,
      child: ReportDialogWidget(targetType: targetType, targetId: targetId),
    );
  }

  static void showFAQDialog(BuildContext context) {
    VayuBottomSheet.show(
      context: context,
      title: 'Frequently Asked Questions',
      icon: Icons.help_outline,
      useDraggable: true,
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Everything you need to know about Vayug',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          // **FIX: Removed Expanded and ListView to prevent layout crashes in VayuBottomSheet**
          _buildFAQItem(
            question: "Why should I use Vayug instead of Instagram?",
            answer:
                "Because on Vayug, you can start growing your profile from day one, with meaningful content. And unlike Instagram, you'll see relevant, meaningful content, not adult or sexual material. It's a platform built to reward real creators and protect genuine viewers.",
            icon: Icons.compare_arrows,
            color: Colors.green,
          ),
          _buildFAQItem(
            question: "Viewers ke liye kya fayde hai?",
            answer:
                "Viewers ke liye sabse bada fayda hai 'Ad-free Experience'. Aap bina kisi distraction ke apne favorite show ya videos dekh sakte hai. Saath hi, humara algorithm aapko wahi dikhata hai jo aapke liye value add kare, na ki bekar ki ads.",
            icon: Icons.visibility,
            color: Colors.green,
          ),
          _buildFAQItem(
            question: "Creators ke liye kya fayde hai?",
            answer:
                "Creators ko hum pehle din se monetization ka mauka dete hai. Aapko YouTube ki tarah lambe intezar ki zaroorat nahi hai. Aapki video ki quality aur engagement ke hisaab se aapko rewards milte hai. Early joining se aapko reach bhi zyada milti hai.",
            icon: Icons.stars,
            color: Colors.orange,
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
      icon: Icons.gavel_rounded,
      iconColor: AppColors.primary,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children:  [
           Text(
            'Policies and contact information',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
           SizedBox(height: 8),
          // **FIX: Use _LegalItemWidget to provide visual feedback on click**
         const _VerticalLegalItem(
            title: 'Privacy Policy',
            icon: Icons.privacy_tip_outlined,
            url: 'https://snehayog.site/privacy.html',
          ),
          _VerticalLegalItem(
            title: 'Terms & Conditions',
            icon: Icons.description_outlined,
            url: 'https://snehayog.site/terms.html',
          ),
          _VerticalLegalItem(
            title: 'Refund & Cancellation',
            icon: Icons.assignment_return_outlined,
            url: 'https://snehayog.site/refund.html',
          ),
          _VerticalLegalItem(
            title: 'Contact Us',
            icon: Icons.contact_support_outlined,
            url: 'https://snehayog.site/contact.html',
          ),
          _VerticalLegalItem(
            title: 'About Us',
            icon: Icons.info_outline_rounded,
            url: 'https://snehayog.site/about.html',
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }


  static Future<void> _launchURL(String url, {BuildContext? context}) async {
    final enrichedUrl = UrlUtils.enrichUrl(
      url.trim(),
      source: 'vayug',
      medium: 'internal_link',
      campaign: 'legal_docs',
    );
    
    AppLogger.log('🔗 ProfileDialogs: Attempting to launch legal link: $enrichedUrl');
    
    try {
      final Uri uri = Uri.parse(enrichedUrl);
      if (await canLaunchUrl(uri)) {
        // **FIX: Launch first, then optionally pop if successful**
        final success = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        
        if (success) {
          // If we launched successfully, we can close the bottom sheet
          if (context != null && context.mounted) {
             Navigator.maybePop(context);
          }
        } else {
          AppLogger.log('❌ ProfileDialogs: launchUrl returned false for $enrichedUrl');
          if (context != null && context.mounted) {
            VayuSnackBar.showError(context, 'Could not open link in browser.');
          }
        }
      } else {
        AppLogger.log('⚠️ ProfileDialogs: canLaunchUrl returned false for $enrichedUrl');
        if (context != null && context.mounted) {
          VayuSnackBar.showError(context, 'Invalid link or no browser found.');
        }
      }
    } catch (e) {
      AppLogger.log('❌ ProfileDialogs: Exception while launching link: $e');
      if (context != null && context.mounted) {
        VayuSnackBar.showError(context, 'An error occurred while opening the link.');
      }
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
      icon: Icons.monetization_on_outlined,
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
      icon: Icons.emoji_events_outlined,
      child: const TopEarnersBottomSheet(),
    );
  }
}

// **NEW: Internal widget for legal items with loading state feedback**
class _VerticalLegalItem extends StatefulWidget {
  final String title;
  final IconData icon;
  final String url;

  const _VerticalLegalItem({
    required this.title,
    required this.icon,
    required this.url,
  });

  @override
  State<_VerticalLegalItem> createState() => _VerticalLegalItemState();
}

class _VerticalLegalItemState extends State<_VerticalLegalItem> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(widget.icon, color: AppColors.primary),
      title: Text(
        widget.title,
        style: AppTypography.bodyMedium.copyWith(
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
      ),
      trailing: _isLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            )
          : const Icon(Icons.chevron_right,
              color: AppColors.textTertiary, size: 18),
      onTap: _isLoading
          ? null
          : () async {
              setState(() => _isLoading = true);
              try {
                await ProfileDialogsWidget._launchURL(widget.url,
                    context: context);
              } finally {
                if (mounted) {
                  setState(() => _isLoading = false);
                }
              }
            },
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
    );
  }
}
