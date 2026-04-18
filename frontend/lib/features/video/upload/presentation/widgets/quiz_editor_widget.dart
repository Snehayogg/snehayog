import 'package:flutter/material.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';

class QuizEditorWidget extends StatefulWidget {
  final List<QuizModel>? initialQuizzes;
  final Function(List<QuizModel>) onQuizzesChanged;
  final double videoDurationInSeconds;

  const QuizEditorWidget({
    super.key,
    this.initialQuizzes,
    required this.onQuizzesChanged,
    required this.videoDurationInSeconds,
  });

  @override
  State<QuizEditorWidget> createState() => _QuizEditorWidgetState();
}

class _QuizEditorWidgetState extends State<QuizEditorWidget> {
  late List<QuizModel> _quizzes;

  @override
  void initState() {
    super.initState();
    _quizzes = widget.initialQuizzes != null ? List.from(widget.initialQuizzes!) : [];
  }

  void _addQuiz() {
    setState(() {
      _quizzes.add(QuizModel(
        timestamp: widget.videoDurationInSeconds > 10 ? 10 : widget.videoDurationInSeconds / 2,
        question: '',
        options: ['', ''],
        correctIndex: 0,
      ));
    });
    widget.onQuizzesChanged(_quizzes);
  }

  void _removeQuiz(int index) {
    setState(() {
      _quizzes.removeAt(index);
    });
    widget.onQuizzesChanged(_quizzes);
  }

  void _updateQuiz(int index, QuizModel updated) {
    setState(() {
      _quizzes[index] = updated;
    });
    widget.onQuizzesChanged(_quizzes);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Interactive Quizzes',
              style: TextStyle(
                fontSize: AppTypography.fontSizeBase,
                fontWeight: AppTypography.weightSemiBold,
                color: AppColors.textPrimary,
              ),
            ),
            TextButton.icon(
              onPressed: _addQuiz,
              icon: const Icon(Icons.add_circle_outline, size: 20),
              label: const Text('Add Quiz'),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            ),
          ],
        ),
        if (_quizzes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text(
                'Add a quiz to engage your viewers!',
                style: TextStyle(
                  color: AppColors.textSecondary.withValues(alpha: 0.6),
                  fontSize: AppTypography.fontSizeSM,
                ),
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _quizzes.length,
            separatorBuilder: (context, index) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              return _QuizItemEditor(
                quiz: _quizzes[index],
                maxDuration: widget.videoDurationInSeconds,
                onChanged: (updated) => _updateQuiz(index, updated),
                onRemove: () => _removeQuiz(index),
                index: index,
              );
            },
          ),
      ],
    );
  }
}

class _QuizItemEditor extends StatelessWidget {
  final QuizModel quiz;
  final double maxDuration;
  final Function(QuizModel) onChanged;
  final VoidCallback onRemove;
  final int index;

  const _QuizItemEditor({
    required this.quiz,
    required this.maxDuration,
    required this.onChanged,
    required this.onRemove,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderPrimary.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Quiz #${index + 1}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          // Timestamp Slider
          Text(
            'Appears at: ${quiz.timestamp.toStringAsFixed(1)}s',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: quiz.timestamp.clamp(0.0, maxDuration),
              min: 0,
              max: maxDuration > 0 ? maxDuration : 1.0,
              onChanged: (val) {
                onChanged(quiz.copyWith(timestamp: val));
              },
            ),
          ),

          // Question Text
          TextField(
            onChanged: (val) => onChanged(quiz.copyWith(question: val)),
            controller: TextEditingController(text: quiz.question)..selection = TextSelection.fromPosition(TextPosition(offset: quiz.question.length)),
            decoration: const InputDecoration(
              hintText: 'Enter question...',
              isDense: true,
              border: UnderlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),

          // Options
          const Text('Options (select correct one):', style: TextStyle(fontSize: 11)),
          const SizedBox(height: 8),
          ...List.generate(quiz.options.length, (optIndex) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                children: [
                  Radio<int>(
                    value: optIndex,
                    groupValue: quiz.correctIndex,
                    activeColor: AppColors.primary,
                    onChanged: (val) {
                      if (val != null) onChanged(quiz.copyWith(correctIndex: val));
                    },
                  ),
                  Expanded(
                    child: TextField(
                      onChanged: (val) {
                        final newOptions = List<String>.from(quiz.options);
                        newOptions[optIndex] = val;
                        onChanged(quiz.copyWith(options: newOptions));
                      },
                      controller: TextEditingController(text: quiz.options[optIndex])..selection = TextSelection.fromPosition(TextPosition(offset: quiz.options[optIndex].length)),
                      decoration: InputDecoration(
                        hintText: 'Option ${optIndex + 1}',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                  if (quiz.options.length > 2)
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 16),
                      onPressed: () {
                        final newOptions = List<String>.from(quiz.options);
                        newOptions.removeAt(optIndex);
                        onChanged(quiz.copyWith(
                          options: newOptions,
                          correctIndex: quiz.correctIndex >= newOptions.length ? 0 : quiz.correctIndex,
                        ));
                      },
                    ),
                ],
              ),
            );
          }),
          if (quiz.options.length < 4)
            TextButton.icon(
              onPressed: () {
                final newOptions = List<String>.from(quiz.options)..add('');
                onChanged(quiz.copyWith(options: newOptions));
              },
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Add Option', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
