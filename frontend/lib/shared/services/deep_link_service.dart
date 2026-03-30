import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayu/shared/utils/app_logger.dart';

class DeepLinkService {
  static final DeepLinkService _instance = DeepLinkService._internal();
  factory DeepLinkService() => _instance;
  DeepLinkService._internal();

  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  void initialize() {
    _appLinks = AppLinks();
    _checkInitialLink();
    _listenToLinks();
  }

  Future<void> _checkInitialLink() async {
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleUri(initialUri);
      }
    } catch (e) {
      AppLogger.log('❌ DeepLinkService: Error getting initial link: $e');
    }
  }

  void _listenToLinks() {
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleUri(uri);
    }, onError: (err) {
      AppLogger.log('❌ DeepLinkService: Stream error: $err');
    });
  }

  void _handleUri(Uri uri) {
    AppLogger.log('🔗 DeepLinkService: Handling URI: $uri');
    
    // **FIX: Ignore legal links to prevent circular interception when launching externally**
    final path = uri.path.toLowerCase();
    if (path.contains('/privacy.html') || 
        path.contains('/terms.html') || 
        path.contains('/refund.html') || 
        path.contains('/contact.html') || 
        path.contains('/about.html')) {
      AppLogger.log('🔗 DeepLinkService: Ignoring legal link (should open in browser)');
      return;
    }

    // Check for social success (vayu://auth/social-success?platform=youtube)
    if (uri.path.contains('social-success')) {
      final platform = uri.queryParameters['platform'];
      AppLogger.log('🔗 DeepLinkService: Social connection success for $platform');
      // No immediate action needed as user is likely in browser, 
      // but we logged it for tracking.
      return;
    }

    // Check for referral code (?ref=CODE)
    if (uri.queryParameters.containsKey('ref') || uri.path.contains('ref=')) {
      String? refCode = uri.queryParameters['ref'];
      
      // Fallback for weird URL formats
      if (refCode == null || refCode.isEmpty) {
        final pathStr = uri.path;
        if (pathStr.contains('ref=')) {
          final parts = pathStr.split('ref=');
          if (parts.length > 1) {
            final afterRef = parts.last;
            final subParts = afterRef.split('&');
            if (subParts.isNotEmpty) {
              refCode = subParts.first;
            }
          }
        }
      }

      if (refCode != null && refCode.isNotEmpty) {
        _saveReferralCode(refCode);
      }
    }
  }

  Future<void> _saveReferralCode(String code) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Only save if not already signed in (don't overwrite or track for existing users here)
      // Actually, saved referral code is tracked during sign-up in AuthService.
      await prefs.setString('pending_referral_code', code);
      AppLogger.log('🎁 DeepLinkService: Saved referral code: $code');
    } catch (e) {
      AppLogger.log('❌ DeepLinkService: Error saving referral code: $e');
    }
  }

  void dispose() {
    _linkSubscription?.cancel();
  }
}
