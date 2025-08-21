import 'package:flutter/material.dart';
import 'package:snehayog/core/constants/profile_constants.dart';

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
          Icon(
            Icons.error_outline,
            size: ProfileConstants.profileIconSize * 2,
            color: const Color(ProfileConstants.redColor),
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
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(ProfileConstants.blueColor),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: ProfileConstants.largeSpacing,
                  vertical: ProfileConstants.mediumSpacing,
                ),
              ),
              child: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }
}
