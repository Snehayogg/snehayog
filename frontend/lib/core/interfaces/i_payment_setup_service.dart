abstract class IPaymentSetupService {
  Future<bool> hasCompletedPaymentSetup();
  Future<void> markPaymentSetupCompleted();
  Future<void> clearPaymentSetupStatus();
  Future<Map<String, dynamic>> getPaymentSetupStatus();
  Future<Map<String, dynamic>?> fetchPaymentProfile();
  Future<void> updateUpiId(String upiId);
}
