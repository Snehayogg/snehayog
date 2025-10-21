import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snehayog/core/managers/profile_state_manager.dart';
import 'package:snehayog/core/services/auto_scroll_settings.dart';
import 'package:snehayog/view/screens/creator_payout_dashboard.dart';

class ProfileMenuWidget extends StatelessWidget {
  final ProfileStateManager stateManager;
  final String? userId;
  final VoidCallback? onEditProfile;
  final VoidCallback? onSaveProfile;
  final VoidCallback? onCancelEdit;
  final VoidCallback? onReportUser;
  final VoidCallback? onShowFeedback;
  final VoidCallback? onShowFAQ;
  final VoidCallback? onEnterSelectionMode;
  final VoidCallback? onShowSettings;
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
    this.onShowFAQ,
    this.onEnterSelectionMode,
    this.onShowSettings,
    this.onLogout,
    this.onGoogleSignIn,
    this.onCheckPaymentSetupStatus,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Container(
        color: Colors.white,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  border: Border(
                    bottom: BorderSide(color: Colors.grey[300]!, width: 1),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.menu, color: Colors.black87),
                    SizedBox(width: 12),
                    Text(
                      'Menu',
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Consumer<ProfileStateManager>(
                  builder: (context, stateManager, child) {
                    // Create list of menu items
                    List<Map<String, dynamic>> menuItems = [];

                    // Auto Scroll item
                    menuItems.add({
                      'title': 'Auto Scroll',
                      'icon': Icons.swap_vert_circle,
                      'color': Colors.blue,
                      'onTap': () async {
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
                    });

                    // Edit Profile / Save / Cancel items
                    if (!stateManager.isEditing) {
                      menuItems.add({
                        'title': 'Edit Profile',
                        'icon': Icons.edit,
                        'color': Colors.green,
                        'onTap': () {
                          Navigator.pop(context);
                          onEditProfile?.call();
                        },
                      });
                    } else {
                      menuItems.add({
                        'title': 'Save',
                        'icon': Icons.save,
                        'color': Colors.green,
                        'onTap': () {
                          Navigator.pop(context);
                          onSaveProfile?.call();
                        },
                      });
                      menuItems.add({
                        'title': 'Cancel',
                        'icon': Icons.close,
                        'color': Colors.red,
                        'onTap': () {
                          Navigator.pop(context);
                          onCancelEdit?.call();
                        },
                      });
                    }

                    // Creator Dashboard
                    menuItems.add({
                      'title': 'Dashboard',
                      'icon': Icons.dashboard,
                      'color': Colors.purple,
                      'onTap': () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const CreatorPayoutDashboard(),
                          ),
                        );
                      },
                    });

                    // Report User (conditionally show)
                    if (userId != null &&
                        ((stateManager.userData?['_id'] ??
                                stateManager.userData?['id'] ??
                                stateManager.userData?['googleId']) !=
                            userId)) {
                      menuItems.add({
                        'title': 'Report',
                        'icon': Icons.flag_outlined,
                        'color': Colors.orange,
                        'onTap': () {
                          Navigator.pop(context);
                          onReportUser?.call();
                        },
                      });
                    }

                    // Feedback
                    menuItems.add({
                      'title': 'Feedback',
                      'icon': Icons.feedback_outlined,
                      'color': Colors.teal,
                      'onTap': () {
                        Navigator.pop(context);
                        onShowFeedback?.call();
                      },
                    });

                    // FAQ
                    menuItems.add({
                      'title': 'FAQ',
                      'icon': Icons.help_outline,
                      'color': Colors.indigo,
                      'onTap': () {
                        Navigator.pop(context);
                        onShowFAQ?.call();
                      },
                    });

                    // Delete Videos
                    menuItems.add({
                      'title': 'Delete',
                      'icon': Icons.delete_outline,
                      'color': Colors.red,
                      'onTap': () {
                        Navigator.pop(context);
                        onEnterSelectionMode?.call();
                      },
                    });

                    // Settings
                    menuItems.add({
                      'title': 'Settings',
                      'icon': Icons.settings,
                      'color': Colors.grey,
                      'onTap': () {
                        Navigator.pop(context);
                        onShowSettings?.call();
                      },
                    });

                    // Sign Out
                    menuItems.add({
                      'title': 'Sign Out',
                      'icon': Icons.logout,
                      'color': Colors.red,
                      'onTap': () {
                        Navigator.pop(context);
                        onLogout?.call();
                      },
                    });

                    return Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 1.2,
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
                      ),
                    );
                  },
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: color.withOpacity(0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
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
                color: Colors.black87,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
