import 'package:flutter/material.dart';

import '../theme/chapter_theme.dart';

@immutable
class ChapterNavItem {
  const ChapterNavItem({required this.label, required this.icon, required this.selectedIcon});

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Bottom navigation. Only the current tab is highlighted, with the theme's
/// terracotta indicator.
class ChapterNavBar extends StatelessWidget {
  const ChapterNavBar({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final List<ChapterNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.chapterColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.line)),
      ),
      child: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onSelected,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          for (var i = 0; i < items.length; i++)
            NavigationDestination(
              label: items[i].label,
              icon: Icon(items[i].icon),
              selectedIcon: Icon(items[i].selectedIcon),
            ),
        ],
      ),
    );
  }
}
