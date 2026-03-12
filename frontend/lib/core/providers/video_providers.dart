import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayu/features/video/presentation/managers/video_provider.dart';

final videoProvider = ChangeNotifierProvider<VideoProvider>((ref) {
  return VideoProvider();
});
