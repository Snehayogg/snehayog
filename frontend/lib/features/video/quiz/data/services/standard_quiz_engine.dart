import 'package:vayug/core/interfaces/i_quiz_engine.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/shared/utils/app_logger.dart';

/// **StandardQuizEngine**
/// Default pluggable quiz evaluator that monitors timestamps and tracks historical overlays in memory.
class StandardQuizEngine implements IQuizEngine {
  final Map<String, Set<String>> _shownQuizzes = {};
  final Map<String, List<QuizModel>> _quizHistory = {};

  @override
  QuizModel? evaluatePosition({
    required String videoId,
    required Duration currentPosition,
    required List<QuizModel> quizzes,
  }) {
    if (quizzes.isEmpty) return null;

    final currentMillis = currentPosition.inMilliseconds;
    final shown = _shownQuizzes[videoId] ??= {};

    for (final quiz in quizzes) {
      final key = '${quiz.question}_${quiz.timestamp}';
      if (shown.contains(key)) continue;

      final targetMillis = quiz.timestamp * 1000;
      final diff = currentMillis - targetMillis;

      // Trigger if player position is within 1.5s past the target timestamp
      if (diff >= 0 && diff < 1500) {
        return quiz;
      }
    }
    return null;
  }

  @override
  void markShown(String videoId, QuizModel quiz) {
    final key = '${quiz.question}_${quiz.timestamp}';
    (_shownQuizzes[videoId] ??= {}).add(key);
    (_quizHistory[videoId] ??= []).add(quiz);
    AppLogger.log('🎉 StandardQuizEngine: Triggered quiz "${quiz.question}"');
  }

  @override
  void submitAnswer(String videoId, QuizModel quiz, int optionIndex) {
    AppLogger.log('📝 StandardQuizEngine: Answer for "${quiz.question}" submitted: index $optionIndex');
  }

  @override
  List<QuizModel> getHistory(String videoId) {
    return _quizHistory[videoId] ?? [];
  }

  @override
  QuizModel? removeLastHistory(String videoId) {
    final history = _quizHistory[videoId];
    if (history != null && history.isNotEmpty) {
      final last = history.removeLast();
      final key = '${last.question}_${last.timestamp}';
      _shownQuizzes[videoId]?.remove(key);
      return last;
    }
    return null;
  }

  @override
  void reset(String videoId) {
    _shownQuizzes.remove(videoId);
    _quizHistory.remove(videoId);
    AppLogger.log('🧹 StandardQuizEngine: Reset quiz history for video $videoId');
  }
}
