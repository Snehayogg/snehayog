import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/shared/providers/user_provider.dart';

final userProvider = ChangeNotifierProvider<UserProvider>((ref) {
  return UserProvider();
});
