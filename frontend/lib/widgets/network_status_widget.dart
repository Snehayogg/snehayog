import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/network_service.dart';

/// Widget to display current network status and allow switching between servers
class NetworkStatusWidget extends StatefulWidget {
  const NetworkStatusWidget({Key? key}) : super(key: key);

  @override
  State<NetworkStatusWidget> createState() => _NetworkStatusWidgetState();
}

class _NetworkStatusWidgetState extends State<NetworkStatusWidget> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const SizedBox.shrink();
    }

    final networkInfo = NetworkService.instance.getConnectionInfo();
    final isLocal = networkInfo['isLocal'] as bool;
    final currentUrl = networkInfo['currentUrl'] as String?;

    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      right: 10,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _isExpanded = !_isExpanded;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isLocal ? Colors.green : Colors.orange,
            borderRadius: BorderRadius.circular(_isExpanded ? 8 : 20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: _isExpanded
              ? _buildExpandedView(networkInfo)
              : _buildCollapsedView(isLocal),
        ),
      ),
    );
  }

  Widget _buildCollapsedView(bool isLocal) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isLocal ? Icons.home : Icons.cloud,
          color: Colors.white,
          size: 16,
        ),
        const SizedBox(width: 4),
        Text(
          isLocal ? 'LOCAL' : 'PROD',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildExpandedView(Map<String, dynamic> networkInfo) {
    final isLocal = networkInfo['isLocal'] as bool;
    final currentUrl = networkInfo['currentUrl'] as String?;
    final serverStatus = networkInfo['serverStatus'] as Map<String, bool>;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isLocal ? Icons.home : Icons.cloud,
              color: Colors.white,
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              'Network Status',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Current: ${currentUrl ?? 'Unknown'}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Mode: ${isLocal ? 'Local Development' : 'Production'}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: () async {
                await NetworkService.instance.tryLocalServer();
                setState(() {});
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
              ),
              child: const Text('Local', style: TextStyle(fontSize: 10)),
            ),
            const SizedBox(width: 4),
            ElevatedButton(
              onPressed: () async {
                await NetworkService.instance.switchToProduction();
                setState(() {});
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.orange,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
              ),
              child: const Text('Prod', style: TextStyle(fontSize: 10)),
            ),
            const SizedBox(width: 4),
            ElevatedButton(
              onPressed: () async {
                await NetworkService.instance.reconnect();
                setState(() {});
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
              ),
              child: const Text('Reconnect', style: TextStyle(fontSize: 10)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Server status indicators
        ...serverStatus.entries.map((entry) {
          final url = entry.key;
          final isOnline = entry.value;
          final shortUrl =
              url.contains('192.168.0.199') ? 'Local' : 'Production';

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isOnline ? Icons.check_circle : Icons.cancel,
                color: isOnline ? Colors.green : Colors.red,
                size: 12,
              ),
              const SizedBox(width: 4),
              Text(
                '$shortUrl: ${isOnline ? 'Online' : 'Offline'}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                ),
              ),
            ],
          );
        }).toList(),
      ],
    );
  }
}
