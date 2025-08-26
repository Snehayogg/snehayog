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
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _stateManager = ProfileStateManager();
    // Initialize loading state properly
    _isLoading = false;
    _loadUserData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stateManager.setContext(context);
  }

  @override
  void dispose() {
    _stateManager.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  Future<void> _loadUserData() async {
    // Remove the early return that was causing infinite loop
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Check authentication
      final prefs = await SharedPreferences.getInstance();
      final hasJwtToken = prefs.getString('jwt_token') != null;
      final hasFallbackUser = prefs.getString('fallback_user') != null;

      if (!hasJwtToken && !hasFallbackUser) {
        setState(() {
          _isLoading = false;
          _error = 'No authentication data found';
        });
        return;
      }

      // **OPTIMIZED: Parallel API calls instead of sequential**
      final userProvider = Provider.of<UserProvider>(context, listen: false);

      // Start all API calls simultaneously
      final List<Future> parallelTasks = [
        // Task 1: Load profile data via ProfileStateManager
        _stateManager.loadUserData(widget.userId),

        // Task 2: Load user data + followers via UserProvider (if needed)
        if (widget.userId != null)
          userProvider.getUserDataWithFollowers(widget.userId!)
        else
          Future.value(null),
      ];

      // Wait for all tasks to complete
      await Future.wait(parallelTasks);

      // **OPTIMIZED: Load additional user data only if needed**
      if (widget.userId == null && _stateManager.userData != null) {
        final currentUserId = _stateManager.userData!['id'] ??
            _stateManager.userData!['googleId'];
        if (currentUserId != null) {
          // Load this in background without blocking UI
          userProvider.getUserDataWithFollowers(currentUserId).catchError((e) {
            print('⚠️ Background user data load failed: $e');
          });
        }
      }

      setState(() {
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      print('❌ ProfileScreen: Error in _loadUserData: $e');
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading profile: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _loadUserData(),
            ),
          ),
        );
      }
    }
  }

  Future<void> _handleLogout() async {
    try {
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
    } catch (e) {
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
      final userData = await _stateManager.handleGoogleSignIn();
      if (userData != null) {
        await _loadUserData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Signed in successfully!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
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

  Future<void> _handleEditProfile() async {
    _stateManager.startEditing();
  }

  Future<void> _handleSaveProfile() async {
    try {
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
    } catch (e) {
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
    _stateManager.cancelEditing();
  }

  Future<void> _handleDeleteSelectedVideos() async {
    try {
      final shouldDelete = await _showDeleteConfirmationDialog();
      if (!shouldDelete) return;

      await _stateManager.deleteSelectedVideos();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${_stateManager.selectedVideoIds.length} videos deleted successfully!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
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
      }
    } catch (e) {
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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: Consumer<UserProvider>(
        builder: (context, userProvider, child) {
          // Get user data from UserProvider if available
          UserModel? userModel;
          if (widget.userId != null) {
            userModel = userProvider.getUserData(widget.userId!);
          }

          // Use the local _stateManager directly since it's not in Provider
          return _buildBody(userProvider, userModel);
        },
      ),
      // **NEW: Floating action button for delete when videos are selected**
      floatingActionButton: _stateManager.isSelecting &&
              _stateManager.selectedVideoIds.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _handleDeleteSelectedVideos,
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.delete),
              label: Text('Delete ${_stateManager.selectedVideoIds.length}'),
            )
          : null,
    );
  }

  Widget _buildBody(UserProvider userProvider, UserModel? userModel) {
    // Show loading indicator
    if (_isLoading) {
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
                onPressed: _loadUserData,
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
        await _loadUserData();
      },
      child: SingleChildScrollView(
        physics:
            const AlwaysScrollableScrollPhysics(), // Enable pull-to-refresh
        child: Column(
          children: [
            _buildProfileHeader(userProvider, userModel),
            _buildProfileContent(userProvider, userModel),
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

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      title: Text(
        _stateManager.userData?['name'] ?? 'Profile',
        style: const TextStyle(color: Color(0xFF424242)),
      ),
      actions: [
        // Debug button to check cache status
        IconButton(
          icon: const Icon(Icons.bug_report, color: Colors.orange),
          onPressed: () {
            final stats = _stateManager.getCacheStats();
            print('📊 Cache Stats: $stats');
            print('📊 User Data: ${_stateManager.userData}');
            print('📊 Videos Count: ${_stateManager.userVideos.length}');
            print('📊 Loading: ${_stateManager.isLoading}');
            print('📊 Error: ${_stateManager.error}');

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    'Cache: ${stats['cacheSize']}, Videos: ${_stateManager.userVideos.length}'),
                duration: Duration(seconds: 3),
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
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
                    if (_stateManager.userData != null) ...[
                      ListTile(
                        leading: const Icon(Icons.delete, color: Colors.red),
                        title: const Text('Delete Videos'),
                        subtitle: const Text('Select and delete your videos'),
                        onTap: () {
                          Navigator.pop(context);
                          _stateManager.enterSelectionMode();
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.logout, color: Colors.red),
                        title: const Text('Logout'),
                        onTap: () {
                          Navigator.pop(context);
                          _handleLogout();
                        },
                      ),
                    ] else ...[
                      ListTile(
                        leading: const Icon(Icons.login, color: Colors.blue),
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
                  CircleAvatar(
                    radius: ResponsiveHelper.isMobile(context) ? 50 : 75,
                    backgroundColor: const Color(0xFFF5F5F5),
                    // **FIXED: Use ProfileStateManager data first, then fall back to UserProvider data**
                    backgroundImage: _getProfileImage(),
                    onBackgroundImageError: (exception, stackTrace) {
                      print('Error loading profile image: $exception');
                    },
                    child: _getProfileImage() == null
                        ? Icon(
                            Icons.person,
                            size: ResponsiveHelper.getAdaptiveIconSize(context),
                            color: const Color(0xFF757575),
                          )
                        : null,
                  ),
                  if (_stateManager.isEditing)
                    Positioned(
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

            if (_stateManager.isEditing)
              RepaintBoundary(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    controller: _stateManager.nameController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Name',
                      hintText: 'Enter a unique name',
                    ),
                  ),
                ),
              )
            else
              RepaintBoundary(
                child: Text(
                  _getUserName(),
                  style: TextStyle(
                    color: const Color(0xFF424242),
                    fontSize: ResponsiveHelper.getAdaptiveFontSize(context, 24),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            if (_stateManager.isEditing)
              RepaintBoundary(
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
              )
            else
              RepaintBoundary(
                child: TextButton.icon(
                  onPressed: _handleEditProfile,
                  icon: const Icon(Icons.edit),
                  label: const Text('Edit Profile'),
                ),
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
      print(
          '🔍 ProfileScreen: Using profile pic from ProfileStateManager: $profilePic');

      if (profilePic.startsWith('http')) {
        return NetworkImage(profilePic);
      } else if (profilePic.isNotEmpty) {
        try {
          return FileImage(File(profilePic));
        } catch (e) {
          print('⚠️ ProfileScreen: Error creating FileImage: $e');
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
        print(
            '🔍 ProfileScreen: Using profile pic from UserProvider: $profilePic');

        if (profilePic.startsWith('http')) {
          return NetworkImage(profilePic);
        } else if (profilePic.isNotEmpty) {
          try {
            return FileImage(File(profilePic));
          } catch (e) {
            print('⚠️ ProfileScreen: Error creating FileImage: $e');
            return null;
          }
        }
      }
    }

    print('🔍 ProfileScreen: No profile pic available');
    return null;
  }

  // **NEW: Helper method to get user name with fallback logic**
  String _getUserName() {
    // **FIXED: Prioritize ProfileStateManager data, then fall back to UserProvider data**
    if (_stateManager.userData != null &&
        _stateManager.userData!['name'] != null) {
      final name = _stateManager.userData!['name'];
      print('🔍 ProfileScreen: Using name from ProfileStateManager: $name');
      return name;
    }

    // Fall back to UserProvider data
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    if (widget.userId != null) {
      final userModel = userProvider.getUserData(widget.userId!);
      if (userModel?.name != null) {
        final name = userModel!.name;
        print('🔍 ProfileScreen: Using name from UserProvider: $name');
        return name;
      }
    }

    // Final fallback
    print('🔍 ProfileScreen: No name available, using default');
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildStatColumn('Videos', _stateManager.userVideos.length),
                  _buildStatColumn(
                    'Followers',
                    _getFollowersCount(),
                  ),
                  _buildStatColumn(
                    'Earnings',
                    _getCurrentMonthRevenue(), // Current month's revenue
                    isEarnings: true,
                    onTap: () async {
                      // Check if user has completed payment setup
                      final hasPaymentSetup = await _checkPaymentSetupStatus();

                      if (hasPaymentSetup) {
                        // Navigate to revenue screen if payment setup is complete
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const CreatorRevenueScreen(),
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
                  // Add helpful instruction text for delete feature
                  if (_stateManager.userData != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.blue.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.blue[600],
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Long press on any video to enter selection mode, then tap videos to select them for deletion.',
                              style: TextStyle(
                                color: Colors.blue[700],
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  SizedBox(
                      height: ResponsiveHelper.isMobile(context) ? 16 : 24),
                  RepaintBoundary(
                    child: GridView.builder(
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
                      itemCount: _stateManager.userVideos.length,
                      itemBuilder: (context, index) {
                        final video = _stateManager.userVideos[index];
                        final isSelected =
                            _stateManager.selectedVideoIds.contains(video.id);

                        // Simplified video selection logic
                        final canSelectVideo = _stateManager.isSelecting &&
                            _stateManager.userData != null;
                        return RepaintBoundary(
                          child: GestureDetector(
                            onTap: () {
                              // Single tap: Play video (navigate to VideoScreen)
                              if (!_stateManager.isSelecting) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => VideoScreen(
                                      initialIndex: index,
                                      initialVideos: _stateManager.userVideos,
                                    ),
                                  ),
                                );
                              } else if (_stateManager.isSelecting &&
                                  canSelectVideo) {
                                // Use proper logic for video selection
                                print('🔍 Video tapped in selection mode');
                                print('🔍 Video ID: ${video.id}');
                                print('🔍 Can select: $canSelectVideo');
                                _stateManager.toggleVideoSelection(video.id);
                              } else {
                                print('🔍 Video tapped but not selectable');
                                print(
                                    '🔍 isSelecting: ${_stateManager.isSelecting}');
                                print('🔍 canSelectVideo: $canSelectVideo');
                              }
                            },
                            onLongPress: () {
                              // Long press: Enter selection mode for deletion
                              print('🔍 Long press detected on video');
                              print(
                                  '🔍 userData: ${_stateManager.userData != null}');
                              print('🔍 canSelectVideo: $canSelectVideo');
                              print(
                                  '🔍 isSelecting: ${_stateManager.isSelecting}');

                              if (_stateManager.userData != null &&
                                  !_stateManager.isSelecting) {
                                print(
                                    '🔍 Entering selection mode via long press');
                                _stateManager.enterSelectionMode();
                                _stateManager.toggleVideoSelection(video.id);
                              } else {
                                print(
                                    '🔍 Cannot enter selection mode via long press');
                              }
                            },
                            child: Stack(
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
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
                                              color:
                                                  Colors.blue.withOpacity(0.3),
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
                                                errorBuilder: (context, error,
                                                    stackTrace) {
                                                  print(
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
                                                    decoration: BoxDecoration(
                                                      color: Colors.blue
                                                          .withOpacity(0.3),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12),
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
                                            ResponsiveHelper.isMobile(context)
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
                                                  color:
                                                      const Color(0xFF424242),
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: ResponsiveHelper
                                                      .getAdaptiveFontSize(
                                                          context, 14),
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              SizedBox(
                                                  height:
                                                      ResponsiveHelper.isMobile(
                                                              context)
                                                          ? 4
                                                          : 8),
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons.visibility,
                                                    color:
                                                        const Color(0xFF757575),
                                                    size: ResponsiveHelper
                                                            .getAdaptiveIconSize(
                                                                context) *
                                                        0.6,
                                                  ),
                                                  SizedBox(
                                                      width: ResponsiveHelper
                                                              .isMobile(context)
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
                                if (_stateManager.isSelecting &&
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
                                        _stateManager
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
                  ),

                  // **NEW: Delete button when videos are selected**
                  if (_stateManager.isSelecting &&
                      _stateManager.selectedVideoIds.isNotEmpty)
                    RepaintBoundary(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            const Divider(height: 1),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${_stateManager.selectedVideoIds.length} video${_stateManager.selectedVideoIds.length == 1 ? '' : 's'} selected',
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
                                        _stateManager.exitSelectionMode();
                                      },
                                      child: const Text('Cancel'),
                                    ),
                                    const SizedBox(width: 16),
                                    ElevatedButton.icon(
                                      onPressed: _handleDeleteSelectedVideos,
                                      icon: const Icon(Icons.delete,
                                          color: Colors.white),
                                      label: Text(
                                          'Delete ${_stateManager.selectedVideoIds.length}'),
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
        print(
            '🔍 ProfileScreen: Using followers count from UserProvider: ${userModel!.followersCount}');
        return userModel.followersCount;
      }
    }

    // Fall back to ProfileStateManager data
    if (_stateManager.userData != null &&
        _stateManager.userData!['followersCount'] != null) {
      final followersCount = _stateManager.userData!['followersCount'];
      print(
          '🔍 ProfileScreen: Using followers count from ProfileStateManager: $followersCount');
      return followersCount;
    }

    // Final fallback
    print('🔍 ProfileScreen: No followers count available, using default');
    return 0;
  }

  Future<bool> _checkPaymentSetupStatus() async {
    try {
      // **FIXED: Prioritize SharedPreferences flag first**
      final prefs = await SharedPreferences.getInstance();
      final hasPaymentSetup = prefs.getBool('has_payment_setup') ?? false;

      if (hasPaymentSetup) {
        print('✅ Payment setup flag found in SharedPreferences');
        return true;
      }

      // **NEW: If no flag, try to load payment setup data from backend**
      if (_stateManager.userData != null &&
          _stateManager.userData!['id'] != null) {
        print('🔍 No payment setup flag found, checking backend data...');
        final hasBackendSetup = await _checkBackendPaymentSetup();
        if (hasBackendSetup) {
          // Set the flag for future use
          await prefs.setBool('has_payment_setup', true);
          print('✅ Backend payment setup found, setting flag');
          return true;
        }
      }

      print('❌ No payment setup found');
      return false;
    } catch (e) {
      print('Error checking payment setup status: $e');
      return false;
    }
  }

  // **NEW: Method to check payment setup from backend**
  Future<bool> _checkBackendPaymentSetup() async {
    try {
      print('🔍 _checkBackendPaymentSetup: Starting backend check...');
      final userData = _stateManager.getUserData();
      final token = userData?['token'];

      if (token == null) {
        print('❌ _checkBackendPaymentSetup: No token available');
        return false;
      }

      print(
          '🔍 _checkBackendPaymentSetup: Making API call to creator-payouts/profile');
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/creator-payouts/profile'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      print(
          '🔍 _checkBackendPaymentSetup: Response status: ${response.statusCode}');
      print('🔍 _checkBackendPaymentSetup: Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final paymentMethod = data['creator']?['preferredPaymentMethod'];
        final paymentDetails = data['paymentDetails'];

        print('🔍 _checkBackendPaymentSetup: Payment method: $paymentMethod');
        print('🔍 _checkBackendPaymentSetup: Payment details: $paymentDetails');

        // Check if user has completed payment setup
        if (paymentMethod != null &&
            paymentMethod.isNotEmpty &&
            paymentDetails != null) {
          print('✅ Backend payment setup found: $paymentMethod');
          return true;
        } else {
          print(
              '❌ _checkBackendPaymentSetup: Payment setup incomplete - method: $paymentMethod, details: $paymentDetails');
        }
      } else {
        print(
            '❌ _checkBackendPaymentSetup: API call failed with status ${response.statusCode}');
      }

      return false;
    } catch (e) {
      print('❌ _checkBackendPaymentSetup: Error: $e');
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
      {bool isEarnings = false, VoidCallback? onTap}) {
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
                  isEarnings
                      ? '₹${value.toStringAsFixed(2)}'
                      : value.toString(),
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
      print(
          '✅ ProfileScreen: Authentication data cleared from SharedPreferences');
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
    print('🔍 ProfileScreen: === CHECKING API ENDPOINTS ===');

    // Check AppConfig.baseUrl
    try {
      final appConfig = AppConfig.baseUrl;
      print('🔍 ProfileScreen: AppConfig.baseUrl: $appConfig');
    } catch (e) {
      print('❌ ProfileScreen: Error getting AppConfig.baseUrl: $e');
    }

    // Check VideoService.baseUrl
    print('🔍 ProfileScreen: VideoService.baseUrl: Not implemented');

    // Check if endpoints are different
    print(
        '🔍 ProfileScreen: VideoService not implemented - skipping endpoint comparison');

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
    print('🔍 ProfileScreen: === DEBUG STATE ===');
    print(
        '🔍 ProfileScreen: userData: ${_stateManager.userData != null ? "Available" : "Not Available"}');
    print('🔍 ProfileScreen: _isLoading: $_isLoading');
    print('🔍 ProfileScreen: _error: $_error');
    print(
        '🔍 ProfileScreen: userVideos count: ${_stateManager.userVideos.length}');
    print('🔍 ProfileScreen: userId: ${widget.userId}');

    // **NEW: Check UserProvider data**
    if (widget.userId != null) {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final userModel = userProvider.getUserData(widget.userId!);
      print(
          '🔍 ProfileScreen: UserProvider data: ${userModel != null ? "Available" : "Not Available"}');
      if (userModel != null) {
        print(
            '🔍 ProfileScreen: UserProvider - Name: ${userModel.name}, Followers: ${userModel.followersCount}');
      }
    }

    // Check SharedPreferences
    SharedPreferences.getInstance().then((prefs) {
      final hasJwtToken = prefs.getString('jwt_token') != null;
      final hasFallbackUser = prefs.getString('fallback_user') != null;
      print(
          '🔍 ProfileScreen: SharedPreferences - JWT: $hasJwtToken, Fallback: $hasFallbackUser');
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
                _loadUserData();
              },
              child: const Text('Force Load'),
            ),
          ],
        ),
      );
    }
  }

  /// **NEW: Test video playback to debug issues**
  void _testVideoPlayback() {
    print('🔍 ProfileScreen: === TESTING VIDEO PLAYBACK ===');

    if (_stateManager.userVideos.isEmpty) {
      print('❌ ProfileScreen: No videos available to test');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No videos available to test'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final testVideo = _stateManager.userVideos.first;
    print('🔍 ProfileScreen: Testing with video: ${testVideo.videoName}');
    print('🔍 ProfileScreen: Video URL: ${testVideo.videoUrl}');
    print('🔍 ProfileScreen: Video ID: ${testVideo.id}');

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
      print('✅ ProfileScreen: Successfully navigated to VideoScreen');
    } catch (e) {
      print('❌ ProfileScreen: Error navigating to VideoScreen: $e');
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
    print('🔄 ProfileScreen: Force refreshing profile data...');

    try {
      // Clear any existing data by calling handleLogout and then reloading
      await _stateManager.handleLogout();

      // Force reload from scratch
      await _loadUserData();

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
      print('❌ ProfileScreen: Error force refreshing profile data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error refreshing profile data: $e'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// **NEW: Method to check ProfileStateManager state**
  void _checkProfileStateManagerState() {
    print('🔍 ProfileScreen: === CHECKING ProfileStateManager STATE ===');
    print('🔍 ProfileScreen: userData: ${_stateManager.userData}');
    print('🔍 ProfileScreen: _isLoading: $_isLoading');
    print('🔍 ProfileScreen: _error: $_error');
    print('🔍 ProfileScreen: isEditing: ${_stateManager.isEditing}');
    print('🔍 ProfileScreen: isSelecting: ${_stateManager.isSelecting}');
    print(
        '🔍 ProfileScreen: selectedVideoIds: ${_stateManager.selectedVideoIds}');
    print(
        '🔍 ProfileScreen: userVideos count: ${_stateManager.userVideos.length}');
    print(
        '🔍 ProfileScreen: nameController text: ${_stateManager.nameController.text}');

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
}
