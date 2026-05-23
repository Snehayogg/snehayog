import 'package:vayug/features/video/core/data/models/video_model.dart';

/// **IQuizEngine**
/// Decoupled interface for interactive quiz overlay tracking and state management.
abstract class IQuizEngine {
  /// Evaluates if a quiz should be shown based on the current playback position.
  QuizModel? evaluatePosition({
    required String videoId,
    required Duration currentPosition,
    required List<QuizModel> quizzes,
  });

  /// Marks a quiz as shown so it does not trigger multiple times.
  void markShown(String videoId, QuizModel quiz);

  /// Registers the answer selected by the user.
  void submitAnswer(String videoId, QuizModel quiz, int optionIndex);

  /// Returns the history of active/shown quizzes for a video.
  List<QuizModel> getHistory(String videoId);

  /// Removes the last quiz from the history (useful for backtrack/dismiss options).
  QuizModel? removeLastHistory(String videoId);

  /// Resets the quiz tracking state/history for a video (e.g. on replay).
  void reset(String videoId);
}
