import 'package:flutter/material.dart';
import 'package:vayug/core/interfaces/i_subscription_service.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/shared/utils/app_logger.dart';

enum SubscriptionStatus { idle, loading, success, error }

class SubscriptionStateManager extends ChangeNotifier {
  final ISubscriptionService _service;

  SubscriptionStateManager({required ISubscriptionService service}) : _service = service;

  List<VideoModel> _allVideos = [];
  List<VideoModel> _exclusiveVideos = [];
  List<VideoModel> _feedVideos = [];
  List<Uploader> _creators = [];
  
  SubscriptionStatus _status = SubscriptionStatus.idle;
  String? _errorMessage;

  List<VideoModel> get allVideos => _allVideos;
  List<VideoModel> get exclusiveVideos => _exclusiveVideos;
  List<VideoModel> get feedVideos => _feedVideos;
  List<Uploader> get creators => _creators;
  SubscriptionStatus get status => _status;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _status == SubscriptionStatus.loading;

  Future<void> loadSubscriberContent({bool refresh = false}) async {
    if (_status == SubscriptionStatus.loading && !refresh) return;

    _status = SubscriptionStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final videos = await _service.getSubscriberVideos(forceRefresh: refresh);
      
      _allVideos = videos;
      
      // Heuristic for exclusive content
      _exclusiveVideos = videos.where((v) => 
        v.videoName.toLowerCase().contains('exclusive') || 
        (v.tags?.contains('exclusive') ?? false)
      ).toList();
      
      _feedVideos = videos.where((v) => !_exclusiveVideos.contains(v)).toList();
      
      // Extract unique creators
      final creatorsMap = <String, Uploader>{};
      for (var v in videos) {
        creatorsMap[v.uploader.id] = v.uploader;
      }
      _creators = creatorsMap.values.toList();

      _status = SubscriptionStatus.success;
    } catch (e) {
      AppLogger.log('❌ SubscriptionStateManager: $e');
      _status = SubscriptionStatus.error;
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      notifyListeners();
    }
  }

  void reset() {
    _allVideos = [];
    _exclusiveVideos = [];
    _feedVideos = [];
    _creators = [];
    _status = SubscriptionStatus.idle;
    _errorMessage = null;
    notifyListeners();
  }
}
