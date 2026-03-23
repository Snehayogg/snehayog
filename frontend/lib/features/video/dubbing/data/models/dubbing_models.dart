/// Status of a dubbing job (shared between local and server-side logic)
enum DubbingStatus {
  idle,
  checking, // Checking if already dubbed / requesting
  queued,
  downloadingVideo,
  checkingContent, // Whisper speech pre-check
  extractingAudio,
  transcribing,
  translating,
  synthesizing,
  muxing,
  uploading,
  completed,
  notSuitable,
  failed,
}

class DubbingResult {
  final DubbingStatus status;
  final int progress; // 0–100
  final String? dubbedUrl;
  final String? language;
  final bool fromCache;
  final String? reason; // for notSuitable
  final String? error; // for failed

  const DubbingResult({
    required this.status,
    this.progress = 0,
    this.dubbedUrl,
    this.language,
    this.fromCache = false,
    this.reason,
    this.error,
  });

  bool get isDone =>
      status == DubbingStatus.completed ||
      status == DubbingStatus.notSuitable ||
      status == DubbingStatus.failed;

  String get statusLabel {
    switch (status) {
      case DubbingStatus.idle:
        return 'Smart Dub';
      case DubbingStatus.checking:
        return 'Checking...';
      case DubbingStatus.queued:
        return 'Starting...';
      case DubbingStatus.downloadingVideo:
        return 'Downloading...';
      case DubbingStatus.checkingContent:
        return 'Analysing...';
      case DubbingStatus.extractingAudio:
        return 'Processing audio...';
      case DubbingStatus.transcribing:
        return 'Transcribing...';
      case DubbingStatus.translating:
        return 'Translating...';
      case DubbingStatus.synthesizing:
        return 'Generating voice...';
      case DubbingStatus.muxing:
        return 'Finalizing...';
      case DubbingStatus.uploading:
        return 'Uploading...';
      case DubbingStatus.completed:
        return 'Play Dubbed';
      case DubbingStatus.notSuitable:
        return 'Not dub-able';
      case DubbingStatus.failed:
        return 'Failed';
    }
  }
}
