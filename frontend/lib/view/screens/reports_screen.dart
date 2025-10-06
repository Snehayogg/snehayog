import 'package:flutter/material.dart';
import 'package:snehayog/model/report_model.dart';
import 'package:snehayog/services/report_service.dart';
import 'package:snehayog/view/widget/report/report_form_widget.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _reportService = ReportService();
  List<ReportModel> _reportsList = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUserReports();
  }

  Future<void> _loadUserReports() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // For now, we'll use a placeholder user ID
      // In a real app, you'd get this from your user provider/state
      final reports = await _reportService.getReportsByUser('current_user_id');
      setState(() {
        _reportsList = reports;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Reports'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showReportInfo(),
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _navigateToReportForm(),
        icon: const Icon(Icons.report),
        label: const Text('Report Content'),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'Error loading reports',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadUserReports,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_reportsList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.report_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No reports submitted yet',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Help keep our community safe by reporting inappropriate content',
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _navigateToReportForm(),
              icon: const Icon(Icons.report),
              label: const Text('Submit Your First Report'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadUserReports,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _reportsList.length,
        itemBuilder: (context, index) {
          final report = _reportsList[index];
          return _buildReportCard(report);
        },
      ),
    );
  }

  Widget _buildReportCard(ReportModel report) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Expanded(
                  child: Text(
                    report.reportedContent,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _buildStatusChip(report.status),
              ],
            ),

            const SizedBox(height: 8),

            // Type and severity
            Row(
              children: [
                _buildInfoChip(report.typeDisplayName, Colors.red),
                const SizedBox(width: 8),
                _buildInfoChip(report.severityDisplayName,
                    _getSeverityColor(report.severity)),
                const SizedBox(width: 8),
                _buildInfoChip(report.priorityDisplayName,
                    _getPriorityColor(report.priority)),
              ],
            ),

            const SizedBox(height: 12),

            // Reason and description (truncated)
            Text(
              'Reason: ${report.reason}',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              report.description,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: 12),

            // Footer row
            Row(
              children: [
                Icon(Icons.access_time, size: 16, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Text(
                  report.formattedCreatedAt,
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                if (report.actionTaken != null)
                  Icon(Icons.gavel, size: 16, color: Colors.green[600]),
                if (report.resolvedAt != null) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.check_circle, size: 16, color: Colors.green[600]),
                ],
                if (report.isRepeatReport) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.repeat, size: 16, color: Colors.orange[600]),
                ],
              ],
            ),

            // Action taken (if any)
            if (report.actionTaken != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle,
                        size: 16, color: Colors.green[600]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Action taken: ${report.actionTakenDisplayName}',
                        style: TextStyle(
                          color: Colors.green[700],
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color color;
    switch (status.toLowerCase()) {
      case 'pending':
        color = Colors.orange;
        break;
      case 'under_review':
        color = Colors.blue;
        break;
      case 'resolved':
        color = Colors.green;
        break;
      case 'dismissed':
        color = Colors.grey;
        break;
      case 'escalated':
        color = Colors.red;
        break;
      default:
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildInfoChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return Colors.red;
      case 'severe':
        return Colors.deepOrange;
      case 'moderate':
        return Colors.orange;
      case 'minor':
        return Colors.yellow[700]!;
      default:
        return Colors.grey;
    }
  }

  Color _getPriorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'urgent':
        return Colors.red;
      case 'high':
        return Colors.deepOrange;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  void _navigateToReportForm() {
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (context) => const ReportFormWidget(),
      ),
    )
        .then((_) {
      // Refresh the list when returning from the form
      _loadUserReports();
    });
  }

  void _showReportInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About Reports'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'What can you report?',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('• Spam or misleading content'),
              Text('• Harassment or bullying'),
              Text('• Hate speech or discrimination'),
              Text('• Inappropriate or explicit content'),
              Text('• Violence or dangerous behavior'),
              Text('• Copyright violations'),
              Text('• Fake accounts or scams'),
              SizedBox(height: 16),
              Text(
                'What happens after you report?',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('• Our moderation team reviews all reports'),
              Text('• We take appropriate action when needed'),
              Text('• You\'ll be notified of the outcome'),
              Text('• False reports may result in action against your account'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}
