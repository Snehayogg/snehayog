import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vayu/features/auth/presentation/controllers/google_sign_in_controller.dart';
import 'package:vayu/features/profile/presentation/managers/profile_state_manager.dart';
import 'package:vayu/shared/services/auto_scroll_settings.dart';
import 'package:vayu/features/profile/presentation/screens/creator_revenue_screen.dart';
import 'package:vayu/shared/widgets/feedback/feedback_dialog_widget.dart';
import 'package:vayu/shared/widgets/report_dialog_widget.dart';
import 'package:vayu/features/profile/presentation/widgets/top_earners_bottom_sheet.dart';
import 'package:vayu/shared/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

class ProfileDialogsWidget {
  static void showSettingsBottomSheet(
    BuildContext context, {
    required ProfileStateManager stateManager,
    required Future<bool> Function() checkPaymentSetupStatus,
  }) {
    print('🔧 ProfileScreen: Opening Settings Bottom Sheet');
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.backgroundPrimary,
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
              decoration: const BoxDecoration(
                color: AppTheme.backgroundSecondary,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(AppTheme.radiusLarge),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.settings, color: AppTheme.textPrimary, size: 24),
                  const SizedBox(width: 12),
                  Text(
                    'Settings',
                    style: AppTheme.titleLarge.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
            Divider(color: AppTheme.borderPrimary, height: 1),

            // Settings options
            Consumer<ProfileStateManager>(
              builder: (context, stateManager, child) {
                if (stateManager.userData != null) {
                  final authController = Provider.of<GoogleSignInController>(
                    context,
                    listen: false,
                  );
                  final loggedInUserId =
                      authController.userData?['id']?.toString() ??
                          authController.userData?['googleId']?.toString();
                  final viewedUserId =
                      stateManager.userData?['googleId']?.toString() ??
                          stateManager.userData?['id']?.toString();
                  final bool isViewingOwnProfile = loggedInUserId != null &&
                      loggedInUserId.isNotEmpty &&
                      loggedInUserId == viewedUserId;

                  return Column(
                    children: [
                      _buildSettingsTile(
                        context: context,
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
                                  'Auto Scroll: ${!enabled ? 'ON' : 'OFF'}',
                                ),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          }
                          Navigator.pop(context);
                        },
                        iconColor: AppTheme.textSecondary,
                      ),
                      _buildSettingsTile(
                        context: context,
                        icon: Icons.edit,
                        title: 'Edit Profile',
                        subtitle: 'Update your profile information',
                        onTap: () {
                          Navigator.pop(context);
                          // Handle edit profile
                        },
                      ),
                      _buildSettingsTile(
                        context: context,
                        icon: Icons.video_library,
                        title: 'Manage Videos',
                        subtitle: 'View and manage your videos',
                        onTap: () {
                          Navigator.pop(context);
                          // Already on profile screen, just scroll to videos
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
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const CreatorRevenueScreen(),
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
                    ],
                  );
                } else {
                  return Column(
                    children: [
                      _buildSettingsTile(
                        context: context,
                        icon: Icons.login,
                        title: 'Sign In',
                        subtitle: 'Sign in to access your profile',
                        onTap: () {
                          Navigator.pop(context);
                          // Handle sign in
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
          color: (iconColor ?? AppTheme.textTertiary).withOpacity(0.1),
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        ),
        child: Icon(icon, color: iconColor ?? AppTheme.textTertiary, size: 20),
      ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w500,
            ),
      ),
      subtitle: Text(
        subtitle,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppTheme.textSecondary,
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
        backgroundColor: AppTheme.surfacePrimary,
        title: Row(
          children: [
            const Icon(Icons.help_outline, color: AppTheme.textPrimary),
            const SizedBox(width: 12),
            Text('Help & Support', style: Theme.of(context).textTheme.headlineSmall),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Need help? Here are some common solutions:',
              style: AppTheme.bodyMedium,
            ),
            SizedBox(height: 16),
            Text(
              '• Profile Issues: Try refreshing your profile',
              style: AppTheme.bodySmall,
            ),
            Text(
              '• Video Problems: Check if videos need HLS conversion',
              style: AppTheme.bodySmall,
            ),
            Text(
              '• Billing Setup: Complete billing setup for rewards',
              style: AppTheme.bodySmall,
            ),
            Text(
              '• Account Issues: Try signing out and back in',
              style: AppTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Handle debug info
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: AppTheme.textPrimary,
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
      builder: (context) =>
          ReportDialogWidget(targetType: targetType, targetId: targetId),
    );
  }

  static void showFAQDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.backgroundPrimary,
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
                      color: AppTheme.primary.withValues(alpha:0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.help_outline,
                      color: AppTheme.primary,
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
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Everything you need to know about Vayug',
                          style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppTheme.textSecondary),
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
                            "Why should I use Vayug instead of Instagram?",
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
                        question:
                            "Does Vayug have a creator support model?",
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
                    backgroundColor: AppTheme.primary,
                    foregroundColor: AppTheme.textPrimary,
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
        color: AppTheme.backgroundSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderPrimary, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.1),
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
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  question,
                  style: AppTheme.titleSmall.copyWith(
                    color: AppTheme.textPrimary,
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
              color: AppTheme.backgroundPrimary,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderPrimary, width: 1),
            ),
            child: Text(
              answer,
              style: AppTheme.bodySmall.copyWith(
                color: AppTheme.textSecondary,
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Allow full height if needed
      backgroundColor: AppTheme.backgroundPrimary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              controller: scrollController,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.gavel,
                          color: AppTheme.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Legal & About',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Policies and contact information',
                              style: TextStyle(
                                  fontSize: 14, color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
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
                      style: AppTheme.bodySmall
                          .copyWith(color: AppTheme.textTertiary),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
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
      leading: Icon(icon, color: AppTheme.primary),
      title: Text(
        title,
        style: AppTheme.bodyMedium.copyWith(
          fontWeight: FontWeight.w500,
          color: AppTheme.textPrimary,
        ),
      ),
      trailing: const Icon(Icons.chevron_right, color: AppTheme.textTertiary),
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

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.backgroundPrimary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        void closeSheet() {
          Navigator.pop(context);
        }

        return StatefulBuilder(
          builder: (context, setState) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;

            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 16,
                  bottom: bottomInset + 16,
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha:0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.workspace_premium,
                              color: AppTheme.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Creator Rewards Info',
                              style: AppTheme.titleLarge.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                            onPressed: closeSheet,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
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
                            color: AppTheme.backgroundSecondary,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.borderPrimary),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                               const Text(
                                  'Saved UPI ID',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              const SizedBox(height: 6),
                              Text(
                                currentUpi,
                                style: const TextStyle(
                                  fontSize: 15,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () {
                              setState(() {
                                showUpiField = true;
                                validationMessage = null;
                                upiController.text = currentUpi;
                              });
                            },
                            child: const Text(
                              'Update UPI ID',
                              style: TextStyle(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: isSaving
                              ? null
                              : () async {
                                  if (!showUpiField) {
                                    closeSheet();
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
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
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
                                      validationMessage = e
                                          .toString()
                                          .replaceFirst('Exception: ', '');
                                    });
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            backgroundColor: AppTheme.primary,
                            foregroundColor: AppTheme.white,
                          ),
                          child: Text(
                            isSaving
                                ? 'Saving...'
                                : showUpiField
                                    ? 'Verify & Save'
                                    : 'Done',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
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
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  static void showTopEarnersBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const TopEarnersBottomSheet(),
    );
  }
}

