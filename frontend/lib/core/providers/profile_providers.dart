import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/features/profile/core/presentation/managers/profile_state_manager.dart';

final profileStateManagerProvider = ChangeNotifierProvider<ProfileStateManager>((ref) {
  return ProfileStateManager();
});
