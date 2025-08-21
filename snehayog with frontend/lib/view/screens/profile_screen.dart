import 'package:flutter/material.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/services/video_service.dart';
import 'package:snehayog/services/authservices.dart';
import 'package:snehayog/utils/responsive_helper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:async';
import 'package:snehayog/services/user_service.dart';
import 'package:snehayog/view/screens/video_screen.dart';
import 'package:snehayog/view/screens/creator_payment_setup_screen.dart';
import 'package:snehayog/view/screens/creator_revenue_screen.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:snehayog/config/app_config.dart';
import 'package:snehayog/core/managers/profile_state_manager.dart';

class ProfileScreen extends StatefulWidget {
  final String? userId;
  const ProfileScreen({super.key, this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final ProfileStateManager _stateManager;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _stateManager = ProfileStateManager();
    _loadUserData();
  }

  @override
  void dispose() {
    _stateManager.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    await _stateManager.loadUserData(widget.userId);
  }

  Future<void> _handleLogout() async {
    try {
      // Clear payment setup flag on logout
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('has_payment_setup');

      await _stateManager.handleLogout();
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
        // Since this is a fresh sign-in, we're on our own profile.
        // We can reload all data.
        _loadUserData();
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
            content: Text('Profile updated successfully'),
            backgroundColor: Colors.green,
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
    return Center(
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
          ),
          const SizedBox(height: 30),
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
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Color(0xFFE0E0E0)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _stateManager,
      builder: (context, child) {
        final userData = _stateManager.userData;
        final bool isMyProfile = userData != null;

        return Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
              backgroundColor: Colors.white,
              title: Text(userData?['name'] ?? 'Profile',
                  style: const TextStyle(color: Color(0xFF424242))),
              actions: isMyProfile && userData != null
                  ? [
                      IconButton(
                        icon: const Icon(Icons.more_vert,
                            color: Color(0xFF424242)),
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            builder: (context) => Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.select_all),
                                  title: const Text('Select & Delete Videos'),
                                  onTap: () {
                                    Navigator.pop(context);
                                    _stateManager.enterSelectionMode();
                                  },
                                ),
                                ListTile(
                                  leading: const Icon(Icons.logout),
                                  title: const Text('Logout'),
                                  onTap: () {
                                    Navigator.pop(context);
                                    _handleLogout();
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ]
                  : null,
            ),
            body: _stateManager.isLoading
                ? const Center(child: CircularProgressIndicator())
                : _stateManager.error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Error: ${_stateManager.error}',
                                style:
                                    const TextStyle(color: Color(0xFF424242)),
                                textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () {
                                _stateManager.clearError();
                                _loadUserData();
                              },
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : userData == null
                        ? _buildSignInView()
                        : RefreshIndicator(
                            onRefresh: () =>
                                _stateManager.loadUserVideos(widget.userId),
                            child: SingleChildScrollView(
                              child: Column(
                                children: [
                                  if (_stateManager.isSelecting && isMyProfile)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 8.0),
                                      child: Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                            color: Colors.blue.withOpacity(0.3),
                                            width: 1,
                                          ),
                                        ),
                                        child: Column(
                                          children: [
                                            Text(
                                              'Selection Mode',
                                              style: TextStyle(
                                                color: Colors.blue[700],
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              '${_stateManager.selectedVideoIds.length} video${_stateManager.selectedVideoIds.length == 1 ? '' : 's'} selected',
                                              style: TextStyle(
                                                color: Colors.blue[600],
                                                fontSize: 14,
                                              ),
                                            ),
                                            const SizedBox(height: 16),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                ElevatedButton.icon(
                                                  icon:
                                                      const Icon(Icons.delete),
                                                  label: Text(
                                                      'Delete Selected (${_stateManager.selectedVideoIds.length})'),
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                    backgroundColor: Colors.red,
                                                    foregroundColor:
                                                        Colors.white,
                                                    disabledBackgroundColor:
                                                        Colors.grey,
                                                  ),
                                                  onPressed: _stateManager
                                                          .hasSelectedVideos
                                                      ? () => _stateManager
                                                          .deleteSelectedVideos()
                                                      : null,
                                                ),
                                                const SizedBox(width: 16),
                                                TextButton.icon(
                                                  icon: const Icon(Icons.clear),
                                                  label: const Text(
                                                      'Clear Selection'),
                                                  onPressed: () {
                                                    print(
                                                        '🔍 Clear Selection button pressed');
                                                    print(
                                                        '🔍 Before clear: ${_stateManager.selectedVideoIds}');
                                                    _stateManager
                                                        .clearSelection();
                                                    print(
                                                        '🔍 After clear: ${_stateManager.selectedVideoIds}');
                                                  },
                                                ),
                                                const SizedBox(width: 16),
                                                TextButton.icon(
                                                  icon: const Icon(Icons.close),
                                                  label: const Text(
                                                      'Exit Selection'),
                                                  onPressed: () {
                                                    _stateManager
                                                        .exitSelectionMode();
                                                  },
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  Container(
                                    padding:
                                        ResponsiveHelper.getAdaptivePadding(
                                            context),
                                    child: Column(
                                      children: [
                                        Stack(
                                          children: [
                                            CircleAvatar(
                                              radius: ResponsiveHelper.isMobile(
                                                      context)
                                                  ? 50
                                                  : 75,
                                              backgroundColor:
                                                  const Color(0xFFF5F5F5),
                                              backgroundImage: userData?[
                                                          'profilePic'] !=
                                                      null
                                                  ? userData!['profilePic']
                                                          .startsWith('http')
                                                      ? NetworkImage(userData![
                                                          'profilePic'])
                                                      : FileImage(File(userData![
                                                              'profilePic']))
                                                          as ImageProvider
                                                  : null,
                                              onBackgroundImageError:
                                                  (exception, stackTrace) {
                                                print(
                                                    'Error loading profile image: $exception');
                                              },
                                              child: userData?['profilePic'] ==
                                                      null
                                                  ? Icon(
                                                      Icons.person,
                                                      size: ResponsiveHelper
                                                          .getAdaptiveIconSize(
                                                              context),
                                                      color: const Color(
                                                          0xFF757575),
                                                    )
                                                  : null,
                                            ),
                                            if (_stateManager.isEditing)
                                              Positioned(
                                                bottom: 0,
                                                right: 0,
                                                child: IconButton(
                                                  icon: const Icon(
                                                      Icons.camera_alt),
                                                  onPressed:
                                                      _handleProfilePhotoChange,
                                                  color: Colors.white,
                                                  style: IconButton.styleFrom(
                                                    backgroundColor:
                                                        Colors.blue,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        SizedBox(
                                            height: ResponsiveHelper.isMobile(
                                                    context)
                                                ? 16
                                                : 24),
                                        if (_stateManager.isEditing)
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 20),
                                            child: TextField(
                                              controller:
                                                  _stateManager.nameController,
                                              decoration: const InputDecoration(
                                                border: OutlineInputBorder(),
                                                labelText: 'Name',
                                                hintText: 'Enter a unique name',
                                              ),
                                            ),
                                          )
                                        else
                                          Text(
                                            userData?['name'] ?? 'User',
                                            style: TextStyle(
                                              color: const Color(0xFF424242),
                                              fontSize: ResponsiveHelper
                                                  .getAdaptiveFontSize(
                                                      context, 24),
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        if (isMyProfile)
                                          if (_stateManager.isEditing)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.all(16.0),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  ElevatedButton(
                                                    onPressed:
                                                        _handleCancelEdit,
                                                    child: const Text('Cancel'),
                                                  ),
                                                  const SizedBox(width: 16),
                                                  ElevatedButton(
                                                    onPressed:
                                                        _handleSaveProfile,
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
                                  ),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      vertical:
                                          ResponsiveHelper.isMobile(context)
                                              ? 20
                                              : 30,
                                    ),
                                    decoration: const BoxDecoration(
                                      border: Border(
                                        top: BorderSide(
                                            color: Color(0xFFE0E0E0)),
                                        bottom: BorderSide(
                                            color: Color(0xFFE0E0E0)),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceEvenly,
                                      children: [
                                        _buildStatColumn('Videos',
                                            _stateManager.userVideos.length),
                                        _buildStatColumn(
                                          'Followers',
                                          0, // This will be updated when we implement followers functionality
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
                                    ),
                                  ),
                                  Padding(
                                    padding:
                                        ResponsiveHelper.getAdaptivePadding(
                                            context),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Your Videos',
                                          style: TextStyle(
                                            color: const Color(0xFF424242),
                                            fontSize: ResponsiveHelper
                                                .getAdaptiveFontSize(
                                                    context, 20),
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        SizedBox(
                                            height: ResponsiveHelper.isMobile(
                                                    context)
                                                ? 8
                                                : 12),
                                        // Add helpful instruction text for delete feature
                                        if (isMyProfile)
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color:
                                                  Colors.blue.withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: Colors.blue
                                                    .withOpacity(0.3),
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
                                            height: ResponsiveHelper.isMobile(
                                                    context)
                                                ? 16
                                                : 24),
                                        GridView.builder(
                                          shrinkWrap: true,
                                          physics:
                                              const NeverScrollableScrollPhysics(),
                                          gridDelegate:
                                              SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount:
                                                ResponsiveHelper.isMobile(
                                                        context)
                                                    ? 2
                                                    : 3,
                                            crossAxisSpacing:
                                                ResponsiveHelper.isMobile(
                                                        context)
                                                    ? 16
                                                    : 24,
                                            mainAxisSpacing:
                                                ResponsiveHelper.isMobile(
                                                        context)
                                                    ? 16
                                                    : 24,
                                            childAspectRatio:
                                                ResponsiveHelper.isMobile(
                                                        context)
                                                    ? 0.75
                                                    : 0.8,
                                          ),
                                          itemCount:
                                              _stateManager.userVideos.length,
                                          itemBuilder: (context, index) {
                                            final video =
                                                _stateManager.userVideos[index];
                                            final isSelected = _stateManager
                                                .selectedVideoIds
                                                .contains(video.id);

                                            // Check if this is the user's own video by comparing multiple possible ID fields
                                            final userGoogleId =
                                                userData?['googleId'];
                                            final userId = userData?['id'];
                                            final videoUploaderId =
                                                video.uploader.id;

                                            final isOwnVideo = isMyProfile &&
                                                (videoUploaderId ==
                                                        userGoogleId ||
                                                    videoUploaderId == userId ||
                                                    videoUploaderId ==
                                                        userData?['_id']);

                                            // Debug logging for video selection
                                            print('🔍 Video Selection Debug:');
                                            print('  - Video ID: ${video.id}');
                                            print(
                                                '  - Video Uploader ID: ${video.uploader.id}');
                                            print(
                                                '  - User Google ID: $userGoogleId');
                                            print('  - User ID: $userId');
                                            print(
                                                '  - User _ID: ${userData?['_id']}');
                                            print(
                                                '  - isMyProfile: $isMyProfile');
                                            print(
                                                '  - isOwnVideo: $isOwnVideo');
                                            print(
                                                '  - isSelecting: ${_stateManager.isSelecting}');
                                            print(
                                                '  - isSelected: $isSelected');

                                            // For debugging, allow selection of any video when in selection mode
                                            final canSelectVideo =
                                                _stateManager.isSelecting &&
                                                    isMyProfile;

                                            // Use proper logic for video selection
                                            final canSelectVideoFinal =
                                                _stateManager.isSelecting &&
                                                    isMyProfile;
                                            return GestureDetector(
                                              onTap: () {
                                                // Single tap: Play video (navigate to VideoScreen)
                                                if (!_stateManager
                                                    .isSelecting) {
                                                  final updatedVideos =
                                                      _stateManager.userVideos
                                                          .map((video) {
                                                    if (userData != null &&
                                                        userData!['name'] !=
                                                            null) {
                                                      return video.copyWith(
                                                        uploader: video.uploader
                                                            .copyWith(
                                                                name: userData![
                                                                    'name']),
                                                      );
                                                    }
                                                    return video;
                                                  }).toList();

                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (context) =>
                                                          VideoScreen(
                                                        initialIndex: index,
                                                        initialVideos:
                                                            updatedVideos,
                                                      ),
                                                    ),
                                                  );
                                                } else if (_stateManager
                                                        .isSelecting &&
                                                    canSelectVideoFinal) {
                                                  // Use proper logic for video selection
                                                  print(
                                                      '🔍 Video tapped in selection mode');
                                                  print(
                                                      '🔍 Video ID: ${video.id}');
                                                  print(
                                                      '🔍 Can select: $canSelectVideoFinal');
                                                  _stateManager
                                                      .toggleVideoSelection(
                                                          video.id);
                                                } else {
                                                  print(
                                                      '🔍 Video tapped but not selectable');
                                                  print(
                                                      '🔍 isSelecting: ${_stateManager.isSelecting}');
                                                  print(
                                                      '🔍 canSelectVideoFinal: $canSelectVideoFinal');
                                                }
                                              },
                                              onLongPress: () {
                                                // Long press: Enter selection mode for deletion
                                                print(
                                                    '🔍 Long press detected on video');
                                                print(
                                                    '🔍 isMyProfile: $isMyProfile');
                                                print(
                                                    '🔍 canSelectVideoFinal: $canSelectVideoFinal');
                                                print(
                                                    '🔍 isSelecting: ${_stateManager.isSelecting}');

                                                if (isMyProfile &&
                                                    canSelectVideoFinal && // Use proper logic for video selection
                                                    !_stateManager
                                                        .isSelecting) {
                                                  print(
                                                      '🔍 Entering selection mode via long press');
                                                  _stateManager
                                                      .enterSelectionMode();
                                                  _stateManager
                                                      .toggleVideoSelection(
                                                          video.id);
                                                } else {
                                                  print(
                                                      '🔍 Cannot enter selection mode via long press');
                                                }
                                              },
                                              child: Stack(
                                                children: [
                                                  AnimatedContainer(
                                                    duration: const Duration(
                                                        milliseconds: 200),
                                                    decoration: BoxDecoration(
                                                      border: isSelected
                                                          ? Border.all(
                                                              color:
                                                                  Colors.blue,
                                                              width: 3)
                                                          : null,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12),
                                                      // Add shadow when selected
                                                      boxShadow: isSelected
                                                          ? [
                                                              BoxShadow(
                                                                color: Colors
                                                                    .blue
                                                                    .withOpacity(
                                                                        0.3),
                                                                blurRadius: 8,
                                                                spreadRadius: 2,
                                                              )
                                                            ]
                                                          : null,
                                                    ),
                                                    child: Card(
                                                      color: isSelected
                                                          ? Colors.blue
                                                              .withOpacity(0.05)
                                                          : const Color(
                                                              0xFFF5F5F5),
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .stretch,
                                                        children: [
                                                          Expanded(
                                                            child: Stack(
                                                              children: [
                                                                Image.network(
                                                                  video
                                                                      .videoUrl,
                                                                  fit: BoxFit
                                                                      .cover,
                                                                  errorBuilder:
                                                                      (context,
                                                                          error,
                                                                          stackTrace) {
                                                                    print(
                                                                        'Error loading thumbnail: $error');
                                                                    return Center(
                                                                      child:
                                                                          Icon(
                                                                        Icons
                                                                            .video_library,
                                                                        color: const Color(
                                                                            0xFF424242),
                                                                        size: ResponsiveHelper.getAdaptiveIconSize(
                                                                            context),
                                                                      ),
                                                                    );
                                                                  },
                                                                ),
                                                                // Selection overlay
                                                                if (isSelected)
                                                                  Positioned
                                                                      .fill(
                                                                    child:
                                                                        Container(
                                                                      decoration:
                                                                          BoxDecoration(
                                                                        color: Colors
                                                                            .blue
                                                                            .withOpacity(0.3),
                                                                        borderRadius:
                                                                            BorderRadius.circular(12),
                                                                      ),
                                                                      child:
                                                                          const Center(
                                                                        child:
                                                                            Icon(
                                                                          Icons
                                                                              .check_circle,
                                                                          color:
                                                                              Colors.white,
                                                                          size:
                                                                              48,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                              ],
                                                            ),
                                                          ),
                                                          Padding(
                                                            padding:
                                                                EdgeInsets.all(
                                                              ResponsiveHelper
                                                                      .isMobile(
                                                                          context)
                                                                  ? 8.0
                                                                  : 12.0,
                                                            ),
                                                            child: Column(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [
                                                                Text(
                                                                  video
                                                                      .videoName,
                                                                  style:
                                                                      TextStyle(
                                                                    color: const Color(
                                                                        0xFF424242),
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                    fontSize: ResponsiveHelper
                                                                        .getAdaptiveFontSize(
                                                                            context,
                                                                            14),
                                                                  ),
                                                                  maxLines: 1,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                ),
                                                                SizedBox(
                                                                    height: ResponsiveHelper.isMobile(
                                                                            context)
                                                                        ? 4
                                                                        : 8),
                                                                Row(
                                                                  children: [
                                                                    Icon(
                                                                      Icons
                                                                          .visibility,
                                                                      color: const Color(
                                                                          0xFF757575),
                                                                      size: ResponsiveHelper.getAdaptiveIconSize(
                                                                              context) *
                                                                          0.6,
                                                                    ),
                                                                    SizedBox(
                                                                        width: ResponsiveHelper.isMobile(context)
                                                                            ? 4
                                                                            : 8),
                                                                    Text(
                                                                      '${video.views}',
                                                                      style:
                                                                          TextStyle(
                                                                        color: const Color(
                                                                            0xFF757575),
                                                                        fontSize: ResponsiveHelper.getAdaptiveFontSize(
                                                                            context,
                                                                            12),
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
                                                  if (_stateManager
                                                          .isSelecting &&
                                                      canSelectVideoFinal) // Use proper logic for video selection
                                                    Positioned(
                                                      top: 8,
                                                      right: 8,
                                                      child: Checkbox(
                                                        value: isSelected,
                                                        activeColor:
                                                            Colors.blue,
                                                        checkColor:
                                                            Colors.white,
                                                        side: const BorderSide(
                                                            color: Colors.blue,
                                                            width: 2),
                                                        onChanged: (checked) {
                                                          _stateManager
                                                              .toggleVideoSelection(
                                                                  video.id);
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
                              ),
                            ),
                          ));
      },
    );
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
      final userData = await _stateManager.getUserData();
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
}
