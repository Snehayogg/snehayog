import 'package:vayug/features/video/core/data/models/video_model.dart';

abstract class ISubscriptionService {
  /// Fetches subscriber-only videos for the current user
  Future<List<VideoModel>> getSubscriberVideos({bool forceRefresh = false});

  /// Fetches a list of creators the user is subscribed to
  Future<List<Uploader>> getSubscribedCreators();

  /// Toggles subscription for a specific creator
  Future<bool> toggleSubscription(String creatorId);
}
