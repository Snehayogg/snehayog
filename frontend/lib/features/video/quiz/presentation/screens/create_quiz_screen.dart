import 'package:flutter/material.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/shared/widgets/app_button.dart';
import 'package:hugeicons/hugeicons.dart';

class CreateQuizScreen extends StatefulWidget {
  final List<QuizModel> initialQuizzes;
  final double videoDurationInSeconds;

  const CreateQuizScreen({
    super.key,
    required this.initialQuizzes,
    required this.videoDurationInSeconds,
  });

  @override
  State<CreateQuizScreen> createState() => _CreateQuizScreenState();
}

class _CreateQuizScreenState extends State<CreateQuizScreen> {
  late List<QuizModel> _quizzes;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _quizzes = List.from(widget.initialQuizzes);
  }

  void _addQuiz() {
    // Density check: 1 quiz per 5 seconds
    final maxAllowedCount = (widget.videoDurationInSeconds / 5).floor().clamp(1, 99);
    
    if (_quizzes.length >= maxAllowedCount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Maximum density reached (${maxAllowedCount} quizzes for this video length).'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() {
      _quizzes.add(QuizModel(
        timestamp: widget.videoDurationInSeconds > 10 ? 10 : widget.videoDurationInSeconds / 2,
        question: '',
        options: ['', ''],
        correctIndex: 0,
      ));
    });
    
    // Scroll to bottom after adding
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _removeQuiz(int index) {
    setState(() {
      _quizzes.removeAt(index);
    });
  }

  void _updateQuiz(int index, QuizModel updated) {
    setState(() {
      _quizzes[index] = updated;
    });
  }

  void _saveAndExit() {
    // Basic validation
    for (int i = 0; i < _quizzes.length; i++) {
      final q = _quizzes[i];
      if (q.question.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please enter a question for Quiz #${i + 1}')),
        );
        return;
      }
      if (q.options.any((opt) => opt.trim().isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('All options in Quiz #${i + 1} must be filled')),
        );
        return;
      }
    }

    Navigator.pop(context, _quizzes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        title: const Text('Manage Quizzes', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.backgroundPrimary,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _saveAndExit,
            child: const Text('SAVE', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildInfoBanner(),
          Expanded(
            child: _quizzes.isEmpty ? _buildEmptyState() : _buildQuizList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addQuiz,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('Add Quiz', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Interactive quizzes appear at specific times to engage your audience. You can add up to 1 quiz per 5 seconds.',
              style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.backgroundSecondary.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: HugeIcon(icon: HugeIcons.strokeRoundedHelpCircle, size: 64, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 16),
          Text(
            'No quizzes added yet',
            style: AppTypography.titleMedium.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            'Keep your viewers engaged with short questions.',
            style: AppTypography.bodySmall.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildQuizList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: _quizzes.length,
      itemBuilder: (context, index) {
        return _QuizItemEditor(
          key: ValueKey('quiz_$index'),
          quiz: _quizzes[index],
          index: index,
          maxDuration: widget.videoDurationInSeconds,
          onChanged: (updated) => _updateQuiz(index, updated),
          onRemove: () => _removeQuiz(index),
        );
      },
    );
  }
}

class _QuizItemEditor extends StatefulWidget {
  final QuizModel quiz;
  final int index;
  final double maxDuration;
  final Function(QuizModel) onChanged;
  final VoidCallback onRemove;

  const _QuizItemEditor({
    super.key,
    required this.quiz,
    required this.index,
    required this.maxDuration,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  State<_QuizItemEditor> createState() => _QuizItemEditorState();
}

class _QuizItemEditorState extends State<_QuizItemEditor> {
  late TextEditingController _questionController;
  late TextEditingController _timeController;
  late List<TextEditingController> _optionControllers;
  bool _isExpanded = true;

  @override
  void initState() {
    super.initState();
    _questionController = TextEditingController(text: widget.quiz.question);
    _timeController = TextEditingController(text: widget.quiz.timestamp.toStringAsFixed(1));
    _optionControllers = widget.quiz.options
        .map((opt) => TextEditingController(text: opt))
        .toList();
    
    // Auto-collapse if it's not the first one and has content
    if (widget.index > 0 && widget.quiz.question.isNotEmpty) {
      _isExpanded = false;
    }
  }

  @override
  void dispose() {
    _questionController.dispose();
    _timeController.dispose();
    for (var c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _updateTimeFromText() {
    final val = double.tryParse(_timeController.text);
    if (val != null) {
      final clamped = val.clamp(0.0, widget.maxDuration);
      widget.onChanged(widget.quiz.copyWith(timestamp: clamped));
      // Update text field if it was clamped
      if (clamped != val) {
        _timeController.text = clamped.toStringAsFixed(1);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderPrimary.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'QUIZ ${widget.index + 1}',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      _isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: AppColors.textTertiary,
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 22),
                  onPressed: widget.onRemove,
                ),
              ],
            ),
          ),
          if (_isExpanded) ...[
            const SizedBox(height: 16),
          
          // Question Input
          Text('Question', style: AppTypography.labelSmall.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _questionController,
            onChanged: (val) => widget.onChanged(widget.quiz.copyWith(question: val)),
            decoration: InputDecoration(
              hintText: 'e.g. What is the main message?',
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.5),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Timestamp Section (Slider + Text)
          Row(
            children: [
              Text('Show at (seconds)', style: AppTypography.labelSmall.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              SizedBox(
                width: 60,
                child: TextField(
                  controller: _timeController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  onSubmitted: (_) => _updateTimeFromText(),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: AppColors.primary.withValues(alpha: 0.1),
              thumbColor: AppColors.primary,
              overlayColor: AppColors.primary.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: widget.quiz.timestamp.clamp(0.0, widget.maxDuration),
              min: 0,
              max: widget.maxDuration > 0 ? widget.maxDuration : 1.0,
              onChanged: (val) {
                widget.onChanged(widget.quiz.copyWith(timestamp: val));
                _timeController.text = val.toStringAsFixed(1);
              },
            ),
          ),

          const SizedBox(height: 16),
          
          // Options
          Text('Options (Select correct one)', style: AppTypography.labelSmall.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...List.generate(widget.quiz.options.length, (optIndex) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Radio<int>(
                    value: optIndex,
                    groupValue: widget.quiz.correctIndex,
                    activeColor: AppColors.primary,
                    onChanged: (val) {
                      if (val != null) widget.onChanged(widget.quiz.copyWith(correctIndex: val));
                    },
                  ),
                  Expanded(
                    child: TextField(
                      controller: _optionControllers[optIndex],
                      onChanged: (val) {
                        final newOptions = List<String>.from(widget.quiz.options);
                        newOptions[optIndex] = val;
                        widget.onChanged(widget.quiz.copyWith(options: newOptions));
                      },
                      decoration: InputDecoration(
                        hintText: 'Option ${optIndex + 1}',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  if (widget.quiz.options.length > 2)
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 20, color: AppColors.textTertiary),
                      onPressed: () {
                        setState(() {
                          _optionControllers.removeAt(optIndex);
                        });
                        final newOptions = List<String>.from(widget.quiz.options);
                        newOptions.removeAt(optIndex);
                        widget.onChanged(widget.quiz.copyWith(
                          options: newOptions,
                          correctIndex: widget.quiz.correctIndex >= newOptions.length ? 0 : widget.quiz.correctIndex,
                        ));
                      },
                    ),
                ],
              ),
            );
          }),
          
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _optionControllers.add(TextEditingController());
                });
                final newOptions = List<String>.from(widget.quiz.options)..add('');
                widget.onChanged(widget.quiz.copyWith(options: newOptions));
              },
              icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
              label: const Text('Add Option', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            ),
          ],
        ],
      ),
    );
  }
}
