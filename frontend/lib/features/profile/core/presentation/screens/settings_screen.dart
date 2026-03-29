import 'package:flutter/material.dart';
import 'package:vayu/core/design/spacing.dart';
import 'package:provider/provider.dart';
import 'package:vayu/features/auth/presentation/controllers/google_sign_in_controller.dart';
import 'package:vayu/features/profile/core/presentation/screens/saved_videos_screen.dart';
import 'package:vayu/features/profile/core/presentation/screens/linked_accounts_screen.dart';
import 'package:vayu/core/design/colors.dart';
import 'package:vayu/core/design/typography.dart';
import 'package:vayu/shared/utils/app_text.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDeveloperToken();
  }

  Future<void> _loadDeveloperToken() async {
    setState(() {
      _isLoading = false;
    });
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        title: Text(AppText.get('settings_title', fallback: 'Settings')),
        backgroundColor: AppColors.backgroundPrimary,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              padding: EdgeInsets.all(AppSpacing.spacing4),
              itemCount: 3,
              separatorBuilder: (_, __) =>
                  SizedBox(height: AppSpacing.spacing4),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _buildActionTile(
                    title: AppText.get('settings_saved_videos',
                        fallback: 'Saved Videos'),
                    icon: Icons.bookmark_outlined,
                    color: AppColors.textPrimary,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const SavedVideosScreen()),
                      );
                    },
                  );
                } else if (index == 1) {
                  return _buildActionTile(
                    title: AppText.get('settings_linked_accounts',
                        fallback: 'Linked Accounts'),
                    icon: Icons.link,
                    color: AppColors.textPrimary,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const LinkedAccountsScreen()),
                      );
                    },
                  );
                }
                return _buildActionTile(
                  title: AppText.get('btn_logout', fallback: 'Logout'),
                  icon: Icons.logout,
                  color: AppColors.error,
                  onTap: () {
                    context.read<GoogleSignInController>().signOut();
                    Navigator.of(context).pop();
                  },
                );
              },
            ),
    );
  }


  Widget _buildActionTile({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: AppTypography.bodyMedium.copyWith(color: color),
      ),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textTertiary),
    );
  }
}
