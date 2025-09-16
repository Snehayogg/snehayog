import 'package:flutter/material.dart';

/// **AdDetailsFormWidget - Handles ad title, description, and link input**
class AdDetailsFormWidget extends StatelessWidget {
  final TextEditingController titleController;
  final TextEditingController descriptionController;
  final TextEditingController linkController;
  final Function() onClearErrors;

  const AdDetailsFormWidget({
    Key? key,
    required this.titleController,
    required this.descriptionController,
    required this.linkController,
    required this.onClearErrors,
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
              decoration: const InputDecoration(
                labelText: 'Ad Title *',
                hintText: 'Enter a compelling title for your ad',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => onClearErrors(),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter an ad title';
                }
                if (value.trim().length < 5) {
                  return 'Title must be at least 5 characters';
                }
                if (value.trim().length > 100) {
                  return 'Title must be less than 100 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description *',
                hintText: 'Describe your ad content and call to action',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              onChanged: (_) => onClearErrors(),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a description';
                }
                if (value.trim().length < 10) {
                  return 'Description must be at least 10 characters';
                }
                if (value.trim().length > 500) {
                  return 'Description must be less than 500 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: linkController,
              decoration: const InputDecoration(
                labelText: 'Landing Page URL (Optional)',
                hintText: 'https://your-website.com',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
                helperText:
                    'Enter your website URL where users will land after clicking the ad',
              ),
              keyboardType: TextInputType.url,
              onChanged: (_) => onClearErrors(),
              validator: (value) {
                if (value != null && value.trim().isNotEmpty) {
                  if (!value.trim().startsWith('http://') &&
                      !value.trim().startsWith('https://')) {
                    return 'Please enter a valid URL starting with http:// or https://';
                  }
                  try {
                    Uri.parse(value.trim());
                  } catch (e) {
                    return 'Please enter a valid URL';
                  }
                }
                return null;
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
