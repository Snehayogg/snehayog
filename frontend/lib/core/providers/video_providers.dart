import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/features/video/core/presentation/managers/video_provider.dart';

import 'package:vayug/features/video/core/data/services/video_service.dart';

final videoServiceProvider = Provider<VideoService>((ref) {
  return VideoService();
});

final videoProvider = ChangeNotifierProvider<VideoProvider>((ref) {
  return VideoProvider();
});

