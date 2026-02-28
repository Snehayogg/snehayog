import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vayu/shared/widgets/app_button.dart';

class ExternalLinkButton extends StatelessWidget {
  final String url;
  final ThemeData theme;
  const ExternalLinkButton({Key? key, required this.url, required this.theme})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AppButton(
      onPressed: () async {
        final uri = Uri.tryParse(url.trim());
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open link.')),
          );
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
