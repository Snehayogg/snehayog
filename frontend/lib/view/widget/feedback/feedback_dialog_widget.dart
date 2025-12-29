import 'package:flutter/material.dart';
import 'package:vayu/core/services/http_client_service.dart';
import 'dart:convert';
import 'package:vayu/config/app_config.dart';
import 'package:vayu/services/authservices.dart';

class FeedbackDialogWidget extends StatefulWidget {
  const FeedbackDialogWidget({super.key});

  @override
  State<FeedbackDialogWidget> createState() => _FeedbackDialogWidgetState();
}

class _FeedbackDialogWidgetState extends State<FeedbackDialogWidget> {
  final _formKey = GlobalKey<FormState>();
  double _rating = 0;
  final TextEditingController _messageController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);

    try {
      // Get user data for feedback submission
      final authService = AuthService();
      final userData = await authService.getUserData();

      // Submit feedback to backend
      final response = await httpClientService.post(
        Uri.parse('${AppConfig.baseUrl}/api/feedback/submit'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'rating': _rating.toInt(),
          'comments': _messageController.text.trim(),
          'userEmail': userData?['email'] ?? 'anonymous@user.com',
          'userId': userData?['googleId'] ?? userData?['id'] ?? 'anonymous',
        }),
      );

      if (response.statusCode == 201) {
        if (!mounted) return;
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Thanks for your feedback!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw Exception('Failed to submit feedback');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error submitting feedback: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Feedback'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: List.generate(5, (index) {
                final filled = index < _rating.round();
                return IconButton(
                  icon: Icon(
                    filled ? Icons.star : Icons.star_border,
                    color: Colors.amber,
                  ),
                  onPressed: () => setState(() => _rating = index + 1.0),
                );
              }),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _messageController,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Share your thoughts (optional)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Submit'),
        )
      ],
    );
  }
}
