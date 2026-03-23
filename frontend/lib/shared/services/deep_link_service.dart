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
    
    // Check for referral code (?ref=CODE)
    if (uri.queryParameters.containsKey('ref') || uri.path.contains('ref=')) {
      String? refCode = uri.queryParameters['ref'];
      
      // Fallback for weird URL formats
      if (refCode == null || refCode.isEmpty) {
        final path = uri.path;
        if (path.contains('ref=')) {
          refCode = path.split('ref=').last.split('&').first;
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
