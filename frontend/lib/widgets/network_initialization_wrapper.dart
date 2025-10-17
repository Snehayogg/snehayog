import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/network_service.dart';

/// Widget wrapper that initializes NetworkService on app startup
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
  bool _isInitialized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeNetworkService();
  }

  Future<void> _initializeNetworkService() async {
    try {
      if (kDebugMode) {
        print(
            '🌐 NetworkInitializationWrapper: Initializing NetworkService...');
      }

      await NetworkService.instance.initialize();

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }

      if (kDebugMode) {
        final networkInfo = NetworkService.instance.getConnectionInfo();
        print('✅ NetworkInitializationWrapper: NetworkService initialized');
        print('📍 Current URL: ${networkInfo['currentUrl']}');
        print('🏠 Is Local: ${networkInfo['isLocal']}');
        print('☁️ Is Production: ${networkInfo['isProduction']}');
      }
    } catch (e) {
      if (kDebugMode) {
        print(
            '❌ NetworkInitializationWrapper: Failed to initialize NetworkService: $e');
      }

      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // If there's an error, show error widget
    if (_error != null) {
      return Scaffold(
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
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _error = null;
                    _isInitialized = false;
                  });
                  _initializeNetworkService();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // If not initialized yet, show loading screen
    if (!_isInitialized) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Initializing network connection...'),
              if (kDebugMode) ...[
                SizedBox(height: 8),
                Text(
                  'Debug: Testing server connectivity',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // Network service initialized successfully, show the app
    return widget.child;
  }
}
