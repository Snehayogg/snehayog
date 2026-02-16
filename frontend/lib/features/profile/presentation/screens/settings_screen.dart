import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayu/shared/theme/app_theme.dart';
import 'package:vayu/shared/utils/app_text.dart';
import 'package:vayu/features/auth/presentation/controllers/google_sign_in_controller.dart';
import 'package:provider/provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _developerToken;
  bool _isLoading = true;

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
          content: Text(AppText.get('settings_token_copied', fallback: 'Token copied to clipboard')),
          backgroundColor: AppTheme.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      appBar: AppBar(
        title: Text(AppText.get('settings_title', fallback: 'Settings')),
        backgroundColor: AppTheme.backgroundPrimary,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppTheme.spacing4),
              children: [
                _buildSectionHeader(AppText.get('settings_developer_header', fallback: 'Developer Settings')),
                const SizedBox(height: AppTheme.spacing2),
                _buildTokenCard(),
                const SizedBox(height: AppTheme.spacing6),
                _buildSectionHeader(AppText.get('settings_account_header', fallback: 'Account')),
                const SizedBox(height: AppTheme.spacing2),
                _buildActionTile(
                  title: AppText.get('btn_logout', fallback: 'Logout'),
                  icon: Icons.logout,
                  color: AppTheme.error,
                  onTap: () {
                    context.read<GoogleSignInController>().signOut();
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: AppTheme.titleMedium.copyWith(
        color: AppTheme.textSecondary,
        fontWeight: AppTheme.weightSemiBold,
      ),
    );
  }

  Widget _buildTokenCard() {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing4),
      decoration: BoxDecoration(
        color: AppTheme.backgroundSecondary,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.borderPrimary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppText.get('settings_developer_token', fallback: 'Access Token'),
                style: AppTheme.titleSmall.copyWith(color: AppTheme.textPrimary),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 20, color: AppTheme.primary),
                onPressed: _copyToken,
                tooltip: 'Copy Token',
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing2),
          Text(
            _developerToken ?? 'No token found',
            style: AppTheme.bodySmall.copyWith(
              fontFamily: 'monospace',
              color: AppTheme.textSecondary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppTheme.spacing2),
          Text(
             AppText.get('settings_token_usage', fallback: 'Use this token to authenticate with the Game Creator Web Portal.'),
            style: AppTheme.labelSmall.copyWith(color: AppTheme.warning),
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
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: AppTheme.bodyMedium.copyWith(color: color),
      ),
      tileColor: AppTheme.backgroundSecondary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        side: BorderSide(color: AppTheme.borderPrimary),
      ),
    );
  }
}
