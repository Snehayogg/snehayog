import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vayu/features/profile/presentation/managers/profile_state_manager.dart';
import 'package:vayu/features/profile/presentation/managers/game_creator_manager.dart';
import 'package:vayu/shared/services/auto_scroll_settings.dart';
import 'package:vayu/features/profile/presentation/widgets/profile_dialogs_widget.dart';
import 'package:vayu/shared/theme/app_theme.dart';

import 'package:vayu/features/profile/presentation/screens/creator_payment_setup_screen.dart';

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
                child: Consumer2<ProfileStateManager, GameCreatorManager>(
                  builder: (context, stateManager, gameManager, child) {
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



                    // Payment Setup
                    menuItems.add({
                      'title': 'Payment Setup',
                      'icon': Icons.payment,
                      'color': Colors.green,
                      'onTap': () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const CreatorPaymentSetupScreen(),
                          ),
                        );
                      },
                    });

                    // Game Creator Dashboard Toggle
                    menuItems.add({
                      'title': gameManager.isCreatorMode ? 'Video Creator' : 'Game Creator',
                      'icon': gameManager.isCreatorMode ? Icons.video_collection_outlined : Icons.videogame_asset_outlined,
                      'color': AppTheme.primary,
                      'onTap': () {
                        Navigator.pop(context);
                        gameManager.toggleCreatorMode();
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

                    // Legal & About
                    menuItems.add({
                      'title': 'Legal & About',
                      'icon': Icons.gavel,
                      'color': Colors.blueGrey,
                      'onTap': () {
                        Navigator.pop(context);
                        ProfileDialogsWidget.showLegalBottomSheet(context);
                      },
                    });

                    // Delete Videos (Only for owner)
                    if (stateManager.isOwner) {
                      menuItems.add({
                        'title': 'Delete',
                        'icon': Icons.delete_outline,
                        'color': Colors.red,
                        'onTap': () {
                          Navigator.pop(context);
                          onEnterSelectionMode?.call();
                        },
                      });
                    }



                    // Sign Out
                    menuItems.add({
                      'title': 'Logout',
                      'icon': Icons.logout,
                      'color': Colors.red,
                      'onTap': () {
                        Navigator.pop(context);
                        onLogout?.call();
                      },
                    });

                    return Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 1.05,
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
          borderRadius: BorderRadius.circular(8),
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
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: color,
                size: 17,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 10,
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
