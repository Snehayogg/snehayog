import 'package:flutter/material.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/shared/services/feedback_service.dart';
import 'package:vayug/shared/widgets/app_button.dart';
import 'package:vayug/shared/widgets/vayu_snackbar.dart';

class VayuSuggestionDialog extends StatefulWidget {
  final String videoId;

  const VayuSuggestionDialog({
    super.key,
    required this.videoId,
  });

  @override
  State<VayuSuggestionDialog> createState() => _VayuSuggestionDialogState();
}

class _VayuSuggestionDialogState extends State<VayuSuggestionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _suggestionController = TextEditingController();
  final _feedbackService = FeedbackService();
  bool _submitting = false;

  @override
  void dispose() {
    _suggestionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final suggestionText = _suggestionController.text.trim();
    if (suggestionText.isEmpty) {
      VayuSnackBar.showError(context, 'Please enter your suggestion');
      return;
    }

    setState(() => _submitting = true);

    final success = await _feedbackService.submitFeedback(
      rating: 5, // Default rating for suggestions
      comments: 'Video ID: ${widget.videoId}\nSuggestion: $suggestionText',
      type: 'suggestion',
    );

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop(true);
      VayuSnackBar.showSuccess(context, 'Suggestion shared. Thank you!');
    } else {
      VayuSnackBar.showError(context, 'Failed to share suggestion.');
    }

    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Share your suggestion',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: isLandscape ? 11.0 : null,
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _suggestionController,
            minLines: isLandscape ? 2 : 3,
            maxLines: isLandscape ? 5 : 8,
            style: AppTypography.bodyMedium.copyWith(fontSize: isLandscape ? 12.0 : null),
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'What can we improve or add to this video?',
              hintStyle: AppTypography.bodyMedium.copyWith(
                color: AppColors.textTertiary,
                fontSize: isLandscape ? 12.0 : null,
              ),
              filled: true,
              fillColor: AppColors.backgroundSecondary,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: EdgeInsets.all(isLandscape ? 12 : 16),
            ),
          ),
          const SizedBox(height: 24),
          AppButton(
            onPressed: _submitting ? null : _submit,
            label: 'Share Suggestion',
            variant: AppButtonVariant.primary,
            isLoading: _submitting,
            isFullWidth: true,
          ),
        ],
      ),
    );
  }
}
