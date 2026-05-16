import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/core/interfaces/i_subscription_service.dart';
import 'package:vayug/features/video/subscriptions/data/services/subscription_service_impl.dart';
import 'package:vayug/features/video/subscriptions/presentation/managers/subscription_state_manager.dart';

final subscriptionServiceProvider = Provider<ISubscriptionService>((ref) {
  return SubscriptionService();
});

final subscriptionStateManagerProvider = ChangeNotifierProvider<SubscriptionStateManager>((ref) {
  final service = ref.watch(subscriptionServiceProvider);
  return SubscriptionStateManager(service: service);
});
