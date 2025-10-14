import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'network_service.dart';

/// Service to initialize the app with network fallback
class AppInitializationService {
  static bool _isInitialized = false;

  /// Initialize the app services
  static Future<void> initialize() async {
    if (_isInitialized) {
      if (kDebugMode) {
        print('🔄 AppInitializationService: Already initialized');
      }
      return;
    }

    if (kDebugMode) {
      print('🚀 AppInitializationService: Starting initialization...');
    }

    try {
      // Initialize network service with fallback support
      await NetworkService.instance.initialize();

      if (kDebugMode) {
        final networkInfo = NetworkService.instance.getConnectionInfo();
        print('✅ AppInitializationService: Network service initialized');
        print(
            '📍 AppInitializationService: Using server: ${networkInfo['currentUrl']}');
        print(
            '🏠 AppInitializationService: Is local server: ${networkInfo['isLocal']}');
      }

      _isInitialized = true;
    } catch (e) {
      if (kDebugMode) {
        print('❌ AppInitializationService: Initialization failed: $e');
      }
      rethrow;
    }
  }

  /// Get initialization status
  static bool get isInitialized => _isInitialized;

  /// Reset initialization (for testing)
  static void reset() {
    _isInitialized = false;
  }
}

/// Widget wrapper for network initialization
class NetworkInitializationWrapper extends StatefulWidget {
  final Widget child;

  const NetworkInitializationWrapper({
    Key? key,
    required this.child,
  }) : super(key: key);

  @override
  State<NetworkInitializationWrapper> createState() =>
      _NetworkInitializationWrapperState();
}

class _NetworkInitializationWrapperState
    extends State<NetworkInitializationWrapper> {
  bool _isInitializing = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      await AppInitializationService.initialize();

      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Initializing network connection...'),
                SizedBox(height: 8),
                Text(
                  'Trying local server first, then production fallback',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_error != null) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Network Initialization Failed',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _isInitializing = true;
                      _error = null;
                    });
                    _initializeApp();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return widget.child;
  }
}
