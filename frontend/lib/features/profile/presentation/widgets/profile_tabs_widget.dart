import 'package:flutter/material.dart';
import 'package:vayu/shared/theme/app_theme.dart';

class ProfileTabsWidget extends StatelessWidget {
  final int activeIndex;
  final ValueChanged<int> onSelect;
  final bool showTopCreators;

  const ProfileTabsWidget({
    super.key,
    required this.activeIndex,
    required this.onSelect,
    this.showTopCreators = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.backgroundSecondary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTabItem(
              label: 'Videos',
              index: 0,
            ),
          ),
          if (showTopCreators)
            Expanded(
              child: _buildTabItem(
                label: 'Top Creators',
                index: 1,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTabItem({required String label, required int index}) {
    final bool isSelected = activeIndex == index;
    return GestureDetector(
      onTap: () => onSelect(index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.surfacePrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ]
              : [],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
