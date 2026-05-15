import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/core/interfaces/i_user_service.dart';
import 'package:vayug/features/profile/core/data/services/user_service.dart';

final userServiceProvider = Provider<IUserService>((ref) {
  return UserService();
});
