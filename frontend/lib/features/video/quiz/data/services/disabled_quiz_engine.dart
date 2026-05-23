import 'package:vayug/core/interfaces/i_quiz_engine.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';

/// **DisabledQuizEngine**
/// Plug-and-play quiz engine that blocks interactive quiz overlays from appearing.
class DisabledQuizEngine implements IQuizEngine {
  @override
  QuizModel? evaluatePosition({
    required String videoId,
    required Duration currentPosition,
    required List<QuizModel> quizzes,
  }) => null;

  @override
  void markShown(String videoId, QuizModel quiz) {}

  @override
  void submitAnswer(String videoId, QuizModel quiz, int optionIndex) {}

  @override
  List<QuizModel> getHistory(String videoId) => const [];

  @override
  QuizModel? removeLastHistory(String videoId) => null;

  @override
  void reset(String videoId) {}
}
