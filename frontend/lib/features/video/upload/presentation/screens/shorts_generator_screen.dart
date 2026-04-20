import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/shared/services/file_picker_service.dart';
import 'package:vayug/shared/services/http_client_service.dart';
import 'package:vayug/shared/widgets/app_button.dart';
import 'package:vayug/shared/widgets/vayu_snackbar.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayug/core/design/typography.dart';

class ShortsGeneratorScreen extends ConsumerStatefulWidget {
  const ShortsGeneratorScreen({super.key});

  @override
  ConsumerState<ShortsGeneratorScreen> createState() => _ShortsGeneratorScreenState();
}

class _ShortsGeneratorScreenState extends ConsumerState<ShortsGeneratorScreen> {
  File? _selectedFile;
  bool _isProcessing = false;
  double _uploadProgress = 0;
  String? _jobId;
  String? _clipUrl;
  String _status = 'idle'; // idle, uploading, processing, completed, failed
  
  final TextEditingController _startTimeController = TextEditingController(text: "");
  final TextEditingController _durationController = TextEditingController(text: "40");
  bool _useRandomTime = true;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  @override
  void dispose() {
    _startTimeController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  /// **NEW: Load state from storage on entry**
  Future<void> _loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedJobId = prefs.getString('magician_job_id');
      final savedStatus = prefs.getString('magician_status') ?? 'idle';
      final savedClipUrl = prefs.getString('magician_clip_url');

      if (savedJobId != null) {
        setState(() {
          _jobId = savedJobId;
          _status = savedStatus;
          _clipUrl = savedClipUrl;
          if (_status == 'processing') {
             _isProcessing = true;
          }
        });

        // Resume listener if still processing
        if (_status == 'processing' || _status == 'failed') {
          // Check one-time verify manually in case notification was clicked
          _checkStatusOneTime();
          _listenToSSE();
        }
      }
    } catch (e) {
      AppLogger.log("⚠️ Error loading magician state: $e");
    }
  }

  /// **NEW: Save current state to storage**
  Future<void> _saveState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_jobId != null) {
        await prefs.setString('magician_job_id', _jobId!);
        await prefs.setString('magician_status', _status);
        if (_clipUrl != null) {
          await prefs.setString('magician_clip_url', _clipUrl!);
        }
      }
    } catch (e) {
      AppLogger.log("⚠️ Error saving magician state: $e");
    }
  }

  /// **NEW: Clear state from storage**
  Future<void> _clearState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('magician_job_id');
      await prefs.remove('magician_status');
      await prefs.remove('magician_clip_url');
    } catch (e) {}
  }

  Future<void> _pickVideo() async {
    try {
      final result = await ref.read(filePickerServiceProvider).pickFiles(
        type: FileType.video,
      );
      
      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedFile = File(result.files.single.path!);
          _clipUrl = null;
          _status = 'idle';
        });
      }
    } catch (e) {
      AppLogger.log("❌ Error picking video: $e");
    }
  }

  Future<void> _startGeneration() async {
    if (_selectedFile == null) return;

    setState(() {
      _isProcessing = true;
      _status = 'uploading';
      _uploadProgress = 0;
    });

    try {
      final dio = HttpClientService.instance.dioClient;
      
      // 1. Get Presigned URL
      final presignedRes = await dio.post('/api/videos/clipping/presigned', data: {
        'fileName': _selectedFile!.path.split('/').last,
        'fileType': 'video/mp4', // Simplification
      });
      
      final uploadUrl = presignedRes.data['uploadUrl'];
      final tempKey = presignedRes.data['key'];

      // 2. Upload to R2
      final r2Dio = Dio();
      await r2Dio.put(
        uploadUrl,
        data: _selectedFile!.openRead(),
        options: Options(headers: {
          'Content-Type': 'video/mp4',
          'Content-Length': await _selectedFile!.length(),
        }),
        onSendProgress: (sent, total) {
          setState(() => _uploadProgress = sent / total);
        },
      );

      setState(() => _status = 'processing');

      // 3. Trigger Processing
      final processRes = await dio.post(
        '/api/videos/clipping/process', 
        data: {
          'tempKey': tempKey,
          'startTime': _useRandomTime ? 'random' : (double.tryParse(_startTimeController.text) ?? 0),
          'duration': double.tryParse(_durationController.text) ?? 40,
          'videoName': 'Generated Short'
        },
        options: Options(
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );

      _jobId = processRes.data['jobId'];
      await _saveState();

      // 4. Use SSE Stream instead of polling
      _listenToSSE();

    } catch (e) {
      AppLogger.log("❌ Clipping Error: $e");
      setState(() {
        _isProcessing = false;
        _status = 'failed';
      });
      if (!mounted) return;
      VayuSnackBar.showError(context, "Failed to process video: $e");
    }
  }

  /// **NEW: SSE Stream Listener**
  /// Replaces the old 3s polling mechanism with a real-time push connection
  void _listenToSSE() {
    if (_jobId == null) return;
    
    final sseStream = HttpClientService.instance.stream('/api/videos/clipping/stream/$_jobId');
    
    // Safety timer: if we don't get an update from SSE in 10s, start backup polling
    Timer? backupPolling;
    
    sseStream.listen((line) {
      if (!mounted) return;
      
      // SSE lines starting with 'data: ' contain our JSON payload
      if (line.startsWith('data: ')) {
        try {
          final jsonData = jsonDecode(line.substring(6));
          final status = jsonData['status'];
          
          AppLogger.log("📡 SSE Update: Status = $status");

          // Stop backup polling if SSE is working
          backupPolling?.cancel();

          if (status == 'completed') {
            setState(() {
              _status = 'completed';
              _isProcessing = false;
              _clipUrl = jsonData['clipUrl'];
            });
            _saveState(); // Save completion state
            VayuSnackBar.showSuccess(context, "Magic Short is ready! ✨");
          } else if (status == 'failed') {
            setState(() {
              _status = 'failed';
              _isProcessing = false;
            });
            _clearState();
            VayuSnackBar.showError(context, "Clipping failed: ${jsonData['error']}");
          }
        } catch (e) {
          AppLogger.log("⚠️ SSE Parse Error: $e");
        }
      }
    }, onError: (error) {
      AppLogger.log("❌ SSE Stream Error: $error");
      backupPolling?.cancel();
      _checkStatusOneTime();
    });

    // Start 10s safety delay for backup polling
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted && _isProcessing && _status == 'processing') {
        AppLogger.log("🕒 SSE safety delay reached. Starting backup polling...");
        backupPolling = Timer.periodic(const Duration(seconds: 5), (timer) {
          if (!mounted || !_isProcessing || _status == 'completed') {
            timer.cancel();
            return;
          }
          _checkStatusOneTime();
        });
      }
    });
  }

  /// Fallback status check if SSE stream disconnects
  Future<void> _checkStatusOneTime() async {
    if (_jobId == null || !mounted) return;
    try {
      final res = await HttpClientService.instance.dioClient.get('/api/videos/clipping/status/$_jobId');
      final status = res.data['status'];
      
      AppLogger.log("🔍 Manual Status Check: $status");

      if (status == 'completed') {
        setState(() {
          _status = 'completed';
          _isProcessing = false;
          _clipUrl = res.data['clipUrl'];
        });
        _saveState();
      } else if (status == 'failed') {
        setState(() {
          _status = 'failed';
          _isProcessing = false;
        });
        _saveState();
      }
    } catch (_) {}
  }

  Future<void> _downloadClip() async {
    if (_clipUrl == null) return;
    
    VayuSnackBar.showInfo(context, "Downloading to gallery...");
    
    try {
      final tempDir = await getTemporaryDirectory();
      final path = '${tempDir.path}/short_video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      
      await Dio().download(_clipUrl!, path);
      
      await Gal.putVideo(path);
      VayuSnackBar.showSuccess(context, "Video saved to Gallery! ✅");
    } catch (e) {
      if (!mounted) return;
      VayuSnackBar.showError(context, "Download failed: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("Shorts Magician ✨", style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 32),
            _buildFileSelector(),
            if (_selectedFile != null) ...[
              const SizedBox(height: 32),
              _buildOptions(),
              const SizedBox(height: 40),
              _buildActionButtons(),
            ],
            const SizedBox(height: 40),
            if (_isProcessing) ...[
              _buildProgressIndicator(),
              const SizedBox(height: 24),
              _buildProcessingNote(),
            ],
            if (_status == 'completed' && _clipUrl != null) _buildResultView(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Create Professional Shorts from Gallery",
          style: AppTypography.headlineMedium.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text(
          "Upload any long video and we'll transform it into a vertical short with a cinematic blurry background.",
          style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildFileSelector() {
    return GestureDetector(
      onTap: _isProcessing ? null : _pickVideo,
      child: Container(
        width: double.infinity,
        height: 180,
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: _selectedFile != null ? AppColors.primary : AppColors.borderPrimary,
            width: 2,
            style: BorderStyle.solid,
          ),
        ),
        child: _selectedFile == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.video_collection_outlined, size: 48, color: AppColors.primary),
                  const SizedBox(height: 16),
                  Text("Tap to pick from Gallery", style: AppTypography.titleMedium),
                  const SizedBox(height: 4),
                  Text("Supports MP4, MOV up to 500MB", style: AppTypography.labelSmall.copyWith(color: AppColors.textSecondary)),
                ],
              )
            : Stack(
                children: [
                  const Center(child: Icon(Icons.check_circle, size: 64, color: AppColors.primary)),
                  Positioned(
                    bottom: 16,
                    left: 0,
                    right: 0,
                    child: Text(
                      _selectedFile!.path.split('/').last,
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.grey),
                      onPressed: () => setState(() => _selectedFile = null),
                    ),
                  )
                ],
              ),
      ),
    );
  }

  Widget _buildOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("Clipping Options", style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold)),
            Row(
              children: [
                Text("Random Clip", style: AppTypography.labelMedium),
                Switch(
                  value: _useRandomTime,
                  activeThumbColor: AppColors.primary,
                  onChanged: (val) => setState(() => _useRandomTime = val),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            if (!_useRandomTime) ...[
              Expanded(
                child: _buildInput(
                  label: "Start Time (s)",
                  controller: _startTimeController,
                  enabled: true,
                  hint: "0",
                ),
              ),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: _buildInput(
                label: "Duration (s)",
                controller: _durationController,
                enabled: true,
                hint: "40",
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInput({required String label, required TextEditingController controller, bool enabled = true, String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.labelSmall.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          enabled: enabled,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: enabled ? AppColors.backgroundSecondary : Colors.grey.withValues(alpha: 0.1),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    if (_status == 'failed' && _jobId != null) {
      return Column(
        children: [
          const Text("Something went wrong, but your video might still be processing.", 
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.redAccent, fontSize: 13)
          ),
          const SizedBox(height: 12),
          AppButton(
            onPressed: _checkStatusOneTime,
            label: "Check Progress Again",
            variant: AppButtonVariant.secondary,
            isFullWidth: true,
          ),
          const SizedBox(height: 12),
          TextButton(
             onPressed: () => setState(() => _status = 'idle'),
             child: const Text("Start Over", style: TextStyle(color: AppColors.textSecondary)),
          )
        ],
      );
    }
    
    return AppButton(
      onPressed: _isProcessing ? null : _startGeneration,
      label: "Create Short Videos",
      variant: AppButtonVariant.primary,
      isFullWidth: true,
      size: AppButtonSize.large,
    );
  }

  Widget _buildProgressIndicator() {
    return Column(
      children: [
        Text(
          _status == 'uploading' ? "Uploading to Cloud..." : "Processing vertical AI magic...",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        LinearProgressIndicator(
          value: _status == 'uploading' ? _uploadProgress : null,
          backgroundColor: AppColors.borderPrimary,
          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
        ),
        const SizedBox(height: 12),
        if (_status == 'uploading')
          Text("${(_uploadProgress * 100).toStringAsFixed(0)}%", style: AppTypography.labelSmall),
      ],
    );
  }

  Widget _buildProcessingNote() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderPrimary.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.notifications_active_outlined, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "You will be notified once your shorts is ready. You can safely close the app or switch screens.",
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultView() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Icon(Icons.auto_awesome, size: 48, color: AppColors.success),
          const SizedBox(height: 16),
          const Text("Your Short is Ready!", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          AppButton(
            onPressed: _downloadClip,
            label: "Download to Gallery",
            variant: AppButtonVariant.primary,
            icon: const Icon(Icons.download),
            isFullWidth: true,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () {
              setState(() {
                _selectedFile = null;
                _clipUrl = null;
                _status = 'idle';
                _jobId = null;
              });
              _clearState();
            },
            child: const Text("Create Another Short", style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }
}
