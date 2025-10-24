// Removed unused import
import 'package:vayu/core/utils/enhanced_controller_disposal.dart';
import 'package:vayu/core/managers/video_controller_manager.dart';
import 'dart:async';

/// Memory Management Service
/// Handles automatic memory cleanup and prevents memory leaks
class MemoryManagementService {
  static final MemoryManagementService _instance =
      MemoryManagementService._internal();
  factory MemoryManagementService() => _instance;
  MemoryManagementService._internal();

  Timer? _cleanupTimer;
  Timer? _memoryCheckTimer;
  bool _isInitialized = false;
  int _cleanupCount = 0;
  DateTime? _lastCleanup;

  /// Initialize the memory management service
  void initialize() {
    if (_isInitialized) return;

    print('🧠 MemoryManagementService: Initializing memory management');

    // **AUTOMATIC CLEANUP: Run cleanup every 30 seconds**
    _cleanupTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _performAutomaticCleanup();
    });

    // **MEMORY CHECK: Check memory usage every 60 seconds**
    _memoryCheckTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      _checkMemoryUsage();
    });

    _isInitialized = true;
    print('✅ MemoryManagementService: Memory management initialized');
  }

  /// Perform automatic cleanup
  void _performAutomaticCleanup() {
    try {
      print('🧹 MemoryManagementService: Performing automatic cleanup');

      // **ENHANCED DISPOSAL: Process disposal queue**
      // Note: The disposal queue is processed automatically by the EnhancedControllerDisposal
      // No need to call private method directly

      // **VIDEO CONTROLLER: Optimize video controllers**
      VideoControllerManager().optimizeControllers();

      _cleanupCount++;
      _lastCleanup = DateTime.now();

      print(
          '✅ MemoryManagementService: Automatic cleanup completed (count: $_cleanupCount)');
    } catch (e) {
      print('❌ MemoryManagementService: Error during automatic cleanup: $e');
    }
  }

  /// Check memory usage and perform cleanup if needed
  void _checkMemoryUsage() {
    try {
      final disposalStatus = EnhancedControllerDisposal.getDisposalStatus();
      final queueSize = disposalStatus['queueSize'] as int;
      final activeTimers = disposalStatus['activeTimers'] as int;

      print(
          '📊 MemoryManagementService: Memory check - Queue: $queueSize, Timers: $activeTimers');

      // **MEMORY PRESSURE: Force cleanup if queue is too large**
      if (queueSize > 10) {
        print(
            '⚠️ MemoryManagementService: High memory pressure detected, forcing cleanup');
        EnhancedControllerDisposal.forceCleanup();
      }

      // **TIMER CLEANUP: Clean up orphaned timers**
      if (activeTimers > 5) {
        print(
            '⚠️ MemoryManagementService: Too many active timers, clearing queue');
        EnhancedControllerDisposal.clearDisposalQueue();
      }
    } catch (e) {
      print('❌ MemoryManagementService: Error checking memory usage: $e');
    }
  }

  /// Force immediate cleanup
  Future<void> forceCleanup() async {
    print('🧹 MemoryManagementService: Force cleanup initiated');

    try {
      // **ENHANCED DISPOSAL: Force cleanup of all controllers**
      await EnhancedControllerDisposal.forceCleanup();

      // **VIDEO CONTROLLER: Clear all video controllers**
      VideoControllerManager().clear();

      _cleanupCount++;
      _lastCleanup = DateTime.now();

      print('✅ MemoryManagementService: Force cleanup completed');
    } catch (e) {
      print('❌ MemoryManagementService: Error during force cleanup: $e');
    }
  }

  /// Handle app lifecycle changes
  void onAppPaused() {
    print('⏸️ MemoryManagementService: App paused - performing cleanup');
    _performAutomaticCleanup();
  }

  void onAppResumed() {
    print('▶️ MemoryManagementService: App resumed');
    // Don't perform cleanup on resume to avoid disrupting user experience
  }

  void onAppDetached() {
    print(
        '🔌 MemoryManagementService: App detached - performing final cleanup');
    forceCleanup();
  }

  /// Get memory statistics
  Map<String, dynamic> getMemoryStats() {
    return {
      'isInitialized': _isInitialized,
      'cleanupCount': _cleanupCount,
      'lastCleanup': _lastCleanup?.toIso8601String(),
      'disposalStatus': EnhancedControllerDisposal.getDisposalStatus(),
      'memoryStats': EnhancedControllerDisposal.getMemoryStats(),
    };
  }

  /// Dispose the memory management service
  void dispose() {
    print('🗑️ MemoryManagementService: Disposing memory management service');

    // **CANCEL: All timers**
    _cleanupTimer?.cancel();
    _memoryCheckTimer?.cancel();

    // **FINAL CLEANUP: Perform final cleanup**
    forceCleanup();

    _isInitialized = false;
    print('✅ MemoryManagementService: Memory management service disposed');
  }
}

/// Global memory management service instance
final memoryManagementService = MemoryManagementService();
