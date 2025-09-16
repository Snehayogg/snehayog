import 'package:flutter/material.dart';

/// **CampaignSettingsWidget - Handles budget and date selection**
class CampaignSettingsWidget extends StatelessWidget {
  final TextEditingController budgetController;
  final DateTime? startDate;
  final DateTime? endDate;
  final Function() onClearErrors;
  final Function() onSelectDateRange;

  const CampaignSettingsWidget({
    Key? key,
    required this.budgetController,
    required this.startDate,
    required this.endDate,
    required this.onClearErrors,
    required this.onSelectDateRange,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Campaign Settings',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: budgetController,
              decoration: const InputDecoration(
                labelText: 'Daily Budget (₹) *',
                hintText: '100',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.attach_money),
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) => onClearErrors(),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a budget';
                }
                final budget = double.tryParse(value.trim());
                if (budget == null || budget <= 0) {
                  return 'Please enter a valid budget';
                }
                if (budget < 100) {
                  return 'Minimum budget is ₹100';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onSelectDateRange,
                    icon: const Icon(Icons.calendar_today),
                    label: Text(
                      startDate != null && endDate != null
                          ? '${startDate!.toString().split(' ')[0]} - ${endDate!.toString().split(' ')[0]}'
                          : 'Select Date Range *',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            if (startDate != null && endDate != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Campaign will run for ${endDate!.difference(startDate!).inDays + 1} days',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
              ),
            if (startDate == null || endDate == null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Please select start and end dates for your campaign',
                  style: TextStyle(
                    color: Colors.red.shade600,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
