import 'package:flutter_test/flutter_test.dart';

import 'package:snehayog_monetization/snehayog_monetization.dart';

void main() {
  group('RazorpayService Tests', () {
    late RazorpayService razorpayService;

    setUp(() {
      razorpayService = RazorpayService();
    });

    test('should initialize with correct configuration', () {
      expect(() {
        razorpayService.initialize(
          keyId: 'test_key_id',
          keySecret: 'test_key_secret',
          webhookSecret: 'test_webhook_secret',
          baseUrl: 'https://test.com',
        );
      }, returnsNormally);
    });

    test('should calculate revenue split correctly', () {
      final result = razorpayService.calculateRevenueSplit(100.0);

      expect(result['platform'], 20.0);
      expect(result['creator'], 80.0);
      expect(result['total'], 100.0);
    });

    test('should handle disposal correctly', () {
      expect(() {
        razorpayService.dispose();
      }, returnsNormally);
    });
  });
}
