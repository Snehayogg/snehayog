import 'package:flutter/material.dart';
import 'package:vayu/features/profile/core/presentation/managers/profile_state_manager.dart';
import 'package:vayu/features/profile/core/presentation/widgets/profile_videos_widget.dart';

class VayuGridTab extends StatelessWidget {
  final ProfileStateManager manager;

  const VayuGridTab({super.key, required this.manager});

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification scrollInfo) {
        if (scrollInfo.metrics.pixels >=
                scrollInfo.metrics.maxScrollExtent - 300 &&
            !manager.isFetchingMore &&
            manager.hasMoreVideos) {
          manager.loadMoreVideos();
        }
        return false;
      },
      child: CustomScrollView(
        key: const PageStorageKey<String>('profile_tab_vayu'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverOverlapInjector(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
          ),
          ProfileVideosWidget(
            stateManager: manager,
            filterVideoType: 'vayu',
            showHeader: false,
            isSliver: true,
          ),
          if (manager.isFetchingMore)
            SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.green.shade500),
                    ),
                  ),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }
}
