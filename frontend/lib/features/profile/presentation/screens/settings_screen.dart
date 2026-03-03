import 'package:flutter/material.dart';
import 'package:vayu/core/design/spacing.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayu/features/auth/presentation/controllers/google_sign_in_controller.dart';
import 'package:vayu/features/profile/presentation/screens/saved_videos_screen.dart';
import 'package:vayu/core/design/colors.dart';
import 'package:vayu/core/design/typography.dart';
import 'package:vayu/shared/utils/app_text.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _developerToken;
  bool _isLoading = true;
  static const int _tokenPreviewMaxLines = 2;

  @override
  void initState() {
    super.initState();
    _loadDeveloperToken();
  }

  Future<void> _loadDeveloperToken() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _developerToken = prefs.getString('jwt_token');
      _isLoading = false;
    });
  }

  void _copyToken() {
    if (_developerToken != null) {
      Clipboard.setData(ClipboardData(text: _developerToken!));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppText.get('settings_token_copied',
              fallback: 'Token copied to clipboard')),
          backgroundColor: AppColors.success,
        ),
      );
    }
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
          ? Center(child: CircularProgressIndicator())
          : ListView.separated(
              padding: EdgeInsets.all(AppSpacing.spacing4),
              itemCount: 3,
              separatorBuilder: (_, __) =>
                  SizedBox(height: AppSpacing.spacing4),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _buildSection(
                    title: AppText.get('settings_developer_header',
                        fallback: 'Developer Settings'),
                    child: _buildTokenCard(),
                  );
                }
                if (index == 1) {
                  return _buildSection(
                    title: AppText.get('settings_library_header',
                        fallback: 'Library'),
                    child: _buildActionTile(
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
                    ),
                  );
                }
                return _buildSection(
                  title: AppText.get('settings_account_header',
                      fallback: 'Account'),
                  child: _buildActionTile(
                    title: AppText.get('btn_logout', fallback: 'Logout'),
                    icon: Icons.logout,
                    color: AppColors.error,
                    onTap: () {
                      context.read<GoogleSignInController>().signOut();
                      Navigator.of(context).pop();
                    },
                  ),
                );
              },
            ),
    );
  }

  Widget _buildSection({
    required String title,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(title),
        SizedBox(height: AppSpacing.spacing2),
        child,
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: AppTypography.titleMedium.copyWith(
        color: AppColors.textSecondary,
        fontWeight: AppTypography.weightSemiBold,
      ),
    );
  }

  Widget _buildTokenCard() {
    return Container(
      padding: EdgeInsets.all(AppSpacing.spacing4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppText.get('settings_developer_token',
                    fallback: 'Access Token'),
                style: AppTypography.titleSmall
                    .copyWith(color: AppColors.textPrimary),
              ),
              IconButton(
                icon: Icon(
                  Icons.copy,
                  size: AppSpacing.spacing5,
                  color: AppColors.primary,
                ),
                onPressed: _copyToken,
                tooltip:
                    AppText.get('settings_copy_token', fallback: 'Copy token'),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.spacing2),
          Text(
            _developerToken ??
                AppText.get('settings_no_token', fallback: 'No token found'),
            style: AppTypography.bodySmall.copyWith(
              fontFamily: 'monospace',
              color: AppColors.textSecondary,
            ),
            maxLines: _tokenPreviewMaxLines,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: AppSpacing.spacing2),
          Text(
            AppText.get('settings_token_usage',
                fallback:
                    'Use this token to authenticate with the Arcade Creator Web Portal.'),
            style: AppTypography.labelSmall.copyWith(color: AppColors.warning),
          ),
        ],
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
      trailing: Icon(Icons.chevron_right, color: AppColors.textTertiary),
    );
  }
}
