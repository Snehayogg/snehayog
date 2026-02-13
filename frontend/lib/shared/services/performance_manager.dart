import 'package:firebase_performance/firebase_performance.dart';
import 'package:vayu/shared/utils/app_logger.dart';

class PerformanceManager {
  static final PerformanceManager _instance = PerformanceManager._internal();
  factory PerformanceManager() => _instance;
  PerformanceManager._internal();

  bool _isInitialized = false;

  /// Initialize Firebase Performance
  Future<void> initialize() async {
    try {
      if (_isInitialized) return;
      
      // Automatic tracing is enabled by default in Firebase Performance
      await FirebasePerformance.instance.setPerformanceCollectionEnabled(true);
      
      _isInitialized = true;
      AppLogger.log('🚀 PerformanceManager: Firebase Performance initialized');
    } catch (e) {
      AppLogger.log('⚠️ PerformanceManager: Initialization failed: $e');
    }
  }

  /// Start a custom trace for manual performance monitoring
  /// Useful for measuring specific complex operations like video compression
  Future<Trace?> startTrace(String name) async {
    if (!_isInitialized) await initialize();
    
    try {
      final trace = FirebasePerformance.instance.newTrace(name);
      await trace.start();
      AppLogger.log('⏱️ PerformanceManager: Started trace: $name');
      return trace;
    } catch (e) {
      AppLogger.log('⚠️ PerformanceManager: Failed to start trace $name: $e');
      return null;
    }
  }

  /// Stop a trace
  Future<void> stopTrace(Trace trace) async {
    try {
      await trace.stop();
      // Note: We can't easily get the trace name back from the Trace object to log it
    } catch (e) {
      AppLogger.log('⚠️ PerformanceManager: Failed to stop trace: $e');
    }
  }

  /// Measure an asynchronous function using a custom trace
  Future<T> measure<T>(String name, Future<T> Function() action) async {
    final trace = await startTrace(name);
    try {
      return await action();
    } finally {
      if (trace != null) {
        await stopTrace(trace);
        AppLogger.log('✅ PerformanceManager: Completed trace: $name');
      }
    }
  }
}
