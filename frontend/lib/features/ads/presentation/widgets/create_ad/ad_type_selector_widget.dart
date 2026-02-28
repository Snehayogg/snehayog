import 'package:flutter/material.dart';
import 'package:vayu/core/design/theme.dart';
import 'package:vayu/core/design/colors.dart';
import 'package:vayu/core/design/typography.dart';
import 'package:vayu/core/design/elevation.dart';
import 'package:vayu/shared/widgets/app_button.dart';

/// **AdTypeSelectorWidget - Handles ad type selection**
class AdTypeSelectorWidget extends StatelessWidget {
  final String selectedAdType;
  final Function(String) onAdTypeChanged;
  final Function() onShowBenefits;

  const AdTypeSelectorWidget({
    Key? key,
    required this.selectedAdType,
    required this.onAdTypeChanged,
    required this.onShowBenefits,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final List<String> adTypes = ['banner', 'carousel'];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ad Type',
              style: AppTypography.headlineSmall.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _getAdTypeDescription(selectedAdType),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.05),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.primary.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _getAdTypeInfo(selectedAdType),
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedAdType,
              decoration: const InputDecoration(
                labelText: 'Select Ad Type',
                border: OutlineInputBorder(),
              ),
              items: adTypes.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(type.toUpperCase()),
                );
              }).toList(),
              onChanged: (value) => onAdTypeChanged(value!),
            ),
            const SizedBox(height: 16),
            // Benefits Button
            AppButton(
                onPressed: onShowBenefits,
                icon: const Icon(Icons.info_outline, size: 20),
                label: 'Why Advertise on Vayug?',
                variant: AppButtonVariant.outline,
                isFullWidth: true,
                size: AppButtonSize.medium,
            ),
          ],
        ),
      ),
    );
  }

  String _getAdTypeDescription(String adType) {
    switch (adType) {
      case 'banner':
        return 'Banner ads are static image advertisements displayed at the top or sides of content';
      case 'carousel':
        return 'Carousel ads support up to 3 images and 1 video in a swipeable format. You can add multiple media items to create an engaging slideshow.';
      default:
        return '';
    }
  }

  String _getAdTypeInfo(String adType) {
    switch (adType) {
      case 'banner':
        return 'CPM: ₹10 per 1000 impressions (lower cost for static ads)';
      case 'carousel':
        return 'CPM: ₹30 per 1000 impressions (higher engagement for interactive ads)';
      default:
        return '';
    }
  }
}
