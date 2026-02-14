import 'package:flutter/material.dart';
import 'package:vayu/features/profile/data/services/payment_setup_service.dart';
import 'package:vayu/shared/theme/app_theme.dart';

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
        color: AppTheme.backgroundSecondary,
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children:  [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.textTertiary),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Checking...',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
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
          color: _hasPaymentSetup
              ? AppTheme.success.withOpacity(0.1)
              : AppTheme.warning.withOpacity(0.1),
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          border: Border.all(
            color: _hasPaymentSetup
                ? AppTheme.success.withOpacity(0.2)
                : AppTheme.warning.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _hasPaymentSetup
                    ? AppTheme.success.withOpacity(0.1)
                    : AppTheme.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              ),
              child: Icon(
                _hasPaymentSetup ? Icons.check_circle : Icons.payment,
                color: _hasPaymentSetup ? AppTheme.success : AppTheme.warning,
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
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: _hasPaymentSetup
                              ? AppTheme.success
                              : AppTheme.warning,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _hasPaymentSetup
                        ? 'You\'ll receive 80% of ad revenue automatically'
                        : 'Set up payment details to receive earnings',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
            if (!_hasPaymentSetup)
              const Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: AppTheme.warning,
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
          color: _hasPaymentSetup
              ? AppTheme.success.withOpacity(0.1)
              : AppTheme.warning.withOpacity(0.1),
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
          border: Border.all(
            color: _hasPaymentSetup
                ? AppTheme.success.withOpacity(0.2)
                : AppTheme.warning.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _hasPaymentSetup ? Icons.check_circle : Icons.payment,
              size: 16,
              color: _hasPaymentSetup ? AppTheme.success : AppTheme.warning,
            ),
            const SizedBox(width: 6),
            Text(
              _hasPaymentSetup ? 'Payment Ready' : 'Setup Payment',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color:
                        _hasPaymentSetup ? AppTheme.success : AppTheme.warning,
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
          color: hasPaymentSetup
              ? AppTheme.success.withOpacity(0.1)
              : AppTheme.warning.withOpacity(0.1),
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasPaymentSetup ? Icons.check_circle : Icons.payment,
              size: 14,
              color: hasPaymentSetup ? AppTheme.success : AppTheme.warning,
            ),
            const SizedBox(width: 4),
            Text(
              hasPaymentSetup ? 'Ready' : 'Setup',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color:
                        hasPaymentSetup ? AppTheme.success : AppTheme.warning,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
