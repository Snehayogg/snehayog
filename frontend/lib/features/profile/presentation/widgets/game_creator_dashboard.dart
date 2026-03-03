import 'package:flutter/material.dart';
import 'package:vayu/core/design/spacing.dart';
import 'package:vayu/core/design/radius.dart';
import 'package:provider/provider.dart';
import 'package:vayu/features/profile/presentation/managers/game_creator_manager.dart';
import 'package:vayu/features/games/data/game_model.dart';
import 'package:vayu/core/design/theme.dart';
import 'package:vayu/core/design/colors.dart';
import 'package:vayu/core/design/typography.dart';
import 'package:vayu/core/design/elevation.dart';
import 'package:vayu/shared/widgets/app_button.dart';

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
          return Center(child: CircularProgressIndicator());
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
                color: Colors.black.withValues(alpha: 0.3),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: AppColors.primary),
                      SizedBox(height: AppSpacing.spacing4),
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
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.spacing4,
        vertical: AppSpacing.spacing4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Arcade Studio',
                style: AppTypography.headlineMedium,
              ),
              IconButton(
                onPressed: () => gameManager.loadCreatorGames(),
                icon: Icon(Icons.refresh, color: AppColors.primary),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.spacing4),
          _buildWebUploadCard(),
        ],
      ),
    );
  }

  Widget _buildWebUploadCard() {
    return Container(
      padding: EdgeInsets.all(AppSpacing.spacing4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_upload_outlined, color: AppColors.primary),
              SizedBox(width: AppSpacing.spacing2),
              Text(
                'Upload New Content via Web',
                style: AppTypography.titleMedium.copyWith(color: AppColors.primary, fontWeight: AppTypography.weightBold),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.spacing2),
          Text(
            'To ensure the best deployment experience, arcade content uploads are now handled through our dedicated web portal.',
            style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
          ),
          SizedBox(height: AppSpacing.spacing3),
          AppButton(
            onPressed: () {
              // Show instructions or open URL
              showModalBottomSheet(
                context: context,
                backgroundColor: AppColors.backgroundSecondary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
                ),
                builder: (context) => Padding(
                  padding: EdgeInsets.all(AppSpacing.spacing6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Deploy from Computer', style: AppTypography.headlineSmall),
                      SizedBox(height: AppSpacing.spacing4),
                      Text(
                        '1. Visit snehayog.site/creator.html\n2. Log in with your developer token\n3. Upload your Content ZIP',
                        style: AppTypography.bodyMedium,
                      ),
                      SizedBox(height: AppSpacing.spacing6),
                      Text(
                        'Your Developer Token:',
                        style: AppTypography.labelSmall.copyWith(color: AppColors.textTertiary),
                      ),
                      SizedBox(height: AppSpacing.spacing2),
                      Container(
                        padding: EdgeInsets.all(AppSpacing.spacing3),
                        decoration: BoxDecoration(
                          color: AppColors.backgroundPrimary,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: const SelectableText(
                          'Copy your token from Profile > Settings',
                          style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                        ),
                      ),
                      SizedBox(height: AppSpacing.spacing6),
                      AppButton(
                        isFullWidth: true,
                        onPressed: () => Navigator.pop(context),
                        label: 'GOT IT',
                        variant: AppButtonVariant.primary,
                      ),
                    ],
                  ),
                ),
              );
            },
            label: 'HOW TO UPLOAD',
            variant: AppButtonVariant.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.spacing8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(AppSpacing.spacing6),
              decoration: BoxDecoration(
                color: AppColors.backgroundSecondary,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.borderSecondary, width: 2),
              ),
              child: Icon(
                Icons.sports_esports_outlined,
                size: 64,
                color: AppColors.textTertiary.withValues(alpha: 0.5),
              ),
            ),
            SizedBox(height: AppSpacing.spacing6),
            Text(
              'Your Arcade Content',
              style: AppTypography.headlineSmall.copyWith(color: AppColors.textPrimary),
            ),
            SizedBox(height: AppSpacing.spacing2),
            Text(
              'Begin your journey by uploading high-quality interactive arcade content.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGamesList(GameCreatorManager gameManager) {
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 16),
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
      margin: EdgeInsets.only(bottom: AppSpacing.spacing4),
      decoration: AppTheme.createCardDecoration(
        shadows: AppElevation.shadowMd,
      ),
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.spacing4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.backgroundSecondary,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.borderSecondary),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: game.thumbnailUrl != null && game.thumbnailUrl!.isNotEmpty
                        ? Image.network(game.thumbnailUrl!, fit: BoxFit.cover)
                        : Icon(Icons.sports_esports_outlined, color: AppColors.primary),
                  ),
                ),
                SizedBox(width: AppSpacing.spacing4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        game.title,
                        style: AppTypography.titleLarge.copyWith(fontWeight: AppTypography.weightBold),
                      ),
                      SizedBox(height: AppSpacing.spacing1),
                      Row(
                        children: [
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: AppSpacing.spacing2,
                              vertical: AppSpacing.spacing1 * 0.5,
                            ),
                            decoration: BoxDecoration(
                              color: isPending 
                                  ? AppColors.warning.withValues(alpha: 0.1) 
                                  : AppColors.success.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                            ),
                            child: Text(
                              (game.status ?? 'active').toUpperCase(),
                              style: AppTypography.labelSmall.copyWith(
                                color: isPending ? AppColors.warning : AppColors.success,
                                fontWeight: AppTypography.weightBold,
                              ),
                            ),
                          ),
                          SizedBox(width: AppSpacing.spacing4),
                          Icon(Icons.play_arrow_outlined, size: 16, color: AppColors.primary),
                          SizedBox(width: 4),
                          Text(
                            '${game.plays} plays',
                            style: AppTypography.bodySmall.copyWith(fontWeight: AppTypography.weightBold),
                          ),
                          if (game.totalTimeSpent > 0) ...[
                             SizedBox(width: AppSpacing.spacing4),
                            Icon(Icons.timer_outlined, size: 14, color: AppColors.warning),
                             SizedBox(width: 4),
                             Text(
                               '${(game.totalTimeSpent / 60).toStringAsFixed(1)}m',
                               style: AppTypography.bodySmall,
                             ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (isPending)
                  AppButton(
                    onPressed: () => _confirmPublish(context, game, gameManager),
                    label: 'PUBLISH',
                    variant: AppButtonVariant.text,
                  ),
              ],
            ),
            if (game.description.isNotEmpty) ...[
              SizedBox(height: AppSpacing.spacing3),
              Text(
                game.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
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
        title: Text('Publish Content', style: AppTypography.headlineSmall),
        content: Text(
          'Are you sure you want to publish "${game.title}"? It will become visible to all users.',
          style: AppTypography.bodyMedium,
        ),
        actions: [
          AppButton(
            onPressed: () => Navigator.pop(context, false),
            label: 'Cancel',
            variant: AppButtonVariant.text,
          ),
          AppButton(
            onPressed: () => Navigator.pop(context, true),
            label: 'Yes, Publish',
            variant: AppButtonVariant.primary,
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await gameManager.publishGame(game.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Content published successfully!' : 'Failed to publish content'),
            backgroundColor: success ? AppColors.success : AppColors.error,
          ),
        );
      }
    }
  }
}

