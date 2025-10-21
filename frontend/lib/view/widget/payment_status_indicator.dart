import 'package:flutter/material.dart';
import 'package:snehayog/services/payment_setup_service.dart';

/// Widget to display payment setup status
class PaymentStatusIndicator extends StatefulWidget {
  final bool showAsCard;
  final VoidCallback? onTap;

  const PaymentStatusIndicator({
    Key? key,
    this.showAsCard = false,
    this.onTap,
  }) : super(key: key);

  @override
  State<PaymentStatusIndicator> createState() => _PaymentStatusIndicatorState();
}

class _PaymentStatusIndicatorState extends State<PaymentStatusIndicator> {
  bool _hasPaymentSetup = false;
  bool _isLoading = true;
  final PaymentSetupService _paymentService = PaymentSetupService();

  @override
  void initState() {
    super.initState();
    _checkPaymentStatus();
  }

  Future<void> _checkPaymentStatus() async {
    try {
      final hasSetup = await _paymentService.hasCompletedPaymentSetup();
      if (mounted) {
        setState(() {
          _hasPaymentSetup = hasSetup;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildLoadingIndicator();
    }

    if (widget.showAsCard) {
      return _buildCardIndicator();
    }

    return _buildInlineIndicator();
  }

  Widget _buildLoadingIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.grey[600]!),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Checking...',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardIndicator() {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _hasPaymentSetup ? Colors.green[50] : Colors.orange[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _hasPaymentSetup ? Colors.green[200]! : Colors.orange[200]!,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color:
                    _hasPaymentSetup ? Colors.green[100] : Colors.orange[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _hasPaymentSetup ? Icons.check_circle : Icons.payment,
                color:
                    _hasPaymentSetup ? Colors.green[700] : Colors.orange[700],
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _hasPaymentSetup
                        ? 'Payment Setup Complete'
                        : 'Payment Setup Required',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _hasPaymentSetup
                          ? Colors.green[800]
                          : Colors.orange[800],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _hasPaymentSetup
                        ? 'You\'ll receive 80% of ad revenue automatically'
                        : 'Set up payment details to receive earnings',
                    style: TextStyle(
                      fontSize: 12,
                      color: _hasPaymentSetup
                          ? Colors.green[600]
                          : Colors.orange[600],
                    ),
                  ),
                ],
              ),
            ),
            if (!_hasPaymentSetup)
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Colors.orange[600],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInlineIndicator() {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _hasPaymentSetup ? Colors.green[100] : Colors.orange[100],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _hasPaymentSetup ? Colors.green[300]! : Colors.orange[300]!,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _hasPaymentSetup ? Icons.check_circle : Icons.payment,
              size: 16,
              color: _hasPaymentSetup ? Colors.green[700] : Colors.orange[700],
            ),
            const SizedBox(width: 6),
            Text(
              _hasPaymentSetup ? 'Payment Ready' : 'Setup Payment',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color:
                    _hasPaymentSetup ? Colors.green[700] : Colors.orange[700],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Simple payment status badge
class PaymentStatusBadge extends StatelessWidget {
  final bool hasPaymentSetup;
  final VoidCallback? onTap;

  const PaymentStatusBadge({
    Key? key,
    required this.hasPaymentSetup,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: hasPaymentSetup ? Colors.green[100] : Colors.orange[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasPaymentSetup ? Icons.check_circle : Icons.payment,
              size: 14,
              color: hasPaymentSetup ? Colors.green[700] : Colors.orange[700],
            ),
            const SizedBox(width: 4),
            Text(
              hasPaymentSetup ? 'Ready' : 'Setup',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: hasPaymentSetup ? Colors.green[700] : Colors.orange[700],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
