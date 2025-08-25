import 'package:flutter/material.dart';
import 'package:snehayog/utils/responsive_helper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:async';
import 'package:snehayog/view/screens/video_screen.dart';
import 'package:snehayog/view/screens/creator_payment_setup_screen.dart';
import 'package:snehayog/view/screens/creator_revenue_screen.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:snehayog/config/app_config.dart';
import 'package:snehayog/core/managers/profile_state_manager.dart';
import 'package:snehayog/services/video_service.dart';
import 'package:provider/provider.dart';
import 'package:snehayog/core/providers/user_provider.dart';
import 'package:snehayog/model/usermodel.dart';
import 'package:snehayog/services/authservices.dart';
import 'package:snehayog/utils/feature_flags.dart';

class ProfileScreen extends StatefulWidget {
  final String? userId;
  const ProfileScreen({super.key, this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();

  // Public method to refresh videos (called from MainScreen)
  static void refreshVideos(GlobalKey<State<ProfileScreen>> key) {
    final state = key.currentState;
    if (state != null) {
      (state as _ProfileScreenState)._stateManager.refreshVideosOnly();
    }
  }
}

class _ProfileScreenState extends State<ProfileScreen>
    with WidgetsBindingObserver {
  late final ProfileStateManager _stateManager;
  final ImagePicker _imagePicker = ImagePicker();
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _stateManager = ProfileStateManager();

    // Initialize loading state
    _isLoading = true;
    _error = null;

    // **FIXED: Use feature flag to control enhanced profile loading**
    if (Features.enhancedProfileLoading.isEnabled) {
      // NEW: Enhanced profile loading with post-frame callback
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          print(
              '🔄 ProfileScreen: Enhanced loading enabled - post-frame callback');
          _loadUserData();
        }
      });
    } else {
      // ORIGINAL: Standard initialization without post-frame callback
      print('🔄 ProfileScreen: Using standard profile initialization');
    }

    // Add a timeout to prevent infinite loading
    Timer(const Duration(seconds: 10), () {
      if (mounted && _isLoading) {
        print('⚠️ ProfileScreen: Loading timeout reached, forcing refresh');
        setState(() {
          _isLoading = false;
          _error = 'Loading timeout reached';
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stateManager.setContext(context);

    // **FIXED: Only load data if not already loading and no data available**
    if (!_isLoading && _stateManager.userData == null && _error == null) {
      print('🔍 ProfileScreen: didChangeDependencies - loading user data');
      _loadUserData();
    }
  }

  // **NEW: Method to handle when profile screen becomes visible**
  void onProfileTabSelected() {
    print(
        '🔄 ProfileScreen: Profile tab selected - checking if data needs to be loaded');

    // **FIXED: Use feature flag to control enhanced profile loading**
    if (Features.enhancedProfileLoading.isEnabled) {
      // If we don't have user data and we're not currently loading, load it
      if (_stateManager.userData == null && !_isLoading && _error == null) {
        print('🔄 ProfileScreen: Enhanced loading enabled - loading user data');
        _loadUserData();
      } else if (_stateManager.userData != null) {
        print('✅ ProfileScreen: User data already available');
      } else if (_isLoading) {
        print('⏳ ProfileScreen: Already loading user data');
      } else if (_error != null) {
        print('⚠️ ProfileScreen: Error state, user can retry');
      }
    } else {
      // ORIGINAL: No enhanced loading behavior
      print(
          '🔄 ProfileScreen: Enhanced loading disabled - using standard behavior');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // **FIXED: Use consistent data refresh approach**
    if (state == AppLifecycleState.resumed) {
      print('🔄 ProfileScreen: App resumed, refreshing data...');
      // Refresh all data using the main loading method
      if (mounted && !_isLoading) {
        _loadUserData();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stateManager.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    print('🔄 ProfileScreen: Loading user data for userId: ${widget.userId}');

    try {
      // Set loading state
      setState(() {
        _isLoading = true;
        _error = null;
      });

      // First, check if we have any stored authentication data
      final prefs = await SharedPreferences.getInstance();
      final hasJwtToken = prefs.getString('jwt_token') != null;
      final hasFallbackUser = prefs.getString('fallback_user') != null;

      print(
          '🔍 ProfileScreen: Auth check - JWT: $hasJwtToken, Fallback: $hasFallbackUser');

      if (!hasJwtToken && !hasFallbackUser) {
        print(
            '❌ ProfileScreen: No authentication data found - user needs to sign in');
        setState(() {
          _isLoading = false;
          _error = 'No authentication data found';
        });
        return;
      }

      // **FIXED: Always load user data via UserProvider for profile info**
      final userProvider = Provider.of<UserProvider>(context, listen: false);

      // If userId is provided, load that specific user's data
      if (widget.userId != null) {
        print(
            '🔄 ProfileScreen: Loading user data via UserProvider for ID: ${widget.userId}');
        print('🔄 ProfileScreen: userId type: ${widget.userId.runtimeType}');
        print('🔄 ProfileScreen: userId length: ${widget.userId!.length}');

        final userData =
            await userProvider.getUserDataWithFollowers(widget.userId!);
        if (userData != null) {
          print(
              '✅ ProfileScreen: User data loaded via UserProvider: ${userData.name}');
        } else {
          print('⚠️ ProfileScreen: UserProvider returned null data');
        }
      } else {
        // If no userId, load current user's data from ProfileStateManager
        print(
            '🔄 ProfileScreen: Loading current user data from ProfileStateManager');

        // **FIXED: Check if ProfileStateManager already has user data**
        if (_stateManager.userData != null) {
          // Get current user ID from ProfileStateManager
          final currentUserId = _stateManager.userData!['id'];
          print(
              '🔄 ProfileScreen: Current user ID from ProfileStateManager: $currentUserId');
          print(
              '🔄 ProfileScreen: Current user ID type: ${currentUserId.runtimeType}');
          print(
              '🔄 ProfileScreen: Current user ID length: ${currentUserId?.length ?? 'null'}');

          if (currentUserId != null) {
            print(
                '🔄 ProfileScreen: Loading current user data for ID: $currentUserId');
            final userData =
                await userProvider.getUserDataWithFollowers(currentUserId);
            if (userData != null) {
              print(
                  '✅ ProfileScreen: Current user data loaded: ${userData.name}');
            }
          }
        } else {
          // **NEW: If ProfileStateManager doesn't have user data, try to get it from AuthService**
          print(
              '🔄 ProfileScreen: ProfileStateManager has no user data, trying AuthService');
          try {
            final authService = AuthService();
            final authUserData = await authService.getUserData();
            if (authUserData != null && authUserData['id'] != null) {
              print(
                  '🔄 ProfileScreen: Got user data from AuthService: ${authUserData['id']}');
              final userData = await userProvider
                  .getUserDataWithFollowers(authUserData['id']);
              if (userData != null) {
                print(
                    '✅ ProfileScreen: User data loaded from AuthService: ${userData.name}');
              }
            }
          } catch (e) {
            print(
                '⚠️ ProfileScreen: Error getting user data from AuthService: $e');
          }
        }
      }

      // **FIXED: Load profile data via ProfileStateManager for videos and profile info**
      await _stateManager.loadUserData(widget.userId);
      print('✅ ProfileScreen: Profile data loaded successfully');

      // **DEBUG: Check what data was loaded**
      print(
          '🔍 ProfileScreen: ProfileStateManager userData: ${_stateManager.userData}');
      print(
          '🔍 ProfileScreen: ProfileStateManager userVideos count: ${_stateManager.userVideos.length}');

      if (_stateManager.userData != null) {
        print(
            '🔍 ProfileScreen: User ID from ProfileStateManager: ${_stateManager.userData!['id']}');
        print(
            '🔍 ProfileScreen: User Name from ProfileStateManager: ${_stateManager.userData!['name']}');
        print(
            '🔍 ProfileScreen: User Email from ProfileStateManager: ${_stateManager.userData!['email']}');
      }

      // Trigger rebuild to show profile content
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      print('❌ ProfileScreen: Error loading user data: $e');

      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });

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
      // Clear payment setup flag on logout
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('has_payment_setup');

      // Clear all authentication data
      await prefs.remove('jwt_token');
      await prefs.remove('fallback_user');

      print('✅ ProfileScreen: Authentication data cleared');

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
      print('🔐 ProfileScreen: Starting Google sign-in process...');

      final userData = await _stateManager.handleGoogleSignIn();
      if (userData != null) {
        print('✅ ProfileScreen: Google sign-in successful');

        // Since this is a fresh sign-in, we're on our own profile.
        // We can reload all data.
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
        print('❌ ProfileScreen: Google sign-in failed - no user data returned');
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
      print('❌ ProfileScreen: Error during Google sign-in: $e');
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

  /// Handles deletion of selected videos with professional error handling
  Future<void> _handleDeleteSelectedVideos() async {
    try {
      // Show confirmation dialog
      final shouldDelete = await _showDeleteConfirmationDialog();

      if (!shouldDelete) return;

      print('🗑️ ProfileScreen: Starting video deletion process');
      print(
          '🗑️ ProfileScreen: Selected videos: ${_stateManager.selectedVideoIds}');
      print('🗑️ ProfileScreen: User data: ${_stateManager.userData}');

      // Perform deletion
      await _stateManager.deleteSelectedVideos();

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${_stateManager.selectedVideoIds.length} videos deleted successfully!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'Undo',
              textColor: Colors.white,
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Undo functionality not implemented yet'),
                    backgroundColor: Colors.orange,
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
          ),
        );
      }
    } catch (e) {
      print('❌ ProfileScreen: Error in _handleDeleteSelectedVideos: $e');
      // Error handling is done in ProfileStateManager, just show the error
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

  /// Shows a confirmation dialog before deleting videos
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
      // Show options to pick image
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
        // Show loading indicator
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Uploading profile photo...'),
              duration: Duration(seconds: 1),
            ),
          );
        }

        // Here you would typically upload the image to your server
        // For now, we'll just use the local file path
        final String imagePath = image.path;

        // Update the profile photo
        await _stateManager.updateProfilePhoto(imagePath);

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
    );
  }

  Widget _buildBody(UserProvider userProvider, UserModel? userModel) {
    // Debug logging
    print('🔍 ProfileScreen: _buildBody called');
    print('🔍 ProfileScreen: _isLoading: $_isLoading');
    print('🔍 ProfileScreen: _error: $_error');
    print(
        '🔍 ProfileScreen: userData: ${_stateManager.userData != null ? "Available" : "Not Available"}');
    print('🔍 ProfileScreen: userId: ${widget.userId}');

    // Show loading indicator
    if (_isLoading) {
      print('🔍 ProfileScreen: Showing loading indicator');
      return RepaintBoundary(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Loading profile...'),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _loadUserData,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // Show error state
    if (_error != null) {
      print('🔍 ProfileScreen: Showing error: $_error');

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
      print('🔍 ProfileScreen: No user data available - showing sign-in view');
      return _buildSignInView();
    }

    // If we reach here, we have user data and can show the profile
    print('🔍 ProfileScreen: User data available - showing profile content');

    print('🔍 ProfileScreen: Showing profile content - user data available');
    return RefreshIndicator(
      onRefresh: () async {
        print('🔍 ProfileScreen: Refresh triggered');
        // **FIXED: Use consistent refresh approach**
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

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      title: Text(
        _stateManager.userData?['name'] ?? 'Profile',
        style: const TextStyle(color: Color(0xFF424242)),
      ),
      actions: [
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

                    // Debug info
                    Container(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Debug Info:',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          Text(
                              'User Data: ${_stateManager.userData != null ? "Available" : "Not Available"}'),
                          Text('Loading: $_isLoading'),
                          Text('Error: ${_error ?? "None"}'),
                        ],
                      ),
                    ),
                    const Divider(height: 1),

                    // Menu items
                    if (_stateManager.userData != null) ...[
                      ListTile(
                        leading:
                            const Icon(Icons.select_all, color: Colors.blue),
                        title: const Text('Select & Delete Videos'),
                        onTap: () {
                          Navigator.pop(context);
                          _stateManager.enterSelectionMode();
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.refresh, color: Colors.green),
                        title: const Text('Refresh Profile'),
                        onTap: () {
                          Navigator.pop(context);
                          _stateManager.refreshData();
                        },
                      ),
                      ListTile(
                        leading:
                            const Icon(Icons.video_library, color: Colors.blue),
                        title: const Text('Refresh Videos'),
                        onTap: () {
                          Navigator.pop(context);
                          _stateManager.refreshVideosOnly();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('🔄 Refreshing videos...'),
                              duration: Duration(seconds: 2),
                              backgroundColor: Colors.blue,
                            ),
                          );
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

                    // Debug options
                    const Divider(height: 1),
                    const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Text('Debug Options:',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                    ListTile(
                      leading:
                          const Icon(Icons.bug_report, color: Colors.orange),
                      title: const Text('Force Refresh'),
                      onTap: () {
                        Navigator.pop(context);
                        _loadUserData();
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.data_usage, color: Colors.blue),
                      title: const Text('Debug State'),
                      onTap: () {
                        Navigator.pop(context);
                        _debugState();
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.api, color: Colors.purple),
                      title: const Text('Check API Endpoints'),
                      onTap: () {
                        Navigator.pop(context);
                        _checkApiEndpoints();
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.clear_all, color: Colors.red),
                      title: const Text('Clear Auth Data'),
                      onTap: () {
                        Navigator.pop(context);
                        _clearAuthenticationData();
                      },
                    ),
                    // **NEW: Video playback test**
                    ListTile(
                      leading:
                          const Icon(Icons.play_circle, color: Colors.green),
                      title: const Text('Test Video Playback'),
                      onTap: () {
                        Navigator.pop(context);
                        _testVideoPlayback();
                      },
                    ),
                    // **NEW: Feature flag controls for testing**
                    const Divider(height: 1),
                    const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Text('Feature Flags:',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                    ListTile(
                      leading: const Icon(Icons.flag, color: Colors.blue),
                      title: const Text('Enhanced Profile Loading'),
                      subtitle: Text(Features.enhancedProfileLoading.isEnabled
                          ? 'Enabled'
                          : 'Disabled'),
                      onTap: () {
                        Navigator.pop(context);
                        _toggleFeatureFlag('enhanced_profile_loading');
                      },
                    ),
                    ListTile(
                      leading:
                          const Icon(Icons.play_circle, color: Colors.green),
                      title: const Text('Profile Video Playback Fix'),
                      subtitle: Text(Features.profileVideoPlaybackFix.isEnabled
                          ? 'Enabled'
                          : 'Disabled'),
                      onTap: () {
                        Navigator.pop(context);
                        _toggleFeatureFlag('profile_video_playback_fix');
                      },
                    ),
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
          Stack(
            children: [
              CircleAvatar(
                radius: ResponsiveHelper.isMobile(context) ? 50 : 75,
                backgroundColor: const Color(0xFFF5F5F5),
                backgroundImage: userModel?.profilePic != null
                    ? userModel!.profilePic.startsWith('http')
                        ? NetworkImage(userModel.profilePic)
                        : FileImage(File(userModel.profilePic)) as ImageProvider
                    : null,
                onBackgroundImageError: (exception, stackTrace) {
                  print('Error loading profile image: $exception');
                },
                child: userModel?.profilePic == null
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
          SizedBox(height: ResponsiveHelper.isMobile(context) ? 16 : 24),

          // Authentication status indicator
          FutureBuilder<SharedPreferences>(
            future: SharedPreferences.getInstance(),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                final prefs = snapshot.data!;
                final hasJwtToken = prefs.getString('jwt_token') != null;
                final hasFallbackUser =
                    prefs.getString('fallback_user') != null;
                final isAuthenticated = hasJwtToken || hasFallbackUser;

                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                        isAuthenticated ? Icons.check_circle : Icons.warning,
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

          SizedBox(height: ResponsiveHelper.isMobile(context) ? 16 : 24),

          if (_stateManager.isEditing)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _stateManager.nameController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Name',
                  hintText: 'Enter a unique name',
                ),
              ),
            )
          else
            Text(
              userModel?.name ?? 'User',
              style: TextStyle(
                color: const Color(0xFF424242),
                fontSize: ResponsiveHelper.getAdaptiveFontSize(context, 24),
                fontWeight: FontWeight.bold,
              ),
            ),
          if (_stateManager.isEditing)
            Padding(
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
            )
          else
            TextButton.icon(
              onPressed: _handleEditProfile,
              icon: const Icon(Icons.edit),
              label: const Text('Edit Profile'),
            ),
        ],
      ),
    ));
  }

  Widget _buildProfileContent(UserProvider userProvider, UserModel? userModel) {
    return RepaintBoundary(
        child: Column(
      children: [
        Container(
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
                userModel?.followersCount ?? 0,
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
                        builder: (context) => const CreatorPaymentSetupScreen(),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: ResponsiveHelper.getAdaptivePadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your Videos',
                style: TextStyle(
                  color: const Color(0xFF424242),
                  fontSize: ResponsiveHelper.getAdaptiveFontSize(context, 20),
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: ResponsiveHelper.isMobile(context) ? 8 : 12),
              // Add helpful instruction text for delete feature
              if (userModel != null)
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
              SizedBox(height: ResponsiveHelper.isMobile(context) ? 16 : 24),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: ResponsiveHelper.isMobile(context) ? 2 : 3,
                  crossAxisSpacing:
                      ResponsiveHelper.isMobile(context) ? 16 : 24,
                  mainAxisSpacing: ResponsiveHelper.isMobile(context) ? 16 : 24,
                  childAspectRatio:
                      ResponsiveHelper.isMobile(context) ? 0.75 : 0.8,
                ),
                itemCount: _stateManager.userVideos.length,
                itemBuilder: (context, index) {
                  final video = _stateManager.userVideos[index];
                  final isSelected =
                      _stateManager.selectedVideoIds.contains(video.id);

                  // Simplified video selection logic
                  final canSelectVideo =
                      _stateManager.isSelecting && userModel != null;
                  return GestureDetector(
                    onTap: () {
                      // Single tap: Play video (navigate to VideoScreen)
                      if (!_stateManager.isSelecting) {
                        print(
                            '🔍 ProfileScreen: Video tapped, preparing to navigate to VideoScreen');
                        print('🔍 ProfileScreen: Video ID: ${video.id}');
                        print('🔍 ProfileScreen: Video URL: ${video.videoUrl}');
                        print(
                            '🔍 ProfileScreen: Video Name: ${video.videoName}');
                        print(
                            '🔍 ProfileScreen: User Model: ${userModel?.name}');
                        print(
                            '🔍 ProfileScreen: Total videos: ${_stateManager.userVideos.length}');

                        // **FIXED: Use feature flag to control video loading approach**
                        if (Features.profileVideoPlaybackFix.isEnabled) {
                          // NEW: Enhanced video loading with user data update
                          final updatedVideos =
                              _stateManager.userVideos.map((video) {
                            if (userModel?.name != null) {
                              print(
                                  '🔍 ProfileScreen: Updating video ${video.id} with uploader name: ${userModel!.name}');
                              return video.copyWith(
                                uploader: video.uploader
                                    .copyWith(name: userModel.name),
                              );
                            }
                            return video;
                          }).toList();

                          print(
                              '🔍 ProfileScreen: Updated videos count: ${updatedVideos.length}');
                          print(
                              '🔍 ProfileScreen: Navigating to VideoScreen with index: $index');

                          // **DEBUG: Check video data structure**
                          if (updatedVideos.isNotEmpty &&
                              index < updatedVideos.length) {
                            final targetVideo = updatedVideos[index];
                            print('🔍 ProfileScreen: Target video details:');
                            print(
                                '🔍 ProfileScreen:   - ID: ${targetVideo.id}');
                            print(
                                '🔍 ProfileScreen:   - Name: ${targetVideo.videoName}');
                            print(
                                '🔍 ProfileScreen:   - URL: ${targetVideo.videoUrl}');
                            print(
                                '🔍 ProfileScreen:   - Thumbnail: ${targetVideo.thumbnailUrl}');
                            print(
                                '🔍 ProfileScreen:   - Uploader: ${targetVideo.uploader.name}');
                            print(
                                '🔍 ProfileScreen:   - Duration: ${targetVideo.duration}');
                            print(
                                '🔍 ProfileScreen:   - Video Type: ${targetVideo.videoType}');
                          }

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => VideoScreen(
                                initialIndex: index,
                                initialVideos: updatedVideos,
                              ),
                            ),
                          );
                        } else {
                          // **ORIGINAL WORKING APPROACH: Direct navigation without data modification**
                          print(
                              '🔍 ProfileScreen: Using original working video navigation approach');
                          print(
                              '🔍 ProfileScreen: Navigating to VideoScreen with index: $index');

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => VideoScreen(
                                initialIndex: index,
                                initialVideos: _stateManager.userVideos,
                              ),
                            ),
                          );
                        }
                      } else if (_stateManager.isSelecting && canSelectVideo) {
                        // Use proper logic for video selection
                        print('🔍 Video tapped in selection mode');
                        print('🔍 Video ID: ${video.id}');
                        print('🔍 Can select: $canSelectVideo');
                        _stateManager.toggleVideoSelection(video.id);
                      } else {
                        print('🔍 Video tapped but not selectable');
                        print('🔍 isSelecting: ${_stateManager.isSelecting}');
                        print('🔍 canSelectVideo: $canSelectVideo');
                      }
                    },
                    onLongPress: () {
                      // Long press: Enter selection mode for deletion
                      print('🔍 Long press detected on video');
                      print('🔍 isMyProfile: ${userModel != null}');
                      print('🔍 canSelectVideo: $canSelectVideo');
                      print('🔍 isSelecting: ${_stateManager.isSelecting}');

                      if (userModel != null && !_stateManager.isSelecting) {
                        print('🔍 Entering selection mode via long press');
                        _stateManager.enterSelectionMode();
                        _stateManager.toggleVideoSelection(video.id);
                      } else {
                        print('🔍 Cannot enter selection mode via long press');
                      }
                    },
                    child: Stack(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            border: isSelected
                                ? Border.all(color: Colors.blue, width: 3)
                                : null,
                            borderRadius: BorderRadius.circular(12),
                            // Add shadow when selected
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: Colors.blue.withOpacity(0.3),
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
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: Stack(
                                    children: [
                                      Image.network(
                                        video.videoUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) {
                                          print(
                                              'Error loading thumbnail: $error');
                                          return Center(
                                            child: Icon(
                                              Icons.video_library,
                                              color: const Color(0xFF424242),
                                              size: ResponsiveHelper
                                                  .getAdaptiveIconSize(context),
                                            ),
                                          );
                                        },
                                      ),
                                      // Selection overlay
                                      if (isSelected)
                                        Positioned.fill(
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color:
                                                  Colors.blue.withOpacity(0.3),
                                              borderRadius:
                                                  BorderRadius.circular(12),
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
                                          color: const Color(0xFF424242),
                                          fontWeight: FontWeight.bold,
                                          fontSize: ResponsiveHelper
                                              .getAdaptiveFontSize(context, 14),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      SizedBox(
                                          height:
                                              ResponsiveHelper.isMobile(context)
                                                  ? 4
                                                  : 8),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.visibility,
                                            color: const Color(0xFF757575),
                                            size: ResponsiveHelper
                                                    .getAdaptiveIconSize(
                                                        context) *
                                                0.6,
                                          ),
                                          SizedBox(
                                              width: ResponsiveHelper.isMobile(
                                                      context)
                                                  ? 4
                                                  : 8),
                                          Text(
                                            '${video.views}',
                                            style: TextStyle(
                                              color: const Color(0xFF757575),
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
                                _stateManager.toggleVideoSelection(video.id);
                              },
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    ));
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
    return Builder(
      builder: (context) => Column(
        children: [
          GestureDetector(
            onTap: onTap,
            child: MouseRegion(
              cursor: isEarnings
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
              child: Text(
                isEarnings ? '₹${value.toStringAsFixed(2)}' : value.toString(),
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
    try {
      final videoServiceUrl = VideoService.baseUrl;
      print('🔍 ProfileScreen: VideoService.baseUrl: $videoServiceUrl');
    } catch (e) {
      print('❌ ProfileScreen: Error getting VideoService.baseUrl: $e');
    }

    // Check if endpoints are different
    try {
      final appConfig = AppConfig.baseUrl;
      final videoServiceUrl = VideoService.baseUrl;
      if (appConfig != videoServiceUrl) {
        print('⚠️ ProfileScreen: WARNING - Different base URLs detected!');
        print('   AppConfig: $appConfig');
        print('   VideoService: $videoServiceUrl');
        print('   This could cause API endpoint conflicts!');
      } else {
        print('✅ ProfileScreen: Base URLs are consistent');
      }
    } catch (e) {
      print('❌ ProfileScreen: Error comparing base URLs: $e');
    }

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

  /// **NEW: Toggle feature flags for testing**
  void _toggleFeatureFlag(String featureName) {
    final currentState = FeatureFlags.instance.isEnabled(featureName);
    if (currentState) {
      FeatureFlags.instance.disable(featureName);
      print('🔧 ProfileScreen: Disabled feature flag: $featureName');
    } else {
      FeatureFlags.instance.enable(featureName);
      print('🔧 ProfileScreen: Enabled feature flag: $featureName');
    }

    // Show feedback to user
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${featureName.replaceAll('_', ' ').toUpperCase()}: ${!currentState ? 'Enabled' : 'Disabled'}'),
          backgroundColor: !currentState ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
    }

    // Force rebuild to update UI
    setState(() {});
  }
}
