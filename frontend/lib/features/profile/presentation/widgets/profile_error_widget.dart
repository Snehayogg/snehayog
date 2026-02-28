import 'package:flutter/material.dart';
import 'package:vayu/shared/constants/profile_constants.dart';
import 'package:vayu/shared/widgets/app_button.dart';

class ProfileErrorWidget extends StatelessWidget {
  final String errorMessage;
  final VoidCallback? onRetry;

  const ProfileErrorWidget({
    Key? key,
    required this.errorMessage,
    this.onRetry,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: ProfileConstants.profileIconSize * 2,
            color: Color(ProfileConstants.redColor),
          ),
          const SizedBox(height: ProfileConstants.mediumSpacing),
          Text(
            'Error: $errorMessage',
            style: const TextStyle(
              color: Color(ProfileConstants.primaryColor),
              fontSize: ProfileConstants.mediumFontSize,
            ),
            textAlign: TextAlign.center,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: ProfileConstants.mediumSpacing),
            AppButton(
              onPressed: onRetry,
              label: 'Retry',
              variant: AppButtonVariant.primary,
            ),
          ],
        ],
      ),
    );
  }
}
