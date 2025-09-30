import 'package:flutter/material.dart';

/// **AdDetailsFormWidget - Handles ad title, description, and link input**
class AdDetailsFormWidget extends StatelessWidget {
  final TextEditingController titleController;
  final TextEditingController descriptionController;
  final TextEditingController linkController;
  final Function() onClearErrors;
  final Function(String)? onFieldChanged;

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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ad Details',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: titleController,
              decoration: InputDecoration(
                labelText: 'Ad Title *',
                hintText: 'Enter a compelling title for your ad',
                border: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: (isTitleValid == false) ? Colors.red : Colors.grey,
                    width: (isTitleValid == false) ? 2.0 : 1.0,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: (isTitleValid == false) ? Colors.red : Colors.grey,
                    width: (isTitleValid == false) ? 2.0 : 1.0,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
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
            TextFormField(
              controller: descriptionController,
              decoration: InputDecoration(
                labelText: 'Description *',
                hintText: 'Describe your ad content and call to action',
                border: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: (isDescriptionValid == false)
                        ? Colors.red
                        : Colors.grey,
                    width: (isDescriptionValid == false) ? 2.0 : 1.0,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: (isDescriptionValid == false)
                        ? Colors.red
                        : Colors.grey,
                    width: (isDescriptionValid == false) ? 2.0 : 1.0,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: (isDescriptionValid == false)
                        ? Colors.red
                        : Colors.blue,
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
            TextFormField(
              controller: linkController,
              decoration: InputDecoration(
                labelText: 'Landing Page URL *',
                hintText: 'https://your-website.com',
                border: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: (isLinkValid == false) ? Colors.red : Colors.grey,
                    width: (isLinkValid == false) ? 2.0 : 1.0,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: (isLinkValid == false) ? Colors.red : Colors.grey,
                    width: (isLinkValid == false) ? 2.0 : 1.0,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: (isLinkValid == false) ? Colors.red : Colors.blue,
                    width: (isLinkValid == false) ? 2.0 : 2.0,
                  ),
                ),
                prefixIcon: const Icon(Icons.link),
                helperText:
                    'Enter your website URL where users will land after clicking the ad',
                errorText: (isLinkValid == false) ? linkError : null,
                errorStyle: const TextStyle(color: Colors.red, fontSize: 12),
              ),
              keyboardType: TextInputType.url,
              onChanged: (_) {
                onClearErrors();
                onFieldChanged?.call('link');
              },
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 16, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '💡 This field is for your website URL where users will go after clicking your ad. Leave empty if you don\'t have a website.',
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
