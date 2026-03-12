import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayu/features/profile/presentation/managers/profile_state_manager.dart';

final profileStateManagerProvider = ChangeNotifierProvider<ProfileStateManager>((ref) {
  return ProfileStateManager();
});
