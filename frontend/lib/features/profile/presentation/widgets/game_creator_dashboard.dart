import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vayu/features/profile/presentation/managers/game_creator_manager.dart';
import 'package:vayu/features/games/data/game_model.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:vayu/shared/theme/app_theme.dart';

class GameCreatorDashboard extends StatefulWidget {
  const GameCreatorDashboard({super.key});

  @override
  State<GameCreatorDashboard> createState() => _GameCreatorDashboardState();
}

class _GameCreatorDashboardState extends State<GameCreatorDashboard> {
  @override
  Widget build(BuildContext context) {
    return Consumer<GameCreatorManager>(
      builder: (context, gameManager, child) {
        if (gameManager.isCreatorGamesLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        return Stack(
          children: [
            Column(
              children: [
                _buildHeader(gameManager),
                Expanded(
                  child: gameManager.creatorGames.isEmpty
                      ? _buildEmptyState()
                      : _buildGamesList(gameManager),
                ),
              ],
            ),
            if (gameManager.isGameActionLoading)
              Container(
                color: Colors.black.withOpacity(0.3),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: AppTheme.primary),
                      SizedBox(height: AppTheme.spacing4),
                      Text(
                        'Processing...',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(GameCreatorManager gameManager) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing4,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'My Games',
            style: AppTheme.headlineMedium,
          ),
          ElevatedButton.icon(
            onPressed: () => _showUploadDialog(context, gameManager),
            icon: const Icon(Icons.add, color: AppTheme.textInverse),
            label: const Text('Upload Game'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: AppTheme.textInverse,
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing4,
                vertical: AppTheme.spacing2,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusFull),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacing8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(AppTheme.spacing6),
              decoration: BoxDecoration(
                color: AppTheme.backgroundSecondary,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.borderSecondary, width: 2),
              ),
              child: Icon(
                Icons.videogame_asset_outlined,
                size: 64,
                color: AppTheme.textTertiary.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: AppTheme.spacing6),
            Text(
              'No games uploaded yet',
              style: AppTheme.headlineSmall.copyWith(color: AppTheme.textPrimary),
            ),
            const SizedBox(height: AppTheme.spacing2),
            Text(
              'Upload your first game to start reaching millions of users and earning rewards!',
              textAlign: TextAlign.center,
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGamesList(GameCreatorManager gameManager) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: gameManager.creatorGames.length,
      itemBuilder: (context, index) {
        final game = gameManager.creatorGames[index];
        return _buildGameCard(game, gameManager);
      },
    );
  }

  Widget _buildGameCard(GameModel game, GameCreatorManager gameManager) {
    final isPending = game.status == 'pending';
    
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacing4),
      decoration: AppTheme.createCardDecoration(
        shadows: AppTheme.shadowMd,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacing4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundSecondary,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    border: Border.all(color: AppTheme.borderSecondary),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    child: game.thumbnailUrl != null && game.thumbnailUrl!.isNotEmpty
                        ? Image.network(game.thumbnailUrl!, fit: BoxFit.cover)
                        : const Icon(Icons.videogame_asset, color: AppTheme.primary),
                  ),
                ),
                const SizedBox(width: AppTheme.spacing4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        game.title,
                        style: AppTheme.titleLarge.copyWith(fontWeight: AppTheme.weightBold),
                      ),
                      const SizedBox(height: AppTheme.spacing1),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppTheme.spacing2,
                              vertical: AppTheme.spacing1 * 0.5,
                            ),
                            decoration: BoxDecoration(
                              color: isPending 
                                  ? AppTheme.warning.withOpacity(0.1) 
                                  : AppTheme.success.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                            ),
                            child: Text(
                              (game.status ?? 'active').toUpperCase(),
                              style: AppTheme.labelSmall.copyWith(
                                color: isPending ? AppTheme.warning : AppTheme.success,
                                fontWeight: AppTheme.weightBold,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppTheme.spacing3),
                          Icon(Icons.remove_red_eye_outlined, size: 14, color: AppTheme.textTertiary),
                          const SizedBox(width: 4),
                          Text(
                            '${game.views} views',
                            style: AppTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (isPending)
                  TextButton(
                    onPressed: () => _confirmPublish(context, game, gameManager),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      textStyle: AppTheme.labelMedium.copyWith(fontWeight: AppTheme.weightBold),
                    ),
                    child: const Text('PUBLISH'),
                  ),
              ],
            ),
            if (game.description.isNotEmpty) ...[
              const SizedBox(height: AppTheme.spacing3),
              Text(
                game.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showUploadDialog(BuildContext context, GameCreatorManager gameManager) async {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    File? selectedFile;
    String orientation = 'portrait';

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Upload New Game', style: AppTheme.headlineSmall),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Game Title',
                    hintText: 'Enter a catchy title',
                  ),
                ),
                const SizedBox(height: AppTheme.spacing4),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'What is this game about?',
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: AppTheme.spacing4),
                DropdownButtonFormField<String>(
                  value: orientation,
                  decoration: const InputDecoration(labelText: 'Orientation'),
                  items: const [
                    DropdownMenuItem(value: 'portrait', child: Text('Portrait')),
                    DropdownMenuItem(value: 'landscape', child: Text('Landscape')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => orientation = val);
                  },
                ),
                const SizedBox(height: AppTheme.spacing4),
                GestureDetector(
                  onTap: () async {
                    FilePickerResult? result = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['zip'],
                    );
                    if (result != null) {
                      setDialogState(() => selectedFile = File(result.files.single.path!));
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(AppTheme.spacing4),
                    decoration: BoxDecoration(
                      color: AppTheme.backgroundSecondary,
                      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                      border: Border.all(
                        color: selectedFile == null ? AppTheme.borderPrimary : AppTheme.primary,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          selectedFile == null ? Icons.file_upload_outlined : Icons.check_circle_outline,
                          color: selectedFile == null ? AppTheme.textSecondary : AppTheme.primary,
                        ),
                        const SizedBox(width: AppTheme.spacing2),
                        Text(
                          selectedFile == null ? 'Select Game ZIP' : 'ZIP Selected',
                          style: AppTheme.labelMedium.copyWith(
                            color: selectedFile == null ? AppTheme.textPrimary : AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (selectedFile != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppTheme.spacing2),
                    child: Text(
                      selectedFile!.path.split('/').last,
                      style: AppTheme.labelSmall.copyWith(color: AppTheme.success),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
            ),
            ElevatedButton(
              onPressed: selectedFile == null || titleController.text.isEmpty
                  ? null
                  : () async {
                      final title = titleController.text;
                      final desc = descController.text;
                      final file = selectedFile!;
                      Navigator.pop(context);
                      
                      final success = await gameManager.uploadGame(
                        zipFile: file,
                        title: title,
                        description: desc,
                        orientation: orientation,
                      );

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(success ? 'Game uploaded successfully!' : 'Failed to upload game'),
                            backgroundColor: success ? AppTheme.success : AppTheme.error,
                          ),
                        );
                      }
                    },
              style: AppTheme.createButtonStyle(),
              child: const Text('Upload'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmPublish(BuildContext context, GameModel game, GameCreatorManager gameManager) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Publish Game', style: AppTheme.headlineSmall),
        content: Text(
          'Are you sure you want to publish "${game.title}"? It will become visible to all users.',
          style: AppTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: AppTheme.createButtonStyle(),
            child: const Text('Yes, Publish'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await gameManager.publishGame(game.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Game published successfully!' : 'Failed to publish game'),
            backgroundColor: success ? AppTheme.success : AppTheme.error,
          ),
        );
      }
    }
  }
}
