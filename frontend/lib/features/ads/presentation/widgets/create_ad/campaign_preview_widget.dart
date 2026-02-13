import 'package:flutter/material.dart';

/// **CampaignPreviewWidget - Shows campaign metrics and preview**
class CampaignPreviewWidget extends StatelessWidget {
  final DateTime? startDate;
  final DateTime? endDate;
  final String budgetText;
  final String selectedAdType;

  const CampaignPreviewWidget({
    Key? key,
    required this.startDate,
    required this.endDate,
    required this.budgetText,
    required this.selectedAdType,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (startDate == null || endDate == null || budgetText.isEmpty) {
      return const SizedBox.shrink();
    }

    final metrics = _getCampaignMetrics();
    if (metrics.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, color: Colors.blue.shade600),
                const SizedBox(width: 8),
                const Text(
                  'Campaign Preview',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ..._buildCampaignMetricsDisplay(metrics),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle,
                      size: 16, color: Colors.green.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '✅ Campaign configuration looks good! You can proceed to create your ad.',
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic> _getCampaignMetrics() {
    if (startDate == null || endDate == null) {
      return {};
    }

    final campaignDays = endDate!.difference(startDate!).inDays + 1;
    final dailyBudget = double.tryParse(budgetText.trim()) ?? 100.0;

    // Calculate metrics based on ad type
    final cpm = selectedAdType == 'banner' ? 10.0 : 30.0;
    final totalBudget = dailyBudget * campaignDays;
    final expectedImpressions = (totalBudget / cpm * 1000).round();
    final dailyImpressions = (expectedImpressions / campaignDays).round();

    return {
      'totalBudget': totalBudget,
      'expectedImpressions': expectedImpressions,
      'campaignDays': campaignDays,
      'dailyImpressions': dailyImpressions,
      'cpm': cpm,
      'estimatedDuration': campaignDays,
    };
  }

  List<Widget> _buildCampaignMetricsDisplay(Map<String, dynamic> metrics) {
    return [
      _buildMetricRow(
          '💰 Total Budget', '₹${metrics['totalBudget']?.toStringAsFixed(0)}'),
      _buildMetricRow('📊 Expected Impressions',
          '${metrics['expectedImpressions']?.toStringAsFixed(0)}'),
      _buildMetricRow(
          '📅 Campaign Duration', '${metrics['campaignDays']} days'),
      _buildMetricRow('📈 Daily Impressions',
          '${metrics['dailyImpressions']?.toStringAsFixed(0)}'),
      _buildMetricRow(
          '💵 CPM Rate', '₹${metrics['cpm']?.toStringAsFixed(0)} per 1000'),
      _buildMetricRow(
          '⏱️ Estimated Duration', '${metrics['estimatedDuration']} days'),
    ];
  }

  Widget _buildMetricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
        ],
      ),
    );
  }
}
