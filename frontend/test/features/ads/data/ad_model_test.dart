import 'package:flutter_test/flutter_test.dart';
import 'package:vayug/features/ads/data/ad_model.dart';
import 'package:flutter/material.dart';

void main() {
  group('AdModel Logic Tests', () {
    final baseAd = AdModel(
      id: 'test-1',
      title: 'Test Ad',
      description: 'Test Description',
      adType: 'banner',
      status: 'active',
      createdAt: DateTime.now(),
      budget: 50000, // ₹500.00
      impressions: 1000,
      clicks: 50,
      ctr: 0.05,
      targetAudience: 'all',
      targetKeywords: ['test'],
      uploaderId: 'u-1',
      uploaderName: 'Test User',
      spend: 250.0,
    );

    test('Correctly formats budget', () {
      expect(baseAd.formattedBudget, '₹500.00');
    });

    test('Calculates CPC correctly', () {
      expect(baseAd.cpc, 5.0); // 250 / 50
    });

    test('Determines performance status correctly', () {
      // CTR 0.05 is 'Good' (according to model logic: > 0.05 is Excellent, > 0.02 is Good)
      expect(baseAd.performanceStatus, 'Good');
      expect(baseAd.performanceColor, Colors.lightGreen);
    });

    test('Calculates budget pacing status', () {
      // Since we just created it, pacing might be tricky without fixed dates
      // but we can test the status logic if we provide dates
      final pacingAd = baseAd.copyWith(
        startDate: DateTime.now().subtract(const Duration(days: 5)),
        endDate: DateTime.now().add(const Duration(days: 5)),
        spend: 250.0,
        budget: 500,
      );
      // After 5 days of 10 days campaign, expected spend is 250. 250/250 = 1.0 (On track)
      expect(pacingAd.budgetPacingStatus, 'On track');
    });
  });
}
