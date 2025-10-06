import 'package:flutter/material.dart';
import 'package:snehayog/model/feedback_model.dart';
import 'package:snehayog/services/feedback_service.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

class FeedbackFormWidget extends StatefulWidget {
  final String? relatedVideoId;
  final String? relatedVideoTitle;
  final String? relatedUserId;
  final String? relatedUserName;
  final VoidCallback? onSuccess;

  const FeedbackFormWidget({
    super.key,
    this.relatedVideoId,
    this.relatedVideoTitle,
    this.relatedUserId,
    this.relatedUserName,
    this.onSuccess,
  });

  @override
  State<FeedbackFormWidget> createState() => _FeedbackFormWidgetState();
}

class _FeedbackFormWidgetState extends State<FeedbackFormWidget> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _feedbackService = FeedbackService();

  String _selectedType = 'general_feedback';
  String _selectedCategory = 'other';
  int _selectedRating = 5;
  final List<String> _selectedTags = [];

  bool _isSubmitting = false;

  final List<Map<String, String>> _feedbackTypes = [
    {'value': 'general_feedback', 'label': 'General Feedback'},
    {'value': 'bug_report', 'label': 'Bug Report'},
    {'value': 'feature_request', 'label': 'Feature Request'},
    {'value': 'user_experience', 'label': 'User Experience'},
    {'value': 'content_issue', 'label': 'Content Issue'},
  ];

  final List<Map<String, String>> _feedbackCategories = [
    {'value': 'other', 'label': 'Other'},
    {'value': 'video_playback', 'label': 'Video Playback'},
    {'value': 'upload_issues', 'label': 'Upload Issues'},
    {'value': 'ui_ux', 'label': 'UI/UX'},
    {'value': 'performance', 'label': 'Performance'},
    {'value': 'monetization', 'label': 'Monetization'},
    {'value': 'social_features', 'label': 'Social Features'},
  ];

  final List<String> _commonTags = [
    'crash',
    'slow',
    'freeze',
    'audio',
    'video',
    'upload',
    'download',
    'navigation',
    'search',
    'profile',
    'comments',
    'sharing',
    'ads'
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Submit Feedback'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Related content info
              if (widget.relatedVideoTitle != null ||
                  widget.relatedUserName != null)
                _buildRelatedContentCard(),

              const SizedBox(height: 16),

              // Feedback type selection
              _buildSectionTitle('Feedback Type'),
              _buildTypeSelector(),

              const SizedBox(height: 16),

              // Category selection
              _buildSectionTitle('Category'),
              _buildCategorySelector(),

              const SizedBox(height: 16),

              // Rating
              _buildSectionTitle('Rating ($_selectedRating/5)'),
              _buildRatingSelector(),

              const SizedBox(height: 16),

              // Title field
              _buildSectionTitle('Title'),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  hintText: 'Brief description of your feedback',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a title';
                  }
                  if (value.trim().length < 5) {
                    return 'Title must be at least 5 characters';
                  }
                  return null;
                },
                maxLength: 200,
              ),

              const SizedBox(height: 16),

              // Description field
              _buildSectionTitle('Description'),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  hintText:
                      'Please provide detailed information about your feedback',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a description';
                  }
                  if (value.trim().length < 10) {
                    return 'Description must be at least 10 characters';
                  }
                  return null;
                },
                maxLines: 5,
                maxLength: 2000,
              ),

              const SizedBox(height: 16),

              // Tags
              _buildSectionTitle('Tags (Optional)'),
              _buildTagsSelector(),

              const SizedBox(height: 32),

              // Submit button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitFeedback,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isSubmitting
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                            SizedBox(width: 12),
                            Text('Submitting...'),
                          ],
                        )
                      : const Text('Submit Feedback'),
                ),
              ),

              const SizedBox(height: 16),

              // Privacy note
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.grey[600], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your feedback is anonymous and helps us improve the app.',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRelatedContentCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.link, color: Colors.blue[600], size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.relatedVideoTitle != null
                  ? 'Feedback for video: ${widget.relatedVideoTitle}'
                  : 'Feedback for user: ${widget.relatedUserName}',
              style: TextStyle(
                color: Colors.blue[800],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildTypeSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedType,
          isExpanded: true,
          items: _feedbackTypes.map((type) {
            return DropdownMenuItem<String>(
              value: type['value'],
              child: Text(type['label']!),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              _selectedType = value!;
            });
          },
        ),
      ),
    );
  }

  Widget _buildCategorySelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedCategory,
          isExpanded: true,
          items: _feedbackCategories.map((category) {
            return DropdownMenuItem<String>(
              value: category['value'],
              child: Text(category['label']!),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              _selectedCategory = value!;
            });
          },
        ),
      ),
    );
  }

  Widget _buildRatingSelector() {
    return Row(
      children: List.generate(5, (index) {
        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedRating = index + 1;
            });
          },
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(
              index < _selectedRating ? Icons.star : Icons.star_border,
              color: Colors.amber,
              size: 32,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildTagsSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _commonTags.map((tag) {
        final isSelected = _selectedTags.contains(tag);
        return FilterChip(
          label: Text(tag),
          selected: isSelected,
          onSelected: (selected) {
            setState(() {
              if (selected) {
                _selectedTags.add(tag);
              } else {
                _selectedTags.remove(tag);
              }
            });
          },
          selectedColor: Theme.of(context).primaryColor.withOpacity(0.2),
          checkmarkColor: Theme.of(context).primaryColor,
        );
      }).toList(),
    );
  }

  Future<void> _submitFeedback() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      // Get device info
      final deviceInfo = await _getDeviceInfo();

      final request = FeedbackCreationRequest(
        type: _selectedType,
        category: _selectedCategory,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        rating: _selectedRating,
        relatedVideoId: widget.relatedVideoId,
        relatedUserId: widget.relatedUserId,
        deviceInfo: deviceInfo,
        tags: _selectedTags,
      );

      await _feedbackService.createFeedback(request);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Feedback submitted successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        if (widget.onSuccess != null) {
          widget.onSuccess!();
        } else {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit feedback: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<DeviceInfo?> _getDeviceInfo() async {
    try {
      final deviceInfoPlugin = DeviceInfoPlugin();
      final packageInfo = await PackageInfo.fromPlatform();

      if (Theme.of(context).platform == TargetPlatform.android) {
        final androidInfo = await deviceInfoPlugin.androidInfo;
        return DeviceInfo(
          platform: 'Android',
          version: androidInfo.version.release,
          model: androidInfo.model,
          appVersion: packageInfo.version,
        );
      } else if (Theme.of(context).platform == TargetPlatform.iOS) {
        final iosInfo = await deviceInfoPlugin.iosInfo;
        return DeviceInfo(
          platform: 'iOS',
          version: iosInfo.systemVersion,
          model: iosInfo.model,
          appVersion: packageInfo.version,
        );
      }
    } catch (e) {
      print('Error getting device info: $e');
    }
    return null;
  }
}
