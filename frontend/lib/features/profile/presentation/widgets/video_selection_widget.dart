import 'package:flutter/material.dart';
import 'package:vayu/shared/constants/profile_constants.dart';
import 'package:vayu/shared/widgets/app_button.dart';

class VideoSelectionWidget extends StatelessWidget {
  final bool isVisible;
  final int selectedCount;
  final VoidCallback? onDelete;
  final VoidCallback? onClearSelection;
  final VoidCallback? onExitSelection;

  const VideoSelectionWidget({
    Key? key,
    required this.isVisible,
    required this.selectedCount,
    this.onDelete,
    this.onClearSelection,
    this.onExitSelection,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ProfileConstants.smallSpacing),
      child: Container(
        padding: const EdgeInsets.all(ProfileConstants.mediumSpacing),
        decoration: BoxDecoration(
          color: const Color(ProfileConstants.blueColor)
              .withValues(alpha: ProfileConstants.lightOpacity),
          borderRadius: BorderRadius.circular(ProfileConstants.mediumBorderRadius),
          border: Border.all(
            color: const Color(ProfileConstants.blueColor)
                .withValues(alpha: ProfileConstants.mediumOpacity),
            width: ProfileConstants.thinBorder,
          ),
        ),
        child: Column(
          children: [
            Text(
              ProfileConstants.selectionModeTitle,
              style: TextStyle(
                color: Colors.blue[700],
                fontWeight: FontWeight.bold,
                fontSize: ProfileConstants.largeFontSize,
              ),
            ),
            const SizedBox(height: ProfileConstants.smallSpacing),
            Text(
              '$selectedCount ${ProfileConstants.videosSelectedText}',
              style: TextStyle(
                color: Colors.blue[600],
                fontSize: ProfileConstants.mediumFontSize,
              ),
            ),
            const SizedBox(height: ProfileConstants.mediumSpacing),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: ProfileConstants.mediumSpacing,
                runSpacing: ProfileConstants.smallSpacing,
                children: [
                  AppButton(
                    icon: const Icon(Icons.delete),
                    label: '${ProfileConstants.deleteSelectedText} ($selectedCount)',
                    variant: AppButtonVariant.danger,
                    isDisabled: selectedCount <= 0,
                    onPressed: onDelete,
                  ),
                  AppButton(
                    icon: const Icon(Icons.clear),
                    label: ProfileConstants.clearSelectionText,
                    variant: AppButtonVariant.text,
                    onPressed: onClearSelection,
                  ),
                  AppButton(
                    icon: const Icon(Icons.close),
                    label: ProfileConstants.exitSelectionText,
                    variant: AppButtonVariant.text,
                    onPressed: onExitSelection,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
