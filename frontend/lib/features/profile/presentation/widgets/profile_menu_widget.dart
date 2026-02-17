import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vayu/features/profile/presentation/managers/profile_state_manager.dart';
import 'package:vayu/features/profile/presentation/managers/game_creator_manager.dart';
import 'package:vayu/shared/services/auto_scroll_settings.dart';
import 'package:vayu/features/profile/presentation/widgets/profile_dialogs_widget.dart';
import 'package:vayu/shared/theme/app_theme.dart';
import 'package:vayu/features/profile/presentation/screens/settings_screen.dart';

class ProfileMenuWidget extends StatelessWidget {
  final ProfileStateManager stateManager;
  final String? userId;
  final VoidCallback? onEditProfile;
  final VoidCallback? onSaveProfile;
  final VoidCallback? onCancelEdit;
  final VoidCallback? onReportUser;
  final VoidCallback? onShowFeedback;
  final VoidCallback? onShowWhatsApp;
  final VoidCallback? onShowFAQ;
  final VoidCallback? onEnterSelectionMode;
  final VoidCallback? onLogout;
  final VoidCallback? onGoogleSignIn;
  final Future<bool> Function()? onCheckPaymentSetupStatus;

  const ProfileMenuWidget({
    super.key,
    required this.stateManager,
    this.userId,
    this.onEditProfile,
    this.onSaveProfile,
    this.onCancelEdit,
    this.onReportUser,
    this.onShowFeedback,
    this.onShowWhatsApp,
    this.onShowFAQ,
    this.onEnterSelectionMode,
    this.onLogout,
    this.onGoogleSignIn,
    this.onCheckPaymentSetupStatus,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppTheme.backgroundPrimary,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.backgroundPrimary,
          border: Border(
            left: BorderSide(color: AppTheme.borderPrimary.withOpacity(0.5), width: 1),
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(AppTheme.spacing5),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundSecondary.withOpacity(0.5),
                  border: const Border(
                    bottom: BorderSide(color: AppTheme.borderPrimary, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.grid_view_rounded, color: AppTheme.primary, size: 24),
                    const SizedBox(width: AppTheme.spacing3),
                    Text(
                      'Account Menu',
                      style: AppTheme.headlineSmall.copyWith(
                        color: AppTheme.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Consumer2<ProfileStateManager, GameCreatorManager>(
                  builder: (context, stateManager, gameManager, child) {
                    List<Map<String, dynamic>> menuItems = [];

                    // Settings (New)
                    menuItems.add({
                      'title': 'Settings',
                      'icon': Icons.settings_outlined,
                      'color': AppTheme.textSecondary,
                      'onTap': () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const SettingsScreen()),
                        );
                      },
                    });

                    // Auto Scroll
                    menuItems.add({
                      'title': 'Auto Scroll',
                      'icon': Icons.swap_vert_circle_outlined,
                      'color': AppTheme.info,
                      'onTap': () async {
                        final enabled = await AutoScrollSettings.isEnabled();
                        await AutoScrollSettings.setEnabled(!enabled);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Auto Scroll: ${!enabled ? 'ON' : 'OFF'}'),
                              duration: const Duration(seconds: 1),
                              backgroundColor: AppTheme.surfacePrimary,
                            ),
                          );
                          Navigator.pop(context);
                        }
                      },
                    });

                    // Edit Profile / Save / Cancel
                    if (!stateManager.isEditing) {
                      menuItems.add({
                        'title': 'Edit Profile',
                        'icon': Icons.person_outline,
                        'color': AppTheme.success,
                        'onTap': () {
                          Navigator.pop(context);
                          onEditProfile?.call();
                        },
                      });
                    } else {
                      menuItems.add({
                        'title': 'Save',
                        'icon': Icons.check_circle_outline,
                        'color': AppTheme.success,
                        'onTap': () {
                          Navigator.pop(context);
                          onSaveProfile?.call();
                        },
                      });
                      menuItems.add({
                        'title': 'Cancel',
                        'icon': Icons.cancel_outlined,
                        'color': AppTheme.error,
                        'onTap': () {
                          Navigator.pop(context);
                          onCancelEdit?.call();
                        },
                      });
                    }


                    // Creator Mode Toggle
                    menuItems.add({
                      'title': gameManager.isCreatorMode ? 'Video Studio' : 'Arcade Studio',
                      'icon': gameManager.isCreatorMode ? Icons.video_library_outlined : Icons.sports_esports,
                      'color': AppTheme.primary,
                      'onTap': () {
                        Navigator.pop(context);
                        gameManager.toggleCreatorMode();
                      },
                    });

                    // Report User
                    if (userId != null &&
                        ((stateManager.userData?['_id'] ??
                                stateManager.userData?['id'] ??
                                stateManager.userData?['googleId']) !=
                            userId)) {
                      menuItems.add({
                        'title': 'Report',
                        'icon': Icons.report_gmailerrorred_outlined,
                        'color': AppTheme.error,
                        'onTap': () {
                          Navigator.pop(context);
                          onReportUser?.call();
                        },
                      });
                    }

                    // Support Chat (Replaced Feedback)
                    menuItems.add({
                      'title': 'Support Chat',
                      'icon': Icons.chat,
                      'color': const Color(0xFF10B981),
                      'onTap': () {
                        Navigator.pop(context);
                        onShowWhatsApp?.call();
                      },
                    });

                    // FAQ
                    menuItems.add({
                      'title': 'Help & FAQ',
                      'icon': Icons.help_outline_rounded,
                      'color': AppTheme.primaryLight,
                      'onTap': () {
                        Navigator.pop(context);
                        onShowFAQ?.call();
                      },
                    });

                    // Legal & About
                    menuItems.add({
                      'title': 'Legal',
                      'icon': Icons.gavel_rounded,
                      'color': AppTheme.textSecondary,
                      'onTap': () {
                        Navigator.pop(context);
                        ProfileDialogsWidget.showLegalBottomSheet(context);
                      },
                    });

                    // Delete Videos
                    if (stateManager.isOwner) {
                      menuItems.add({
                        'title': 'Manage Content',
                        'icon': Icons.delete_sweep_outlined,
                        'color': AppTheme.error,
                        'onTap': () {
                          Navigator.pop(context);
                          onEnterSelectionMode?.call();
                        },
                      });
                    }

                    // Sign Out (Moved to bottom or kept in grid?)
                    menuItems.add({
                      'title': 'Logout',
                      'icon': Icons.logout_rounded,
                      'color': AppTheme.error,
                      'onTap': () {
                        Navigator.pop(context);
                        onLogout?.call();
                      },
                    });

                    return GridView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spacing4,
                        vertical: AppTheme.spacing2,
                      ),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: AppTheme.spacing3,
                        mainAxisSpacing: AppTheme.spacing3,
                        childAspectRatio: 1.1,
                      ),
                      itemCount: menuItems.length,
                      itemBuilder: (context, index) {
                        final item = menuItems[index];
                        return _buildMenuBox(
                          title: item['title'],
                          icon: item['icon'],
                          color: item['color'],
                          onTap: item['onTap'],
                        );
                      },
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppTheme.spacing5),
                child: Text(
                  'Vayu v1.1.0',
                  style: AppTheme.labelSmall.copyWith(color: AppTheme.textTertiary),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuBox({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.backgroundSecondary.withOpacity(0.3),
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            border: Border.all(
              color: AppTheme.borderPrimary.withOpacity(0.5),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(AppTheme.spacing2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 22,
                ),
              ),
              const SizedBox(height: AppTheme.spacing2),
              Text(
                title,
                style: AppTheme.labelMedium.copyWith(
                  color: AppTheme.textPrimary,
                  fontWeight: AppTheme.weightMedium,
                  fontSize: 11,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
