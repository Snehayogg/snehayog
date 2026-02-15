import 'dart:io';
import 'package:flutter/material.dart';
import 'package:vayu/features/games/data/services/vayu_game_service.dart';
import 'package:vayu/features/games/data/game_model.dart';
import 'package:vayu/shared/utils/app_logger.dart';

class GameCreatorManager extends ChangeNotifier {
  final VayuGameService _vayuGameService = VayuGameService();
  bool _isDisposed = false;

  // State variables
  bool _isCreatorMode = false;
  List<GameModel> _creatorGames = [];
  bool _isCreatorGamesLoading = false;
  bool _isGameActionLoading = false;
  String? _error;

  // Getters
  bool get isCreatorMode => _isCreatorMode;
  List<GameModel> get creatorGames => _creatorGames;
  bool get isCreatorGamesLoading => _isCreatorGamesLoading;
  bool get isGameActionLoading => _isGameActionLoading;
  String? get error => _error;

  void notifyListenersSafe() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  void toggleCreatorMode() {
    _isCreatorMode = !_isCreatorMode;
    AppLogger.log('🎮 GameCreatorManager: Creator mode toggled to $_isCreatorMode');
    if (_isCreatorMode && _creatorGames.isEmpty) {
      loadCreatorGames();
    }
    // Safety reset for action loading
    _isGameActionLoading = false;
    notifyListenersSafe();
  }

  Future<void> loadCreatorGames() async {
    _isCreatorGamesLoading = true;
    _error = null;
    notifyListenersSafe();

    try {
      final games = await _vayuGameService.fetchDeveloperGames();
      _creatorGames = games;
      AppLogger.log('🎮 GameCreatorManager: Loaded ${_creatorGames.length} games');
    } catch (e) {
      AppLogger.log('❌ GameCreatorManager: Error loading games: $e');
      _error = 'Failed to load games: ${e.toString()}';
    } finally {
      _isCreatorGamesLoading = false;
      notifyListenersSafe();
    }
  }

  Future<bool> uploadGame({
    required File zipFile,
    required String title,
    String? description,
    String orientation = 'portrait',
  }) async {
    _isGameActionLoading = true;
    _error = null;
    notifyListenersSafe();

    try {
      final success = await _vayuGameService.uploadGame(
        zipFile: zipFile,
        title: title,
        description: description,
        orientation: orientation,
      );
      
      if (success) {
        await loadCreatorGames();
      }
      return success;
    } catch (e) {
      AppLogger.log('❌ GameCreatorManager: Error uploading game: $e');
      _error = 'Upload failed: ${e.toString()}';
      return false;
    } finally {
      _isGameActionLoading = false;
      notifyListenersSafe();
    }
  }

  Future<bool> publishGame(String gameId) async {
    _isGameActionLoading = true;
    _error = null;
    notifyListenersSafe();

    try {
      final success = await _vayuGameService.publishGame(gameId);
      if (success) {
        await loadCreatorGames();
      }
      return success;
    } catch (e) {
      AppLogger.log('❌ GameCreatorManager: Error publishing game: $e');
      _error = 'Publishing failed: ${e.toString()}';
      return false;
    } finally {
      _isGameActionLoading = false;
      notifyListenersSafe();
    }
  }

  void clearData() {
    _isCreatorMode = false;
    _creatorGames = [];
    _isCreatorGamesLoading = false;
    _isGameActionLoading = false;
    _error = null;
    notifyListenersSafe();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
