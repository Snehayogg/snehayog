import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vayug/shared/widgets/app_button.dart';
import 'package:vayug/shared/utils/url_utils.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/shared/widgets/vayu_snackbar.dart';

class ExternalLinkButton extends StatelessWidget {
  final String url;
  final ThemeData theme;
  const ExternalLinkButton({Key? key, required this.url, required this.theme})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AppButton(
      onPressed: () async {
        final enrichedUrl = UrlUtils.enrichUrl(
          url.trim(),
          source: 'vayug',
          medium: 'visit_now',
        );
        
        AppLogger.log('🔗 ExternalLinkButton: Attempting to launch: $enrichedUrl');
        
        try {
          final uri = Uri.tryParse(enrichedUrl);
          if (uri != null && await canLaunchUrl(uri)) {
            final success = await launchUrl(uri, mode: LaunchMode.externalApplication);
            if (!success) {
              AppLogger.log('❌ ExternalLinkButton: launchUrl returned false for $enrichedUrl');
              if (context.mounted) {
                VayuSnackBar.showError(context, 'Could not open link in browser.');
              }
            }
          } else {
            AppLogger.log('⚠️ ExternalLinkButton: canLaunchUrl returned false or uri is null for $enrichedUrl');
            if (context.mounted) {
              VayuSnackBar.showError(context, 'Invalid link or no browser found.');
            }
          }
        } catch (e) {
          AppLogger.log('❌ ExternalLinkButton: Exception while launching link: $e');
          if (context.mounted) {
            VayuSnackBar.showError(context, 'An error occurred while opening the link.');
          }
        }
      },
      label: 'Visit Now',
      icon: const Icon(Icons.open_in_new, color: Colors.white, size: 20),
      variant: AppButtonVariant.primary,
      size: AppButtonSize.medium,
      isFullWidth: true,
    );
  }
}
