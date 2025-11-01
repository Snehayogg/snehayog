import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vayu/model/video_model.dart';
import 'package:vayu/services/video_service.dart';

class CustomShareWidget extends StatefulWidget {
  final VideoModel video;

  const CustomShareWidget({
    Key? key,
    required this.video,
  }) : super(key: key);

  @override
  State<CustomShareWidget> createState() => _CustomShareWidgetState();
}

class _CustomShareWidgetState extends State<CustomShareWidget> {
  final List<ShareOption> _shareOptions = [
    ShareOption(
      name: 'WhatsApp',
      icon: '📱',
      color: const Color(0xFF25D366),
      scheme: 'whatsapp://send',
      webUrl: 'https://wa.me/?text=',
      fallbackUrl: 'https://web.whatsapp.com/send?text=',
    ),
    ShareOption(
      name: 'Instagram',
      icon: '📸',
      color: const Color(0xFFE4405F),
      scheme: 'instagram://',
      webUrl: 'https://www.instagram.com/',
      fallbackUrl: 'https://www.instagram.com/',
    ),
    ShareOption(
      name: 'Facebook',
      icon: '👥',
      color: const Color(0xFF1877F2),
      scheme: 'fb://',
      webUrl: 'https://www.facebook.com/sharer/sharer.php?u=',
      fallbackUrl: 'https://www.facebook.com/sharer/sharer.php?u=',
    ),
    ShareOption(
      name: 'Telegram',
      icon: '✈️',
      color: const Color(0xFF0088CC),
      scheme: 'tg://',
      webUrl: 'https://t.me/share/url?url=',
      fallbackUrl: 'https://t.me/share/url?url=',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar with better styling
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // Title with better styling
          const Text(
            'Share Video',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 24),

          // Video preview
          _buildVideoPreview(),
          const SizedBox(height: 24),

          // Share options grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 2.5,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: _shareOptions.length,
            itemBuilder: (context, index) {
              final option = _shareOptions[index];
              return _buildShareOption(option);
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildVideoPreview() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.grey[50]!,
            Colors.grey[100]!,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.grey[200]!,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Thumbnail with play icon
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.grey[300]!,
                  Colors.grey[400]!,
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.play_circle_filled,
              size: 32,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 16),

          // Video info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.video.videoName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Colors.black87,
                    letterSpacing: 0.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.green[500],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'by ${widget.video.uploader.name}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShareOption(ShareOption option) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            // Add haptic feedback
            HapticFeedback.lightImpact();
            _handleShare(option);
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  option.color.withOpacity(0.1),
                  option.color.withOpacity(0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: option.color.withOpacity(0.2),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: option.color.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Text(
                option.name,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: option.color,
                  fontSize: 13, // Reduced size to fit better in container
                  letterSpacing: 0.3,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleShare(ShareOption option) async {
    try {
      final shareText = _generateShareText();
      final webLink = 'https://snehayog.site/video/${widget.video.id}';

      // Close the bottom sheet first
      Navigator.of(context).pop();

      // Show loading indicator
      _showLoadingDialog();

      // Try to share via app scheme first
      bool appLaunched = false;

      if (option.name == 'WhatsApp') {
        appLaunched = await _shareToWhatsApp(shareText, '');
      } else if (option.name == 'Instagram') {
        appLaunched = await _shareToInstagram(shareText, '');
      } else if (option.name == 'Facebook') {
        appLaunched = await _shareToFacebook(shareText, '');
      } else if (option.name == 'Telegram') {
        appLaunched = await _shareToTelegram(shareText, '');
      }

      // Close loading dialog
      Navigator.of(context).pop();

      // If app didn't launch, try web fallback
      if (!appLaunched) {
        await _launchWebFallback(option, shareText, webLink);
      }

      // Update share count on server after successful share
      try {
        await _updateShareCount();
      } catch (e) {
        print('⚠️ CustomShareWidget: Failed to update share count: $e');
        // Don't show error to user as sharing still worked
      }
    } catch (e) {
      // Close loading dialog if it's still open
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      _showErrorDialog('Failed to share: $e');
    }
  }

  /// **UPDATE SHARE COUNT: Call backend to update share count**
  Future<void> _updateShareCount() async {
    try {
      final videoService = VideoService();
      await videoService.incrementShares(widget.video.id);
      print('✅ Share count updated for video: ${widget.video.id}');
    } catch (e) {
      print('❌ Error updating share count: $e');
      // Don't throw error, just log it
    }
  }

  Future<bool> _shareToWhatsApp(String text, String url) async {
    try {
      final encodedText = Uri.encodeComponent(text);
      final whatsappUrl = 'whatsapp://send?text=$encodedText';

      if (await canLaunchUrl(Uri.parse(whatsappUrl))) {
        return await launchUrl(Uri.parse(whatsappUrl));
      }
      return false;
    } catch (e) {
      print('WhatsApp share error: $e');
      return false;
    }
  }

  Future<bool> _shareToInstagram(String text, String url) async {
    try {
      // Instagram doesn't support direct text sharing via URL scheme
      // We'll try to open the app and let user manually share
      if (await canLaunchUrl(Uri.parse('instagram://'))) {
        return await launchUrl(Uri.parse('instagram://'));
      }
      return false;
    } catch (e) {
      print('Instagram share error: $e');
      return false;
    }
  }

  Future<bool> _shareToFacebook(String text, String url) async {
    try {
      // Extract URL from text since it's already included
      final urlMatch = RegExp(r'https://[^\s]+').firstMatch(text);
      final videoUrl = urlMatch?.group(0) ?? 'https://snehayog.site';
      final encodedUrl = Uri.encodeComponent(videoUrl);
      final facebookUrl = 'fb://share?link=$encodedUrl';

      if (await canLaunchUrl(Uri.parse(facebookUrl))) {
        return await launchUrl(Uri.parse(facebookUrl));
      }
      return false;
    } catch (e) {
      print('Facebook share error: $e');
      return false;
    }
  }

  Future<bool> _shareToTelegram(String text, String url) async {
    try {
      final encodedText = Uri.encodeComponent(text);
      final telegramUrl = 'tg://msg?text=$encodedText';

      if (await canLaunchUrl(Uri.parse(telegramUrl))) {
        return await launchUrl(Uri.parse(telegramUrl));
      }
      return false;
    } catch (e) {
      print('Telegram share error: $e');
      return false;
    }
  }

  Future<void> _launchWebFallback(
      ShareOption option, String text, String url) async {
    try {
      String webUrl;
      final encodedText = Uri.encodeComponent(text);

      // Prefer provided url; fall back to first https URL in text, else homepage
      String videoUrl = url.isNotEmpty
          ? url
          : (RegExp(r'https://[^\s]+').firstMatch(text)?.group(0) ??
              'https://snehayog.site');
      final encodedUrl = Uri.encodeComponent(videoUrl);

      if (option.name == 'WhatsApp') {
        webUrl = 'https://web.whatsapp.com/send?text=$encodedText';
      } else if (option.name == 'Instagram') {
        // Instagram web doesn't support direct sharing, open main page
        webUrl = 'https://www.instagram.com/';
      } else if (option.name == 'Facebook') {
        webUrl = 'https://www.facebook.com/sharer/sharer.php?u=$encodedUrl';
      } else if (option.name == 'Telegram') {
        webUrl = 'https://t.me/share/url?url=$encodedUrl&text=$encodedText';
      } else {
        webUrl = videoUrl;
      }

      if (await canLaunchUrl(Uri.parse(webUrl))) {
        await launchUrl(Uri.parse(webUrl),
            mode: LaunchMode.externalApplication);
      } else {
        _showErrorDialog(
            'Cannot open ${option.name}. Please install the app or try again.');
      }
    } catch (e) {
      _showErrorDialog('Failed to open ${option.name}: $e');
    }
  }

  String _generateShareText() {
    final appDeepLink = 'snehayog://video/${widget.video.id}';
    final webLink = 'https://snehayog.site/video/${widget.video.id}';
    return 'Upload your videos on Vayu and start earning from day one! 💰\n'
        'No 1000 subs or long watch hours\n\n'
        '🎯 Example video: ${widget.video.videoName} ⬇️\n'
        'Open in app: $appDeepLink\n'
        'Web: $webLink\n\n'
        'Only First 1000 early creators — grab 80% ad revenue';
  }

  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Opening...'),
          ],
        ),
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class ShareOption {
  final String name;
  final String icon;
  final Color color;
  final String scheme;
  final String webUrl;
  final String fallbackUrl;

  ShareOption({
    required this.name,
    required this.icon,
    required this.color,
    required this.scheme,
    required this.webUrl,
    required this.fallbackUrl,
  });
}
