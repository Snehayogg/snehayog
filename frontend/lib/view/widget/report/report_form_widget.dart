import 'package:flutter/material.dart';
import 'package:snehayog/model/report_model.dart';
import 'package:snehayog/services/report_service.dart';

class ReportFormWidget extends StatefulWidget {
  final String? reportedUserId;
  final String? reportedUserName;
  final String? reportedVideoId;
  final String? reportedVideoTitle;
  final String? reportedCommentId;
  final String? reportedCommentContent;
  final VoidCallback? onSuccess;

  const ReportFormWidget({
    super.key,
    this.reportedUserId,
    this.reportedUserName,
    this.reportedVideoId,
    this.reportedVideoTitle,
    this.reportedCommentId,
    this.reportedCommentContent,
    this.onSuccess,
  });

  @override
  State<ReportFormWidget> createState() => _ReportFormWidgetState();
}

class _ReportFormWidgetState extends State<ReportFormWidget> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _reportService = ReportService();

  String _selectedType = 'other';
  final List<Evidence> _evidence = [];

  bool _isSubmitting = false;

  final List<Map<String, String>> _reportTypes = [
    {'value': 'spam', 'label': 'Spam'},
    {'value': 'harassment', 'label': 'Harassment'},
    {'value': 'hate_speech', 'label': 'Hate Speech'},
    {'value': 'inappropriate_content', 'label': 'Inappropriate Content'},
    {'value': 'violence', 'label': 'Violence'},
    {'value': 'nudity', 'label': 'Nudity'},
    {'value': 'copyright_violation', 'label': 'Copyright Violation'},
    {'value': 'fake_account', 'label': 'Fake Account'},
    {'value': 'scam', 'label': 'Scam'},
    {'value': 'underage_user', 'label': 'Underage User'},
    {'value': 'other', 'label': 'Other'},
  ];

  @override
  void dispose() {
    _reasonController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report Content'),
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
              // Reported content info
              _buildReportedContentCard(),

              const SizedBox(height: 16),

              // Report type selection
              _buildSectionTitle('Report Type'),
              _buildTypeSelector(),

              const SizedBox(height: 16),

              // Reason field
              _buildSectionTitle('Reason'),
              TextFormField(
                controller: _reasonController,
                decoration: const InputDecoration(
                  hintText: 'Brief reason for reporting',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a reason';
                  }
                  if (value.trim().length < 5) {
                    return 'Reason must be at least 5 characters';
                  }
                  return null;
                },
                maxLength: 500,
              ),

              const SizedBox(height: 16),

              // Description field
              _buildSectionTitle('Description'),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  hintText:
                      'Please provide detailed information about the issue',
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
                maxLines: 4,
                maxLength: 1000,
              ),

              const SizedBox(height: 16),

              // Evidence section
              _buildSectionTitle('Evidence (Optional)'),
              _buildEvidenceSection(),

              const SizedBox(height: 32),

              // Submit button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitReport,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
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
                      : const Text('Submit Report'),
                ),
              ),

              const SizedBox(height: 16),

              // Important note
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_amber_outlined,
                            color: Colors.orange[700], size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Important Information',
                          style: TextStyle(
                            color: Colors.orange[800],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• False reports may result in action against your account\n'
                      '• Reports are reviewed by our moderation team\n'
                      '• You will be notified of the outcome via email',
                      style: TextStyle(
                        color: Colors.orange[700],
                        fontSize: 12,
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

  Widget _buildReportedContentCard() {
    String contentTitle = '';
    IconData contentIcon = Icons.report;

    if (widget.reportedVideoTitle != null) {
      contentTitle = 'Video: ${widget.reportedVideoTitle}';
      contentIcon = Icons.video_library;
    } else if (widget.reportedUserName != null) {
      contentTitle = 'User: ${widget.reportedUserName}';
      contentIcon = Icons.person;
    } else if (widget.reportedCommentContent != null) {
      contentTitle =
          'Comment: ${widget.reportedCommentContent!.substring(0, 50)}...';
      contentIcon = Icons.comment;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Row(
        children: [
          Icon(contentIcon, color: Colors.red[600], size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Reporting: $contentTitle',
              style: TextStyle(
                color: Colors.red[800],
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
          items: _reportTypes.map((type) {
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

  Widget _buildEvidenceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Add screenshots or other evidence to support your report',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),

        // Add evidence button
        OutlinedButton.icon(
          onPressed: _addEvidence,
          icon: const Icon(Icons.add_photo_alternate),
          label: const Text('Add Evidence'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).primaryColor,
          ),
        ),

        const SizedBox(height: 8),

        // Evidence list
        if (_evidence.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...(_evidence.asMap().entries.map((entry) {
            final index = entry.key;
            final evidence = entry.value;
            return Card(
              child: ListTile(
                leading: const Icon(Icons.attachment),
                title: Text(evidence.description ?? 'Evidence ${index + 1}'),
                subtitle: Text(evidence.url),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () {
                    setState(() {
                      _evidence.removeAt(index);
                    });
                  },
                ),
              ),
            );
          })),
        ],
      ],
    );
  }

  void _addEvidence() {
    showDialog(
      context: context,
      builder: (context) => _EvidenceDialog(
        onAdd: (evidence) {
          setState(() {
            _evidence.add(evidence);
          });
        },
      ),
    );
  }

  Future<void> _submitReport() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final request = ReportCreationRequest(
        type: _selectedType,
        reason: _reasonController.text.trim(),
        description: _descriptionController.text.trim(),
        reportedUserId: widget.reportedUserId,
        reportedVideoId: widget.reportedVideoId,
        reportedCommentId: widget.reportedCommentId,
        evidence: _evidence,
      );

      await _reportService.createReport(request);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report submitted successfully!'),
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
            content: Text('Failed to submit report: ${e.toString()}'),
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
}

class _EvidenceDialog extends StatefulWidget {
  final Function(Evidence) onAdd;

  const _EvidenceDialog({required this.onAdd});

  @override
  State<_EvidenceDialog> createState() => _EvidenceDialogState();
}

class _EvidenceDialogState extends State<_EvidenceDialog> {
  final _urlController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Evidence'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'URL or File Path',
              border: OutlineInputBorder(),
              hintText: 'Enter URL or file path',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _descriptionController,
            decoration: const InputDecoration(
              labelText: 'Description (Optional)',
              border: OutlineInputBorder(),
              hintText: 'Brief description of evidence',
            ),
            maxLines: 2,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_urlController.text.trim().isNotEmpty) {
              final evidence = Evidence(
                url: _urlController.text.trim(),
                description: _descriptionController.text.trim().isEmpty
                    ? null
                    : _descriptionController.text.trim(),
              );
              widget.onAdd(evidence);
              Navigator.of(context).pop();
            }
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
