import 'package:flutter/material.dart';
import 'package:snehayog/utils/responsive_helper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:snehayog/view/screens/video_screen.dart';
import 'package:snehayog/view/screens/creator_payment_setup_screen.dart';
import 'package:snehayog/view/screens/creator_revenue_screen.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:snehayog/config/app_config.dart';
import 'package:snehayog/core/managers/profile_state_manager.dart';
import 'package:provider/provider.dart';
import 'package:snehayog/core/providers/user_provider.dart';
import 'package:snehayog/model/usermodel.dart';
import 'package:snehayog/services/video_service.dart';
import 'package:snehayog/core/services/profile_screen_logger.dart';
import 'dart:async';

class ProfileScreen extends StatefulWidget {
  final String? userId;
  const ProfileScreen({super.key, this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();

  static void refreshVideos(GlobalKey<State<ProfileScreen>> key) {
    final state = key.currentState;
    if (state != null) {
      (state as _ProfileScreenState)._stateManager.refreshVideosOnly();
    }
  }
}

class _ProfileScreenState extends State<ProfileScreen>
    with AutomaticKeepAliveClientMixin {
  late final ProfileStateManager _stateManager;
  final ImagePicker _imagePicker = ImagePicker();

  // Progressive loading states
  bool _isProfileDataLoaded = false;
  bool _isVideosLoaded = false;
  bool _isFollowersLoaded = false;
  bool _isLoading = true;
  String? _error;

  // Progressive loading timers
  Timer? _progressiveLoadTimer;
  int _currentLoadStep = 0;

  @override
  void initState() {
    super.initState();
    ProfileScreenLogger.logProfileScreenInit();
    _stateManager = ProfileStateManager();

    // Start progressive loading immediately
    _startProgressiveLoading();
  }

  void _startProgressiveLoading() {
    // Step 1: Load basic profile data first (fastest)
    _loadBasicProfileData();

    // Step 2: Start progressive loading timer for other data
    _progressiveLoadTimer =
        Timer.periodic(const Duration(milliseconds: 300), (timer) {
      if (_currentLoadStep < 3) {
        _executeNextLoadStep();
      } else {
        timer.cancel();
      }
    });
  }

  void _executeNextLoadStep() {
    switch (_currentLoadStep) {
      case 0:
        // Step 1: Load videos (after profile data)
        if (_isProfileDataLoaded && !_isVideosLoaded) {
          _loadVideosProgressive();
        }
        break;
      case 1:
        // Step 2: Load followers data
        if (_isVideosLoaded && !_isFollowersLoaded) {
          _loadFollowersProgressive();
        }
        break;
      case 2:
        // Step 3: Load additional user data
        if (_isFollowersLoaded) {
          _loadAdditionalUserData();
        }
        break;
    }
    _currentLoadStep++;
  }

  Future<void> _loadBasicProfileData() async {
    try {
      ProfileScreenLogger.logProfileLoad();

      // Check authentication first
      final prefs = await SharedPreferences.getInstance();
      final hasJwtToken = prefs.getString('jwt_token') != null;
      final hasFallbackUser = prefs.getString('fallback_user') != null;

      if (!hasJwtToken && !hasFallbackUser) {
        setState(() {
          _error = 'No authentication data found';
          _isLoading = false;
        });
        return;
      }

      // Load basic profile data only
      await _stateManager.loadUserData(widget.userId);

      if (_stateManager.userData != null) {
        setState(() {
          _isProfileDataLoaded = true;
          _isLoading = false;
        });

        ProfileScreenLogger.logProfileLoadSuccess(userId: widget.userId);

        // Show success feedback
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Profile loaded! Loading videos...'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      ProfileScreenLogger.logProfileLoadError(e.toString());
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadVideosProgressive() async {
    if (_stateManager.userData == null) return;

    try {
      final currentUserId =
          _stateManager.userData!['id'] ?? _stateManager.userData!['googleId'];
      if (currentUserId != null) {
        ProfileScreenLogger.logVideoLoad(userId: currentUserId);

        // Load videos in background
        await _stateManager.loadUserVideos(currentUserId);

        setState(() {
          _isVideosLoaded = true;
        });

        ProfileScreenLogger.logVideoLoadSuccess(
            count: _stateManager.userVideos.length);

        // Show progress feedback
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '✅ ${_stateManager.userVideos.length} videos loaded! Loading followers...'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      ProfileScreenLogger.logVideoLoadError(e.toString());
      // Don't block UI for video loading errors
    }
  }

  Future<void> _loadFollowersProgressive() async {
    try {
      if (widget.userId != null) {
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        await userProvider.getUserDataWithFollowers(widget.userId!);

        setState(() {
          _isFollowersLoaded = true;
        });

        // Show progress feedback
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Followers data loaded!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 1),
            ),
          );
        }
      }
    } catch (e) {
      ProfileScreenLogger.logWarning('Followers load failed: $e');
      // Don't block UI for followers loading errors
    }
  }

  Future<void> _loadAdditionalUserData() async {
    try {
      if (widget.userId == null && _stateManager.userData != null) {
        final currentUserId = _stateManager.userData!['id'] ??
            _stateManager.userData!['googleId'];
        if (currentUserId != null) {
          final userProvider =
              Provider.of<UserProvider>(context, listen: false);
          await userProvider.getUserDataWithFollowers(currentUserId);

          // Show completion feedback
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('🎉 All profile data loaded successfully!'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      }
    } catch (e) {
      ProfileScreenLogger.logWarning('Additional user data load failed: $e');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stateManager.setContext(context);
  }

  @override
  void dispose() {
    _progressiveLoadTimer?.cancel();
    ProfileScreenLogger.logProfileScreenDispose();
    _stateManager.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  Future<void> _handleLogout() async {
    try {
      ProfileScreenLogger.logLogout();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('has_payment_setup');
      await prefs.remove('jwt_token');
      await prefs.remove('fallback_user');

      await _stateManager.handleLogout();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Logged out successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
      ProfileScreenLogger.logLogoutSuccess();
    } catch (e) {
      ProfileScreenLogger.logLogoutError(e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error logging out: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    try {
      ProfileScreenLogger.logGoogleSignIn();
      final userData = await _stateManager.handleGoogleSignIn();
      if (userData != null) {
        _restartProgressiveLoading();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Signed in successfully!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
        ProfileScreenLogger.logGoogleSignInSuccess();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sign-in failed. Please try again.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      ProfileScreenLogger.logGoogleSignInError(e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error signing in: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _restartProgressiveLoading() {
    // Reset all loading states
    setState(() {
      _isProfileDataLoaded = false;
      _isVideosLoaded = false;
      _isFollowersLoaded = false;
      _isLoading = true;
      _error = null;
      _currentLoadStep = 0;
    });

    // Cancel existing timer and restart
    _progressiveLoadTimer?.cancel();
    _startProgressiveLoading();
  }

  Future<void> _handleEditProfile() async {
    ProfileScreenLogger.logProfileEditStart();
    _stateManager.startEditing();
  }

  Future<void> _handleSaveProfile() async {
    try {
      ProfileScreenLogger.logProfileEditSave();
      final newName = _stateManager.nameController.text.trim();
      if (newName.isEmpty) {
        throw 'Name cannot be empty';
      }

      await _stateManager.saveProfile();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
      ProfileScreenLogger.logProfileEditSaveSuccess();
    } catch (e) {
      ProfileScreenLogger.logProfileEditSaveError(e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleCancelEdit() async {
    ProfileScreenLogger.logProfileEditCancel();
    _stateManager.cancelEditing();
  }

  Future<void> _handleDeleteSelectedVideos() async {
    try {
      final initialCount = _stateManager.selectedVideoIds.length;
      ProfileScreenLogger.logVideoDeletion(count: initialCount);
      final shouldDelete = await _showDeleteConfirmationDialog();
      if (!shouldDelete) return;

      await _stateManager.deleteSelectedVideos();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$initialCount videos deleted successfully!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      ProfileScreenLogger.logVideoDeletionSuccess(count: initialCount);
    } catch (e) {
      ProfileScreenLogger.logVideoDeletionError(e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_stateManager.error ?? 'Failed to delete videos'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _handleDeleteSelectedVideos(),
            ),
          ),
        );
      }
    }
  }

  Future<bool> _showDeleteConfirmationDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange),
                  SizedBox(width: 8),
                  Text('Confirm Deletion'),
                ],
              ),
              content: Text(
                'Are you sure you want to delete ${_stateManager.selectedVideoIds.length} video${_stateManager.selectedVideoIds.length == 1 ? '' : 's'}? This action cannot be undone.',
                style: const TextStyle(fontSize: 16),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  Future<void> _handleProfilePhotoChange() async {
    try {
      ProfileScreenLogger.logProfilePhotoChange();
      final XFile? image = await showDialog<XFile>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Change Profile Photo'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.camera_alt),
                  title: const Text('Take Photo'),
                  onTap: () async {
                    final XFile? photo = await _imagePicker.pickImage(
                        source: ImageSource.camera);
                    Navigator.pop(context, photo);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('Choose from Gallery'),
                  onTap: () async {
                    final XFile? photo = await _imagePicker.pickImage(
                        source: ImageSource.gallery);
                    Navigator.pop(context, photo);
                  },
                ),
              ],
            ),
          );
        },
      );

      if (image != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Uploading profile photo...'),
              duration: Duration(seconds: 1),
            ),
          );
        }

        await _stateManager.updateProfilePhoto(image.path);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile photo updated successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
        ProfileScreenLogger.logProfilePhotoChangeSuccess();
      }
    } catch (e) {
      ProfileScreenLogger.logProfilePhotoChangeError(e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error changing profile photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// **NEW: Toggle feature flags for testing**
  void _toggleFeatureFlag(String featureName) {
    // For now, just show a placeholder message since Features class is not defined
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Feature flag toggle: $featureName (Features class not implemented)'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildSignInView() {
    return RepaintBoundary(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.account_circle,
                size: 100,
                color: Color(0xFF757575),
              ),
              const SizedBox(height: 20),
              const Text(
                'Sign in to view your profile',
                style: TextStyle(
                  fontSize: 20,
                  color: Color(0xFF424242),
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'You need to sign in with your Google account to access your profile, upload videos, and track your earnings.',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF757575),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _handleGoogleSignIn,
                icon: Image.network(
                  'https://www.google.com/favicon.ico',
                  height: 24,
                ),
                label: const Text('Sign in with Google'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF424242),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: Color(0xFFE0E0E0)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ChangeNotifierProvider.value(
      value: _stateManager,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: _buildAppBar(),
        body: Consumer<UserProvider>(
          builder: (context, userProvider, child) {
            UserModel? userModel;
            if (widget.userId != null) {
              userModel = userProvider.getUserData(widget.userId!);
            }
            // Use the local _stateManager directly since it's not in Provider
            return _buildBody(userProvider, userModel);
          },
        ),
        // **NEW: Floating action button for delete when videos are selected**
        floatingActionButton: Consumer<ProfileStateManager>(
          builder: (context, stateManager, child) {
            if (stateManager.isSelecting &&
                stateManager.selectedVideoIds.isNotEmpty) {
              return FloatingActionButton.extended(
                onPressed: _handleDeleteSelectedVideos,
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.delete),
                label: Text('Delete ${stateManager.selectedVideoIds.length}'),
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  Widget _buildBody(UserProvider userProvider, UserModel? userModel) {
    // Show loading indicator only for initial profile data
    if (_isLoading && !_isProfileDataLoaded) {
      return RepaintBoundary(
        child: _buildSkeletonLoading(),
      );
    }

    // Show error state
    if (_error != null) {
      // If it's an authentication error, show sign-in view
      if (_error == 'No authentication data found') {
        return _buildSignInView();
      }

      // Otherwise show error with retry
      return RepaintBoundary(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red[300],
              ),
              const SizedBox(height: 16),
              Text(
                'Failed to load profile data',
                style: TextStyle(
                  color: Colors.red[700],
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'You appear to be signed in, but we couldn\'t load your profile.',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _restartProgressiveLoading,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry Loading Profile'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _handleGoogleSignIn,
                icon: const Icon(Icons.login),
                label: const Text('Sign In Again'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.blue,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Check if we have user data
    if (_stateManager.userData == null) {
      return _buildSignInView();
    }

    // If we reach here, we have user data and can show the profile
    return RefreshIndicator(
      onRefresh: () async {
        _restartProgressiveLoading();
      },
      child: SingleChildScrollView(
        physics:
            const AlwaysScrollableScrollPhysics(), // Enable pull-to-refresh
        child: Column(
          children: [
            _buildProfileHeader(userProvider, userModel),
            _buildProfileContent(userProvider, userModel),
            // Show loading indicators for progressive loading
            if (!_isVideosLoaded) _buildVideosLoadingIndicator(),
            if (!_isFollowersLoaded && _isVideosLoaded)
              _buildFollowersLoadingIndicator(),
          ],
        ),
      ),
    );
  }

  // **NEW: Skeleton loading for better UX**
  Widget _buildSkeletonLoading() {
    return RepaintBoundary(
      child: SingleChildScrollView(
        child: Column(
          children: [
            // Profile header skeleton
            RepaintBoundary(
              child: Container(
                padding: ResponsiveHelper.getAdaptivePadding(context),
                child: Column(
                  children: [
                    // Profile picture skeleton
                    Container(
                      width: ResponsiveHelper.isMobile(context) ? 100 : 150,
                      height: ResponsiveHelper.isMobile(context) ? 100 : 150,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Name skeleton
                    Container(
                      width: 200,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Edit button skeleton
                    Container(
                      width: 120,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Stats skeleton
            RepaintBoundary(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Color(0xFFE0E0E0)),
                    bottom: BorderSide(color: Color(0xFFE0E0E0)),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(
                      3,
                      (index) => Column(
                            children: [
                              Container(
                                width: 60,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.grey[300],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                width: 80,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: Colors.grey[300],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ],
                          )),
                ),
              ),
            ),

            // Videos section skeleton
            RepaintBoundary(
              child: Padding(
                padding: ResponsiveHelper.getAdaptivePadding(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title skeleton
                    Container(
                      width: 150,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Video grid skeleton
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount:
                            ResponsiveHelper.isMobile(context) ? 2 : 3,
                        crossAxisSpacing:
                            ResponsiveHelper.isMobile(context) ? 16 : 24,
                        mainAxisSpacing:
                            ResponsiveHelper.isMobile(context) ? 16 : 24,
                        childAspectRatio:
                            ResponsiveHelper.isMobile(context) ? 0.75 : 0.8,
                      ),
                      itemCount: 6, // Show 6 skeleton videos
                      itemBuilder: (context, index) => Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: Consumer<ProfileStateManager>(
        builder: (context, stateManager, child) {
          return AppBar(
            backgroundColor: Colors.white,
            title: Text(
              stateManager.userData?['name'] ?? 'Profile',
              style: const TextStyle(color: Color(0xFF424242)),
            ),
            actions: [
              // Debug button to check cache status
              IconButton(
                icon: const Icon(Icons.bug_report, color: Colors.orange),
                onPressed: () {
                  final stats = stateManager.getCacheStats();
                  ProfileScreenLogger.logCacheStats(stats);
                  ProfileScreenLogger.logDebugInfo(
                      'User Data: ${stateManager.userData}');
                  ProfileScreenLogger.logDebugInfo(
                      'Videos Count: ${stateManager.userVideos.length}');
                  ProfileScreenLogger.logDebugInfo(
                      'Loading: ${stateManager.isLoading}');
                  ProfileScreenLogger.logDebugInfo(
                      'Error: ${stateManager.error}');

                  // **NEW: Additional debug info**
                  if (stateManager.userData != null) {
                    final currentUserId = stateManager.userData!['id'] ??
                        stateManager.userData!['googleId'];
                    ProfileScreenLogger.logDebugInfo(
                        'Current User ID: $currentUserId');
                    ProfileScreenLogger.logDebugInfo(
                        'User ID type: ${currentUserId.runtimeType}');
                  }

                  // **NEW: Check HLS conversion status for all videos**
                  _showHlsConversionStatus();

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Cache: ${stats['cacheSize']}, Videos: ${stateManager.userVideos.length}'),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.more_vert, color: Color(0xFF424242)),
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    builder: (context) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Header
                          Container(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                const Text(
                                  'Menu Options',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  onPressed: () => Navigator.pop(context),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),

                          // Menu items
                          if (stateManager.userData != null) ...[
                            ListTile(
                              leading:
                                  const Icon(Icons.delete, color: Colors.red),
                              title: const Text('Delete Videos'),
                              subtitle:
                                  const Text('Select and delete your videos'),
                              onTap: () {
                                Navigator.pop(context);
                                stateManager.enterSelectionMode();
                              },
                            ),
                            ListTile(
                              leading:
                                  const Icon(Icons.logout, color: Colors.red),
                              title: const Text('Logout'),
                              onTap: () {
                                Navigator.pop(context);
                                _handleLogout();
                              },
                            ),
                          ] else ...[
                            ListTile(
                              leading:
                                  const Icon(Icons.login, color: Colors.blue),
                              title: const Text('Sign In'),
                              onTap: () {
                                Navigator.pop(context);
                                _handleGoogleSignIn();
                              },
                            ),
                          ],
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProfileHeader(UserProvider userProvider, UserModel? userModel) {
    return RepaintBoundary(
      child: Container(
        padding: ResponsiveHelper.getAdaptivePadding(context),
        child: Column(
          children: [
            RepaintBoundary(
              child: Stack(
                children: [
                  Consumer<ProfileStateManager>(
                    builder: (context, stateManager, child) {
                      return CircleAvatar(
                        radius: ResponsiveHelper.isMobile(context) ? 50 : 75,
                        backgroundColor: const Color(0xFFF5F5F5),
                        // **FIXED: Use ProfileStateManager data first, then fall back to UserProvider data**
                        backgroundImage: _getProfileImage(),
                        onBackgroundImageError: (exception, stackTrace) {
                          ProfileScreenLogger.logError(
                              'Error loading profile image: $exception');
                        },
                        child: _getProfileImage() == null
                            ? Icon(
                                Icons.person,
                                size: ResponsiveHelper.getAdaptiveIconSize(
                                    context),
                                color: const Color(0xFF757575),
                              )
                            : null,
                      );
                    },
                  ),
                  Consumer<ProfileStateManager>(
                    builder: (context, stateManager, child) {
                      if (stateManager.isEditing) {
                        return Positioned(
                          bottom: 0,
                          right: 0,
                          child: IconButton(
                            icon: const Icon(Icons.camera_alt),
                            onPressed: _handleProfilePhotoChange,
                            color: Colors.white,
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.blue,
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ),
            ),
            SizedBox(height: ResponsiveHelper.isMobile(context) ? 16 : 24),

            // Authentication status indicator
            RepaintBoundary(
              child: FutureBuilder<SharedPreferences>(
                future: SharedPreferences.getInstance(),
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    final prefs = snapshot.data!;
                    final hasJwtToken = prefs.getString('jwt_token') != null;
                    final hasFallbackUser =
                        prefs.getString('fallback_user') != null;
                    final isAuthenticated = hasJwtToken || hasFallbackUser;

                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isAuthenticated
                            ? Colors.green[100]
                            : Colors.orange[100],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isAuthenticated
                              ? Colors.green[300]!
                              : Colors.orange[300]!,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isAuthenticated
                                ? Icons.check_circle
                                : Icons.warning,
                            size: 16,
                            color: isAuthenticated
                                ? Colors.green[700]
                                : Colors.orange[700],
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isAuthenticated
                                ? 'Authenticated'
                                : 'Authentication Issue',
                            style: TextStyle(
                              fontSize: 12,
                              color: isAuthenticated
                                  ? Colors.green[700]
                                  : Colors.orange[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),

            SizedBox(height: ResponsiveHelper.isMobile(context) ? 16 : 24),

            Consumer<ProfileStateManager>(
              builder: (context, stateManager, child) {
                if (stateManager.isEditing) {
                  return RepaintBoundary(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: TextField(
                        controller: stateManager.nameController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Name',
                          hintText: 'Enter a unique name',
                        ),
                      ),
                    ),
                  );
                } else {
                  return RepaintBoundary(
                    child: Text(
                      _getUserName(),
                      style: TextStyle(
                        color: const Color(0xFF424242),
                        fontSize:
                            ResponsiveHelper.getAdaptiveFontSize(context, 24),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                }
              },
            ),
            Consumer<ProfileStateManager>(
              builder: (context, stateManager, child) {
                if (stateManager.isEditing) {
                  return RepaintBoundary(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton(
                            onPressed: _handleCancelEdit,
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton(
                            onPressed: _handleSaveProfile,
                            child: const Text('Save'),
                          ),
                        ],
                      ),
                    ),
                  );
                } else {
                  return RepaintBoundary(
                    child: TextButton.icon(
                      onPressed: _handleEditProfile,
                      icon: const Icon(Icons.edit),
                      label: const Text('Edit Profile'),
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // **NEW: Helper method to get profile image with fallback logic**
  ImageProvider? _getProfileImage() {
    // **FIXED: Prioritize ProfileStateManager data, then fall back to UserProvider data**
    if (_stateManager.userData != null &&
        _stateManager.userData!['profilePic'] != null) {
      final profilePic = _stateManager.userData!['profilePic'];
      ProfileScreenLogger.logDebugInfo(
          'Using profile pic from ProfileStateManager: $profilePic');

      if (profilePic.startsWith('http')) {
        return NetworkImage(profilePic);
      } else if (profilePic.isNotEmpty) {
        try {
          return FileImage(File(profilePic));
        } catch (e) {
          ProfileScreenLogger.logWarning('Error creating FileImage: $e');
          return null;
        }
      }
    }

    // Fall back to UserProvider data
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    if (widget.userId != null) {
      final userModel = userProvider.getUserData(widget.userId!);
      if (userModel?.profilePic != null) {
        final profilePic = userModel!.profilePic;
        ProfileScreenLogger.logDebugInfo(
            'Using profile pic from UserProvider: $profilePic');

        if (profilePic.startsWith('http')) {
          return NetworkImage(profilePic);
        } else if (profilePic.isNotEmpty) {
          try {
            return FileImage(File(profilePic));
          } catch (e) {
            ProfileScreenLogger.logWarning('Error creating FileImage: $e');
            return null;
          }
        }
      }
    }

    ProfileScreenLogger.logDebugInfo('No profile pic available');
    return null;
  }

  // **NEW: Helper method to get user name with fallback logic**
  String _getUserName() {
    // **FIXED: Prioritize ProfileStateManager data, then fall back to UserProvider data**
    if (_stateManager.userData != null &&
        _stateManager.userData!['name'] != null) {
      final name = _stateManager.userData!['name'];
      ProfileScreenLogger.logDebugInfo(
          'Using name from ProfileStateManager: $name');
      return name;
    }

    // Fall back to UserProvider data
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    if (widget.userId != null) {
      final userModel = userProvider.getUserData(widget.userId!);
      if (userModel?.name != null) {
        final name = userModel!.name;
        ProfileScreenLogger.logDebugInfo('Using name from UserProvider: $name');
        return name;
      }
    }

    // Final fallback
    ProfileScreenLogger.logDebugInfo('No name available, using default');
    return 'User';
  }

  Widget _buildProfileContent(UserProvider userProvider, UserModel? userModel) {
    return RepaintBoundary(
      child: Column(
        children: [
          RepaintBoundary(
            child: Container(
              padding: EdgeInsets.symmetric(
                vertical: ResponsiveHelper.isMobile(context) ? 20 : 30,
              ),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: Color(0xFFE0E0E0)),
                  bottom: BorderSide(color: Color(0xFFE0E0E0)),
                ),
              ),
              child: Consumer<ProfileStateManager>(
                builder: (context, stateManager, child) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildStatColumn(
                        'Videos',
                        _isVideosLoaded
                            ? stateManager.userVideos.length
                            : '...',
                        isLoading: !_isVideosLoaded,
                      ),
                      _buildStatColumn(
                        'Followers',
                        _isFollowersLoaded ? _getFollowersCount() : '...',
                        isLoading: !_isFollowersLoaded,
                      ),
                      _buildStatColumn(
                        'Earnings',
                        _getCurrentMonthRevenue(), // Current month's revenue
                        isEarnings: true,
                        onTap: () async {
                          // Check if user has completed payment setup
                          final hasPaymentSetup =
                              await _checkPaymentSetupStatus();

                          if (hasPaymentSetup) {
                            // Navigate to revenue screen if payment setup is complete
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const CreatorRevenueScreen(),
                              ),
                            );
                          } else {
                            // Navigate to payment setup screen if not complete
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const CreatorPaymentSetupScreen(),
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          RepaintBoundary(
            child: Padding(
              padding: ResponsiveHelper.getAdaptivePadding(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your Videos',
                    style: TextStyle(
                      color: const Color(0xFF424242),
                      fontSize:
                          ResponsiveHelper.getAdaptiveFontSize(context, 20),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.isMobile(context) ? 8 : 12),

                  SizedBox(
                      height: ResponsiveHelper.isMobile(context) ? 16 : 24),
                  Consumer<ProfileStateManager>(
                    builder: (context, stateManager, child) {
                      if (!_isVideosLoaded) {
                        return RepaintBoundary(
                          child: Container(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              children: [
                                const SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: CircularProgressIndicator(),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Loading your videos...',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      if (stateManager.userVideos.isEmpty) {
                        return RepaintBoundary(
                          child: Container(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.video_library_outlined,
                                  size: 64,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No videos yet',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Upload your first video to get started!',
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 14,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return RepaintBoundary(
                        child: GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount:
                                ResponsiveHelper.isMobile(context) ? 2 : 3,
                            crossAxisSpacing:
                                ResponsiveHelper.isMobile(context) ? 16 : 24,
                            mainAxisSpacing:
                                ResponsiveHelper.isMobile(context) ? 16 : 24,
                            childAspectRatio:
                                ResponsiveHelper.isMobile(context) ? 0.75 : 0.8,
                          ),
                          itemCount: stateManager.userVideos.length,
                          itemBuilder: (context, index) {
                            final video = stateManager.userVideos[index];
                            final isSelected = stateManager.selectedVideoIds
                                .contains(video.id);

                            // Simplified video selection logic
                            final canSelectVideo = stateManager.isSelecting &&
                                stateManager.userData != null;
                            return RepaintBoundary(
                              child: GestureDetector(
                                onTap: () {
                                  if (!stateManager.isSelecting) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => VideoScreen(
                                          initialIndex: index,
                                          initialVideos:
                                              stateManager.userVideos,
                                        ),
                                      ),
                                    );
                                  } else if (stateManager.isSelecting &&
                                      canSelectVideo) {
                                    // Use proper logic for video selection
                                    ProfileScreenLogger.logVideoSelection(
                                        videoId: video.id,
                                        isSelected: !stateManager
                                            .selectedVideoIds
                                            .contains(video.id));
                                    ProfileScreenLogger.logDebugInfo(
                                        'Video ID: ${video.id}');
                                    ProfileScreenLogger.logDebugInfo(
                                        'Can select: $canSelectVideo');
                                    stateManager.toggleVideoSelection(video.id);
                                  } else {
                                    ProfileScreenLogger.logDebugInfo(
                                        'Video tapped but not selectable');
                                    ProfileScreenLogger.logDebugInfo(
                                        'isSelecting: ${stateManager.isSelecting}');
                                    ProfileScreenLogger.logDebugInfo(
                                        'canSelectVideo: $canSelectVideo');
                                  }
                                },
                                onLongPress: () {
                                  // Long press: Enter selection mode for deletion
                                  ProfileScreenLogger.logDebugInfo(
                                      'Long press detected on video');
                                  ProfileScreenLogger.logDebugInfo(
                                      'userData: ${stateManager.userData != null}');
                                  ProfileScreenLogger.logDebugInfo(
                                      'canSelectVideo: $canSelectVideo');
                                  ProfileScreenLogger.logDebugInfo(
                                      'isSelecting: ${stateManager.isSelecting}');

                                  if (stateManager.userData != null &&
                                      !stateManager.isSelecting) {
                                    ProfileScreenLogger.logDebugInfo(
                                        'Entering selection mode via long press');
                                    stateManager.enterSelectionMode();
                                    stateManager.toggleVideoSelection(video.id);
                                  } else {
                                    ProfileScreenLogger.logDebugInfo(
                                        'Cannot enter selection mode via long press');
                                  }
                                },
                                child: Stack(
                                  children: [
                                    AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 200),
                                      decoration: BoxDecoration(
                                        border: isSelected
                                            ? Border.all(
                                                color: Colors.blue, width: 3)
                                            : null,
                                        borderRadius: BorderRadius.circular(12),
                                        // Add shadow when selected
                                        boxShadow: isSelected
                                            ? [
                                                BoxShadow(
                                                  color: Colors.blue
                                                      .withOpacity(0.3),
                                                  blurRadius: 8,
                                                  spreadRadius: 2,
                                                )
                                              ]
                                            : null,
                                      ),
                                      child: Card(
                                        color: isSelected
                                            ? Colors.blue.withOpacity(0.05)
                                            : const Color(0xFFF5F5F5),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            Expanded(
                                              child: Stack(
                                                children: [
                                                  Image.network(
                                                    video.videoUrl,
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (context,
                                                        error, stackTrace) {
                                                      ProfileScreenLogger.logError(
                                                          'Error loading thumbnail: $error');
                                                      return Center(
                                                        child: Icon(
                                                          Icons.video_library,
                                                          color: const Color(
                                                              0xFF424242),
                                                          size: ResponsiveHelper
                                                              .getAdaptiveIconSize(
                                                                  context),
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                  // Selection overlay
                                                  if (isSelected)
                                                    Positioned.fill(
                                                      child: Container(
                                                        decoration:
                                                            BoxDecoration(
                                                          color: Colors.blue
                                                              .withOpacity(0.3),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(12),
                                                        ),
                                                        child: const Center(
                                                          child: Icon(
                                                            Icons.check_circle,
                                                            color: Colors.white,
                                                            size: 48,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            Padding(
                                              padding: EdgeInsets.all(
                                                ResponsiveHelper.isMobile(
                                                        context)
                                                    ? 8.0
                                                    : 12.0,
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    video.videoName,
                                                    style: TextStyle(
                                                      color: const Color(
                                                          0xFF424242),
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: ResponsiveHelper
                                                          .getAdaptiveFontSize(
                                                              context, 14),
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  SizedBox(
                                                      height: ResponsiveHelper
                                                              .isMobile(context)
                                                          ? 4
                                                          : 8),
                                                  Row(
                                                    children: [
                                                      Icon(
                                                        Icons.visibility,
                                                        color: const Color(
                                                            0xFF757575),
                                                        size: ResponsiveHelper
                                                                .getAdaptiveIconSize(
                                                                    context) *
                                                            0.6,
                                                      ),
                                                      SizedBox(
                                                          width: ResponsiveHelper
                                                                  .isMobile(
                                                                      context)
                                                              ? 4
                                                              : 8),
                                                      Text(
                                                        '${video.views}',
                                                        style: TextStyle(
                                                          color: const Color(
                                                              0xFF757575),
                                                          fontSize: ResponsiveHelper
                                                              .getAdaptiveFontSize(
                                                                  context, 12),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (stateManager.isSelecting &&
                                        canSelectVideo) // Use proper logic for video selection
                                      Positioned(
                                        top: 8,
                                        right: 8,
                                        child: Checkbox(
                                          value: isSelected,
                                          activeColor: Colors.blue,
                                          checkColor: Colors.white,
                                          side: const BorderSide(
                                              color: Colors.blue, width: 2),
                                          onChanged: (checked) {
                                            stateManager
                                                .toggleVideoSelection(video.id);
                                          },
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),

                  // **NEW: Delete button when videos are selected**
                  Consumer<ProfileStateManager>(
                    builder: (context, stateManager, child) {
                      if (stateManager.isSelecting &&
                          stateManager.selectedVideoIds.isNotEmpty) {
                        return RepaintBoundary(
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                const Divider(height: 1),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '${stateManager.selectedVideoIds.length} video${stateManager.selectedVideoIds.length == 1 ? '' : 's'} selected',
                                      style: TextStyle(
                                        color: Colors.blue[700],
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        TextButton(
                                          onPressed: () {
                                            stateManager.exitSelectionMode();
                                          },
                                          child: const Text('Cancel'),
                                        ),
                                        const SizedBox(width: 16),
                                        ElevatedButton.icon(
                                          onPressed:
                                              _handleDeleteSelectedVideos,
                                          icon: const Icon(Icons.delete,
                                              color: Colors.white),
                                          label: Text(
                                              'Delete ${stateManager.selectedVideoIds.length}'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.red,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 24, vertical: 12),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // **NEW: Helper method to get followers count with fallback logic**
  int _getFollowersCount() {
    // **FIXED: Prioritize UserProvider data for followers count, then fall back to ProfileStateManager**
    if (widget.userId != null) {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final userModel = userProvider.getUserData(widget.userId!);
      if (userModel?.followersCount != null) {
        ProfileScreenLogger.logDebugInfo(
            'Using followers count from UserProvider: ${userModel!.followersCount}');
        return userModel.followersCount;
      }
    }

    // Fall back to ProfileStateManager data
    if (_stateManager.userData != null &&
        _stateManager.userData!['followersCount'] != null) {
      final followersCount = _stateManager.userData!['followersCount'];
      ProfileScreenLogger.logDebugInfo(
          'Using followers count from ProfileStateManager: $followersCount');
      return followersCount;
    }

    // Final fallback
    ProfileScreenLogger.logDebugInfo(
        'No followers count available, using default');
    return 0;
  }

  Future<bool> _checkPaymentSetupStatus() async {
    try {
      // **FIXED: Prioritize SharedPreferences flag first**
      ProfileScreenLogger.logPaymentSetupCheck();
      final prefs = await SharedPreferences.getInstance();
      final hasPaymentSetup = prefs.getBool('has_payment_setup') ?? false;

      if (hasPaymentSetup) {
        ProfileScreenLogger.logPaymentSetupFound();
        return true;
      }

      // **NEW: If no flag, try to load payment setup data from backend**
      if (_stateManager.userData != null &&
          _stateManager.userData!['id'] != null) {
        ProfileScreenLogger.logDebugInfo(
            'No payment setup flag found, checking backend data...');
        final hasBackendSetup = await _checkBackendPaymentSetup();
        if (hasBackendSetup) {
          // Set the flag for future use
          await prefs.setBool('has_payment_setup', true);
          ProfileScreenLogger.logPaymentSetupFound();
          return true;
        }
      }

      ProfileScreenLogger.logPaymentSetupNotFound();
      return false;
    } catch (e) {
      ProfileScreenLogger.logPaymentSetupCheckError(e.toString());
      return false;
    }
  }

  // **NEW: Method to check payment setup from backend**
  Future<bool> _checkBackendPaymentSetup() async {
    try {
      ProfileScreenLogger.logDebugInfo(
          'Starting backend payment setup check...');
      final userData = _stateManager.getUserData();
      final token = userData?['token'];

      if (token == null) {
        ProfileScreenLogger.logError(
            'No token available for backend payment setup check');
        return false;
      }

      ProfileScreenLogger.logApiCall(
          endpoint: 'creator-payouts/profile', method: 'GET');
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/creator-payouts/profile'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      ProfileScreenLogger.logApiResponse(
        endpoint: 'creator-payouts/profile',
        statusCode: response.statusCode,
        body: response.body,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final paymentMethod = data['creator']?['preferredPaymentMethod'];
        final paymentDetails = data['paymentDetails'];

        ProfileScreenLogger.logDebugInfo('Payment method: $paymentMethod');
        ProfileScreenLogger.logDebugInfo('Payment details: $paymentDetails');

        // Check if user has completed payment setup
        if (paymentMethod != null &&
            paymentMethod.isNotEmpty &&
            paymentDetails != null) {
          ProfileScreenLogger.logPaymentSetupFound(method: paymentMethod);
          return true;
        } else {
          ProfileScreenLogger.logDebugWarning(
              'Payment setup incomplete - method: $paymentMethod, details: $paymentDetails');
        }
      } else {
        ProfileScreenLogger.logApiError(
          endpoint: 'creator-payouts/profile',
          error: 'API call failed with status ${response.statusCode}',
        );
      }

      return false;
    } catch (e) {
      ProfileScreenLogger.logApiError(
        endpoint: 'creator-payouts/profile',
        error: e.toString(),
      );
      return false;
    }
  }

  // Get current month's revenue (placeholder for now)
  double _getCurrentMonthRevenue() {
    // TODO: Implement actual revenue calculation from backend
    // For now, return 0.00
    return 0.00;
  }

  Widget _buildStatColumn(String label, dynamic value,
      {bool isEarnings = false, VoidCallback? onTap, bool isLoading = false}) {
    return RepaintBoundary(
      child: Builder(
        builder: (context) => Column(
          children: [
            GestureDetector(
              onTap: onTap,
              child: MouseRegion(
                cursor: isEarnings
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
                child: Text(
                  isLoading
                      ? '...'
                      : (isEarnings
                          ? '₹${value.toStringAsFixed(2)}'
                          : value.toString()),
                  style: TextStyle(
                    color: const Color(0xFF424242),
                    fontSize: ResponsiveHelper.getAdaptiveFontSize(context, 24),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            SizedBox(height: ResponsiveHelper.isMobile(context) ? 4 : 8),
            SizedBox(height: ResponsiveHelper.isMobile(context) ? 4 : 8),
            Text(
              label,
              style: TextStyle(
                color: const Color(0xFF757575),
                fontSize: ResponsiveHelper.getAdaptiveFontSize(context, 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _clearAuthenticationData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('jwt_token');
      await prefs.remove('fallback_user');
      await prefs.remove('has_payment_setup');
      ProfileScreenLogger.logSuccess(
          'Authentication data cleared from SharedPreferences');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Authentication data cleared.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
      await _stateManager.handleLogout(); // Also clear state manager's data
    } catch (e) {
      ProfileScreenLogger.logError('Error clearing authentication data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error clearing authentication data: $e'),
          ),
        );
      }
    }
  }

  /// Check API endpoints being used
  void _checkApiEndpoints() {
    ProfileScreenLogger.logDebugInfo('=== CHECKING API ENDPOINTS ===');

    // Check AppConfig.baseUrl
    try {
      final appConfig = AppConfig.baseUrl;
      ProfileScreenLogger.logDebugInfo('AppConfig.baseUrl: $appConfig');
    } catch (e) {
      ProfileScreenLogger.logError('Error getting AppConfig.baseUrl: $e');
    }

    // Check VideoService.baseUrl
    ProfileScreenLogger.logDebugInfo('VideoService.baseUrl: Not implemented');

    // Check if endpoints are different
    ProfileScreenLogger.logDebugInfo(
        'VideoService not implemented - skipping endpoint comparison');

    // Show in UI
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('API Endpoints Check'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Check the console for detailed endpoint information.'),
              SizedBox(height: 16),
              Text('Key endpoints used:'),
              Text('• AuthService: /api/users/profile'),
              Text('• UserService: /api/users/{userId}'),
              Text('• VideoService: /api/videos/user/{userId}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }

  /// Debug method to show current state
  void _debugState() {
    ProfileScreenLogger.logDebugState();
    ProfileScreenLogger.logDebugInfo(
        'userData: ${_stateManager.userData != null ? "Available" : "Not Available"}');
    ProfileScreenLogger.logDebugInfo('_isLoading: $_isLoading');
    ProfileScreenLogger.logDebugInfo('_error: $_error');
    ProfileScreenLogger.logDebugInfo(
        'userVideos count: ${_stateManager.userVideos.length}');
    ProfileScreenLogger.logDebugInfo('userId: ${widget.userId}');

    // **NEW: Check UserProvider data**
    if (widget.userId != null) {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final userModel = userProvider.getUserData(widget.userId!);
      ProfileScreenLogger.logDebugInfo(
          'UserProvider data: ${userModel != null ? "Available" : "Not Available"}');
      if (userModel != null) {
        ProfileScreenLogger.logDebugInfo(
            'UserProvider - Name: ${userModel.name}, Followers: ${userModel.followersCount}');
      }
    }

    // Check SharedPreferences
    SharedPreferences.getInstance().then((prefs) {
      final hasJwtToken = prefs.getString('jwt_token') != null;
      final hasFallbackUser = prefs.getString('fallback_user') != null;
      ProfileScreenLogger.logDebugInfo(
          'SharedPreferences - JWT: $hasJwtToken, Fallback: $hasFallbackUser');
    });

    // Show debug info in UI
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Debug State'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'User Data: ${_stateManager.userData != null ? "Available" : "Not Available"}'),
              Text('Loading: $_isLoading'),
              Text('Error: ${_error ?? "None"}'),
              Text('Videos: ${_stateManager.userVideos.length}'),
              Text('User ID: ${widget.userId ?? "None"}'),
              // **NEW: Show UserProvider data**
              if (widget.userId != null) ...[
                const SizedBox(height: 8),
                Consumer<UserProvider>(
                  builder: (context, userProvider, child) {
                    final userModel = userProvider.getUserData(widget.userId!);
                    return Text(
                        'UserProvider: ${userModel != null ? "Available" : "Not Available"}');
                  },
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _restartProgressiveLoading();
              },
              child: const Text('Force Load'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _forceRefreshVideos();
              },
              child: const Text('Refresh Videos'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                if (_stateManager.userData != null) {
                  final currentUserId = _stateManager.userData!['id'] ??
                      _stateManager.userData!['googleId'];
                  if (currentUserId != null) {
                    _stateManager.forceRefreshVideos(currentUserId);
                  }
                }
              },
              child: const Text('Force Refresh Videos'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _testVideoService();
              },
              child: const Text('Test VideoService'),
            ),
          ],
        ),
      );
    }
  }

  /// **NEW: Test video playback to debug issues**
  void _testVideoPlayback() {
    ProfileScreenLogger.logDebugInfo('=== TESTING VIDEO PLAYBACK ===');

    if (_stateManager.userVideos.isEmpty) {
      ProfileScreenLogger.logError('No videos available to test');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No videos available to test'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final testVideo = _stateManager.userVideos.first;
    ProfileScreenLogger.logDebugInfo(
        'Testing with video: ${testVideo.videoName}');
    ProfileScreenLogger.logDebugInfo('Video URL: ${testVideo.videoUrl}');
    ProfileScreenLogger.logDebugInfo('Video ID: ${testVideo.id}');

    // Try to navigate to VideoScreen with just this one video
    try {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VideoScreen(
            initialIndex: 0,
            initialVideos: [testVideo],
          ),
        ),
      );
      ProfileScreenLogger.logSuccess('Successfully navigated to VideoScreen');
    } catch (e) {
      ProfileScreenLogger.logError('Error navigating to VideoScreen: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// **NEW: Method to force refresh ProfileStateManager data**
  Future<void> _forceRefreshProfileData() async {
    ProfileScreenLogger.logVideoRefresh();

    try {
      // Clear any existing data by calling handleLogout and then reloading
      await _stateManager.handleLogout();

      // Force reload from scratch
      _restartProgressiveLoading();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile data refreshed successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      ProfileScreenLogger.logError('Error force refreshing profile data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error refreshing profile data: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// **NEW: Method to force refresh only videos**
  Future<void> _forceRefreshVideos() async {
    ProfileScreenLogger.logVideoRefresh();

    try {
      if (_stateManager.userData != null) {
        final currentUserId = _stateManager.userData!['id'] ??
            _stateManager.userData!['googleId'];
        if (currentUserId != null) {
          ProfileScreenLogger.logDebugInfo(
              'Refreshing videos for user: $currentUserId');
          await _stateManager.loadUserVideos(currentUserId);
          ProfileScreenLogger.logVideoRefreshSuccess(
              count: _stateManager.userVideos.length);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    'Videos refreshed: ${_stateManager.userVideos.length} videos'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } else {
          ProfileScreenLogger.logWarning(
              'No currentUserId found for video refresh');
        }
      } else {
        ProfileScreenLogger.logWarning(
            'No userData available for video refresh');
      }
    } catch (e) {
      ProfileScreenLogger.logVideoRefreshError(e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error refreshing videos: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// **NEW: Test VideoService directly**
  Future<void> _testVideoService() async {
    ProfileScreenLogger.logDebugInfo('Testing VideoService directly...');

    try {
      if (_stateManager.userData != null) {
        final currentUserId = _stateManager.userData!['id'] ??
            _stateManager.userData!['googleId'];
        if (currentUserId != null) {
          ProfileScreenLogger.logDebugInfo(
              'Testing with user ID: $currentUserId');

          // Import VideoService and test it directly
          final videoService = VideoService();
          final videos = await videoService.getUserVideos(currentUserId);

          ProfileScreenLogger.logSuccess(
              'VideoService returned ${videos.length} videos');
          for (int i = 0; i < videos.length; i++) {
            ProfileScreenLogger.logDebugInfo(
                '  Video $i: ${videos[i].videoName} (ID: ${videos[i].id})');
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content:
                    Text('VideoService test: ${videos.length} videos found'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        } else {
          ProfileScreenLogger.logWarning(
              'No currentUserId for VideoService test');
        }
      } else {
        ProfileScreenLogger.logWarning('No userData for VideoService test');
      }
    } catch (e) {
      ProfileScreenLogger.logError('VideoService test failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('VideoService test failed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// **NEW: Method to check ProfileStateManager state**
  void _checkProfileStateManagerState() {
    ProfileScreenLogger.logDebugState();
    ProfileScreenLogger.logDebugInfo('userData: ${_stateManager.userData}');
    ProfileScreenLogger.logDebugInfo('_isLoading: $_isLoading');
    ProfileScreenLogger.logDebugInfo('_error: $_error');
    ProfileScreenLogger.logDebugInfo('isEditing: ${_stateManager.isEditing}');
    ProfileScreenLogger.logDebugInfo(
        'isSelecting: ${_stateManager.isSelecting}');
    ProfileScreenLogger.logDebugInfo(
        'selectedVideoIds: ${_stateManager.selectedVideoIds}');
    ProfileScreenLogger.logDebugInfo(
        'userVideos count: ${_stateManager.userVideos.length}');
    ProfileScreenLogger.logDebugInfo(
        'nameController text: ${_stateManager.nameController.text}');

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('ProfileStateManager Debug'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('User Data: ${_stateManager.userData}'),
              Text('Loading: $_isLoading'),
              Text('Error: $_error'),
              Text('Editing: ${_stateManager.isEditing}'),
              Text('Selecting: ${_stateManager.isSelecting}'),
              Text('Selected Videos: ${_stateManager.selectedVideoIds}'),
              Text('Videos Count: ${_stateManager.userVideos.length}'),
              Text(
                  'Name Controller Text: ${_stateManager.nameController.text}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }

  /// **NEW: Method to show HLS conversion status for all videos**
  void _showHlsConversionStatus() {
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('HLS Conversion Status'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _stateManager.userVideos.map((video) {
                // **FIXED: Use existing VideoModel fields and VideoUrlService**
                final hasHlsMaster = video.hlsMasterPlaylistUrl != null &&
                    video.hlsMasterPlaylistUrl!.isNotEmpty;
                final hasHlsPlaylist = video.hlsPlaylistUrl != null &&
                    video.hlsPlaylistUrl!.isNotEmpty;
                final isHlsEncoded = video.isHLSEncoded ?? false;

                // Determine conversion status
                String status;
                Color statusColor;
                if (hasHlsMaster || hasHlsPlaylist || isHlsEncoded) {
                  status = 'HLS Ready';
                  statusColor = Colors.green;
                } else if (video.videoUrl.isNotEmpty) {
                  status = 'Needs HLS Conversion';
                  statusColor = Colors.orange;
                } else {
                  status = 'No Video URL';
                  statusColor = Colors.red;
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          '${video.videoName} (ID: ${video.id})',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: ResponsiveHelper.getAdaptiveFontSize(
                                context, 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Status: $status',
                            style: TextStyle(
                              fontSize: ResponsiveHelper.getAdaptiveFontSize(
                                  context, 12),
                              color: statusColor,
                            ),
                          ),
                          Text(
                            'HLS Master: ${hasHlsMaster ? "Yes" : "No"}',
                            style: TextStyle(
                              fontSize: ResponsiveHelper.getAdaptiveFontSize(
                                  context, 10),
                              color: hasHlsMaster ? Colors.green : Colors.grey,
                            ),
                          ),
                          Text(
                            'HLS Playlist: ${hasHlsPlaylist ? "Yes" : "No"}',
                            style: TextStyle(
                              fontSize: ResponsiveHelper.getAdaptiveFontSize(
                                  context, 10),
                              color:
                                  hasHlsPlaylist ? Colors.green : Colors.grey,
                            ),
                          ),
                          Text(
                            'HLS Encoded: ${isHlsEncoded ? "Yes" : "No"}',
                            style: TextStyle(
                              fontSize: ResponsiveHelper.getAdaptiveFontSize(
                                  context, 10),
                              color: isHlsEncoded ? Colors.green : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                // Show conversion recommendations
                _showConversionRecommendations();
              },
              child: const Text('Get Help'),
            ),
          ],
        ),
      );
    }
  }

  /// **NEW: Show conversion recommendations**
  void _showConversionRecommendations() {
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('HLS Conversion Help'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'To fix video playback issues, your videos need to be converted to HLS format:',
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 16),
              Text(
                'What is HLS?',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              SizedBox(height: 8),
              Text(
                '• HTTP Live Streaming (HLS) is a streaming protocol\n'
                '• Provides better playback compatibility\n'
                '• Enables adaptive bitrate streaming\n'
                '• Required for smooth video playback',
                style: TextStyle(fontSize: 12),
              ),
              SizedBox(height: 16),
              Text(
                'How to convert:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              SizedBox(height: 8),
              Text(
                '1. Contact support to request HLS conversion\n'
                '2. Use video processing tools (FFmpeg)\n'
                '3. Re-upload videos in HLS format\n'
                '4. Wait for automatic server-side conversion',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildFollowersLoadingIndicator() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(
            'Loading followers data...',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideosLoadingIndicator() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(
            'Loading videos...',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
