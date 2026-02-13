import 'package:flutter/material.dart';

/// **CampaignSettingsWidget - Handles budget and date selection**
class CampaignSettingsWidget extends StatelessWidget {
  final TextEditingController budgetController;
  final DateTime? startDate;
  final DateTime? endDate;
  final Function() onClearErrors;
  final Function() onSelectDateRange;
  final Function(String)? onFieldChanged;
  final bool? isBudgetValid;
  final bool? isDateValid;
  final String? budgetError;
  final String? dateError;

  const CampaignSettingsWidget({
    Key? key,
    required this.budgetController,
    required this.startDate,
    required this.endDate,
    required this.onClearErrors,
    required this.onSelectDateRange,
    this.onFieldChanged,
    // **NEW: Optional validation parameters**
    this.isBudgetValid,
    this.isDateValid,
    this.budgetError,
    this.dateError,
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
              decoration: InputDecoration(
                labelText: 'Daily Budget (₹) *',
                hintText: '100',
                border: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: (isBudgetValid == false) ? Colors.red : Colors.grey,
                    width: (isBudgetValid == false) ? 2.0 : 1.0,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: (isBudgetValid == false) ? Colors.red : Colors.grey,
                    width: (isBudgetValid == false) ? 2.0 : 1.0,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: (isBudgetValid == false) ? Colors.red : Colors.blue,
                    width: (isBudgetValid == false) ? 2.0 : 2.0,
                  ),
                ),
                prefixIcon: const Icon(Icons.attach_money),
                errorText: (isBudgetValid == false) ? budgetError : null,
                errorStyle: const TextStyle(color: Colors.red, fontSize: 12),
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) {
                onClearErrors();
                onFieldChanged?.call('budget');
              },
            ),
            const SizedBox(height: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: (isDateValid == false) ? Colors.red : Colors.grey,
                      width: (isDateValid == false) ? 2.0 : 1.0,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: ElevatedButton.icon(
                    onPressed: onSelectDateRange,
                    icon: const Icon(Icons.calendar_today),
                    label: Text(
                      startDate != null && endDate != null
                          ? '${startDate!.toString().split(' ')[0]} - ${endDate!.toString().split(' ')[0]}'
                          : 'Select Date Range *',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: (isDateValid == false)
                          ? Colors.red.shade100
                          : Colors.orange,
                      foregroundColor:
                          (isDateValid == false) ? Colors.red : Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
                if (isDateValid == false && dateError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      dateError!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
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
