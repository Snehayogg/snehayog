import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/core/interfaces/i_payment_setup_service.dart';
import 'package:vayug/features/profile/payouts/data/services/payment_setup_service.dart';

final paymentSetupServiceProvider = Provider<IPaymentSetupService>((ref) {
  return PaymentSetupService();
});
