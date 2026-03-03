import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:vayu/shared/services/local_dubbing_service.dart';
import 'package:vayu/shared/utils/app_logger.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DubbingTestApp());
}

class DubbingTestApp extends StatelessWidget {
  const DubbingTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dubbing Isolated Test',
      theme: ThemeData.dark(),
      home: const DubbingTestScreen(),
    );
  }
}

class DubbingTestScreen extends StatefulWidget {
  const DubbingTestScreen({super.key});

  @override
  State<DubbingTestScreen> createState() => _DubbingTestScreenState();
}

class _DubbingTestScreenState extends State<DubbingTestScreen> {
  String _status = 'Ready';
  double _progress = 0.0;
  String? _resultPath;
  bool _isProcessing = false;

  Future<void> _startTest() async {
    // 1. Pick a short video file for testing
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );

    if (result == null || result.files.single.path == null) {
      setState(() => _status = 'Selection canceled');
      return;
    }

    final videoPath = result.files.single.path!;
    
    setState(() {
      _isProcessing = true;
      _status = 'Starting dubbing test...';
      _progress = 0.0;
      _resultPath = null;
    });

    try {
      final startTime = DateTime.now();
      
      // 2. Run the isolated pipeline
      final outputPath = await localDubbingService.processDubbing(
        videoPath: videoPath,
        videoId: 'test_vid_${DateTime.now().millisecondsSinceEpoch}',
        targetLang: 'hindi', // Default test language
        onProgress: (msg, percent) {
          setState(() {
            _status = msg;
            _progress = percent;
          });
          AppLogger.log('Progress: ${(percent * 100).toInt()}% - $msg');
        },
      );

      final elapsed = DateTime.now().difference(startTime);
      
      setState(() {
        _status = 'Success! Took ${elapsed.inSeconds} seconds.';
        _resultPath = outputPath;
        _progress = 1.0;
      });
      
      AppLogger.log('Dubbing Test Complete: $outputPath');

    } catch (e) {
      setState(() {
        _status = 'Error: $e';
        _progress = 0;
      });
      AppLogger.log('Dubbing Test Error: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Isolated Dubbing Test')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Memory Leak Fix Tester',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'Use this minimal app to test the dubbing pipeline without compiling the entire Vayu UI.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            if (_isProcessing) 
               LinearProgressIndicator(value: _progress),
            const SizedBox(height: 16),
            Text(
              _status,
              style: TextStyle(
                color: _status.startsWith('Error') ? Colors.red : Colors.white
              ),
              textAlign: TextAlign.center,
            ),
            if (_resultPath != null) ...[
              const SizedBox(height: 16),
              const Text('Output File:', style: TextStyle(fontWeight: FontWeight.bold)),
              SelectableText(_resultPath!, style: const TextStyle(fontSize: 12)),
            ],
            const Spacer(),
            ElevatedButton(
              onPressed: _isProcessing ? null : _startTest,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Select Video & Run Test'),
            ),
          ],
        ),
      ),
    );
  }
}
