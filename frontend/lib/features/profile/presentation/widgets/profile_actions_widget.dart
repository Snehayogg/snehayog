import 'package:flutter/material.dart';
import 'package:vayu/shared/constants/profile_constants.dart';

class ProfileActionsWidget extends StatelessWidget {
  final bool isEditing;
  final bool isMyProfile;
  final VoidCallback? onEdit;
  final VoidCallback? onSave;
  final VoidCallback? onCancel;

  const ProfileActionsWidget({
    Key? key,
    required this.isEditing,
    required this.isMyProfile,
    this.onEdit,
    this.onSave,
    this.onCancel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!isMyProfile) return const SizedBox.shrink();

    if (isEditing) {
      return Padding(
        padding: const EdgeInsets.all(ProfileConstants.mediumSpacing),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: onCancel,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(ProfileConstants.greyColor),
                foregroundColor: Colors.white,
              ),
              child: const Text(ProfileConstants.cancelText),
            ),
            const SizedBox(width: ProfileConstants.mediumSpacing),
            ElevatedButton(
              onPressed: onSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(ProfileConstants.blueColor),
                foregroundColor: Colors.white,
              ),
              child: const Text(ProfileConstants.saveText),
            ),
          ],
        ),
      );
    } else {
      return Padding(
        padding: const EdgeInsets.all(ProfileConstants.mediumSpacing),
        child: ElevatedButton(
          onPressed: onEdit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(ProfileConstants.blueColor),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(
              horizontal: ProfileConstants.largeSpacing,
              vertical: ProfileConstants.mediumSpacing,
            ),
          ),
          child: const Text(ProfileConstants.editText),
        ),
      );
    }
  }
}
