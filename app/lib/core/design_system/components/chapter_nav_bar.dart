import 'package:flutter/material.dart';

import '../theme/chapter_theme.dart';

@immutable
class ChapterNavItem {
  const ChapterNavItem({required this.label, required this.icon, required this.selectedIcon});

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Bottom navigation. The item at [emphasizedIndex] (Read) is drawn with a
/// filled accent disc so the core loop is always one obvious tap away.
class ChapterNavBar extends StatelessWidget {
  const ChapterNavBar({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
    this.emphasizedIndex,
  });

  final List<ChapterNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final int? emphasizedIndex;

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
              icon: i == emphasizedIndex ? _Emphasized(icon: items[i].icon) : Icon(items[i].icon),
              selectedIcon: i == emphasizedIndex
                  ? _Emphasized(icon: items[i].selectedIcon)
                  : Icon(items[i].selectedIcon),
            ),
        ],
      ),
    );
  }
}

class _Emphasized extends StatelessWidget {
  const _Emphasized({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.chapterColors;
    return DecoratedBox(
      decoration: BoxDecoration(color: colors.accent, shape: BoxShape.circle),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, color: colors.onAccent, size: 22),
      ),
    );
  }
}
