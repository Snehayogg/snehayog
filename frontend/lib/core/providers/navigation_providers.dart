import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayu/features/video/core/presentation/managers/main_controller.dart';

final mainControllerProvider = ChangeNotifierProvider<MainController>((ref) {
  return MainController();
});

