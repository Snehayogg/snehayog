import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
// import 'package:whisper_flutter_new/whisper_flutter_new.dart';
import 'package:vayug/features/video/dubbing/data/models/dubbing_models.dart';
import 'package:vayug/features/video/dubbing/data/services/translation_processor.dart';
import 'package:vayug/shared/utils/app_logger.dart';

/// Orchestrates the on-device dubbing process.
class OnDeviceDubbingService {
  final FlutterTts _tts = FlutterTts();
  // final Whisper _whisper = const Whisper(model: WhisperModel.base);
  late OnDeviceTranslator _translator;
  late TranslationProcessor _processor;
  
  String? _currentSource;
  String? _currentTarget;
  bool _initialized = false;
  final Map<String, bool> _cancellationTokens = {};

  void cancelDubbing(String videoUrl) {
    AppLogger.log('🛑 OnDeviceDubbing: Cancelling dubbing for $videoUrl');
    _cancellationTokens[videoUrl] = true;
    FFmpegKit.cancel(); // Best effort to cancel running FFmpeg sessions
  }

  Future<void> _init(String sourceLang, String targetLang) async {
    // Check if we need to re-initialize due to language change
    if (_initialized && _currentSource == sourceLang && _currentTarget == targetLang) {
      return;
    }
    
    AppLogger.log('🎬 OnDeviceDubbing: Initializing with Source: $sourceLang, Target: $targetLang');
    
    // Close old translator if exists
    if (_initialized) {
      _translator.close();
    }
    
    _translator = OnDeviceTranslator(
      sourceLanguage: _langToEnum(sourceLang == 'auto' ? 'english' : sourceLang), // Fallback to en if auto
      targetLanguage: _langToEnum(targetLang),
    );
    _processor = TranslationProcessor(_translator);
    
    // Configure TTS
    await _tts.setLanguage(targetLang == 'hindi' ? 'hi-IN' : 'en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    
    _currentSource = sourceLang;
    _currentTarget = targetLang;
    _initialized = true;
    
    // Advanced TTS debugging
    _tts.setErrorHandler((msg) {
      AppLogger.log('❌ OnDeviceDubbing: TTS background error: $msg');
    });
  }

  TranslateLanguage _langToEnum(String lang) {
    if (lang == 'hindi') return TranslateLanguage.hindi;
    return TranslateLanguage.english;
  }

  /// Starts the on-device dubbing for a video file (local or remote).
  Stream<DubbingResult> dubLocalVideo(String videoPath, {String targetLang = 'english'}) async* {
    _cancellationTokens[videoPath] = false;
    String effectivePath = videoPath;
    bool isRemote = videoPath.startsWith('http');
    bool isHls = videoPath.contains('.m3u8');
    
    if (isRemote) {
      if (isHls) {
        effectivePath = videoPath;
        AppLogger.log('🌐 OnDeviceDubbing: Using remote HLS URL directly: $effectivePath');
      } else {
        yield const DubbingResult(status: DubbingStatus.checking, progress: 5);
        try {
          final tempDir = await getTemporaryDirectory();
          effectivePath = p.join(tempDir.path, 'temp_video_${DateTime.now().millisecondsSinceEpoch}.mp4');
          AppLogger.log('🌐 OnDeviceDubbing: Downloading remote video to $effectivePath');
          
          final dio = Dio();
          dio.options.headers['User-Agent'] = 'Mozilla/5.0 (VayuApp; Android)';
          
          final response = await dio.download(videoPath, effectivePath);
          if (response.statusCode != 200) {
            throw Exception('Download failed with status: ${response.statusCode}');
          }
          
          final downloadedFile = File(effectivePath);
          if (!downloadedFile.existsSync() || downloadedFile.lengthSync() < 1000) {
            throw Exception('Downloaded file is too small or missing');
          }

          // Simple check for HTML instead of video
          final firstBytes = await downloadedFile.openRead(0, 100).first;
          final head = String.fromCharCodes(firstBytes).toLowerCase();
          if (head.contains('<!doctype html') || head.contains('<html')) {
             throw Exception('URL returned HTML instead of a video file. This might be a private video or require authentication.');
          }
          
          AppLogger.log('✅ OnDeviceDubbing: Download complete (${downloadedFile.lengthSync()} bytes)');
        } catch (e) {
          AppLogger.log('❌ OnDeviceDubbing: Download failed: $e');
          yield DubbingResult(status: DubbingStatus.failed, error: 'Download failed: $e');
          return;
        }
      }
    }

    if (!isRemote) {
      final videoFile = File(effectivePath);
      if (!videoFile.existsSync()) {
        yield const DubbingResult(status: DubbingStatus.failed, error: 'File not found');
        return;
      }
    }

    final tempBaseDir = await getTemporaryDirectory();
    
    // On Android, system TTS engine often cannot write to internal app cache.
    // We use external cache directory which is accessible by system services.
    Directory isolationBaseDir = tempBaseDir;
    if (Platform.isAndroid) {
      try {
        final externalDirs = await getExternalCacheDirectories();
        if (externalDirs != null && externalDirs.isNotEmpty) {
          isolationBaseDir = externalDirs.first;
          AppLogger.log('📂 OnDeviceDubbing: Using external cache for TTS: ${isolationBaseDir.path}');
        }
      } catch (e) {
        AppLogger.log('⚠️ OnDeviceDubbing: Failed to get external cache: $e');
      }
    }

    final dubbingTaskId = 'dub_${DateTime.now().microsecondsSinceEpoch}';
    final isolationDir = Directory(p.join(isolationBaseDir.path, dubbingTaskId));
    if (!isolationDir.existsSync()) await isolationDir.create(recursive: true);
    
    // We'll still give it a preferred name/path, but our discovery will be robust enough to find whatever is produced.
    final audioPath = p.join(isolationDir.path, 'extracted_audio.wav');
    
    final finalVideoPath = p.join(tempBaseDir.path, 'final_dubbed_${DateTime.now().millisecondsSinceEpoch}.mp4');

    try {
      yield const DubbingResult(status: DubbingStatus.extractingAudio, progress: 10);
      
      // 1. Extract & Clean Audio using FFmpeg
      AppLogger.log('🎬 OnDeviceDubbing: Extracting & Cleaning audio from $effectivePath');
      
      // Filter Chain:
      // - highpass/lowpass: Keep speech frequencies (80Hz-10kHz)
      // - afftdn: FFT-based noise reduction (stable & efficient)
      // - loudnorm: Integrated loudness normalization for clearer voice
      const filterChain = 'highpass=f=80,lowpass=f=10000,afftdn=nf=-25,loudnorm';
      
      final extractSession = await FFmpegKit.execute(
        '-y -i "$effectivePath" -af "$filterChain" -ac 1 -ar 16000 "$audioPath"'
      );
      final returnCode = await extractSession.getReturnCode();
      
      if (!ReturnCode.isSuccess(returnCode)) {
        final logs = await extractSession.getLogs();
        final lastLog = logs.isNotEmpty ? logs.last.getMessage() : 'No logs';
        AppLogger.log('❌ OnDeviceDubbing: Audio extraction/cleaning failed with code $returnCode. Last log: $lastLog');
        throw Exception('Audio extraction failed: $lastLog');
      }

      // 2. Transcribing & Checking Content
      if (_cancellationTokens[videoPath] == true) throw Exception('Cancelled by user');
      yield const DubbingResult(status: DubbingStatus.checkingContent, progress: 25);
      
      String fullTranscript = '';
      /*
      try {
        AppLogger.log('🎬 OnDeviceDubbing: Starting Whisper transcription...');
        final res = await _whisper.transcribe(
          transcribeRequest: TranscribeRequest(
            audio: audioPath,
          ),
        );
        fullTranscript = res.text.trim();
        AppLogger.log('📝 OnDeviceDubbing: Whisper Transcript: "$fullTranscript"');
      } catch (e) {
        AppLogger.log('❌ OnDeviceDubbing: Whisper transcription failed: $e');
        throw Exception('Transcription failed: $e');
      }
      */
      AppLogger.log('📝 OnDeviceDubbing: Whisper transcription is temporarily disabled for Play Store compliance.');
      
      // Validation Logic: Detect if the content is likely music, dance, or no-vocal
      // 1. Empty Transcript
      if (fullTranscript.isEmpty) {
        yield const DubbingResult(
          status: DubbingStatus.notSuitable, 
          reason: 'No vocal detected in the video'
        );
        return;
      }

      // 2. Noise/Music Markers (Improved recursive check)
      final musicRegex = RegExp(
        r'\[(music|muzak|laughter|silence|bgm|instrumental|noise|ambient|sounds)\]|\((music|muzak|laughter|silence)\)', 
        caseSensitive: false
      );
      
      // Clean transcript of markers to see if anything else remains
      final String cleanedOfMarkers = fullTranscript.replaceAll(musicRegex, '').trim();
      
      if (cleanedOfMarkers.isEmpty || (fullTranscript.contains(musicRegex) && cleanedOfMarkers.length < 5)) {
        yield const DubbingResult(
          status: DubbingStatus.notSuitable, 
          reason: 'Content appears to be primarily music, noise or instrumental'
        );
        return;
      }

      // 3. Speech Density & Hallucination Check
      // Whisper sometimes hallucinates long strings of nonsense for background noise (e.g. repeated scripts)
      // We check if the transcript has a suspiciously low word count or is just repeated characters
      final words = cleanedOfMarkers.split(RegExp(r'\s+')).where((w) => w.length > 1).toList();
      
      // If it's a 15s+ video but has < 3 words, it's probably not dub-worthy
      if (words.length < 3 && cleanedOfMarkers.length < 15) {
         yield const DubbingResult(
          status: DubbingStatus.notSuitable, 
          reason: 'Insufficient vocal content detected for dubbing'
        );
        return;
      }
      
      if (_cancellationTokens[videoPath] == true) throw Exception('Cancelled by user');
      
      // 3. Translate using Context-Based Processor (Detects source and swaps if targetLang is default)
      await _init('auto', targetLang); 
      final translationResult = await _processor.translateContextBlock(fullTranscript, targetLang: targetLang);
      final String translatedText = translationResult['text'] ?? '';
      final String finalTargetLang = translationResult['targetLang'] ?? targetLang;
      final bool isSuitableVal = translationResult['isSuitable'] == 'true';
      
      AppLogger.log('🔄 OnDeviceDubbing: Translation Result: $finalTargetLang (Suitable: $isSuitableVal)');
      AppLogger.log('📝 OnDeviceDubbing: Translated Text: "$translatedText"');

      if (!isSuitableVal || translatedText.trim().isEmpty) {
        yield DubbingResult(
          status: DubbingStatus.notSuitable, 
          reason: !isSuitableVal ? 'AI detected non-vocal or repetitive noise' : 'Translated text is empty'
        );
        return;
      }

      // Re-initialize TTS if the final target language is different
      if (finalTargetLang != targetLang) {
        await _tts.setLanguage(finalTargetLang == 'hindi' ? 'hi-IN' : 'en-US');
      }

      yield DubbingResult(status: DubbingStatus.synthesizing, progress: 75, language: finalTargetLang);
      
      if (_cancellationTokens[videoPath] == true) throw Exception('Cancelled by user');

      // 4. Synthesize using TTS
      AppLogger.log('🎙️ OnDeviceDubbing: Starting synthesis to isolation dir: ${isolationDir.path}');
      
      // Split text into chunks to avoid TTS character limits and improve stability
      // some engines have a 1000-4000 char limit.
      const int maxTtsLength = 1000;
      List<String> textChunks = [];
      String remainingText = translatedText;

      while (remainingText.length > maxTtsLength) {
        int splitIndex = remainingText.lastIndexOf(RegExp(r'[.!?] '), maxTtsLength);
        if (splitIndex == -1 || splitIndex == 0) {
          splitIndex = remainingText.lastIndexOf(' ', maxTtsLength);
        }
        if (splitIndex == -1 || splitIndex == 0) {
          splitIndex = maxTtsLength;
        } else {
          splitIndex += 1; // Include the punctuation or space
        }
        textChunks.add(remainingText.substring(0, splitIndex).trim());
        remainingText = remainingText.substring(splitIndex).trim();
      }
      if (remainingText.isNotEmpty) {
        textChunks.add(remainingText);
      }

      AppLogger.log('🎙️ OnDeviceDubbing: Split translated text into ${textChunks.length} chunks');

      List<String> chunkFilePaths = [];
      for (int i = 0; i < textChunks.length; i++) {
        if (_cancellationTokens[videoPath] == true) throw Exception('Cancelled by user');
        
        final chunkText = textChunks[i];
        final expectedChunkName = 'synthesized_chunk_$i.wav';
        
        // Android TTS behaves poorly with absolute paths and puts files in public/external dirs.
        // We pass just a filename so we can track it reliably.
        final String ttsInputPath = Platform.isAndroid 
            ? 'vayu_dub_${dubbingTaskId}_chunk_$i.wav' 
            : p.join(isolationDir.path, expectedChunkName);
            
        final startTime = DateTime.now();
        final int result = await _tts.synthesizeToFile(chunkText, ttsInputPath);
        
        if (result == 0) {
          AppLogger.log('❌ OnDeviceDubbing: synthesizeToFile returned failure (0) for chunk $i');
        }
        
        AppLogger.log('🎙️ OnDeviceDubbing: Synthesis started for chunk $i...');
        
        int retries = 0;
        bool chunkSuccess = false;
        String? foundActualPath;
        
        while (retries < 120) { // Max 60 seconds per chunk
          await Future.delayed(const Duration(milliseconds: 500));
          try {
            List<Directory> dirsToCheck = [isolationDir];
            if (Platform.isAndroid) {
              try {
                // Check common external directories where flutter_tts might output
                final extDirs = await getExternalStorageDirectories();
                if (extDirs != null) dirsToCheck.addAll(extDirs);
                
                // Add specific typed directories
                try {
                  final musicDirs = await getExternalStorageDirectories(type: StorageDirectory.music);
                  if (musicDirs != null) dirsToCheck.addAll(musicDirs);
                } catch (_) {}
                
                try {
                  final dlDirs = await getExternalStorageDirectories(type: StorageDirectory.downloads);
                  if (dlDirs != null) dirsToCheck.addAll(dlDirs);
                } catch (_) {}
                
                final extDir = await getExternalStorageDirectory();
                if (extDir != null) {
                  dirsToCheck.add(extDir);
                  dirsToCheck.add(Directory(p.join(extDir.path, 'Music')));
                  dirsToCheck.add(Directory(p.join(extDir.path, 'Download')));
                  // Public Download directory
                  final parentPath = extDir.parent.parent.parent.parent.path;
                  dirsToCheck.add(Directory(p.join(parentPath, 'Download')));
                  dirsToCheck.add(Directory(p.join(parentPath, 'Music')));
                }
                
                final cacheDirs = await getExternalCacheDirectories();
                if (cacheDirs != null) dirsToCheck.addAll(cacheDirs);
              } catch (_) {}
            }

            File? newestFile;
            for (final dir in dirsToCheck) {
              if (dir.existsSync()) {
                final files = dir.listSync().whereType<File>().toList();
                for (final file in files) {
                   final baseName = p.basename(file.path);
                   if (baseName == 'extracted_audio.wav' || baseName.startsWith('final_chunk_') || baseName.startsWith('concat')) continue;
                   
                   // On Android, only match our specific filename to avoid picking up arbitrary files
                   if (Platform.isAndroid && baseName != ttsInputPath) continue;

                   if (file.existsSync() && file.lengthSync() > 100) {
                     final modTime = file.lastModifiedSync();
                     if (modTime.isAfter(startTime.subtract(const Duration(seconds: 1)))) {
                        if (newestFile == null || modTime.isAfter(newestFile.lastModifiedSync())) {
                          newestFile = file;
                        }
                     }
                   }
                }
              }
            }

            if (newestFile != null) {
               final sizeBefore = newestFile.lengthSync();
               await Future.delayed(const Duration(milliseconds: 300));
               final sizeAfter = newestFile.lengthSync();
               
               if (sizeBefore == sizeAfter && sizeAfter > 500) {
                  foundActualPath = newestFile.path;
                  chunkSuccess = true;
                  break;
               }
            }
          } catch (e) {
            AppLogger.log('⚠️ OnDeviceDubbing: Discovery error on chunk $i: $e');
          }
          retries++;
        }
        
        if (!chunkSuccess || foundActualPath == null) {
            throw Exception('Synthesized audio chunk $i is missing or empty after waiting 60s');
        }
        
        // Move found file to a definitive chunk name so it's not picked up by next chunk
        final definiteChunkPath = p.join(isolationDir.path, 'final_chunk_$i.wav');
        try {
          File(foundActualPath).renameSync(definiteChunkPath);
        } catch (e) {
          // Fallback if renaming across partitions fails (Cross-device link)
          File(foundActualPath).copySync(definiteChunkPath);
          File(foundActualPath).deleteSync();
        }
        chunkFilePaths.add(definiteChunkPath);
        AppLogger.log('✅ OnDeviceDubbing: Successfully synthesized chunk $i to $definiteChunkPath');
      }

      String actualOutputFilePath;
      if (chunkFilePaths.length == 1) {
        actualOutputFilePath = chunkFilePaths.first;
      } else {
        final concatListPath = p.join(isolationDir.path, 'concat.txt');
        final concatFile = File(concatListPath);
        String concatContent = '';
        for (final path in chunkFilePaths) {
           final escapedPath = p.basename(path).replaceAll("'", "'\\''");
           concatContent += "file '$escapedPath'\n";
        }
        concatFile.writeAsStringSync(concatContent);
        
        actualOutputFilePath = p.join(isolationDir.path, 'combined_synthesized.wav');
        final concatSession = await FFmpegKit.execute('-f concat -safe 0 -i "$concatListPath" -c copy "$actualOutputFilePath"');
        if (!ReturnCode.isSuccess(await concatSession.getReturnCode())) {
            throw Exception('Failed to concatenate audio chunks');
        }
        AppLogger.log('✅ OnDeviceDubbing: Successfully concatenated ${chunkFilePaths.length} chunks');
      }

      if (_cancellationTokens[videoPath] == true) throw Exception('Cancelled by user');
      yield const DubbingResult(status: DubbingStatus.muxing, progress: 90);
      
      // 5. Mux Video + New Audio
      if (!File(actualOutputFilePath).existsSync() || File(actualOutputFilePath).lengthSync() == 0) {
        throw Exception('Synthesized audio file is missing or empty');
      }

      AppLogger.log('🎬 OnDeviceDubbing: Muxing audio/video into $finalVideoPath');
      // Using -c:a aac for better MP4 compatibility (+ -y to overwrite)
      final muxSession = await FFmpegKit.execute(
        '-y -i "$effectivePath" -i "$actualOutputFilePath" -c:v copy -c:a aac -map 0:v:0 -map 1:a:0 -shortest "$finalVideoPath"'
      );
      
      final muxReturnCode = await muxSession.getReturnCode();
      if (ReturnCode.isSuccess(muxReturnCode)) {
        yield DubbingResult(
          status: DubbingStatus.completed,
          progress: 100,
          dubbedUrl: finalVideoPath, // Local path
          language: finalTargetLang,
        );
      } else {
        final logs = await muxSession.getLogs();
        final lastLog = logs.isNotEmpty ? logs.last.getMessage() : 'No logs';
        AppLogger.log('❌ OnDeviceDubbing: Muxing failed with code $muxReturnCode. Last log: $lastLog');
        throw Exception('Muxing failed: $lastLog');
      }

    } catch (e) {
      AppLogger.log('❌ OnDeviceDubbing: Error: $e');
      yield DubbingResult(status: DubbingStatus.failed, error: e.toString());
    } finally {
      // Isolation cleanup
      try { 
        if (isolationDir.existsSync()) {
          isolationDir.deleteSync(recursive: true);
          AppLogger.log('🧹 OnDeviceDubbing: Cleaned isolation directory');
        }
        if (isRemote && File(effectivePath).existsSync()) {
          File(effectivePath).deleteSync();
        }
      } catch (e) {
        AppLogger.log('⚠️ OnDeviceDubbing: Cleanup error: $e');
      }
    }
  }
}

