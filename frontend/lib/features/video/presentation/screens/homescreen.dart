import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:talker_flutter/talker_flutter.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:vayu/features/video/presentation/managers/main_controller.dart';
import 'package:vayu/features/profile/presentation/screens/profile_screen.dart';
import 'package:vayu/features/video/presentation/screens/upload_screen.dart';
import 'package:vayu/features/video/presentation/screens/vayu_screen.dart';
import 'package:vayu/features/video/presentation/screens/video_screen.dart';
import 'package:vayu/features/auth/data/services/authservices.dart';
import 'package:vayu/features/profile/data/services/background_profile_preloader.dart';
import 'package:vayu/features/onboarding/data/services/location_onboarding_service.dart';
import 'package:vayu/shared/utils/app_logger.dart';
import 'package:vayu/features/onboarding/presentation/managers/app_initialization_manager.dart';
import 'package:vayu/features/games/presentation/screens/games_feed_screen.dart'; // Import GamesFeedScreen
import 'package:in_app_update/in_app_update.dart';
import 'package:vayu/shared/theme/app_theme.dart';
import 'package:vayu/shared/managers/activity_recovery_manager.dart';
import 'package:vayu/shared/models/app_activity.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final _videoScreenKey = GlobalKey();
  final _vayuScreenKey = GlobalKey<VayuScreenState>();
  final _profileScreenKey = GlobalKey<State<ProfileScreen>>();
  final AuthService _authService = AuthService();

  // **NEW: Track refresh state for visual feedback**
  bool _isRefreshing = false;

  // **NEW: Animation controller for refresh icon**
  late AnimationController _refreshAnimationController;

  // **BACKGROUND PRELOADING: Preload profile data when user is on video feed**
  final BackgroundProfilePreloader _profilePreloader =
      BackgroundProfilePreloader();
  bool _hasCheckedForUpdates = false;

  Future<void> _refreshVideoList() async {
    try {
      // Refresh the video screen
      final videoScreenState = _videoScreenKey.currentState;
      if (videoScreenState != null) {
        // Cast to access the public method and await completion
        await (videoScreenState as dynamic).refreshVideos();
      } else {
        AppLogger.log('❌ MainScreen: VideoScreen state not found');
      }

      // **NEW: Also refresh the Vayu screen videos**
      try {
        VayuScreen.refresh(_vayuScreenKey);
      } catch (e) {
        AppLogger.log('❌ MainScreen: Error refreshing Vayu videos: $e');
      }

      // Navigate to video tab ONLY if user is still on upload tab (index 3)
      final mainController = Provider.of<MainController>(context, listen: false);
      if (mainController.currentIndex == 3) {
        AppLogger.log('🔄 MainScreen: Still on upload tab, navigating to video tab');
        mainController.changeIndex(0);
      }
    } catch (e) {
      AppLogger.log('❌ MainScreen: Error in _refreshVideoList: $e');
    }
  }

  /// **NEW: Handle double-tap refresh with visual feedback and error handling**
  Future<void> _handleYugTabDoubleTap() async {
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

      print('🔄 MainScreen: Double-tap on Yug tab detected - starting refresh');

      // Get the video screen state
      State? videoScreenState = _videoScreenKey.currentState;
      if (videoScreenState == null) {
        await Future.delayed(const Duration(milliseconds: 32));
        videoScreenState = _videoScreenKey.currentState;
      }
      if (videoScreenState != null) {
        // Call refresh method with await
        await (videoScreenState as dynamic).refreshVideos();
        print('✅ MainScreen: Video refresh completed via Yug tab double-tap');

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

  /// **IN-APP UPDATE: Check for Google Play updates (flexible preferred)**
  Future<void> _checkForAppUpdates() async {
    if (_hasCheckedForUpdates || !mounted) return;
    if (!Platform.isAndroid) {
      _hasCheckedForUpdates = true;
      return;
    }

    try {
      final info = await InAppUpdate.checkForUpdate();
      _hasCheckedForUpdates = true;

      if (info.updateAvailability ==
          UpdateAvailability.developerTriggeredUpdateInProgress) {
        await InAppUpdate.completeFlexibleUpdate();
        return;
      }

      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        if (info.immediateUpdateAllowed) {
          await InAppUpdate.performImmediateUpdate();
        } else if (info.flexibleUpdateAllowed) {
          final result = await InAppUpdate.startFlexibleUpdate();
          if (result == AppUpdateResult.success) {
            await InAppUpdate.completeFlexibleUpdate();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Update installed, restarting...'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('In-app update check failed: $e');
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

    // **NEW: Restore last tab index when app starts**
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreLastTabIndex();
    });

    // **BACKGROUND PRELOADING: Start preloading profile data when app opens (user starts on Yug tab)**
    WidgetsBinding.instance.addPostFrameCallback((_) {
      print(
          '🚀 MainScreen: Starting background profile preloading on app start');
      _profilePreloader.startBackgroundPreloading();

      // **LOCATION ONBOARDING: Check and show location permission request**
      _checkAndShowLocationOnboarding();

      // **ACTIVITY RECOVERY: Check for recoverable activity (Upload, etc.)**
      _checkActivityRecovery();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForAppUpdates();
    });

    // **STAGE 3: BACKGROUND SDK INITIALIZATION (Firebase, AdMob, etc.)**
    // Delay initialization to prevent stutter during initial screen mount
    // **DEBUG OPTIMIZATION: Longer delay in debug mode to prevent ANR**
    const stage3Delay = kDebugMode ? Duration(seconds: 15) : Duration(seconds: 5);
    Future.delayed(stage3Delay, () {
      if (mounted) {
        AppLogger.log('🚀 MainScreen: Triggering Stage 3 Initialization');
        AppInitializationManager.instance.initializeStage3();
      }
    });
  }

  /// **NEW: Restore last tab index from saved state**
  Future<void> _restoreLastTabIndex() async {
    try {
      final mainController =
          Provider.of<MainController>(context, listen: false);
      
      // Check for high-priority activity recovery first
      final activity = await ActivityRecoveryManager().getSavedActivity();
      if (activity != null) {
        if (activity.type == ActivityType.videoUpload) {
          print('🚀 MainScreen: Recoverable upload activity found, switching to upload tab');
          mainController.changeIndex(3);
          return;
        } else if (activity.type == ActivityType.adCreation) {
          print('🚀 MainScreen: Recoverable ad creation activity found, switching to account tab');
          mainController.changeIndex(4); // Account tab
          return;
        }
      }

      final restoredIndex = await mainController.restoreLastTabIndex();
      print('✅ MainScreen: Restored to tab index $restoredIndex');
    } catch (e) {
      print('❌ MainScreen: Error restoring tab index: $e');
    }
  }

  /// **NEW: Check for activity recovery without changing tab (for other cases)**
  Future<void> _checkActivityRecovery() async {
    // This can handle other activity types that don't need a tab switch
    // but might need global management.
  }

  /// Check if JWT token is valid and handle expired tokens
  Future<void> _checkTokenValidity() async {
    try {
      // **DISABLED: Always skip login screen, never redirect to login**
      // Users can access login from settings/profile if needed
      final needsReLogin = await _authService.needsReLogin();
      if (needsReLogin) {
        print(
            '⚠️ MainScreen: Token validation failed, clearing expired tokens');
        await _authService.clearExpiredTokens();
        // **DISABLED: No redirect to login screen - user stays on home screen**
        print(
            'ℹ️ MainScreen: Token expired but staying on home screen (login disabled)');
      }
    } catch (e) {
      print('❌ MainScreen: Error checking token validity: $e');
    }
  }

  /// Check and show location onboarding if needed
  Future<void> _checkAndShowLocationOnboarding() async {
    try {
      print('📍 MainScreen: Checking location onboarding status...');

      // Wait a bit to ensure the app is fully loaded
      await Future.delayed(const Duration(seconds: 2));

      if (!mounted) return;

      final shouldShow =
          await LocationOnboardingService.shouldShowLocationOnboarding();
      print('📍 MainScreen: Should show location onboarding: $shouldShow');

      if (shouldShow) {
        print('📍 MainScreen: Showing location onboarding dialog...');
        final result =
            await LocationOnboardingService.showLocationOnboarding(context);
        print('📍 MainScreen: Location onboarding result: $result');

        if (result) {
          print('✅ MainScreen: Location permission granted successfully');
          // You can add additional logic here, like getting current location
          // or updating user preferences
        } else {
          print('❌ MainScreen: Location permission not granted');
        }
      } else {
        print('📍 MainScreen: Location onboarding not needed');
      }
    } catch (e) {
      print('❌ MainScreen: Error in location onboarding: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // **NEW: Dispose animation controller**
    _refreshAnimationController.dispose();
    // **BACKGROUND PRELOADING: Dispose preloader**
    _profilePreloader.dispose();
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
      // **NEW: Save navigation state when app goes to background**
      mainController.saveStateForBackground();
    } else if (state == AppLifecycleState.resumed) {
      mainController.handleAppForegrounded();
    }
  }

  /// Handle back button press with proper navigation lifecycle
  Future<void> _handleBackPress(MainController mainController) async {
    // Use MainController's back button handling logic
    final shouldExit = mainController.handleBackPress();

    if (shouldExit) {
      // If we're on home tab, directly exit the app
      print('🔙 MainScreen: Back button pressed on home tab, closing app');
      SystemNavigator.pop();
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

        // **BACKGROUND PRELOADING: Stop preloading when leaving Yug tab**
        print(
            '⏸️ MainScreen: Stopping background profile preloading (leaving Yug tab)');
        _profilePreloader.stopBackgroundPreloading();
      }

      // **BACKGROUND PRELOADING: Start preloading when switching TO Yug tab**
      if (index == 0) {
        print(
            '🚀 MainScreen: Starting background profile preloading (switching to Yug tab)');
        _profilePreloader.startBackgroundPreloading();
      }

      // **VAYU TAB AUTO-LOAD: Trigger refresh if Vayu tab is selected and empty**
      if (index == 1) {
        print('🔄 MainScreen: Switching to Vayu tab - checking if refresh is needed');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final vayuState = _vayuScreenKey.currentState;
          if (vayuState != null && vayuState.mounted) {
            // Access _videos via dynamic since it's private in VayuScreenState
            final videos = (vayuState as dynamic)._videos as List?;
            if (videos == null || videos.isEmpty) {
              print('🔄 MainScreen: Vayu list is empty, triggering auto-load');
              vayuState.refreshVideos();
            }
          }
        });
      }

      // If switching to profile tab, ensure profile data is loaded
      if (index == 4) { // Profile is now index 4
        print(
            '🔄 Homescreen: Switching to profile tab - ensuring profile data is loaded');

        // Force immediate data load when profile tab is selected
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final profileScreenState = _profileScreenKey.currentState;
          if (profileScreenState != null && mounted) {
            try {
              // Call the public method through dynamic to avoid type casting issues
              (profileScreenState as dynamic).onProfileTabSelected();
              print('✅ Homescreen: Successfully triggered profile data load');
            } catch (e) {
              print('⚠️ Homescreen: Error calling onProfileTabSelected: $e');
            }
          }
        });
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
          canPop: false, // Prevent default back behavior
          onPopInvokedWithResult: (didPop, result) async {
            await _handleBackPress(mainController);
          },
          child: Scaffold(
            backgroundColor: AppTheme.backgroundPrimary,
            floatingActionButton: kDebugMode
                ? FloatingActionButton(
                    mini: true,
                    backgroundColor: Colors.deepPurple.withOpacity(0.8),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TalkerScreen(
                            talker: AppLogger.talker,
                            theme: const TalkerScreenTheme(
                              backgroundColor: Color(0xFF1A1A2E),
                              cardColor: Color(0xFF16213E),
                            ),
                          ),
                        ),
                      );
                    },
                    child: const Icon(Icons.bug_report, color: Colors.white, size: 20),
                  )
                : null,
            body: IndexedStack(
              index: mainController.currentIndex,
              children: [
                VideoScreen(
                  key: _videoScreenKey,
                  initialVideos: AppInitializationManager.instance.initialVideos,
                ),
                VayuScreen(key: _vayuScreenKey),
                const GamesFeedScreen(key: PageStorageKey('gamesFeedScreen')), // Index 2: Games
                UploadScreen(
                  key: const PageStorageKey('uploadScreen'),
                  onVideoUploaded: _refreshVideoList,
                ),
                ProfileScreen(
                  key: _profileScreenKey,
                ),
              ],
            ),
            bottomNavigationBar: RepaintBoundary(
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.backgroundPrimary,
                  border: const Border(
                    top: BorderSide(color: AppTheme.borderPrimary, width: 0.5),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, -4),
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: Container(
                  height: 60 + MediaQuery.of(context).padding.bottom,
                  padding: EdgeInsets.only(
                    left: 4,
                    right: 4,
                    top: 2,
                    bottom: math.max(2.0, MediaQuery.of(context).padding.bottom),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildNavItem(
                        index: 0,
                        currentIndex: mainController.currentIndex,
                        icon: Icons.play_circle_filled,
                        label: 'Yug',
                        onTap: () => _handleNavTap(0, mainController),
                        mainController: mainController,
                      ),
                      _buildNavItem(
                        index: 1,
                        currentIndex: mainController.currentIndex,
                        icon: Icons.video_camera_front_rounded,
                        label: 'Vayu',
                        onTap: () => _handleNavTap(1, mainController),
                        mainController: mainController,
                      ),
                      _buildNavItem(
                        index: 2,
                        currentIndex: mainController.currentIndex,
                        icon: Icons.sports_esports, // Game Controller Icon
                        label: 'Arcade',
                        onTap: () => _handleNavTap(2, mainController),
                        mainController: mainController,
                      ),
                      _buildNavItem(
                        index: 3,
                        currentIndex: mainController.currentIndex,
                        icon: Icons.add,
                        label: 'Upload',
                        onTap: () => _handleNavTap(3, mainController),
                        mainController: mainController,
                      ),
                      _buildNavItem(
                        index: 4,
                        currentIndex: mainController.currentIndex,
                        icon: Icons.person_outline_rounded,
                        label: 'Account',
                        onTap: () => _handleNavTap(4, mainController),
                        mainController: mainController,
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

  /// Build navigation item with double-tap support for Yug tab
  Widget _buildNavItem({
    required int index,
    required int currentIndex,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required MainController mainController,
  }) {
    final isSelected = currentIndex == index;
    final isYugTab = index == 0; // Yug tab is at index 0
    final isRefreshingYug = isYugTab && _isRefreshing;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        onDoubleTap: isYugTab ? _handleYugTabDoubleTap : null,
        behavior: HitTestBehavior.opaque, // **FIX: Make entire area tappable**
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(
              horizontal: 2, // Reduced from 4 to 2
              vertical: 0), // Reduced from 1 to 0 for tighter spacing
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isRefreshingYug)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  child: RotationTransition(
                    turns: _refreshAnimationController,
                    child: Container(
                      width: 32, // Same size for all icons
                      height: 32, // Same size for all icons
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF2196F3).withOpacity(0.2)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        Icons.refresh,
                        size: isSelected ? 30 : 28, // Same size for all icons
                        color: isSelected
                            ? AppTheme.primary
                            : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                )
              else
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 32, // Same size for all icons
                  height: 32, // Same size for all icons
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primary.withValues(alpha:0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    icon,
                    size: isSelected ? 30 : 28, // Same size for all icons
                    color: isSelected
                        ? AppTheme.primary
                        : AppTheme.textSecondary,
                  ),
                ),

              // Label always visible below icon (removed SizedBox completely)
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  fontSize: 9, // Increased from 7 to 9 for better readability
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected
                      ? AppTheme.primary
                      : AppTheme.textSecondary,
                  letterSpacing: 0.2,
                ),
                child: Text(isRefreshingYug ? 'Refreshing...' : label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
