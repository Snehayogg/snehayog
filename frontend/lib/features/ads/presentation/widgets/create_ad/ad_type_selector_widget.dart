import 'package:flutter/material.dart';
import 'package:vayu/shared/theme/app_theme.dart';

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
              style: AppTheme.headlineSmall.copyWith(
                fontWeight: FontWeight.bold,
                color: AppTheme.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _getAdTypeDescription(selectedAdType),
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.05),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 16, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _getAdTypeInfo(selectedAdType),
                      style: TextStyle(
                        color: AppTheme.primary,
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
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onShowBenefits,
                icon: const Icon(Icons.info_outline, size: 20),
                label: const Text(
                  'Why Advertise on Vayug?',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary.withOpacity(0.12),
                  foregroundColor: AppTheme.white,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: AppTheme.primary.withOpacity(0.3), width: 1),
                  ),
                ),
              ),
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
