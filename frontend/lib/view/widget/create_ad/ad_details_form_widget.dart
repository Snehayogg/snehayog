import 'package:flutter/material.dart';

/// **AdDetailsFormWidget - Handles ad title, description, and link input**
/// For banner ads, only shows link field (title/description not needed)
class AdDetailsFormWidget extends StatelessWidget {
  final TextEditingController titleController;
  final TextEditingController descriptionController;
  final TextEditingController linkController;
  final Function() onClearErrors;
  final Function(String)? onFieldChanged;
  final String adType; // To determine which fields to show

  // **NEW: Validation states**
  final bool? isTitleValid;
  final bool? isDescriptionValid;
  final bool? isLinkValid;
  final String? titleError;
  final String? descriptionError;
  final String? linkError;

  const AdDetailsFormWidget({
    Key? key,
    required this.titleController,
    required this.descriptionController,
    required this.linkController,
    required this.onClearErrors,
    required this.adType,
    this.onFieldChanged,
    // **NEW: Optional validation parameters**
    this.isTitleValid,
    this.isDescriptionValid,
    this.isLinkValid,
    this.titleError,
    this.descriptionError,
    this.linkError,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isBanner = adType == 'banner';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Only show title for non-banner ads
        if (!isBanner) ...[
          TextFormField(
            controller: titleController,
            decoration: InputDecoration(
              labelText: 'Ad Title *',
              hintText: 'Enter a compelling title for your ad',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: (isTitleValid == false) ? Colors.red : Colors.grey,
                  width: (isTitleValid == false) ? 2.0 : 1.0,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: (isTitleValid == false) ? Colors.red : Colors.grey,
                  width: (isTitleValid == false) ? 2.0 : 1.0,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: (isTitleValid == false) ? Colors.red : Colors.blue,
                  width: (isTitleValid == false) ? 2.0 : 2.0,
                ),
              ),
              errorText: (isTitleValid == false) ? titleError : null,
              errorStyle: const TextStyle(color: Colors.red, fontSize: 12),
            ),
            onChanged: (_) {
              onClearErrors();
              onFieldChanged?.call('title');
            },
          ),
          const SizedBox(height: 16),
        ],

        // Only show description for non-banner ads
        if (!isBanner) ...[
          TextFormField(
            controller: descriptionController,
            decoration: InputDecoration(
              labelText: 'Description *',
              hintText: 'Describe your ad content and call to action',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color:
                      (isDescriptionValid == false) ? Colors.red : Colors.grey,
                  width: (isDescriptionValid == false) ? 2.0 : 1.0,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color:
                      (isDescriptionValid == false) ? Colors.red : Colors.grey,
                  width: (isDescriptionValid == false) ? 2.0 : 1.0,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color:
                      (isDescriptionValid == false) ? Colors.red : Colors.blue,
                  width: (isDescriptionValid == false) ? 2.0 : 2.0,
                ),
              ),
              errorText:
                  (isDescriptionValid == false) ? descriptionError : null,
              errorStyle: const TextStyle(color: Colors.red, fontSize: 12),
            ),
            maxLines: 3,
            onChanged: (_) {
              onClearErrors();
              onFieldChanged?.call('description');
            },
          ),
          const SizedBox(height: 16),
        ],

        // Link field - always visible for all ad types
        TextFormField(
          controller: linkController,
          decoration: InputDecoration(
            labelText: isBanner ? 'Destination URL *' : 'Landing Page URL *',
            hintText: 'https://your-website.com',
            prefixIcon: const Icon(Icons.link),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: (isLinkValid == false) ? Colors.red : Colors.grey,
                width: (isLinkValid == false) ? 2.0 : 1.0,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: (isLinkValid == false) ? Colors.red : Colors.grey,
                width: (isLinkValid == false) ? 2.0 : 1.0,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: (isLinkValid == false) ? Colors.red : Colors.blue,
                width: (isLinkValid == false) ? 2.0 : 2.0,
              ),
            ),
            helperText: isBanner
                ? 'Where users will go when they click the banner'
                : 'Enter your website URL where users will land after clicking the ad',
            errorText: (isLinkValid == false) ? linkError : null,
            errorStyle: const TextStyle(color: Colors.red, fontSize: 12),
          ),
          keyboardType: TextInputType.url,
          onChanged: (_) {
            onClearErrors();
            onFieldChanged?.call('link');
          },
        ),
      ],
    );
  }
}
