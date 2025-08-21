import 'package:flutter/material.dart';
import 'package:snehayog/core/constants/profile_constants.dart';

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
              .withOpacity(ProfileConstants.lightOpacity),
          borderRadius: BorderRadius.circular(ProfileConstants.mediumBorderRadius),
          border: Border.all(
            color: const Color(ProfileConstants.blueColor)
                .withOpacity(ProfileConstants.mediumOpacity),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.delete),
                  label: Text('${ProfileConstants.deleteSelectedText} ($selectedCount)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(ProfileConstants.redColor),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(ProfileConstants.greyColor),
                  ),
                  onPressed: selectedCount > 0 ? onDelete : null,
                ),
                const SizedBox(width: ProfileConstants.mediumSpacing),
                TextButton.icon(
                  icon: const Icon(Icons.clear),
                  label: const Text(ProfileConstants.clearSelectionText),
                  onPressed: onClearSelection,
                ),
                const SizedBox(width: ProfileConstants.mediumSpacing),
                TextButton.icon(
                  icon: const Icon(Icons.close),
                  label: const Text(ProfileConstants.exitSelectionText),
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
