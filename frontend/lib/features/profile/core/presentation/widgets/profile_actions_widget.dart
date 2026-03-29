import 'package:flutter/material.dart';
import 'package:vayu/shared/constants/profile_constants.dart';
import 'package:vayu/shared/widgets/app_button.dart';

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
            AppButton(
              onPressed: onCancel,
              label: ProfileConstants.cancelText,
              variant: AppButtonVariant.secondary,
            ),
            const SizedBox(width: ProfileConstants.mediumSpacing),
            AppButton(
              onPressed: onSave,
              label: ProfileConstants.saveText,
              variant: AppButtonVariant.primary,
            ),
          ],
        ),
      );
    } else {
      return Padding(
        padding: const EdgeInsets.all(ProfileConstants.mediumSpacing),
        child: AppButton(
          onPressed: onEdit,
          label: ProfileConstants.editText,
          variant: AppButtonVariant.primary,
        ),
      );
    }
  }
}
