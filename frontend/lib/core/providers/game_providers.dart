import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayu/features/profile/presentation/managers/game_creator_manager.dart';

final gameCreatorManagerProvider = ChangeNotifierProvider<GameCreatorManager>((ref) {
  return GameCreatorManager();
});
