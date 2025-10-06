import 'package:flutter/material.dart';
import 'package:snehayog/view/screens/feedback_screen.dart';
import 'package:snehayog/view/screens/settings_screen.dart';
import 'package:snehayog/view/widget/feedback/feedback_form_widget.dart';
import 'package:snehayog/view/widget/report/report_form_widget.dart';

class FeedbackReportActionsWidget extends StatelessWidget {
  const FeedbackReportActionsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Support & Feedback',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _buildActionGrid(context),
        ],
      ),
    );
  }

  Widget _buildActionGrid(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // First row
          Row(
            children: [
              Expanded(
                child: _buildActionCard(
                  context,
                  icon: Icons.feedback_outlined,
                  title: 'Feedback',
                  subtitle: 'Share your thoughts',
                  color: Colors.blue,
                  onTap: () => _navigateToFeedbackForm(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionCard(
                  context,
                  icon: Icons.report_outlined,
                  title: 'Report',
                  subtitle: 'Report content',
                  color: Colors.red,
                  onTap: () => _navigateToReportForm(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Second row
          Row(
            children: [
              Expanded(
                child: _buildActionCard(
                  context,
                  icon: Icons.feedback,
                  title: 'My Feedback',
                  subtitle: 'View submitted',
                  color: Colors.green,
                  onTap: () =>
                      _navigateToScreen(context, const FeedbackScreen()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionCard(
                  context,
                  icon: Icons.settings_outlined,
                  title: 'Settings',
                  subtitle: 'More options',
                  color: Colors.orange,
                  onTap: () =>
                      _navigateToScreen(context, const SettingsScreen()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 24,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 11,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
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
}
