import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vayu/features/profile/presentation/managers/game_creator_manager.dart';
import 'package:vayu/features/games/data/game_model.dart';
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Creator Dashboard',
                style: AppTheme.headlineMedium,
              ),
              IconButton(
                onPressed: () => gameManager.loadCreatorGames(),
                icon: const Icon(Icons.refresh, color: AppTheme.primary),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing4),
          _buildWebUploadCard(),
        ],
      ),
    );
  }

  Widget _buildWebUploadCard() {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing4),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cloud_upload_outlined, color: AppTheme.primary),
              const SizedBox(width: AppTheme.spacing2),
              Text(
                'Upload New Games via Web',
                style: AppTheme.titleMedium.copyWith(color: AppTheme.primary, fontWeight: AppTheme.weightBold),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing2),
          Text(
            'To ensure the best deployment experience, game uploads are now handled through our dedicated web portal.',
            style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: AppTheme.spacing3),
          ElevatedButton(
            onPressed: () {
              // Show instructions or open URL
              showModalBottomSheet(
                context: context,
                backgroundColor: AppTheme.backgroundSecondary,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLarge)),
                ),
                builder: (context) => Padding(
                  padding: const EdgeInsets.all(AppTheme.spacing6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Deploy from Computer', style: AppTheme.headlineSmall),
                      const SizedBox(height: AppTheme.spacing4),
                      Text(
                        '1. Visit snehayog.site/creator.html\n2. Log in with your developer token\n3. Upload your Game ZIP',
                        style: AppTheme.bodyMedium,
                      ),
                      const SizedBox(height: AppTheme.spacing6),
                      Text(
                        'Your Developer Token:',
                        style: AppTheme.labelSmall.copyWith(color: AppTheme.textTertiary),
                      ),
                      const SizedBox(height: AppTheme.spacing2),
                      Container(
                        padding: const EdgeInsets.all(AppTheme.spacing3),
                        decoration: BoxDecoration(
                          color: AppTheme.backgroundPrimary,
                          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                        ),
                        child: const SelectableText(
                          'Copy your token from Profile > Settings',
                          style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacing6),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: AppTheme.createButtonStyle(),
                          child: const Text('GOT IT'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMedium)),
            ),
            child: const Text('HOW TO UPLOAD'),
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
                          const SizedBox(width: AppTheme.spacing4),
                          Icon(Icons.play_arrow_outlined, size: 16, color: AppTheme.primary),
                          const SizedBox(width: 4),
                          Text(
                            '${game.plays} plays',
                            style: AppTheme.bodySmall.copyWith(fontWeight: AppTheme.weightBold),
                          ),
                          if (game.totalTimeSpent > 0) ...[
                             const SizedBox(width: AppTheme.spacing4),
                             Icon(Icons.timer_outlined, size: 14, color: AppTheme.warning),
                             const SizedBox(width: 4),
                             Text(
                               '${(game.totalTimeSpent / 60).toStringAsFixed(1)}m',
                               style: AppTheme.bodySmall,
                             ),
                          ],
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

