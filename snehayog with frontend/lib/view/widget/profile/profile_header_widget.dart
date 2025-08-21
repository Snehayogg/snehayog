import 'dart:io';
import 'package:flutter/material.dart';
import 'package:snehayog/core/constants/profile_constants.dart';
import 'package:snehayog/utils/responsive_helper.dart';

class ProfileHeaderWidget extends StatelessWidget {
  final Map<String, dynamic> userData;
  final bool isEditing;
  final bool isMyProfile;
  final VoidCallback? onProfilePhotoChange;
  final TextEditingController? nameController;

  const ProfileHeaderWidget({
    Key? key,
    required this.userData,
    required this.isEditing,
    required this.isMyProfile,
    this.onProfilePhotoChange,
    this.nameController,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Profile Picture Section
        Stack(
          children: [
            CircleAvatar(
              radius: ResponsiveHelper.isMobile(context)
                  ? ProfileConstants.mobileProfileRadius
                  : ProfileConstants.desktopProfileRadius,
              backgroundColor: const Color(ProfileConstants.backgroundColor),
              backgroundImage: _getProfileImage(),
              onBackgroundImageError: (exception, stackTrace) {
                debugPrint('Error loading profile image: $exception');
              },
              child: userData['profilePic'] == null
                  ? Icon(
                      Icons.person,
                      size: ResponsiveHelper.getAdaptiveIconSize(context),
                      color: const Color(ProfileConstants.secondaryColor),
                    )
                  : null,
            ),
            if (isEditing && isMyProfile)
              Positioned(
                bottom: 0,
                right: 0,
                child: IconButton(
                  icon: const Icon(Icons.camera_alt),
                  onPressed: onProfilePhotoChange,
                  color: Colors.white,
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(ProfileConstants.blueColor),
                  ),
                ),
              ),
          ],
        ),

        SizedBox(
          height: ResponsiveHelper.isMobile(context)
              ? ProfileConstants.mediumSpacing
              : ProfileConstants.largeSpacing,
        ),

        // Name Section
        if (isEditing)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ProfileConstants.largeSpacing,
            ),
            child: TextField(
              controller: nameController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: ProfileConstants.nameLabelText,
                hintText: ProfileConstants.nameHintText,
              ),
            ),
          )
        else
          Text(
            userData['name'] ?? 'User',
            style: TextStyle(
              color: const Color(ProfileConstants.primaryColor),
              fontSize: ResponsiveHelper.getAdaptiveFontSize(
                context,
                ProfileConstants.titleFontSize,
              ),
              fontWeight: FontWeight.bold,
            ),
          ),
      ],
    );
  }

  ImageProvider? _getProfileImage() {
    final profilePic = userData['profilePic'];
    if (profilePic == null) return null;

    if (profilePic.startsWith('http')) {
      return NetworkImage(profilePic);
    } else {
      return FileImage(File(profilePic));
    }
  }
}
