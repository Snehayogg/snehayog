import 'package:flutter/material.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/services/video_service.dart';
import 'package:snehayog/services/google_auth_service.dart';
import 'package:snehayog/utils/responsive_helper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:async'; // Add this import for TimeoutException
import 'package:snehayog/services/user_service.dart';
import 'package:snehayog/view/screens/video_screen.dart';
import 'dart:convert'; // Add this import for jsonEncode
import 'package:http/http.dart' as http; // Add this import for http

class ProfileScreen extends StatefulWidget {
  final String? userId; // Add userId to accept a user ID
  const ProfileScreen({super.key, this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final VideoService _videoService = VideoService();
  final GoogleAuthService _authService = GoogleAuthService();
  final UserService _userService = UserService(); // Add user service
  List<VideoModel> _userVideos = [];
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _userData;
  bool _isEditing = false;
  final TextEditingController _nameController = TextEditingController();
  String? _originalName;
  String? _originalProfilePic;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final loggedInUser = await _authService.getUserData();
      final bool isMyProfile =
          widget.userId == null || widget.userId == loggedInUser?['id'];

      Map<String, dynamic>? userData;
      if (isMyProfile) {
        userData = loggedInUser;
        // Load saved profile data for the logged-in user
        final savedName = await _loadSavedName();
        final savedProfilePic = await _loadSavedProfilePic();
        if (userData != null) {
          userData['name'] = savedName ?? userData['name'];
          userData['profilePic'] = savedProfilePic ?? userData['profilePic'];
        }
      } else {
        // Fetch profile data for another user
        userData = await _userService.getUserById(widget.userId!);
      }

      if (userData != null) {
        setState(() {
          _userData = userData;
          _isLoading = false;
        });
        await _loadUserVideos();
      } else {
        setState(() {
          _isLoading = false;
          _error = 'Could not load user data.';
        });
      }
    } on TimeoutException catch (_) {
      setState(() {
        _error =
            'Connection timed out. Please check your internet connection and try again.';
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      print('Error in _loadUserData: $e');
      print('Stack trace: $stackTrace');
      setState(() {
        _error = 'Error loading user data: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<String?> _loadSavedName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_name');
  }

  Future<String?> _loadSavedProfilePic() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_profile_pic');
  }

  Future<void> _saveProfileData(String name, String? profilePic) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', name);
    if (profilePic != null) {
      await prefs.setString('user_profile_pic', profilePic);
    }
  }

  Future<void> _loadUserVideos() async {
    try {
      print('Starting to load user videos...');
      if (_userData == null) {
        print('User data is null, cannot load videos');
        return;
      }

      if (_userData!['id'] == null) {
        print('User ID is null in user data: $_userData');
        return;
      }

      final userId = _userData!['id'];
      print('Loading videos for user ID: $userId');

      final videos = await _videoService.getUserVideos(userId);
      print('Videos loaded successfully: ${videos.length} videos found');

      if (videos.isNotEmpty) {
        print('First video data: ${videos.first.toJson()}');
        print('Video URL: ${videos.first.videoUrl}');
      } else {
        print('No videos found for user');
      }

      setState(() {
        _userVideos = videos;
        _error = null; // Clear any previous errors
      });
    } catch (e, stackTrace) {
      print('Error in _loadUserVideos: $e');
      print('Stack trace: $stackTrace');
      setState(() {
        _error = e.toString();
      });
    }
  }

  Future<void> _handleLogout() async {
    try {
      await _authService.logout();
      setState(() {
        _userData = null;
        _userVideos = [];
      });
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
      final userData = await _authService.signInWithGoogle();
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
    setState(() {
      _isEditing = true;
      _originalName = _userData?['name'];
      _originalProfilePic = _userData?['profilePic'];
      _nameController.text = _userData?['name'] ?? '';
    });
  }

  Future<void> _handleSaveProfile() async {
    try {
      final newName = _nameController.text.trim();

      if (newName.isEmpty) {
        throw 'Name cannot be empty';
      }

      // Call backend to update name
      final googleId = _userData?['id']; // or whatever field is your googleId
      final response = await http.post(
        Uri.parse(
            'https://snehayog-production.up.railway.app/api/auth/update-name'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'googleId': googleId, 'name': newName}),
      );
      if (response.statusCode != 200) throw 'Failed to update name on server';

      // Save locally as before
      await _saveProfileData(newName, _userData?['profilePic']);

      setState(() {
        _userData = {
          ..._userData!,
          'name': newName,
        };
        _isEditing = false;
      });

      // Refresh videos
      await _loadUserVideos();

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
    setState(() {
      _isEditing = false;
      _userData = {
        ..._userData!,
        'name': _originalName,
        'profilePic': _originalProfilePic,
      };
    });
  }

  Future<void> _handleProfilePhotoChange() async {
    try {
      final ImagePicker picker = ImagePicker();

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
                    final XFile? photo =
                        await picker.pickImage(source: ImageSource.camera);
                    Navigator.pop(context, photo);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('Choose from Gallery'),
                  onTap: () async {
                    final XFile? photo =
                        await picker.pickImage(source: ImageSource.gallery);
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

        // Save the profile photo path
        await _saveProfileData(_userData?['name'] ?? '', imagePath);

        // Update the UI
        setState(() {
          _userData = {
            ..._userData!,
            'profilePic': imagePath,
          };
        });

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
    final bool isMyProfile = _userData != null &&
        (_authService.currentUser == null ||
            _authService.currentUser!['id'] == _userData!['id']);

    return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          title: Text(_userData?['name'] ?? 'Profile',
              style: TextStyle(color: Color(0xFF424242))),
          actions: isMyProfile && _userData != null
              ? [
                  IconButton(
                    icon: const Icon(Icons.logout, color: Color(0xFF424242)),
                    onPressed: _handleLogout,
                  ),
                ]
              : null,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Error: $_error',
                          style: const TextStyle(color: Color(0xFF424242)),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _error = null;
                              _isLoading = true;
                            });
                            _loadUserData();
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : _userData == null
                    ? _buildSignInView()
                    : RefreshIndicator(
                        onRefresh: _loadUserVideos,
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              Container(
                                padding: ResponsiveHelper.getAdaptivePadding(
                                    context),
                                child: Column(
                                  children: [
                                    Stack(
                                      children: [
                                        CircleAvatar(
                                          radius:
                                              ResponsiveHelper.isMobile(context)
                                                  ? 50
                                                  : 75,
                                          backgroundColor:
                                              const Color(0xFFF5F5F5),
                                          backgroundImage: _userData?[
                                                      'profilePic'] !=
                                                  null
                                              ? _userData!['profilePic']
                                                      .startsWith('http')
                                                  ? NetworkImage(
                                                      _userData!['profilePic'])
                                                  : FileImage(File(_userData![
                                                          'profilePic']))
                                                      as ImageProvider
                                              : null,
                                          onBackgroundImageError:
                                              (exception, stackTrace) {
                                            print(
                                                'Error loading profile image: $exception');
                                          },
                                          child: _userData?['profilePic'] ==
                                                  null
                                              ? Icon(
                                                  Icons.person,
                                                  size: ResponsiveHelper
                                                      .getAdaptiveIconSize(
                                                          context),
                                                  color:
                                                      const Color(0xFF757575),
                                                )
                                              : null,
                                        ),
                                        if (_isEditing)
                                          Positioned(
                                            bottom: 0,
                                            right: 0,
                                            child: IconButton(
                                              icon:
                                                  const Icon(Icons.camera_alt),
                                              onPressed:
                                                  _handleProfilePhotoChange,
                                              color: Colors.white,
                                              style: IconButton.styleFrom(
                                                backgroundColor: Colors.blue,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    SizedBox(
                                        height:
                                            ResponsiveHelper.isMobile(context)
                                                ? 16
                                                : 24),
                                    if (_isEditing)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 20),
                                        child: TextField(
                                          controller: _nameController,
                                          decoration: const InputDecoration(
                                            border: OutlineInputBorder(),
                                            labelText: 'Name',
                                            hintText: 'Enter a unique name',
                                          ),
                                        ),
                                      )
                                    else
                                      Text(
                                        _userData?['name'] ?? 'User',
                                        style: TextStyle(
                                          color: const Color(0xFF424242),
                                          fontSize: ResponsiveHelper
                                              .getAdaptiveFontSize(context, 24),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    if (isMyProfile)
                                      if (_isEditing)
                                        Padding(
                                          padding: const EdgeInsets.all(16.0),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
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
                              ),
                              Container(
                                padding: EdgeInsets.symmetric(
                                  vertical: ResponsiveHelper.isMobile(context)
                                      ? 20
                                      : 30,
                                ),
                                decoration: const BoxDecoration(
                                  border: Border(
                                    top: BorderSide(color: Color(0xFFE0E0E0)),
                                    bottom:
                                        BorderSide(color: Color(0xFFE0E0E0)),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    _buildStatColumn(
                                        'Videos', _userVideos.length),
                                    _buildStatColumn(
                                      'Followers',
                                      0, // This will be updated when we implement followers functionality
                                    ),
                                    _buildStatColumn(
                                      'Earnings',
                                      (_userVideos.fold(
                                              0.0,
                                              (sum, video) =>
                                                  sum + (video.views * 0.01)))
                                          .toInt(),
                                      isEarnings: true,
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: ResponsiveHelper.getAdaptivePadding(
                                    context),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Your Videos',
                                      style: TextStyle(
                                        color: const Color(0xFF424242),
                                        fontSize: ResponsiveHelper
                                            .getAdaptiveFontSize(context, 20),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    SizedBox(
                                        height:
                                            ResponsiveHelper.isMobile(context)
                                                ? 16
                                                : 24),
                                    GridView.builder(
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      gridDelegate:
                                          SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount:
                                            ResponsiveHelper.isMobile(context)
                                                ? 2
                                                : 3,
                                        crossAxisSpacing:
                                            ResponsiveHelper.isMobile(context)
                                                ? 16
                                                : 24,
                                        mainAxisSpacing:
                                            ResponsiveHelper.isMobile(context)
                                                ? 16
                                                : 24,
                                        childAspectRatio:
                                            ResponsiveHelper.isMobile(context)
                                                ? 0.75
                                                : 0.8,
                                      ),
                                      itemCount: _userVideos.length,
                                      itemBuilder: (context, index) {
                                        final video = _userVideos[index];
                                        return GestureDetector(
                                          onTap: () {
                                            // Update uploader name in all user videos before navigating
                                            final updatedVideos =
                                                _userVideos.map((video) {
                                              if (_userData != null &&
                                                  _userData!['name'] != null) {
                                                return video.copyWith(
                                                  uploader:
                                                      video.uploader.copyWith(
                                                    name: _userData!['name'],
                                                  ),
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
                                                  initialVideos: updatedVideos,
                                                ),
                                              ),
                                            );
                                          },
                                          child: Card(
                                            color: const Color(0xFFF5F5F5),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                Expanded(
                                                  child: Image.network(
                                                    video
                                                        .videoUrl, // Use videoUrl as a fallback
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (context,
                                                        error, stackTrace) {
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
                                                        CrossAxisAlignment
                                                            .start,
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
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                      SizedBox(
                                                          height: ResponsiveHelper
                                                                  .isMobile(
                                                                      context)
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
  }

  Widget _buildStatColumn(String label, int value, {bool isEarnings = false}) {
    return Builder(
      builder: (context) => Column(
        children: [
          Text(
            isEarnings ? '₹${value.toString()}' : value.toString(),
            style: TextStyle(
              color: const Color(0xFF424242),
              fontSize: ResponsiveHelper.getAdaptiveFontSize(context, 24),
              fontWeight: FontWeight.bold,
            ),
          ),
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
