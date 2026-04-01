import 'package:flutter/material.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/shared/services/report_service.dart';
import 'package:vayug/shared/widgets/app_button.dart';
import 'package:vayug/shared/widgets/vayu_snackbar.dart';

class ReportDialogWidget extends StatefulWidget {
  final String targetType;
  final String targetId;

  const ReportDialogWidget({
    super.key,
    required this.targetType,
    required this.targetId,
  });

  @override
  State<ReportDialogWidget> createState() => _ReportDialogWidgetState();
}

class _ReportDialogWidgetState extends State<ReportDialogWidget> {
  final _formKey = GlobalKey<FormState>();
  final _detailsController = TextEditingController();
  final _reportService = ReportService();

  String _selectedReason = 'spam';
  bool _submitting = false;

  final List<String> _reasons = [
    'spam',
    'abusive',
    'nudity',
    'copyright',
    'misinformation',
    'other',
  ];

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);

    final success = await _reportService.submitReport(
      targetType: widget.targetType,
      targetId: widget.targetId,
      reason: _selectedReason,
      details: _detailsController.text.trim().isEmpty
          ? null
          : _detailsController.text.trim(),
    );

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop(true);
      VayuSnackBar.showSuccess(context, 'Report submitted. Thank you.');
    } else {
      VayuSnackBar.showError(context, 'Failed to submit report.');
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
            'What is the issue?',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: isLandscape ? 11.0 : null,
            ),
          ),
          SizedBox(height: isLandscape ? 8 : 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _reasons.map((reason) {
              final isSelected = _selectedReason == reason;
              return ChoiceChip(
                label: Text(
                  reason[0].toUpperCase() + reason.substring(1),
                  style: AppTypography.bodySmall.copyWith(
                    color: isSelected ? Colors.white : AppColors.textSecondary,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) setState(() => _selectedReason = reason);
                },
                selectedColor: AppColors.primary,
                backgroundColor: AppColors.backgroundSecondary,
                checkmarkColor: Colors.white,
                visualDensity: isLandscape ? VisualDensity.compact : null,
                padding: isLandscape ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4) : null,
                labelPadding: isLandscape ? EdgeInsets.zero : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(100),
                  side: BorderSide(
                    color: isSelected ? AppColors.primary : AppColors.borderPrimary,
                    width: 1,
                  ),
                ),
              );
            }).toList(),
          ),
          SizedBox(height: isLandscape ? 12 : 20),
          Text(
            'Actionable details (optional)',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: isLandscape ? 11.0 : null,
            ),
          ),
          SizedBox(height: isLandscape ? 4 : 8),
          TextFormField(
            controller: _detailsController,
            minLines: isLandscape ? 2 : 3,
            maxLines: isLandscape ? 3 : 5,
            style: AppTypography.bodyMedium.copyWith(fontSize: isLandscape ? 12.0 : null),
            decoration: InputDecoration(
              hintText: 'Describe the problem...',
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
          SizedBox(height: isLandscape ? 16 : 24),
          AppButton(
            onPressed: _submitting ? null : _submit,
            label: 'Submit Report',
            variant: AppButtonVariant.primary,
            isLoading: _submitting,
            isFullWidth: true,
          ),
        ],
      ),
    );
  }
}
