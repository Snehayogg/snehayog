import 'package:flutter/material.dart';
import 'package:snehayog/view/screens/feedback_screen.dart';
import 'package:snehayog/view/screens/reports_screen.dart';
import 'package:snehayog/view/widget/feedback/feedback_form_widget.dart';
import 'package:snehayog/view/widget/report/report_form_widget.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings & Support'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Support Section
          _buildSectionHeader('Support & Feedback'),

          _buildMenuItem(
            context,
            icon: Icons.feedback_outlined,
            title: 'Submit Feedback',
            subtitle: 'Share your thoughts and suggestions',
            onTap: () => _navigateToFeedbackForm(context),
          ),

          _buildMenuItem(
            context,
            icon: Icons.feedback,
            title: 'My Feedback',
            subtitle: 'View your submitted feedback',
            onTap: () => _navigateToScreen(context, const FeedbackScreen()),
          ),

          _buildMenuItem(
            context,
            icon: Icons.report_outlined,
            title: 'Report Content',
            subtitle: 'Report inappropriate content',
            onTap: () => _navigateToReportForm(context),
          ),

          _buildMenuItem(
            context,
            icon: Icons.report,
            title: 'My Reports',
            subtitle: 'View your submitted reports',
            onTap: () => _navigateToScreen(context, const ReportsScreen()),
          ),

          const SizedBox(height: 24),

          // App Info Section
          _buildSectionHeader('App Information'),

          _buildMenuItem(
            context,
            icon: Icons.info_outline,
            title: 'About Snehayog',
            subtitle: 'Version 1.0.0',
            onTap: () => _showAboutDialog(context),
          ),

          _buildMenuItem(
            context,
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy Policy',
            subtitle: 'How we handle your data',
            onTap: () => _showPrivacyInfo(context),
          ),

          _buildMenuItem(
            context,
            icon: Icons.help_outline,
            title: 'Help & FAQ',
            subtitle: 'Get help with common questions',
            onTap: () => _showHelpDialog(context),
          ),

          const SizedBox(height: 24),

          // Quick Actions Section
          _buildSectionHeader('Quick Actions'),

          _buildMenuItem(
            context,
            icon: Icons.bug_report_outlined,
            title: 'Report a Bug',
            subtitle: 'Found something broken? Let us know',
            onTap: () => _navigateToBugReport(context),
          ),

          _buildMenuItem(
            context,
            icon: Icons.lightbulb_outline,
            title: 'Feature Request',
            subtitle: 'Suggest new features',
            onTap: () => _navigateToFeatureRequest(context),
          ),

          const SizedBox(height: 32),

          // Contact Information
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.support_agent,
                        color: Colors.blue[600], size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Need More Help?',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.blue[800],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Contact our support team for assistance with any issues or questions.',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () => _showContactOptions(context),
                  icon: const Icon(Icons.email, size: 16),
                  label: const Text('Contact Support'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 40),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: Theme.of(context).primaryColor,
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
          ),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: Colors.grey,
        ),
        onTap: onTap,
      ),
    );
  }

  void _navigateToScreen(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => screen),
    );
  }

  void _navigateToFeedbackForm(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const FeedbackFormWidget(),
      ),
    );
  }

  void _navigateToReportForm(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const ReportFormWidget(),
      ),
    );
  }

  void _navigateToBugReport(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const FeedbackFormWidget(
          relatedVideoId: null,
          relatedVideoTitle: null,
          relatedUserId: null,
          relatedUserName: null,
        ),
      ),
    );
  }

  void _navigateToFeatureRequest(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const FeedbackFormWidget(),
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Snehayog',
      applicationVersion: '1.0.0',
      applicationIcon: const Icon(
        Icons.video_library,
        size: 64,
        color: Colors.blue,
      ),
      children: [
        const Text(
          'Snehayog is a video sharing platform that connects creators with their audience through engaging short-form content.',
        ),
        const SizedBox(height: 16),
        const Text(
          'Built with Flutter and powered by modern cloud infrastructure.',
        ),
      ],
    );
  }

  void _showPrivacyInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Privacy Policy'),
        content: const SingleChildScrollView(
          child: Text(
            'At Snehayog, we take your privacy seriously. We collect only the necessary information to provide you with the best experience.\n\n'
            '• Your profile information is used to personalize your experience\n'
            '• Video data is stored securely and used for content delivery\n'
            '• Feedback and reports are used to improve our platform\n'
            '• We never sell your personal data to third parties\n\n'
            'For more detailed information, please contact our support team.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Help & FAQ'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Frequently Asked Questions:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 12),
              Text(
                'Q: How do I upload videos?',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              Text(
                  'A: Use the upload button on the home screen to select and upload your videos.'),
              SizedBox(height: 8),
              Text(
                'Q: Can I edit my videos?',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              Text(
                  'A: Currently, we support basic video uploads. Advanced editing features are coming soon.'),
              SizedBox(height: 8),
              Text(
                'Q: How do I report inappropriate content?',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              Text(
                  'A: Use the "Report Content" option in Settings to report any inappropriate content.'),
              SizedBox(height: 8),
              Text(
                'Q: How do I contact support?',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              Text(
                  'A: Use the "Contact Support" button in Settings or submit feedback through the app.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  void _showContactOptions(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Contact Support'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Choose how you\'d like to contact us:'),
            SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.email, color: Colors.blue),
                SizedBox(width: 8),
                Text('support@snehayog.com'),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.phone, color: Colors.green),
                SizedBox(width: 8),
                Text('+1 (555) 123-4567'),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.access_time, color: Colors.orange),
                SizedBox(width: 8),
                Text('Mon-Fri, 9 AM - 6 PM'),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _navigateToFeedbackForm(context);
            },
            child: const Text('Submit Feedback'),
          ),
        ],
      ),
    );
  }
}
