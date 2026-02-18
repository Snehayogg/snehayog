import 'package:flutter/material.dart';
import 'package:vayu/shared/services/http_client_service.dart';
import 'dart:convert';
import 'package:vayu/shared/config/app_config.dart';
import 'package:vayu/features/auth/data/services/authservices.dart';
import 'package:url_launcher/url_launcher.dart';

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

  final Map<int, Map<String, dynamic>> _ratingData = {
    1: {'emoji': '😢', 'text': 'Oh no!', 'color': Colors.red},
    2: {'emoji': '😞', 'text': 'Oh no!', 'color': Colors.orange},
    3: {'emoji': '😐', 'text': 'We can do better', 'color': Colors.amber},
    4: {'emoji': '🙂', 'text': 'Good!', 'color': Colors.lightGreen},
    5: {'emoji': '🤩', 'text': 'Awesome!', 'color': Colors.green},
  };

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _launchPlayStore() async {
    const packageName = "com.snehayog.app";
    final url = Uri.parse("market://details?id=$packageName");
    final webUrl = Uri.parse(
        "https://play.google.com/store/apps/details?id=$packageName");

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      } else {
        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      }
    }
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a star rating')),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);

    try {
      // Get user data for feedback submission
      final authService = AuthService();
      final userData = await authService.getUserData();

      // Submit feedback to backend
      final response = await httpClientService.post(
        Uri.parse('${NetworkHelper.apiBaseUrl}/feedback/submit'),
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

        // Handle high ratings (4 or 5 stars)
        if (_rating >= 4) {
          Navigator.of(context).pop(); // Close dialog first

          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Awesome!'),
              content: const Text(
                  'Since you liked the app, would you mind giving us a 5-star rating on the Google Play Store? It really helps us grow!'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Maybe Later'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _launchPlayStore();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Rate Now'),
                ),
              ],
            ),
          );
        } else {
          Navigator.of(context).pop(true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Thanks for your feedback! We will use it to improve our app.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('Failed to submit feedback');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error submitting feedback: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final int ratingInt = _rating.toInt();
    final currentData = _ratingData[ratingInt];

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: const EdgeInsets.all(24),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return ScaleTransition(scale: animation, child: child);
                },
                child: currentData != null
                    ? Column(
                        key: ValueKey<int>(ratingInt),
                        children: [
                          Text(
                            currentData['emoji'],
                            style: const TextStyle(fontSize: 64),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            currentData['text'],
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      )
                    : const Column(
                        key: ValueKey<String>('default'),
                        children: [
                          // Placeholder to keep spacing before rating
                          SizedBox(height: 80), 
                        ],
                      ),
              ),
              const SizedBox(height: 8),
              if (_rating == 0)
                const Text(
                  'How would you rate your experience?',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              if (_rating == 0) const SizedBox(height: 16),
              if (_rating != 0) 
                 const Text(
                  'Please leave us some feedback.',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
               const SizedBox(height: 24),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  final filled = index < _rating.round();
                  return IconButton(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      filled ? Icons.star : Icons.star_border,
                      color: filled ? Colors.amber : Colors.grey,
                      size: 40,
                    ),
                    onPressed: () => setState(() => _rating = index + 1.0),
                  );
                }),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _messageController,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Share your thoughts (optional)',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 24),
               SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          'RATE',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                ),
              ),
               const SizedBox(height: 8),
               TextButton(
                  onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                  child: const Text('Maybe Later', style: TextStyle(color: Colors.grey)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
