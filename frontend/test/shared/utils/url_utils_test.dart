import 'package:flutter_test/flutter_test.dart';
import 'package:vayug/shared/utils/url_utils.dart';

void main() {
  group('UrlUtils.enrichUrl Tests', () {
    test('Should add https if scheme is missing', () {
      final result = UrlUtils.enrichUrl('snehayog.site');
      expect(result, contains('https://snehayog.site'));
    });

    test('Should add UTM parameters correctly', () {
      final url = 'https://google.com';
      final result = UrlUtils.enrichUrl(
        url,
        source: 'test_source',
        medium: 'test_medium',
        campaign: 'test_campaign',
      );

      expect(result, contains('utm_source=test_source'));
      expect(result, contains('utm_medium=test_medium'));
      expect(result, contains('utm_campaign=test_campaign'));
    });

    test('Should handle whitespace and trim URL', () {
      final result = UrlUtils.enrichUrl('  https://vayu.app  ');
      expect(result, startsWith('https://vayu.app'));
    });
  });
}
