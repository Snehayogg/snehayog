import 'package:flutter/material.dart';
import 'package:snehayog/utils/responsive_helper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:snehayog/view/screens/video_screen.dart';
import 'package:snehayog/view/screens/creator_payment_setup_screen.dart';
import 'package:snehayog/view/screens/creator_revenue_screen.dart';
import 'package:snehayog/view/screens/creator_payout_dashboard.dart';
import 'dart:convert';
import 'package:snehayog/config/app_config.dart';
import 'package:snehayog/core/managers/profile_state_manager.dart';
import 'package:provider/provider.dart';
import 'package:snehayog/core/providers/user_provider.dart';
import 'package:snehayog/model/usermodel.dart';
import 'package:snehayog/services/video_service.dart';
import 'package:snehayog/core/services/profile_screen_logger.dart';
import 'package:snehayog/core/services/auto_scroll_settings.dart';
import 'package:snehayog/services/background_profile_preloader.dart';
import 'dart:async';
import 'package:snehayog/view/widget/report/report_dialog_widget.dart';
import 'package:snehayog/view/widget/feedback/feedback_dialog_widget.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;

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
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Progressive loading states
  bool _isProfileDataLoaded = false;
  bool _isVideosLoaded = false;
  bool _isFollowersLoaded = false;
  bool _isLoading = true;
  String? _error;
  int _authRetryAttempts = 0;

  // Referral tracking
  int _invitedCount = 0;
  int _verifiedInstalled = 0;
  int _verifiedSignedUp = 0;

  // Progressive loading timers
  Timer? _progressiveLoadTimer;
  int _currentLoadStep = 0;

  @override
  void initState() {
    super.initState();
    ProfileScreenLogger.logProfileScreenInit();
    _stateManager = ProfileStateManager();

    // Ensure context is set early for providers that may be used during loads
    // It will be set again in didChangeDependencies
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _stateManager.setContext(context);
    });

    // Start progressive loading immediately
    _startProgressiveLoading();
    // Load referral stats
    _loadReferralStats();
    _fetchVerifiedReferralStats();
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
        // Step 2: Load followers data (do not depend on videos)
        if (_isProfileDataLoaded && !_isFollowersLoaded) {
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
        // Retry a few times on first entry; auth may still be restoring
        if (_authRetryAttempts < 5) {
          _authRetryAttempts++;
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) _loadBasicProfileData();
          });
          return; // keep showing loading spinner
        } else {
          setState(() {
            _error = 'No authentication data found';
            _isLoading = false;
          });
          return;
        }
      }

      // **NEW: Check background preloaded data first (HIGHEST PRIORITY)**
      final preloader = BackgroundProfilePreloader();
      final preloadedProfileData = await preloader.getPreloadedProfileData();

      if (preloadedProfileData != null) {
        print('⚡ ProfileScreen: Using PRELOADED profile data (instant load!)');
        ProfileScreenLogger.logProfileLoadSuccess(userId: widget.userId);
        setState(() {
          _isProfileDataLoaded = true;
          _isLoading = false;
        });

        // Load from preloaded data instantly
        _stateManager.setUserData(preloadedProfileData);

        // Schedule background refresh if needed
        _scheduleBackgroundProfileRefresh();
        // Ensure payment setup flag is synced from backend/cache
        unawaited(_ensurePaymentSetupFlag());
        return;
      }

      // **ENHANCED: Check SharedPreferences cache first for instant loading**
      final cachedProfileData = await _loadCachedProfileData();
      if (cachedProfileData != null) {
        print('⚡ ProfileScreen: Using cached profile data');
        ProfileScreenLogger.logProfileLoadSuccess(userId: widget.userId);
        setState(() {
          _isProfileDataLoaded = true;
          _isLoading = false;
        });

        // Load from cache instantly, then refresh in background if needed
        _stateManager.setUserData(cachedProfileData);

        // Schedule background refresh if cache is stale
        _scheduleBackgroundProfileRefresh();
        // Ensure payment setup flag is synced from backend/cache
        unawaited(_ensurePaymentSetupFlag());
        return;
      }

      // Load basic profile data only if no cache available
      print('📡 ProfileScreen: Loading profile data from server...');
      await _stateManager.loadUserData(widget.userId);

      if (_stateManager.userData != null) {
        // **ENHANCED: Cache the loaded profile data**
        await _cacheProfileData(_stateManager.userData!);

        setState(() {
          _isProfileDataLoaded = true;
          _isLoading = false;
        });

        ProfileScreenLogger.logProfileLoadSuccess(userId: widget.userId);
        // Ensure payment setup flag is synced from backend
        unawaited(_ensurePaymentSetupFlag());
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
      final currentUserId = _stateManager.userData!['googleId'] ??
          _stateManager.userData!['_id'] ??
          _stateManager.userData!['id'];
      if (currentUserId != null) {
        ProfileScreenLogger.logVideoLoad(userId: currentUserId);

        // **NEW: Check background preloaded videos first (HIGHEST PRIORITY)**
        final preloader = BackgroundProfilePreloader();
        final preloadedVideos = await preloader.getPreloadedUserVideos();

        if (preloadedVideos != null && preloadedVideos.isNotEmpty) {
          print(
              '⚡ ProfileScreen: Using PRELOADED videos (instant load!) - ${preloadedVideos.length} videos');
          _stateManager.setVideos(preloadedVideos);

          setState(() {
            _isVideosLoaded = true;
          });

          ProfileScreenLogger.logVideoLoadSuccess(
              count: preloadedVideos.length);
          return;
        }

        if (_stateManager.userVideos.isNotEmpty) {
          ProfileScreenLogger.logVideoLoadSuccess(
              count: _stateManager.userVideos.length);
          setState(() {
            _isVideosLoaded = true;
          });
          return;
        }

        print('📡 ProfileScreen: Loading videos from server...');
        await _stateManager.loadUserVideos(currentUserId);

        setState(() {
          _isVideosLoaded = true;
        });

        ProfileScreenLogger.logVideoLoadSuccess(
            count: _stateManager.userVideos.length);
      }
    } catch (e) {
      ProfileScreenLogger.logVideoLoadError(e.toString());
      setState(() {
        _isVideosLoaded = true;
      });
    }
  }

  Future<void> _loadFollowersProgressive() async {
    try {
      // Build candidate IDs: prefer googleId, then Mongo _id/id, then widget.userId
      final List<String> idsToTry = <String?>[
        _stateManager.userData?['googleId'],
        _stateManager.userData?['_id'] ?? _stateManager.userData?['id'],
        widget.userId,
      ]
          .where((e) => e != null && (e).isNotEmpty)
          .map((e) => e as String)
          .toList()
          .toSet()
          .toList();

      if (idsToTry.isEmpty) {
        ProfileScreenLogger.logWarning(
            'No user ID available for followers load');
        setState(() {
          _isFollowersLoaded = true;
        });
        return;
      }

      final userProvider = Provider.of<UserProvider>(context, listen: false);
      bool loadedAny = false;

      // **ENHANCED: Check cache first before making API calls**
      for (final candidateId in idsToTry) {
        final cachedUserData = userProvider.getUserData(candidateId);
        if (cachedUserData != null) {
          ProfileScreenLogger.logDebugInfo(
              'Using cached followers data for user: $candidateId');
          loadedAny = true;
          break;
        }
      }

      // Only make API calls if no cached data is available
      if (!loadedAny) {
        for (final candidateId in idsToTry) {
          try {
            ProfileScreenLogger.logDebugInfo(
                'Loading followers for user: $candidateId');
            await userProvider.getUserDataWithFollowers(candidateId);

            final model = userProvider.getUserData(candidateId);
            final followersCount = model?.followersCount ??
                (_stateManager.userData != null
                    ? (_stateManager.userData!['followers'] ??
                        _stateManager.userData!['followersCount'] ??
                        0)
                    : 0);
            if (model != null || followersCount > 0) {
              loadedAny = true;
              break;
            }
          } catch (e) {
            ProfileScreenLogger.logWarning(
                'Followers load failed for $candidateId: $e');
          }
        }
      }

      setState(() {
        _isFollowersLoaded = true;
      });

      if (!loadedAny) {
        ProfileScreenLogger.logWarning(
            'Followers data not found for any candidate ID');
      }
    } catch (e) {
      ProfileScreenLogger.logWarning('Followers load failed: $e');
      // Mark as loaded to avoid infinite loading
      setState(() {
        _isFollowersLoaded = true;
      });
    }
  }

  Future<void> _loadAdditionalUserData() async {
    try {
      if (widget.userId == null && _stateManager.userData != null) {
        final currentUserId =
            _stateManager.userData!['_id'] ?? _stateManager.userData!['id'];
        if (currentUserId != null) {
          final userProvider =
              Provider.of<UserProvider>(context, listen: false);
          await userProvider.getUserDataWithFollowers(currentUserId);
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

      // **ENHANCED: Clear profile cache on logout**
      await _clearProfileCache();

      await _stateManager.handleLogout();

      // **ENHANCED: Clear UserProvider cache**
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      userProvider.clearAllCaches();

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
    setState(() {
      _isProfileDataLoaded = false;
      _isVideosLoaded = false;
      _isFollowersLoaded = false;
      _isLoading = true;
      _error = null;
      _currentLoadStep = 0;
    });

    _clearProfileCache();

    _progressiveLoadTimer?.cancel();
    _startProgressiveLoading();
  }

  /// Share app referral message
  Future<void> _handleReferFriends() async {
    try {
      // Build a referral link with user code if available
      String base = 'https://snehayog.app';
      String referralCode = '';
      final userData = _stateManager.getUserData();
      final token = userData?['token'];
      if (token != null) {
        try {
          final uri = Uri.parse('${AppConfig.baseUrl}/api/referrals/code');
          final resp = await http.get(uri, headers: {
            'Authorization': 'Bearer $token',
          }).timeout(const Duration(seconds: 6));
          if (resp.statusCode == 200) {
            final data = json.decode(resp.body);
            referralCode = data['code'] ?? '';
          }
        } catch (_) {}
      }
      final String referralLink =
          referralCode.isNotEmpty ? '$base/?ref=$referralCode' : base;
      final String message =
          'I am using Snehayog! Refer 2 friends and get full access. Join now: $referralLink';
      await Share.share(
        message,
        subject: 'Snehayog – Refer 2 friends and get full access',
      );

      // Optimistically increment invite counter
      final prefs = await SharedPreferences.getInstance();
      _invitedCount = (prefs.getInt('referral_invite_count') ?? 0) + 1;
      await prefs.setInt('referral_invite_count', _invitedCount);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to share right now. Please try again.'),
          ),
        );
      }
    }
  }

  Future<void> _loadReferralStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _invitedCount = prefs.getInt('referral_invite_count') ?? 0;
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _fetchVerifiedReferralStats() async {
    try {
      final userData = _stateManager.getUserData();
      final token = userData?['token'];
      if (token == null) return;
      final uri = Uri.parse('${AppConfig.baseUrl}/api/referrals/stats');
      final resp = await http.get(uri, headers: {
        'Authorization': 'Bearer $token',
      }).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        _verifiedInstalled = data['installed'] ?? 0;
        _verifiedSignedUp = data['signedUp'] ?? 0;
        if (mounted) setState(() {});
      }
    } catch (_) {}
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
          barrierDismissible: false,
          builder: (BuildContext context) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Icon with animated background
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.red.withOpacity(0.3),
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.delete_forever,
                        color: Colors.red,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Title
                    const Text(
                      'Delete Videos?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Description
                    Text(
                      'You are about to delete ${_stateManager.selectedVideoIds.length} video${_stateManager.selectedVideoIds.length == 1 ? '' : 's'}. This action cannot be undone.',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 16,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),

                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: Colors.grey.withOpacity(0.3),
                                ),
                              ),
                            ),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              elevation: 0,
                            ),
                            child: const Text(
                              'Delete',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
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
                  backgroundColor: Colors.grey[700],
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.grey[600]!),
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
        key: _scaffoldKey,
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: _buildAppBar(),
        drawer: _buildSideMenu(),
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
                      itemCount: 6,
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
      preferredSize: const Size.fromHeight(kToolbarHeight + 10),
      child: Consumer<ProfileStateManager>(
        builder: (context, stateManager, child) {
          return AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            shadowColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            title: Text(
              stateManager.userData?['name'] ?? 'Profile',
              style: const TextStyle(
                color: Color(0xFF1A1A1A),
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            leading: IconButton(
              icon: const Icon(Icons.menu, color: Color(0xFF1A1A1A), size: 24),
              tooltip: 'Menu',
              onPressed: () {
                _scaffoldKey.currentState?.openDrawer();
              },
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(
                height: 1,
                color: const Color(0xFFE5E7EB),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSideMenu() {
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
                    return ListView(
                      children: [
                        FutureBuilder<bool>(
                          future: AutoScrollSettings.isEnabled(),
                          builder: (context, snapshot) {
                            final enabled = snapshot.data ?? false;
                            return ListTile(
                              leading: const Icon(Icons.swap_vert_circle,
                                  color: Colors.black54),
                              title: const Text('Auto Scroll',
                                  style: TextStyle(color: Colors.black87)),
                              subtitle: Text(
                                enabled
                                    ? 'Auto-scroll is ON'
                                    : 'Auto-scroll is OFF',
                                style: const TextStyle(color: Colors.black54),
                              ),
                              trailing: Switch(
                                value: enabled,
                                activeThumbColor: Colors.blue,
                                activeTrackColor: Colors.blue.withOpacity(0.3),
                                inactiveThumbColor: Colors.grey,
                                inactiveTrackColor:
                                    Colors.grey.withOpacity(0.3),
                                onChanged: (val) async {
                                  await AutoScrollSettings.setEnabled(val);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            'Auto Scroll: ${val ? 'ON' : 'OFF'}'),
                                        duration: const Duration(seconds: 1),
                                      ),
                                    );
                                  }
                                  (context as Element).markNeedsBuild();
                                },
                              ),
                              onTap: () async {
                                final next = !enabled;
                                await AutoScrollSettings.setEnabled(next);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'Auto Scroll: ${next ? 'ON' : 'OFF'}'),
                                      duration: const Duration(seconds: 1),
                                    ),
                                  );
                                }
                                (context as Element).markNeedsBuild();
                              },
                            );
                          },
                        ),
                        Divider(
                            color: Colors.grey[300], height: 1, thickness: 0.5),
                        // Edit Profile / Save / Cancel
                        if (!stateManager.isEditing) ...[
                          ListTile(
                            leading:
                                const Icon(Icons.edit, color: Colors.black54),
                            title: const Text('Edit Profile',
                                style: TextStyle(color: Colors.black87)),
                            subtitle: const Text(
                                'Update your profile information',
                                style: TextStyle(color: Colors.black54)),
                            onTap: () {
                              Navigator.pop(context);
                              _handleEditProfile();
                            },
                          ),
                          Divider(
                              color: Colors.grey[300],
                              height: 1,
                              thickness: 0.5),
                        ] else ...[
                          ListTile(
                            leading:
                                const Icon(Icons.save, color: Colors.black54),
                            title: const Text('Save Changes',
                                style: TextStyle(color: Colors.black87)),
                            subtitle: const Text('Apply your edits',
                                style: TextStyle(color: Colors.black54)),
                            onTap: () {
                              Navigator.pop(context);
                              _handleSaveProfile();
                            },
                          ),
                          ListTile(
                            leading:
                                const Icon(Icons.close, color: Colors.black54),
                            title: const Text('Cancel Edit',
                                style: TextStyle(color: Colors.black87)),
                            subtitle: const Text('Discard changes',
                                style: TextStyle(color: Colors.black54)),
                            onTap: () {
                              Navigator.pop(context);
                              _handleCancelEdit();
                            },
                          ),
                          Divider(
                              color: Colors.grey[300],
                              height: 1,
                              thickness: 0.5),
                        ],
                        ListTile(
                          leading: const Icon(Icons.dashboard,
                              color: Colors.black54),
                          title: const Text('Creator Dashboard',
                              style: TextStyle(color: Colors.black87)),
                          subtitle: const Text('View earnings and analytics',
                              style: TextStyle(color: Colors.black54)),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const CreatorPayoutDashboard(),
                              ),
                            );
                          },
                        ),
                        Divider(
                            color: Colors.grey[300], height: 1, thickness: 0.5),
                        // Conditionally show Report User when viewing someone else's profile
                        if (widget.userId != null &&
                            ((_stateManager.userData?['_id'] ??
                                    _stateManager.userData?['id'] ??
                                    _stateManager.userData?['googleId']) !=
                                widget.userId)) ...[
                          ListTile(
                            leading: const Icon(Icons.flag_outlined,
                                color: Colors.black54),
                            title: const Text('Report User',
                                style: TextStyle(color: Colors.black87)),
                            subtitle: const Text(
                                'Report inappropriate behavior',
                                style: TextStyle(color: Colors.black54)),
                            onTap: () {
                              Navigator.pop(context);
                              final targetId = widget.userId!;
                              _openReportDialog(
                                targetType: 'user',
                                targetId: targetId,
                              );
                            },
                          ),
                          Divider(
                              color: Colors.grey[300],
                              height: 1,
                              thickness: 0.5),
                        ],
                        // Feedback
                        ListTile(
                          leading: const Icon(Icons.feedback_outlined,
                              color: Colors.black54),
                          title: const Text('Feedback',
                              style: TextStyle(color: Colors.black87)),
                          subtitle: const Text('Tell us what you think',
                              style: TextStyle(color: Colors.black54)),
                          onTap: () {
                            Navigator.pop(context);
                            _showFeedbackDialog();
                          },
                        ),
                        Divider(
                            color: Colors.grey[300], height: 1, thickness: 0.5),
                        ListTile(
                          leading: const Icon(Icons.delete_outline,
                              color: Colors.black54),
                          title: const Text('Delete Videos',
                              style: TextStyle(color: Colors.black87)),
                          subtitle: const Text('Select and delete your videos',
                              style: TextStyle(color: Colors.black54)),
                          onTap: () {
                            Navigator.pop(context);
                            stateManager.enterSelectionMode();
                          },
                        ),
                        Divider(
                            color: Colors.grey[300], height: 1, thickness: 0.5),
                        ListTile(
                          leading:
                              const Icon(Icons.settings, color: Colors.black54),
                          title: const Text('Settings',
                              style: TextStyle(color: Colors.black87)),
                          subtitle: const Text('App settings and preferences',
                              style: TextStyle(color: Colors.black54)),
                          onTap: () {
                            Navigator.pop(context);
                            _showSettingsBottomSheet();
                          },
                        ),
                        Divider(
                            color: Colors.grey[300], height: 1, thickness: 0.5),
                        ListTile(
                          leading:
                              const Icon(Icons.logout, color: Colors.black54),
                          title: const Text('Sign Out',
                              style: TextStyle(color: Colors.black87)),
                          subtitle: const Text('Sign out of your account',
                              style: TextStyle(color: Colors.black54)),
                          onTap: () {
                            Navigator.pop(context);
                            _handleLogout();
                          },
                        ),
                      ],
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

  /// **NEW: Professional Settings Bottom Sheet**
  void _showSettingsBottomSheet() {
    print('🔧 ProfileScreen: Opening Settings Bottom Sheet');
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.settings, color: Colors.black87, size: 24),
                  const SizedBox(width: 12),
                  const Text(
                    'Settings',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.black54),
                  ),
                ],
              ),
            ),
            Divider(color: Colors.grey[300], height: 1),

            // Settings options
            Consumer<ProfileStateManager>(
              builder: (context, stateManager, child) {
                if (stateManager.userData != null) {
                  return Column(
                    children: [
                      _buildSettingsTile(
                        icon: Icons.swap_vert_circle,
                        title: 'Auto Scroll',
                        subtitle: 'Auto-scroll to next video after finish',
                        onTap: () async {
                          // Toggle the preference
                          final enabled = await AutoScrollSettings.isEnabled();
                          await AutoScrollSettings.setEnabled(!enabled);
                          if (mounted) {
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
                        iconColor: Colors.grey,
                      ),
                      _buildSettingsTile(
                        icon: Icons.edit,
                        title: 'Edit Profile',
                        subtitle: 'Update your profile information',
                        onTap: () {
                          Navigator.pop(context);
                          _handleEditProfile();
                        },
                      ),
                      _buildSettingsTile(
                        icon: Icons.video_library,
                        title: 'Manage Videos',
                        subtitle: 'View and manage your videos',
                        onTap: () {
                          Navigator.pop(context);
                          // Already on profile screen, just scroll to videos
                        },
                      ),
                      _buildSettingsTile(
                        icon: Icons.dashboard,
                        title: 'Creator Dashboard',
                        subtitle: 'View earnings and analytics',
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const CreatorPayoutDashboard(),
                            ),
                          );
                        },
                      ),
                      _buildSettingsTile(
                        icon: Icons.analytics,
                        title: 'Revenue Analytics',
                        subtitle: 'Track your earnings',
                        onTap: () async {
                          Navigator.pop(context);
                          final hasPaymentSetup =
                              await _checkPaymentSetupStatus();
                          if (hasPaymentSetup) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const CreatorRevenueScreen(),
                              ),
                            );
                          } else {
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
                      _buildSettingsTile(
                        icon: Icons.help_outline,
                        title: 'Help & Support',
                        subtitle: 'Get help with your account',
                        onTap: () {
                          Navigator.pop(context);
                          _showHelpDialog();
                        },
                      ),
                      _buildSettingsTile(
                        icon: Icons.feedback_outlined,
                        title: 'Feedback',
                        subtitle: 'Share ideas or report a problem',
                        onTap: () {
                          Navigator.pop(context);
                          _showFeedbackDialog();
                        },
                      ),
                    ],
                  );
                } else {
                  return Column(
                    children: [
                      _buildSettingsTile(
                        icon: Icons.login,
                        title: 'Sign In',
                        subtitle: 'Sign in to access your profile',
                        onTap: () {
                          Navigator.pop(context);
                          _handleGoogleSignIn();
                        },
                      ),
                      _buildSettingsTile(
                        icon: Icons.help_outline,
                        title: 'Help & Support',
                        subtitle: 'Get help with your account',
                        onTap: () {
                          Navigator.pop(context);
                          _showHelpDialog();
                        },
                      ),
                    ],
                  );
                }
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  /// **NEW: Professional Settings Tile**
  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: (iconColor ?? Colors.grey).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: iconColor ?? Colors.grey,
          size: 20,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: Colors.black54,
          fontSize: 14,
        ),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
    );
  }

  /// **NEW: Help Dialog**
  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: Colors.black87),
            SizedBox(width: 12),
            Text(
              'Help & Support',
              style: TextStyle(color: Colors.black87),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Need help? Here are some common solutions:',
              style: TextStyle(color: Colors.black54, fontSize: 16),
            ),
            SizedBox(height: 16),
            Text(
              '• Profile Issues: Try refreshing your profile',
              style: TextStyle(color: Colors.black87, fontSize: 14),
            ),
            Text(
              '• Video Problems: Check if videos need HLS conversion',
              style: TextStyle(color: Colors.black87, fontSize: 14),
            ),
            Text(
              '• Payment Setup: Complete payment setup for earnings',
              style: TextStyle(color: Colors.black87, fontSize: 14),
            ),
            Text(
              '• Account Issues: Try signing out and back in',
              style: TextStyle(color: Colors.black87, fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.black54)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _debugState();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Debug Info'),
          ),
        ],
      ),
    );
  }

  /// **NEW: Feedback Dialog**
  void _showFeedbackDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const FeedbackDialogWidget(),
    );
  }

  /// **NEW: Open Report Dialog**
  void _openReportDialog(
      {required String targetType, required String targetId}) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => ReportDialogWidget(
        targetType: targetType,
        targetId: targetId,
      ),
    );
  }

  Widget _buildProfileHeader(UserProvider userProvider, UserModel? userModel) {
    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          children: [
            // Profile Picture Section
            RepaintBoundary(
              child: Stack(
                children: [
                  Consumer<ProfileStateManager>(
                    builder: (context, stateManager, child) {
                      return Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFE5E7EB),
                            width: 3,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: 57,
                          backgroundColor: const Color(0xFFF3F4F6),
                          backgroundImage: _getProfileImage(),
                          onBackgroundImageError: (exception, stackTrace) {
                            ProfileScreenLogger.logError(
                                'Error loading profile image: $exception');
                          },
                          child: _getProfileImage() == null
                              ? const Icon(
                                  Icons.person,
                                  size: 48,
                                  color: Color(0xFF9CA3AF),
                                )
                              : null,
                        ),
                      );
                    },
                  ),
                  Consumer<ProfileStateManager>(
                    builder: (context, stateManager, child) {
                      if (stateManager.isEditing) {
                        return Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFF3B82F6),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 3,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: IconButton(
                              icon: const Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                                size: 18,
                              ),
                              onPressed: _handleProfilePhotoChange,
                              padding: EdgeInsets.zero,
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
            const SizedBox(height: 24),

            // Username Section
            Consumer<ProfileStateManager>(
              builder: (context, stateManager, child) {
                if (stateManager.isEditing) {
                  return RepaintBoundary(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: stateManager.nameController,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A1A),
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Enter your name',
                          hintStyle: TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  );
                } else {
                  return RepaintBoundary(
                    child: Text(
                      _getUserName(),
                      style: const TextStyle(
                        color: Color(0xFF1A1A1A),
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                  );
                }
              },
            ),

            // Edit Action Buttons
            Consumer<ProfileStateManager>(
              builder: (context, stateManager, child) {
                if (stateManager.isEditing) {
                  return RepaintBoundary(
                    child: Container(
                      margin: const EdgeInsets.only(top: 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton(
                            onPressed: _handleCancelEdit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFF3F4F6),
                              foregroundColor: const Color(0xFF6B7280),
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide.none,
                              ),
                            ),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton(
                            onPressed: _handleSaveProfile,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3B82F6),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide.none,
                              ),
                            ),
                            child: const Text(
                              'Save',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                } else {
                  return const SizedBox.shrink();
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
          // Stats Section
          RepaintBoundary(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
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
                      Container(
                        width: 1,
                        height: 40,
                        color: const Color(0xFFE5E7EB),
                      ),
                      _buildStatColumn(
                        'Followers',
                        _isFollowersLoaded ? _getFollowersCount() : '...',
                        isLoading: !_isFollowersLoaded,
                        onTap: () {
                          // **NEW: Debug followers loading**
                          ProfileScreenLogger.logDebugInfo(
                              '=== FOLLOWERS DEBUG ===');
                          ProfileScreenLogger.logDebugInfo(
                              '_isFollowersLoaded: $_isFollowersLoaded');
                          ProfileScreenLogger.logDebugInfo(
                              'widget.userId: ${widget.userId}');
                          ProfileScreenLogger.logDebugInfo(
                              '_stateManager.userData: ${_stateManager.userData != null}');
                          if (_stateManager.userData != null) {
                            ProfileScreenLogger.logDebugInfo(
                                'Current user ID: ${_stateManager.userData!['_id'] ?? _stateManager.userData!['id']}');
                          }

                          // Show debug info
                          if (mounted) {
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Followers Debug Info'),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        'Followers Loaded: $_isFollowersLoaded'),
                                    Text(
                                        'User ID: ${widget.userId ?? "Own Profile"}'),
                                    Text(
                                        'Followers Count: ${_getFollowersCount()}'),
                                    Text(
                                        'User Data Available: ${_stateManager.userData != null}'),
                                    if (_stateManager.userData != null) ...[
                                      Text(
                                          'ObjectID: ${_stateManager.userData!['_id'] ?? "Not Set"}'),
                                      Text(
                                          'ID: ${_stateManager.userData!['id'] ?? "Not Set"}'),
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
                                      // Force reload followers
                                      setState(() {
                                        _isFollowersLoaded = false;
                                      });
                                      _loadFollowersProgressive();
                                    },
                                    child: const Text('Reload Followers'),
                                  ),
                                ],
                              ),
                            );
                          }
                        },
                      ),
                      Container(
                        width: 1,
                        height: 40,
                        color: const Color(0xFFE5E7EB),
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

          const SizedBox(height: 24),

          // Action Buttons Section
          RepaintBoundary(
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFF10B981), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: _handleReferFriends,
                      icon: const Icon(
                        Icons.share,
                        color: Color(0xFF10B981),
                        size: 20,
                      ),
                      label: const Text(
                        'Refer 2 friends and get full access',
                        style: TextStyle(
                          color: Color(0xFF10B981),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
                if (_invitedCount > 0 ||
                    _verifiedInstalled > 0 ||
                    _verifiedSignedUp > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Invited: $_invitedCount • Installed: $_verifiedInstalled • Signed up: $_verifiedSignedUp',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),

          // Videos Section
          RepaintBoundary(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your Videos',
                    style: TextStyle(
                      color: Color(0xFF1A1A1A),
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 16),
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
                            padding: const EdgeInsets.all(48),
                            child: Column(
                              children: [
                                Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF3F4F6),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Icon(
                                    Icons.video_library_outlined,
                                    size: 40,
                                    color: Color(0xFF9CA3AF),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                const Text(
                                  'No videos yet',
                                  style: TextStyle(
                                    color: Color(0xFF374151),
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Upload your first video to get started!',
                                  style: TextStyle(
                                    color: Color(0xFF9CA3AF),
                                    fontSize: 16,
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
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            childAspectRatio: 0.75,
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
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.08),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: Stack(
                                      children: [
                                        // Video Thumbnail
                                        Container(
                                          width: double.infinity,
                                          height: double.infinity,
                                          color: const Color(0xFFF3F4F6),
                                          child: video.thumbnailUrl.isNotEmpty
                                              ? Image.network(
                                                  video.thumbnailUrl,
                                                  fit: BoxFit.cover,
                                                  width: double.infinity,
                                                  height: double.infinity,
                                                  errorBuilder: (context, error,
                                                      stackTrace) {
                                                    ProfileScreenLogger.logError(
                                                        'Error loading thumbnail: $error');
                                                    return const Center(
                                                      child: Icon(
                                                        Icons.video_library,
                                                        color:
                                                            Color(0xFF9CA3AF),
                                                        size: 32,
                                                      ),
                                                    );
                                                  },
                                                )
                                              : const Center(
                                                  child: Icon(
                                                    Icons.video_library,
                                                    color: Color(0xFF9CA3AF),
                                                    size: 32,
                                                  ),
                                                ),
                                        ),

                                        // Views Overlay
                                        Positioned(
                                          bottom: 12,
                                          left: 12,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color:
                                                  Colors.black.withOpacity(0.7),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.visibility,
                                                  color: Colors.white,
                                                  size: 14,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  '${video.views}',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),

                                        // Selection Overlay
                                        if (isSelected)
                                          Positioned.fill(
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFEF4444)
                                                    .withOpacity(0.2),
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                                border: Border.all(
                                                  color:
                                                      const Color(0xFFEF4444),
                                                  width: 3,
                                                ),
                                              ),
                                              child: Center(
                                                child: Container(
                                                  width: 48,
                                                  height: 48,
                                                  decoration:
                                                      const BoxDecoration(
                                                    color: Color(0xFFEF4444),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: const Icon(
                                                    Icons.check,
                                                    color: Colors.white,
                                                    size: 24,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),

                                        // Selection Checkbox
                                        if (stateManager.isSelecting &&
                                            canSelectVideo)
                                          Positioned(
                                            top: 12,
                                            right: 12,
                                            child: GestureDetector(
                                              onTap: () {
                                                stateManager
                                                    .toggleVideoSelection(
                                                        video.id);
                                              },
                                              child: Container(
                                                width: 24,
                                                height: 24,
                                                decoration: BoxDecoration(
                                                  color: isSelected
                                                      ? const Color(0xFFEF4444)
                                                      : Colors.white
                                                          .withOpacity(0.8),
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: isSelected
                                                        ? const Color(
                                                            0xFFEF4444)
                                                        : Colors.white,
                                                    width: 2,
                                                  ),
                                                ),
                                                child: isSelected
                                                    ? const Icon(
                                                        Icons.check,
                                                        color: Colors.white,
                                                        size: 16,
                                                      )
                                                    : null,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),

                  // **PROFESSIONAL: Modern delete action bar**
                  Consumer<ProfileStateManager>(
                    builder: (context, stateManager, child) {
                      if (stateManager.isSelecting &&
                          stateManager.selectedVideoIds.isNotEmpty) {
                        return RepaintBoundary(
                          child: Container(
                            margin: const EdgeInsets.all(16),
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                // Selection info with icon
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withOpacity(0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.video_library,
                                        color: Colors.red,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${stateManager.selectedVideoIds.length} video${stateManager.selectedVideoIds.length == 1 ? '' : 's'} selected',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            'Ready for deletion',
                                            style: TextStyle(
                                              color: Colors.grey[400],
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),

                                // Action buttons
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextButton(
                                        onPressed: () {
                                          stateManager.exitSelectionMode();
                                        },
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 14),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            side: BorderSide(
                                              color:
                                                  Colors.grey.withOpacity(0.3),
                                            ),
                                          ),
                                        ),
                                        child: const Text(
                                          'Cancel',
                                          style: TextStyle(
                                            color: Colors.grey,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      flex: 2,
                                      child: ElevatedButton.icon(
                                        onPressed: _handleDeleteSelectedVideos,
                                        icon: const Icon(
                                          Icons.delete_forever,
                                          size: 20,
                                        ),
                                        label: Text(
                                          'Delete ${stateManager.selectedVideoIds.length == 1 ? 'Video' : 'Videos'}',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 14),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          elevation: 0,
                                        ),
                                      ),
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

  // **NEW: Helper method to get followers count using MongoDB ObjectID**
  int _getFollowersCount() {
    ProfileScreenLogger.logDebugInfo('=== GETTING FOLLOWERS COUNT ===');
    ProfileScreenLogger.logDebugInfo('widget.userId: ${widget.userId}');
    ProfileScreenLogger.logDebugInfo(
        '_stateManager.userData: ${_stateManager.userData != null}');

    // Build candidate IDs to query provider with
    final List<String> idsToTry = <String?>[
      widget.userId,
      _stateManager.userData?['googleId'],
      _stateManager.userData?['_id'] ?? _stateManager.userData?['id'],
    ]
        .where((e) => e != null && (e).isNotEmpty)
        .map((e) => e as String)
        .toList()
        .toSet()
        .toList();

    if (idsToTry.isNotEmpty) {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      for (final candidateId in idsToTry) {
        final userModel = userProvider.getUserData(candidateId);
        if (userModel?.followersCount != null) {
          ProfileScreenLogger.logDebugInfo(
              'Using followers count from UserProvider for $candidateId: ${userModel!.followersCount}');
          return userModel.followersCount;
        }
      }
    }

    // **NEW: Check if we're viewing own profile**
    if (widget.userId == null && _stateManager.userData != null) {
      ProfileScreenLogger.logDebugInfo('Viewing own profile');

      // Prefer counts available in userData
      final followersCount = _stateManager.userData!['followers'] ??
          _stateManager.userData!['followersCount'] ??
          0;
      if (followersCount != 0) {
        ProfileScreenLogger.logDebugInfo(
            'Using followers count from ProfileStateManager: $followersCount');
        return followersCount;
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
        'No followers count available, using default: 0');
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
          _stateManager.userData!['_id'] != null) {
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

  /// Sync local 'has_payment_setup' flag from backend once user data exists
  Future<void> _ensurePaymentSetupFlag() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final already = prefs.getBool('has_payment_setup') ?? false;
      if (already) return;

      if (_stateManager.userData != null &&
          _stateManager.userData!['_id'] != null) {
        final backendHas = await _checkBackendPaymentSetup();
        if (backendHas) {
          await prefs.setBool('has_payment_setup', true);
          ProfileScreenLogger.logPaymentSetupFound();
        }
      }
    } catch (e) {
      ProfileScreenLogger.logWarning('ensurePaymentSetupFlag failed: $e');
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
                  style: const TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 14,
                fontWeight: FontWeight.w500,
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
                  final currentUserId = _stateManager.userData!['_id'] ??
                      _stateManager.userData!['id'];
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
        final currentUserId =
            _stateManager.userData!['_id'] ?? _stateManager.userData!['id'];
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
        final currentUserId =
            _stateManager.userData!['_id'] ?? _stateManager.userData!['id'];
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

  // **NEW: Enhanced caching methods for profile data**

  /// Load cached profile data from SharedPreferences
  Future<Map<String, dynamic>?> _loadCachedProfileData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _getProfileCacheKey();
      final cachedDataJson = prefs.getString('profile_cache_$cacheKey');
      final cacheTimestamp = prefs.getInt('profile_cache_timestamp_$cacheKey');

      if (cachedDataJson != null && cacheTimestamp != null) {
        final cacheAge = DateTime.now().millisecondsSinceEpoch - cacheTimestamp;
        const maxCacheAge = 30 * 60 * 1000; // 30 minutes in milliseconds

        if (cacheAge < maxCacheAge) {
          ProfileScreenLogger.logDebugInfo(
              'Loading profile from SharedPreferences cache');
          return Map<String, dynamic>.from(json.decode(cachedDataJson));
        } else {
          ProfileScreenLogger.logDebugInfo(
              'Profile cache expired, removing stale data');
          await _clearProfileCache();
        }
      }
    } catch (e) {
      ProfileScreenLogger.logWarning('Error loading cached profile data: $e');
    }
    return null;
  }

  /// Cache profile data to SharedPreferences
  Future<void> _cacheProfileData(Map<String, dynamic> profileData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _getProfileCacheKey();

      await prefs.setString(
          'profile_cache_$cacheKey', json.encode(profileData));
      await prefs.setInt('profile_cache_timestamp_$cacheKey',
          DateTime.now().millisecondsSinceEpoch);

      ProfileScreenLogger.logDebugInfo(
          'Profile data cached to SharedPreferences');
    } catch (e) {
      ProfileScreenLogger.logWarning('Error caching profile data: $e');
    }
  }

  /// Get cache key for current profile
  String _getProfileCacheKey() {
    if (widget.userId != null) {
      return widget.userId!;
    }
    // For own profile, use a consistent key
    return 'own_profile';
  }

  /// Clear profile cache
  Future<void> _clearProfileCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _getProfileCacheKey();

      await prefs.remove('profile_cache_$cacheKey');
      await prefs.remove('profile_cache_timestamp_$cacheKey');

      ProfileScreenLogger.logDebugInfo('Profile cache cleared');
    } catch (e) {
      ProfileScreenLogger.logWarning('Error clearing profile cache: $e');
    }
  }

  /// Schedule background refresh if cache is getting stale
  void _scheduleBackgroundProfileRefresh() {
    // Only refresh if cache is older than 15 minutes
    Timer(const Duration(seconds: 5), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final cacheKey = _getProfileCacheKey();
        final cacheTimestamp =
            prefs.getInt('profile_cache_timestamp_$cacheKey');

        if (cacheTimestamp != null) {
          final cacheAge =
              DateTime.now().millisecondsSinceEpoch - cacheTimestamp;
          const staleThreshold = 15 * 60 * 1000; // 15 minutes in milliseconds

          if (cacheAge > staleThreshold) {
            ProfileScreenLogger.logDebugInfo(
                'Background refreshing stale profile data');
            await _stateManager.loadUserData(widget.userId);

            if (_stateManager.userData != null) {
              await _cacheProfileData(_stateManager.userData!);
            }
          }
        }
      } catch (e) {
        ProfileScreenLogger.logWarning('Background profile refresh failed: $e');
      }
    });
  }
}
