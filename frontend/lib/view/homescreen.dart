import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:snehayog/controller/main_controller.dart';
import 'package:snehayog/view/screens/profile_screen.dart';
import 'package:snehayog/view/screens/long_video.dart';
import 'package:snehayog/view/screens/upload_screen.dart';
import 'package:snehayog/view/screens/video_screen.dart';
import 'package:snehayog/services/authservices.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final _videoScreenKey = GlobalKey();
  final _profileScreenKey = GlobalKey<State<ProfileScreen>>();
  final AuthService _authService = AuthService();

  // **NEW: Track refresh state for visual feedback**
  bool _isRefreshing = false;

  // **NEW: Animation controller for refresh icon**
  late AnimationController _refreshAnimationController;

  Future<void> _refreshVideoList() async {
    print('🔄 MainScreen: _refreshVideoList() called');

    try {
      // Refresh the video screen
      final videoScreenState = _videoScreenKey.currentState;
      if (videoScreenState != null) {
        print(
            '🔄 MainScreen: VideoScreen state found, calling refreshVideos()');
        // Cast to access the public method and await completion
        await (videoScreenState as dynamic).refreshVideos();
        print('✅ MainScreen: VideoScreen refresh completed');
      } else {
        print('❌ MainScreen: VideoScreen state not found');
      }

      // Also refresh the profile screen videos
      print('🔄 MainScreen: Refreshing ProfileScreen videos');
      try {
        ProfileScreen.refreshVideos(_profileScreenKey);
        print('✅ MainScreen: Profile videos refreshed successfully');
      } catch (e) {
        print('❌ MainScreen: Error refreshing profile videos: $e');
      }

      // Navigate to video tab to show the refreshed content
      final mainController =
          Provider.of<MainController>(context, listen: false);
      if (mainController.currentIndex != 0) {
        print('🔄 MainScreen: Navigating to video tab to show new upload');
        mainController.changeIndex(0);
      }
    } catch (e) {
      print('❌ MainScreen: Error in _refreshVideoList: $e');
    }
  }

  /// **NEW: Handle double-tap refresh with visual feedback and error handling**
  Future<void> _handleYogTabDoubleTap() async {
    if (_isRefreshing) {
      print('🔄 MainScreen: Already refreshing, ignoring double-tap');
      return;
    }

    try {
      // Haptic feedback to indicate action
      HapticFeedback.mediumImpact();

      // Set refreshing state and start animation
      setState(() {
        _isRefreshing = true;
      });

      // Start refresh animation
      _refreshAnimationController.repeat();

      print('🔄 MainScreen: Double-tap on Yog tab detected - starting refresh');

      // Get the video screen state
      final videoScreenState = _videoScreenKey.currentState;
      if (videoScreenState != null) {
        // Call refresh method with await
        await (videoScreenState as dynamic).refreshVideos();
        print('✅ MainScreen: Video refresh completed via Yog tab double-tap');

        // Show success feedback
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.refresh, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('Videos refreshed!'),
                ],
              ),
              backgroundColor: Colors.green[600],
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      } else {
        print('❌ MainScreen: VideoScreen state not found');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('Failed to refresh videos'),
                ],
              ),
              backgroundColor: Colors.red[600],
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      }
    } catch (e) {
      print('❌ MainScreen: Error in double-tap refresh: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Failed to refresh videos'),
              ],
            ),
            backgroundColor: Colors.red[600],
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } finally {
      // Reset refreshing state and stop animation
      if (mounted) {
        _refreshAnimationController.stop();
        _refreshAnimationController.reset();
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // **NEW: Initialize refresh animation controller**
    _refreshAnimationController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );

    _checkTokenValidity();
  }

  /// Check if JWT token is valid and handle expired tokens
  Future<void> _checkTokenValidity() async {
    try {
      final needsReLogin = await _authService.needsReLogin();
      if (needsReLogin) {
        print(
            '⚠️ MainScreen: Token validation failed, clearing expired tokens');
        await _authService.clearExpiredTokens();

        // Show re-login dialog
        if (mounted) {
          _showReLoginDialog();
        }
      }
    } catch (e) {
      print('❌ MainScreen: Error checking token validity: $e');
    }
  }

  /// Show re-login dialog when tokens are expired
  void _showReLoginDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('🔄 Session Expired'),
        content: const Text(
          'Your session has expired. Please sign in again to continue using the app.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _authService.signInWithGoogle();
            },
            child: const Text('Sign In Again'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // **NEW: Dispose animation controller**
    _refreshAnimationController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    final mainController = Provider.of<MainController>(context, listen: false);

    // **FIXED: Use dedicated methods for better audio leak prevention**
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      mainController.handleAppBackgrounded();
    } else if (state == AppLifecycleState.resumed) {
      mainController.handleAppForegrounded();
    }
  }

  // Method to handle navigation taps
  void _handleNavTap(int index, MainController mainController) {
    if (index != mainController.currentIndex) {
      print(
          'Homescreen: Switching from index ${mainController.currentIndex} to $index');

      // If leaving video tab, immediately pause videos through MainController
      if (mainController.currentIndex == 0) {
        print('Homescreen: Leaving video tab, pausing videos immediately');
        mainController.forcePauseVideos();
      }

      // If switching to profile tab, ensure profile data is loaded
      if (index == 3) {
        print(
            '🔄 Homescreen: Switching to profile tab - ensuring profile data is loaded');
        final profileScreenState = _profileScreenKey.currentState;
        if (profileScreenState != null) {
          // Call the profile loading method if it exists
          try {
            (profileScreenState as dynamic).onProfileTabSelected();
          } catch (e) {
            print('⚠️ Homescreen: Could not call onProfileTabSelected: $e');
          }
        }
      }

      // Change index - MainController will handle additional video control
      mainController.changeIndex(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MainController>(
      builder: (context, mainController, child) {
        return PopScope(
          onPopInvokedWithResult: (didPop, result) async {
            // If not on Home (Yog) tab, go to Home instead of exiting
            if (mainController.currentIndex != 0) {
              mainController.changeIndex(0);
            }
            // Don't return anything - let the system handle the back press
          },
          child: Scaffold(
            backgroundColor: Colors.white,
            body: IndexedStack(
              index: mainController.currentIndex,
              children: [
                const VideoScreen(
                  key: PageStorageKey('videoScreen'),
                ),
                const SnehaScreen(key: PageStorageKey('snehaScreen')),
                UploadScreen(
                  key: const PageStorageKey('uploadScreen'),
                  onVideoUploaded: _refreshVideoList,
                ),
                ProfileScreen(
                  key: _profileScreenKey,
                ),
              ],
            ),
            bottomNavigationBar: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 20,
                    offset: const Offset(0, -2),
                    spreadRadius: 0,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, -1),
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: SafeArea(
                child: Container(
                  height: 70,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildNavItem(
                        index: 0,
                        currentIndex: mainController.currentIndex,
                        icon: Icons.play_circle_filled,
                        label: 'Yog',
                        onTap: () => _handleNavTap(0, mainController),
                      ),
                      _buildNavItem(
                        index: 1,
                        currentIndex: mainController.currentIndex,
                        icon: Icons.video_camera_front_rounded,
                        label: 'Sneha',
                        onTap: () => _handleNavTap(1, mainController),
                      ),
                      _buildNavItem(
                        index: 2,
                        currentIndex: mainController.currentIndex,
                        icon: Icons.add_circle_outline,
                        label: 'Upload',
                        onTap: () => _handleNavTap(2, mainController),
                        isSpecial: true,
                      ),
                      _buildNavItem(
                        index: 3,
                        currentIndex: mainController.currentIndex,
                        icon: Icons.person_outline_rounded,
                        label: 'Profile',
                        onTap: () => _handleNavTap(3, mainController),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Build navigation item with double-tap support for Yog tab
  Widget _buildNavItem({
    required int index,
    required int currentIndex,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isSpecial = false,
  }) {
    final isSelected = currentIndex == index;
    final isUpload = index == 2;
    final isYogTab = index == 0; // Yog tab is at index 0
    final isRefreshingYog = isYogTab && _isRefreshing;

    return GestureDetector(
      onTap: onTap,
      onDoubleTap: isYogTab ? _handleYogTabDoubleTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 16 : 12,
          vertical: isSelected ? 12 : 8,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF424242).withOpacity(0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(
            isSelected ? 16 : 12,
          ),
          border: isSelected
              ? Border.all(
                  color: const Color(0xFF424242).withOpacity(0.2),
                  width: 1.5,
                )
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon with special handling for upload and refresh animation for Yog
            if (isUpload && isSpecial)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF424242).withOpacity(0.1),
                      const Color(0xFF757575).withOpacity(0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: isSelected ? 28 : 24,
                  color: isSelected
                      ? const Color(0xFF424242)
                      : const Color(0xFF757575),
                ),
              )
            else if (isRefreshingYog)
              // **NEW: Show rotating refresh icon when Yog tab is refreshing**
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                child: RotationTransition(
                  turns: _refreshAnimationController,
                  child: Icon(
                    Icons.refresh,
                    size: isSelected ? 28 : 24,
                    color: const Color(0xFF424242),
                  ),
                ),
              )
            else
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  icon,
                  size: isSelected ? 28 : 24,
                  color: isSelected
                      ? const Color(0xFF424242)
                      : const Color(0xFF757575),
                ),
              ),

            // Only show label if this tab is currently selected
            if (isSelected) ...[
              const SizedBox(width: 8),

              // Label with better typography (only visible when selected)
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF424242),
                  letterSpacing: 0.2,
                ),
                child: Text(isRefreshingYog ? 'Refreshing...' : label),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
